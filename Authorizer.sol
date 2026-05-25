// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Authorizer
 * @dev 权限管理合约，基于权重系统控制访问权限
 *
 * 权限系统：
 * 1. 每个用户有权重值
 * 2. 操作需要满足最小权重要求
 * 3. 支持批量更新权重
 *
 * 权重用途：
 * - 高级操作权限
 * - 分红权重计算
 * - 投票权重
 */
contract Authorizer {
    /**
     * @dev 用户权重映射
     */
    mapping(address => uint256) public weights;

    /**
     * @dev 总权重
     */
    uint256 public totalWeight;

    /**
     * @dev 管理员地址
     */
    address public admin;

    /**
     * @dev 权重事件
     */
    event WeightGranted(address indexed user, uint256 weight);
    event WeightRevoked(address indexed user);
    event WeightsUpdated(address[] users, uint256[] weights);

    /**
     * @dev 授予权限
     */
    function grantPermission(address user, uint256 weight) external {
        require(msg.sender == admin, "Authorizer: Not admin");

        if (weights[user] == 0) {
            totalWeight += weight;
        } else {
            totalWeight = totalWeight - weights[user] + weight;
        }

        weights[user] = weight;
        emit WeightGranted(user, weight);
    }

    /**
     * @dev 撤销权限
     */
    function revokePermission(address user) external {
        require(msg.sender == admin, "Authorizer: Not admin");

        totalWeight -= weights[user];
        weights[user] = 0;
        emit WeightRevoked(user);
    }

    /**
     * @dev 检查是否有权限
     */
    function hasPermission(address user, uint256 weightRequired) external view returns (bool) {
        return weights[user] >= weightRequired;
    }

    /**
     * @dev 获取用户权重
     */
    function getWeight(address user) external view returns (uint256) {
        return weights[user];
    }

    /**
     * @dev 获取总权重
     */
    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    /**
     * @dev 批量更新权重
     */
    function updateWeightsBatch(
        address[] calldata users,
        uint256[] calldata newWeights
    ) external {
        require(msg.sender == admin, "Authorizer: Not admin");
        require(users.length == newWeights.length, "Authorizer: Length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            if (weights[users[i]] > 0) {
                totalWeight = totalWeight - weights[users[i]] + newWeights[i];
            } else {
                totalWeight += newWeights[i];
            }
            weights[users[i]] = newWeights[i];
        }

        emit WeightsUpdated(users, newWeights);
    }

    /**
     * @dev 设置管理员
     */
    function setAdmin(address _admin) external {
        require(msg.sender == admin, "Authorizer: Not admin");
        admin = _admin;
    }
}
