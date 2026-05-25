// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

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
 *
 * 功能特性：
 * - 支持多个独立资金池
 * - 紧急暂停功能
 * - 管理员提取权限
 * - 支持UUPS升级
 */
contract PoolManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 池子余额映射
     * poolType => balance
     */
    mapping(uint256 => uint256) public poolBalances;

    /**
     * @dev 紧急暂停标志
     */
    bool public paused;

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
        require(msg.sender == owner() || msg.sender == authorizer, "PoolManager: Not authorized");
        _;
    }

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
     * @param amount 提取数量
     */
    function withdrawFromNFTStakingPool(uint256 amount) external onlyOwner {
        require(poolBalances[0] >= amount, "PoolManager: Insufficient balance");
        poolBalances[0] -= amount;
    }

    /**
     * @dev 从代币质押池提取
     * @param amount 提取数量
     */
    function withdrawFromTokenStakingPool(uint256 amount) external onlyOwner {
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
     * @dev 紧急提取（仅用于极端情况）
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 提取数量
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "PoolManager: Invalid address");
        poolBalances[0] -= amount;
    }

    /**
     * @dev 暂停/恢复合约功能
     * @param _paused 是否暂停
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
}
