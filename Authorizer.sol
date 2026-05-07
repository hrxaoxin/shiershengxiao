// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Authorizer
 * @dev 授权管理合约，用于管理系统中各合约的权限
 * 支持添加/移除授权地址、检查授权状态等功能
 * 基于OpenZeppelin可升级合约实现
 */
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Authorizer
 * @dev 授权管理合约
 */
contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /** @dev 权限级别枚举 */
    enum PermissionLevel {
        NONE,       // 无权限
        OPERATOR,   // 操作员权限
        ADMIN,      // 管理员权限
        SUPER_ADMIN // 超级管理员权限
    }

    /** @dev 授权映射（地址 => 权限级别） */
    mapping(address => PermissionLevel) public permissions;

    /** @dev 授权事件 */
    event AddressAuthorized(address indexed addr, PermissionLevel level, uint256 timestamp);
    /** @dev 取消授权事件 */
    event AddressUnauthorized(address indexed addr, uint256 timestamp);
    /** @dev 权限级别更新事件 */
    event PermissionUpdated(address indexed addr, PermissionLevel oldLevel, PermissionLevel newLevel, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者地址
     */
    function initialize(address initialOwner) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        
        transferOwnership(initialOwner);
        
        // 将所有者设置为超级管理员
        permissions[initialOwner] = PermissionLevel.SUPER_ADMIN;
        emit AddressAuthorized(initialOwner, PermissionLevel.SUPER_ADMIN, block.timestamp);
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 授权地址
     * @param addr 要授权的地址
     * @param level 权限级别
     */
    function authorize(address addr, PermissionLevel level) external onlyOwner {
        require(addr != address(0), "Authorizer: Zero address");
        
        PermissionLevel oldLevel = permissions[addr];
        permissions[addr] = level;
        
        if (oldLevel == PermissionLevel.NONE) {
            emit AddressAuthorized(addr, level, block.timestamp);
        } else {
            emit PermissionUpdated(addr, oldLevel, level, block.timestamp);
        }
    }

    /**
     * @dev 批量授权地址
     * @param addrs 要授权的地址数组
     * @param levels 权限级别数组
     */
    function batchAuthorize(address[] calldata addrs, PermissionLevel[] calldata levels) external onlyOwner {
        require(addrs.length == levels.length, "Authorizer: Array length mismatch");
        
        for (uint256 i = 0; i < addrs.length; i++) {
            authorize(addrs[i], levels[i]);
        }
    }

    /**
     * @dev 取消授权地址
     * @param addr 要取消授权的地址
     */
    function unauthorize(address addr) external onlyOwner {
        require(permissions[addr] != PermissionLevel.NONE, "Authorizer: Address not authorized");
        
        permissions[addr] = PermissionLevel.NONE;
        emit AddressUnauthorized(addr, block.timestamp);
    }

    /**
     * @dev 批量取消授权地址
     * @param addrs 要取消授权的地址数组
     */
    function batchUnauthorize(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            unauthorize(addrs[i]);
        }
    }

    /**
     * @dev 检查地址是否有授权
     * @param addr 要检查的地址
     * @return 是否已授权
     */
    function isAuthorized(address addr) external view returns (bool) {
        return permissions[addr] != PermissionLevel.NONE;
    }

    /**
     * @dev 检查地址是否有指定级别或更高的权限
     * @param addr 要检查的地址
     * @param requiredLevel 要求的最低权限级别
     * @return 是否有足够的权限
     */
    function hasPermission(address addr, PermissionLevel requiredLevel) external view returns (bool) {
        PermissionLevel level = permissions[addr];
        return uint256(level) >= uint256(requiredLevel);
    }

    /**
     * @dev 获取地址的权限级别
     * @param addr 要查询的地址
     * @return 权限级别
     */
    function getPermissionLevel(address addr) external view returns (PermissionLevel) {
        return permissions[addr];
    }

    /**
     * @dev 获取权限级别的字符串表示
     * @param level 权限级别
     * @return 权限级别名称
     */
    function getPermissionLevelName(PermissionLevel level) external pure returns (string memory) {
        if (level == PermissionLevel.NONE) return "NONE";
        if (level == PermissionLevel.OPERATOR) return "OPERATOR";
        if (level == PermissionLevel.ADMIN) return "ADMIN";
        if (level == PermissionLevel.SUPER_ADMIN) return "SUPER_ADMIN";
        return "UNKNOWN";
    }
}