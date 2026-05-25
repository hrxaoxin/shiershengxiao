// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
contract DividendManager {
    /**
     * @dev 用户权重映射
     * user => weight
     */
    mapping(address => uint256) public userWeights;

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
     * @dev 添加到分红池
     */
    function addDividendPool(uint256 amount) external {
        require(amount > 0, "DividendManager: Invalid amount");
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
        return dividend;
    }

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
     * @dev 更新用户权重
     */
    function updateUserWeight(address user, uint256 weight) external {
        totalWeight = totalWeight - userWeights[user] + weight;
        userWeights[user] = weight;
    }

    /**
     * @dev 批量更新用户权重
     */
    function updateUserWeightsBatch(
        address[] calldata users,
        uint256[] calldata weights
    ) external {
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
