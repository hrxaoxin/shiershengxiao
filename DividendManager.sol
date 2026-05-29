// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

/**
 * @title DividendManager
 * @dev 分红管理合约，管理NFT持有者的分红分发
 *
 * 分红来源：
 * 1. 交易手续费（3%进入分红池）
 * 2. 战斗胜利奖励
 * 3. 其他游戏收益
 *
 * 分红计算：
 * - 用户分红 = 总分红 × (用户权重 / 总权重)
 * - 权重由用户持有的NFT等级和稀有度决定
 *
 * 权重表（普通NFT）：
 * - 1级: 1
 * - 2级: 2
 * - 3级: 6
 * - 4级: 18
 * - 5级: 66
 *
 * 权重表（稀有NFT）：
 * - 1级: 10
 * - 2级: 12
 * - 3级: 16
 * - 4级: 28
 * - 5级: 76
 */
contract DividendManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 用户权重映射
     * user => weight
     */
    mapping(address => uint256) public userWeights;

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
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
        require(msg.sender == owner() || msg.sender == authorizer, "DividendManager: Not authorized");
        _;
    }

    /**
     * @dev 用户待领取分红映射
     * user => pendingDividend
     */
    mapping(address => uint256) public pendingDividends;

    /**
     * @dev 总权重
     */
    uint256 public totalWeight;

    /**
     * @dev 分红池余额
     */
    uint256 public dividendPoolBalance;

    /**
     * @dev 分红池地址（用于查询外部池余额）
     */
    address public dividendPool;

    /**
     * @dev 代币合约地址（用于领取分红转账）
     */
    address public tokenContract;

    /**
     * @dev 最后更新快照时间
     */
    uint256 public lastSnapshotTime;

    /**
     * @dev 分红快照结构
     */
    struct DividendSnapshot {
        uint256 totalWeight;
        uint256 totalDividend;
        uint256 perWeightDividend;
    }

    /**
     * @dev 历史快照
     */
    DividendSnapshot[] public snapshots;

    /**
     * @dev 上次同步时的合约代币余额（用于自动检测新增资金）
     */
    uint256 public lastSyncedBalance;

    /**
     * @dev 添加到分红池（手动指定金额）
     */
    function addDividendPool(uint256 amount) external onlyOwner {
        require(amount > 0, "DividendManager: Invalid amount");
        _addToDividendPool(amount);
        if (tokenContract != address(0)) {
            lastSyncedBalance = IERC20(tokenContract).balanceOf(address(this));
        }
    }

    /**
     * @dev 同步分红池余额（自动检测合约中新增的代币）
     */
    function syncDividendPool() external {
        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        uint256 currentBalance = token.balanceOf(address(this));

        if (currentBalance > lastSyncedBalance) {
            uint256 newFunds = currentBalance - lastSyncedBalance;
            _addToDividendPool(newFunds);
        }

        lastSyncedBalance = currentBalance;
    }

    /**
     * @dev 内部函数：将金额添加到分红池并创建快照
     */
    function _addToDividendPool(uint256 amount) internal {
        dividendPoolBalance += amount;

        if (totalWeight > 0) {
            DividendSnapshot memory newSnapshot = DividendSnapshot({
                totalWeight: totalWeight,
                totalDividend: dividendPoolBalance,
                perWeightDividend: dividendPoolBalance * 1e18 / totalWeight
            });
            snapshots.push(newSnapshot);
        }
    }

    /**
     * @dev 领取分红
     */
    function claim() external returns (uint256) {
        uint256 userWeight = userWeights[msg.sender];
        require(userWeight > 0, "DividendManager: No weight");

        uint256 dividend = pendingDividends[msg.sender];
        require(dividend > 0, "DividendManager: No dividend");

        pendingDividends[msg.sender] = 0;

        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "DividendManager: Insufficient contract balance");
        require(token.transfer(msg.sender, dividend), "DividendManager: Transfer failed");

        return dividend;
    }

    /**
     * @dev 领取分红并转账（供前端直接调用）
     */
    function claimDividend() external {
        uint256 dividend = pendingDividends[msg.sender];
        require(dividend > 0, "DividendManager: No dividend");
        require(tokenContract != address(0), "DividendManager: Token contract not set");

        pendingDividends[msg.sender] = 0;

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "DividendManager: Insufficient contract balance");
        require(token.transfer(msg.sender, dividend), "DividendManager: Transfer failed");
    }

    /**
     * @dev 计算用户可领取分红（别名，兼容前端调用）
     * @param user 用户地址
     * @return 可领取分红金额和用户权重
     */
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        return (pendingDividends[user], userWeights[user]);
    }

    /**
     * @dev 设置分红池地址
     * @param _pool 分红池合约地址
     */
    function setDividendPool(address _pool) external onlyOwner {
        dividendPool = _pool;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "DividendManager: Invalid token contract");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 接收BNB（用于分红池充值）
     */
    receive() external payable {}

    /**
     * @dev 获取可领取分红
     */
    function getClaimableDividend(address user) external view returns (uint256) {
        return pendingDividends[user];
    }

    /**
     * @dev 获取用户权重
     */
    function getUserWeight(address user) external view returns (uint256) {
        return userWeights[user];
    }

    /**
     * @dev 获取总权重
     */
    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    /**
     * @dev 更新用户权重（旧版：直接设置权重）
     */
    function updateUserWeight(address user, uint256 weight) external onlyOwner {
        totalWeight = totalWeight - userWeights[user] + weight;
        userWeights[user] = weight;
    }

    /**
     * @dev 更新用户权重（新版：支持等级和元素计算）
     * @param user 用户地址
     * @param level NFT等级
     * @param isAdd 是否增加权重（true=增加，false=减少）
     * @param element 元素类型（0-4对应水风火暗光）
     */
    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external onlyOwner {
        uint256 weight = _calculateWeight(level, element);
        
        if (isAdd) {
            totalWeight += weight;
            userWeights[user] += weight;
        } else {
            totalWeight -= weight;
            userWeights[user] -= weight;
        }
    }

    /**
     * @dev 根据等级和元素计算权重
     */
    function _calculateWeight(uint256 level, uint8 element) internal pure returns (uint256) {
        bool isRare = (element == 3 || element == 4);
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            if (level > 0 && level <= 5) {
                return weights[level - 1];
            }
            return 76;
        } else {
            uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
            if (level > 0 && level <= 5) {
                return weights[level - 1];
            }
            return 66;
        }
    }

    /**
     * @dev 批量更新用户权重
     */
    function updateUserWeightsBatch(
        address[] calldata users,
        uint256[] calldata weights
    ) external onlyOwner {
        require(users.length == weights.length, "DividendManager: Length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            totalWeight = totalWeight - userWeights[users[i]] + weights[i];
            userWeights[users[i]] = weights[i];
        }
    }

    /**
     * @dev 计算分红
     */
    function calculateDividend(uint256 amount) external view returns (uint256) {
        if (totalWeight == 0) return 0;
        return amount / totalWeight;
    }

    /**
     * @dev 获取当前快照
     */
    function getCurrentSnapshot() external view returns (uint256, uint256, uint256) {
        if (snapshots.length == 0) {
            return (0, 0, 0);
        }
        DividendSnapshot memory snapshot = snapshots[snapshots.length - 1];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend);
    }
}