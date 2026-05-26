// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";

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
contract RewardManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
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
     * @dev 分发战斗奖励
     */
    function distributeBattleReward(
        address winner,
        address loser,
        uint256 battleType
    ) external {
        uint256 reward = 100 * 10**18;
        _distributeReward(reward);
    }

    /**
     * @dev 添加质押池奖励
     */
    function addStakingReward(uint256 amount, uint256 poolType) external {
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
     * @dev 分红发放事件
     */
    event DividendClaimed(address indexed user, uint256 amount);

    /**
     * @dev 领取分红
     */
    function claimDividend(address user) external returns (uint256) {
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
    function calcUserDividend(address user) external view returns (uint256) {
        return pendingDividends[user];
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

        if (dividendPool != address(0) && dividendAmount > 0) {
            require(token.transfer(dividendPool, dividendAmount), "RewardManager: Transfer to dividend pool failed");
        }
        if (nftStakingPool != address(0) && nftStakingAmount > 0) {
            require(token.transfer(nftStakingPool, nftStakingAmount), "RewardManager: Transfer to NFT staking pool failed");
        }
        if (tokenStakingPool != address(0) && tokenStakingAmount > 0) {
            require(token.transfer(tokenStakingPool, tokenStakingAmount), "RewardManager: Transfer to token staking pool failed");
        }
        if (arenaRewardPool != address(0) && arenaRewardAmount > 0) {
            require(token.transfer(arenaRewardPool, arenaRewardAmount), "RewardManager: Transfer to arena pool failed");
        }

        emit RewardDistributed(
            msg.sender,
            amount,
            dividendAmount,
            nftStakingAmount,
            tokenStakingAmount,
            arenaRewardAmount
        );
    }

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
}
