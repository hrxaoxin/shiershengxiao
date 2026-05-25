// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PoolManager
 * @dev 资金池管理合约，管理游戏的各种奖励池
 *
 * 池子类型：
 * - 0: NFT质押池
 * - 1: 代币质押池
 * - 2: 竞技场奖励池
 *
 * 资金来源：
 * - 交易手续费
 * - 战斗费用
 * - 繁殖费用
 */
contract PoolManager {
    /**
     * @dev 池子余额映射
     * poolType => balance
     */
    mapping(uint256 => uint256) public poolBalances;

    /**
     * @dev 管理员地址
     */
    address public admin;

    /**
     * @dev 紧急暂停标志
     */
    bool public paused;

    /**
     * @dev 添加到NFT质押池
     */
    function addToNFTStakingPool(uint256 amount) external {
        require(!paused, "PoolManager: Paused");
        require(amount > 0, "PoolManager: Invalid amount");
        poolBalances[0] += amount;
    }

    /**
     * @dev 添加到代币质押池
     */
    function addToTokenStakingPool(uint256 amount) external {
        require(!paused, "PoolManager: Paused");
        require(amount > 0, "PoolManager: Invalid amount");
        poolBalances[1] += amount;
    }

    /**
     * @dev 添加到竞技场奖励池
     */
    function addToArenaRewardPool(uint256 amount) external {
        require(!paused, "PoolManager: Paused");
        require(amount > 0, "PoolManager: Invalid amount");
        poolBalances[2] += amount;
    }

    /**
     * @dev 从NFT质押池提取
     */
    function withdrawFromNFTStakingPool(uint256 amount) external {
        require(msg.sender == admin, "PoolManager: Not admin");
        require(poolBalances[0] >= amount, "PoolManager: Insufficient balance");
        poolBalances[0] -= amount;
    }

    /**
     * @dev 从代币质押池提取
     */
    function withdrawFromTokenStakingPool(uint256 amount) external {
        require(msg.sender == admin, "PoolManager: Not admin");
        require(poolBalances[1] >= amount, "PoolManager: Insufficient balance");
        poolBalances[1] -= amount;
    }

    /**
     * @dev 获取池子余额
     */
    function getPoolBalance(uint256 poolType) external view returns (uint256) {
        return poolBalances[poolType];
    }

    /**
     * @dev 紧急提取
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external {
        require(msg.sender == admin, "PoolManager: Not admin");
        require(to != address(0), "PoolManager: Invalid address");
        poolBalances[0] -= amount;
    }

    /**
     * @dev 设置管理员
     */
    function setAdmin(address _admin) external {
        require(msg.sender == admin, "PoolManager: Not admin");
        admin = _admin;
    }

    /**
     * @dev 暂停/恢复
     */
    function setPaused(bool _paused) external {
        require(msg.sender == admin, "PoolManager: Not admin");
        paused = _paused;
    }
}
