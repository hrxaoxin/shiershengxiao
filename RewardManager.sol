// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";

/**
 * @dev PoolManager 接口，用于同步更新各资金池余额
 */
interface IPoolManager {
    function addToNFTStakingPool(uint256 amount) external;
    function addToTokenStakingPool(uint256 amount) external;
    function addToArenaRewardPool(uint256 amount) external;
}

/**
 * @title RewardManager
 * @dev 奖励管理合约，统一管理所有游戏奖励的分发
 *
 * 奖励来源：
 * 1. 战斗胜利奖励
 * 2. 交易手续费（5%）
 * 3. 铸造费用
 *
 * 奖励分配：
 * - 50% 进入分红池
 * - 25% 进入NFT质押池
 * - 15% 进入代币质押池
 * - 10% 进入竞技场奖励池
 */
contract RewardManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "RewardManager: Paused");
        _;
    }

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 代币合约地址
     */
    address public tokenContract;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "RewardManager: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 分红池地址
     */
    address public dividendPool;

    /**
     * @dev NFT质押池地址
     */
    address public nftStakingPool;

    /**
     * @dev 代币质押池地址
     */
    address public tokenStakingPool;

    /**
     * @dev 竞技场奖励池地址
     */
    address public arenaRewardPool;

    /**
     * @dev 资金池管理合约地址（用于追踪各池余额）
     */
    address public poolManager;

    /**
     * @dev 奖励分配比例（精度4位小数）
     */
    uint256 public dividendPercent = 5000;    // 50%
    uint256 public nftStakingPercent = 2500;  // 25%
    uint256 public tokenStakingPercent = 1500; // 15%
    uint256 public arenaRewardPercent = 1000;   // 10%

    /**
     * @dev 精度
     */
    uint256 public constant PRECISION = 10000;

    /**
     * @dev 奖励事件
     */
    event RewardDistributed(
        address indexed from,
        uint256 totalAmount,
        uint256 dividendAmount,
        uint256 nftStakingAmount,
        uint256 tokenStakingAmount,
        uint256 arenaRewardAmount
    );

    /**
     * @dev 设置分红池地址
     */
    function setDividendPool(address _dividendPool) external onlyAuthorized {
        require(_dividendPool != address(0), "RewardManager: Invalid dividend pool");
        dividendPool = _dividendPool;
    }

    /**
     * @dev 设置NFT质押池地址
     */
    function setNFTStakingPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "RewardManager: Invalid NFT staking pool");
        nftStakingPool = _pool;
    }

    /**
     * @dev 设置代币质押池地址
     */
    function setTokenStakingPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "RewardManager: Invalid token staking pool");
        tokenStakingPool = _pool;
    }

    /**
     * @dev 设置代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "RewardManager: Invalid token contract");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置竞技场奖励池地址
     */
    function setArenaRewardPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "RewardManager: Invalid arena reward pool");
        arenaRewardPool = _pool;
    }

    /**
     * @dev 设置资金池管理合约地址
     */
    function setPoolManager(address _poolManager) external onlyAuthorized {
        poolManager = _poolManager;
    }

    /**
     * @dev 战斗类型对应的奖励金额映射
     * battleType => rewardAmount
     */
    mapping(uint256 => uint256) public battleRewardAmounts;

    /**
     * @dev 默认战斗奖励金额
     */
    uint256 public defaultBattleReward = 100 * 10**18;

    /**
     * @dev 设置特定战斗类型的奖励金额
     * @param battleType 战斗类型
     * @param amount 奖励金额
     */
    function setBattleRewardAmount(uint256 battleType, uint256 amount) external onlyOwner {
        battleRewardAmounts[battleType] = amount;
    }

    /**
     * @dev 分发战斗奖励
     */
    function distributeBattleReward(
        address winner,
        address loser,
        uint256 battleType
    ) external onlyAuthorized whenNotPaused {
        // 根据 battleType 动态计算奖励，未配置时使用默认值
        uint256 reward = battleRewardAmounts[battleType];
        if (reward == 0) {
            reward = defaultBattleReward;
        }
        _distributeReward(reward);
    }

    /**
     * @dev 设置默认战斗奖励金额
     */
    function setDefaultBattleReward(uint256 amount) external onlyOwner {
        defaultBattleReward = amount;
    }

    /**
     * @dev 添加质押池奖励
     */
    function addStakingReward(uint256 amount, uint256 poolType) external onlyAuthorized whenNotPaused {
        require(amount > 0, "RewardManager: Invalid amount");
        require(tokenContract != address(0), "RewardManager: Token contract not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(msg.sender) >= amount, "RewardManager: Insufficient balance");

        if (poolType == 0 && nftStakingPool != address(0)) {
            require(token.transferFrom(msg.sender, nftStakingPool, amount), "RewardManager: Transfer failed");
        } else if (poolType == 1 && tokenStakingPool != address(0)) {
            require(token.transferFrom(msg.sender, tokenStakingPool, amount), "RewardManager: Transfer failed");
        } else if (poolType == 2 && arenaRewardPool != address(0)) {
            require(token.transferFrom(msg.sender, arenaRewardPool, amount), "RewardManager: Transfer failed");
        }
    }

    /**
     * @dev 用户可领取分红映射
     * user => pendingDividend
     */
    mapping(address => uint256) public pendingDividends;
    
    /**
     * @dev 用户权重映射
     * user => weight
     */
    mapping(address => uint256) public userWeights;

    /**
     * @dev 分红发放事件
     */
    event DividendClaimed(address indexed user, uint256 amount);

    /**
     * @dev 领取分红
     */
    function claimDividend(address user) external whenNotPaused returns (uint256) {
        require(
            msg.sender == user || msg.sender == owner() || msg.sender == authorizer,
            "RewardManager: Not authorized to claim for other users"
        );
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        
        uint256 dividend = pendingDividends[user];
        require(dividend > 0, "RewardManager: No pending dividend");
        
        pendingDividends[user] = 0;
        
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "RewardManager: Insufficient contract balance");
        require(token.transfer(user, dividend), "RewardManager: Transfer failed");
        
        emit DividendClaimed(user, dividend);
        return dividend;
    }

    /**
     * @dev 获取用户可领取分红
     */
    function getDividend(address user) external view returns (uint256) {
        return pendingDividends[user];
    }

    /**
     * @dev 计算用户可领取分红（前端调用）
     */
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        return (pendingDividends[user], userWeights[user]);
    }

    /**
     * @dev 获取分红池余额
     */
    function dividendPoolBalance() external view returns (uint256) {
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        return IERC20(tokenContract).balanceOf(dividendPool);
    }

    /**
     * @dev 分配奖励到各个池
     */
    function _distributeReward(uint256 amount) internal {
        require(tokenContract != address(0), "RewardManager: Token contract not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "RewardManager: Insufficient contract balance");

        uint256 dividendAmount = amount * dividendPercent / PRECISION;
        uint256 nftStakingAmount = amount * nftStakingPercent / PRECISION;
        uint256 tokenStakingAmount = amount * tokenStakingPercent / PRECISION;
        uint256 arenaRewardAmount = amount * arenaRewardPercent / PRECISION;

        bool dividendSuccess = true;
        bool nftStakingSuccess = true;
        bool tokenStakingSuccess = true;
        bool arenaRewardSuccess = true;

        if (dividendPool != address(0) && dividendAmount > 0) {
            dividendSuccess = token.transfer(dividendPool, dividendAmount);
            if (!dividendSuccess) {
                emit RewardTransferFailed(0, dividendPool, dividendAmount);
            }
        }
        if (nftStakingPool != address(0) && nftStakingAmount > 0) {
            nftStakingSuccess = token.transfer(nftStakingPool, nftStakingAmount);
            if (nftStakingSuccess && poolManager != address(0)) {
                IPoolManager(poolManager).addToNFTStakingPool(nftStakingAmount);
            } else if (!nftStakingSuccess) {
                emit RewardTransferFailed(1, nftStakingPool, nftStakingAmount);
            }
        }
        if (tokenStakingPool != address(0) && tokenStakingAmount > 0) {
            tokenStakingSuccess = token.transfer(tokenStakingPool, tokenStakingAmount);
            if (tokenStakingSuccess && poolManager != address(0)) {
                IPoolManager(poolManager).addToTokenStakingPool(tokenStakingAmount);
            } else if (!tokenStakingSuccess) {
                emit RewardTransferFailed(2, tokenStakingPool, tokenStakingAmount);
            }
        }
        if (arenaRewardPool != address(0) && arenaRewardAmount > 0) {
            arenaRewardSuccess = token.transfer(arenaRewardPool, arenaRewardAmount);
            if (arenaRewardSuccess && poolManager != address(0)) {
                IPoolManager(poolManager).addToArenaRewardPool(arenaRewardAmount);
            } else if (!arenaRewardSuccess) {
                emit RewardTransferFailed(3, arenaRewardPool, arenaRewardAmount);
            }
        }

        distributionHistory.push(DistributionRecord({
            timestamp: block.timestamp,
            totalAmount: amount,
            dividendAmount: dividendSuccess ? dividendAmount : 0,
            nftStakingAmount: nftStakingSuccess ? nftStakingAmount : 0,
            tokenStakingAmount: tokenStakingSuccess ? tokenStakingAmount : 0,
            arenaRewardAmount: arenaRewardSuccess ? arenaRewardAmount : 0,
            distributor: msg.sender
        }));

        emit RewardDistributed(
            msg.sender,
            amount,
            dividendSuccess ? dividendAmount : 0,
            nftStakingSuccess ? nftStakingAmount : 0,
            tokenStakingSuccess ? tokenStakingAmount : 0,
            arenaRewardSuccess ? arenaRewardAmount : 0
        );
    }

    event RewardTransferFailed(uint256 poolType, address pool, uint256 amount);

    /**
     * @dev 设置分配比例
     */
    function setDistributionPercents(
        uint256 _dividendPercent,
        uint256 _nftStakingPercent,
        uint256 _tokenStakingPercent,
        uint256 _arenaRewardPercent
    ) external onlyOwner {
        require(
            _dividendPercent + _nftStakingPercent + _tokenStakingPercent + _arenaRewardPercent == PRECISION,
            "RewardManager: Percentages must sum to 100%"
        );

        dividendPercent = _dividendPercent;
        nftStakingPercent = _nftStakingPercent;
        tokenStakingPercent = _tokenStakingPercent;
        arenaRewardPercent = _arenaRewardPercent;
    }

    /**
     * @dev 获取分配比例
     */
    function getDistributionPercents() external view returns (
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (dividendPercent, nftStakingPercent, tokenStakingPercent, arenaRewardPercent);
    }

    /**
     * @dev 分发历史记录结构体
     */
    struct DistributionRecord {
        uint256 timestamp;
        uint256 totalAmount;
        uint256 dividendAmount;
        uint256 nftStakingAmount;
        uint256 tokenStakingAmount;
        uint256 arenaRewardAmount;
        address distributor;
    }

    /**
     * @dev 分发历史记录数组
     */
    DistributionRecord[] public distributionHistory;

    /**
     * @dev 获取分发历史记录长度
     */
    function getDistributionHistoryLength() external view returns (uint256) {
        return distributionHistory.length;
    }

    /**
     * @dev 获取指定范围的分发历史
     * @param startIndex 起始索引
     * @param count 获取数量
     */
    function getDistributionHistory(uint256 startIndex, uint256 count) external view returns (DistributionRecord[] memory) {
        require(startIndex < distributionHistory.length, "RewardManager: Invalid start index");
        require(count > 0, "RewardManager: Invalid count");

        uint256 endIndex = startIndex + count;
        if (endIndex > distributionHistory.length) {
            endIndex = distributionHistory.length;
        }

        DistributionRecord[] memory records = new DistributionRecord[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            records[i - startIndex] = distributionHistory[i];
        }

        return records;
    }

    /**
     * @dev 获取最新N条分发记录
     * @param count 记录数量
     */
    function getRecentDistributions(uint256 count) external view returns (DistributionRecord[] memory) {
        if (distributionHistory.length == 0) {
            return new DistributionRecord[](0);
        }

        if (count > distributionHistory.length) {
            count = distributionHistory.length;
        }

        DistributionRecord[] memory records = new DistributionRecord[](count);
        uint256 startIndex = distributionHistory.length - count;
        for (uint256 i = 0; i < count; i++) {
            records[i] = distributionHistory[startIndex + i];
        }

        return records;
    }

    /**
     * @dev 获取奖励池统计
     * @return dividendPoolBalance NFT质押池余额
     * @return tokenStakingBalance 代币质押池余额
     * @return arenaRewardBalance 竞技场奖励池余额
     * @return totalDistributed 总分发金额
     */
    function getRewardPoolStats() external view returns (
        uint256 dividendPoolBalance,
        uint256 tokenStakingBalance,
        uint256 arenaRewardBalance,
        uint256 totalDistributed
    ) {
        IERC20 token = IERC20(tokenContract);

        if (dividendPool != address(0)) {
            dividendPoolBalance = token.balanceOf(dividendPool);
        }
        if (tokenStakingPool != address(0)) {
            tokenStakingBalance = token.balanceOf(tokenStakingPool);
        }
        if (arenaRewardPool != address(0)) {
            arenaRewardBalance = token.balanceOf(arenaRewardPool);
        }

        totalDistributed = 0;
        for (uint256 i = 0; i < distributionHistory.length; i++) {
            totalDistributed += distributionHistory[i].totalAmount;
        }
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner {
        require(amount > 0, "RewardManager: Amount must be > 0");
        require(amount <= address(this).balance, "RewardManager: Insufficient balance");
        payable(owner()).transfer(amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner {
        require(amount > 0, "RewardManager: Amount must be > 0");
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "RewardManager: Insufficient token balance");
        require(token.transfer(owner(), amount), "RewardManager: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
}
