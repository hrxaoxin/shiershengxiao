// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title Authorizer
 * @dev 授权管理合约，负责管理系统权限和批量设置合约关联
 * 支持四级权限体系：NONE、OPERATOR、ADMIN、SUPER_ADMIN
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 权限等级枚举
     * NONE: 无权限
     * OPERATOR: 操作员权限（日常操作）
     * ADMIN: 管理员权限（管理功能）
     * SUPER_ADMIN: 超级管理员权限（最高权限）
     */
    enum PermissionLevel {
        NONE,
        OPERATOR,
        ADMIN,
        SUPER_ADMIN
    }

    /** @dev 用户权限映射（地址 => 权限等级） */
    mapping(address => PermissionLevel) public permissions;

    /**
     * @dev 地址授权事件
     * @param addr 被授权地址
     * @param level 授权等级
     * @param timestamp 时间戳
     */
    event AddressAuthorized(address indexed addr, PermissionLevel level, uint256 timestamp);
    
    /**
     * @dev 地址取消授权事件
     * @param addr 被取消授权地址
     * @param timestamp 时间戳
     */
    event AddressUnauthorized(address indexed addr, uint256 timestamp);
    
    /**
     * @dev 权限更新事件
     * @param addr 地址
     * @param oldLevel 旧权限等级
     * @param newLevel 新权限等级
     * @param timestamp 时间戳
     */
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
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        transferOwnership(initialOwner);
        permissions[initialOwner] = PermissionLevel.SUPER_ADMIN;
        emit AddressAuthorized(initialOwner, PermissionLevel.SUPER_ADMIN, block.timestamp);
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 内部授权函数（无权限校验，仅处理逻辑）
     * @param addr 授权地址
     * @param level 权限等级
     */
    function _authorize(address addr, PermissionLevel level) internal {
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
     * @dev 外部授权函数（带onlyOwner权限校验）
     * @param addr 授权地址
     * @param level 权限等级
     */
    function authorize(address addr, PermissionLevel level) external onlyOwner {
        _authorize(addr, level);
    }

    /**
     * @dev 批量授权函数
     * @param addrs 授权地址数组
     * @param levels 权限等级数组（与地址数组一一对应）
     */
    function batchAuthorize(address[] calldata addrs, PermissionLevel[] calldata levels) external onlyOwner {
        require(addrs.length == levels.length, "Authorizer: Array length mismatch");
        for (uint256 i = 0; i < addrs.length; i++) {
            _authorize(addrs[i], levels[i]);
        }
    }

    /**
     * @dev 内部取消授权函数（无权限校验，仅处理逻辑）
     * @param addr 取消授权地址
     */
    function _unauthorize(address addr) internal {
        require(permissions[addr] != PermissionLevel.NONE, "Authorizer: Address not authorized");
        permissions[addr] = PermissionLevel.NONE;
        emit AddressUnauthorized(addr, block.timestamp);
    }

    /**
     * @dev 外部取消授权函数（带onlyOwner权限校验）
     * @param addr 取消授权地址
     */
    function unauthorize(address addr) external onlyOwner {
        _unauthorize(addr);
    }

    /**
     * @dev 批量取消授权函数
     * @param addrs 取消授权地址数组
     */
    function batchUnauthorize(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            _unauthorize(addrs[i]);
        }
    }

    /**
     * @dev 检查地址是否已授权
     * @param addr 检查地址
     * @return bool 是否已授权
     */
    function isAuthorized(address addr) external view returns (bool) {
        return permissions[addr] != PermissionLevel.NONE;
    }

    /**
     * @dev 检查地址是否具有指定权限等级
     * @param addr 检查地址
     * @param requiredLevel 需要的权限等级
     * @return bool 是否具有指定权限
     */
    function hasPermission(address addr, PermissionLevel requiredLevel) external view returns (bool) {
        PermissionLevel level = permissions[addr];
        return uint256(level) >= uint256(requiredLevel);
    }

    /**
     * @dev 获取地址的权限等级
     * @param addr 地址
     * @return PermissionLevel 权限等级
     */
    function getPermissionLevel(address addr) external view returns (PermissionLevel) {
        return permissions[addr];
    }

    /**
     * @dev 将权限等级转换为可读字符串
     * @param level 权限等级
     * @return string memory 权限等级名称
     */
    function getPermissionLevelName(PermissionLevel level) external pure returns (string memory) {
        if (level == PermissionLevel.NONE) return "NONE";
        if (level == PermissionLevel.OPERATOR) return "OPERATOR";
        if (level == PermissionLevel.ADMIN) return "ADMIN";
        if (level == PermissionLevel.SUPER_ADMIN) return "SUPER_ADMIN";
        return "UNKNOWN";
    }

    /**
     * @dev 一键设置所有合约关联
     * 批量配置系统中所有合约的相互关联关系，简化部署流程
     * 
     * @param tokenBurner TokenBurner合约地址
     * @param rewardManager RewardManager合约地址
     * @param nftTrading NFTTrading合约地址（可选）
     * @param nftData NFTData合约地址
     * @param nftMint NFTMint合约地址
     * @param breeding Breeding合约地址（可选）
     * @param staking Staking合约地址（可选）
     * @param tokenContract 代币合约地址
     * @param nftUpdate NFTUpdate合约地址（可选）
     * @param pancakeSwapPair PancakeSwap流动性池地址（可选）
     * @param tokenStaking TokenStaking合约地址（可选）
     * @param battle Battle合约地址（可选）
     * @param arenaRanking ArenaRanking合约地址（可选）
     */
    function authorizeAll(
        address tokenBurner,
        address rewardManager,
        address nftTrading,
        address nftData,
        address nftMint,
        address breeding,
        address staking,
        address tokenContract,
        address nftUpdate,
        address pancakeSwapPair,
        address tokenStaking,
        address battle,
        address arenaRanking
    ) external onlyOwner {
        require(tokenBurner != address(0), "TokenBurner address cannot be zero");
        require(rewardManager != address(0), "RewardManager address cannot be zero");
        require(nftData != address(0), "NFTData address cannot be zero");
        require(nftMint != address(0), "NFTMint address cannot be zero");
        require(tokenContract != address(0), "Token contract address cannot be zero");

        // 配置TokenBurner
        ITokenBurner(tokenBurner).setAuthorizedNFTContract(nftMint);
        ITokenBurner(tokenBurner).setTokenContract(tokenContract);

        // 配置RewardManager
        IRewardManagerExt(rewardManager).setAuthorizedNFTContract(nftMint, true);
        IRewardManagerExt(rewardManager).setNFTContract(nftMint);
        IRewardManagerExt(rewardManager).setNFTDataContract(nftData);
        IRewardManagerExt(rewardManager).setAuthorizer(address(this));

        // 配置RewardManager的子合约（可选）
        if (staking != address(0)) {
            IRewardManagerExt(rewardManager).setStakingContract(staking);
        }
        if (tokenStaking != address(0)) {
            IRewardManagerExt(rewardManager).setTokenStakingContract(tokenStaking);
        }
        if (arenaRanking != address(0)) {
            IRewardManagerExt(rewardManager).setArenaContract(arenaRanking);
        }

        // 配置NFTTrading（可选）
        if (nftTrading != address(0)) {
            INFTTrading(nftTrading).setNFTContract(nftMint);
            INFTTrading(nftTrading).setRewardManager(rewardManager);
        }

        // 配置NFTData
        INFTDataInterface(nftData).setAuthorizedNFTContract(nftMint);

        // 配置NFTMint
        INFTMint(nftMint).setAddresses(tokenBurner, rewardManager);
        INFTMint(nftMint).setMetadataContract(nftData);
        INFTMint(nftMint).setTokenContract(tokenContract);

        // 配置Breeding（可选）
        if (breeding != address(0)) {
            IBreeding(breeding).setNFTContract(nftMint);
            INFTMint(nftMint).setBreedingContract(breeding);
            IBreeding(breeding).setAuthorizer(address(this));
            if (arenaRanking != address(0)) {
                IBreeding(breeding).setArenaRankingContract(arenaRanking);
            }
        }

        // 配置Staking（可选）
        if (staking != address(0)) {
            IStaking(staking).setNFTContract(nftMint);
            IStaking(staking).setTokenContract(tokenContract);
            IStaking(staking).setAuthorizer(address(this));
            if (arenaRanking != address(0)) {
                IStaking(staking).setArenaRankingContract(arenaRanking);
            }
        }

        // 配置NFTUpdate（可选）
        if (nftUpdate != address(0)) {
            INFTMint(nftMint).setNFTUpdateContract(nftUpdate);
            INFTUpdate(nftUpdate).setNFTContract(nftMint);
            INFTUpdate(nftUpdate).setMetadataContract(nftData);
            INFTUpdate(nftUpdate).setTokenContract(tokenContract);
            INFTUpdate(nftUpdate).setAuthorizer(address(this));
            if (pancakeSwapPair != address(0)) {
                INFTUpdate(nftUpdate).setPancakeSwapPair(pancakeSwapPair);
            }
        }

        // 配置TokenStaking（可选）
        if (tokenStaking != address(0)) {
            ITokenStaking(tokenStaking).setTokenContract(tokenContract);
        }

        // 配置Battle（可选）
        if (battle != address(0)) {
            IBattle(battle).setNFTContract(nftMint);
        }

        // 配置ArenaRanking（可选）
        if (arenaRanking != address(0) && battle != address(0)) {
            IArenaRanking(arenaRanking).setBattleContract(battle);
        }
    }
}
