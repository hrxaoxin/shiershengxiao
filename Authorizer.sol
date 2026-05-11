// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    enum PermissionLevel {
        NONE,
        OPERATOR,
        ADMIN,
        SUPER_ADMIN
    }

    mapping(address => PermissionLevel) public permissions;

    event AddressAuthorized(address indexed addr, PermissionLevel level, uint256 timestamp);
    event AddressUnauthorized(address indexed addr, uint256 timestamp);
    event PermissionUpdated(address indexed addr, PermissionLevel oldLevel, PermissionLevel newLevel, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        transferOwnership(initialOwner);
        permissions[initialOwner] = PermissionLevel.SUPER_ADMIN;
        emit AddressAuthorized(initialOwner, PermissionLevel.SUPER_ADMIN, block.timestamp);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // 【内部核心函数】无权限校验，仅处理逻辑
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

    // 外部授权函数：保留onlyOwner权限校验
    function authorize(address addr, PermissionLevel level) external onlyOwner {
        _authorize(addr, level);
    }

    // 批量授权：直接调用内部函数
    function batchAuthorize(address[] calldata addrs, PermissionLevel[] calldata levels) external onlyOwner {
        require(addrs.length == levels.length, "Authorizer: Array length mismatch");
        for (uint256 i = 0; i < addrs.length; i++) {
            _authorize(addrs[i], levels[i]);
        }
    }

    // 【内部核心函数】无权限校验，仅处理逻辑
    function _unauthorize(address addr) internal {
        require(permissions[addr] != PermissionLevel.NONE, "Authorizer: Address not authorized");
        permissions[addr] = PermissionLevel.NONE;
        emit AddressUnauthorized(addr, block.timestamp);
    }

    // 外部取消授权函数：保留onlyOwner权限校验
    function unauthorize(address addr) external onlyOwner {
        _unauthorize(addr);
    }

    // 批量取消授权：直接调用内部函数
    function batchUnauthorize(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            _unauthorize(addrs[i]);
        }
    }

    function isAuthorized(address addr) external view returns (bool) {
        return permissions[addr] != PermissionLevel.NONE;
    }

    function hasPermission(address addr, PermissionLevel requiredLevel) external view returns (bool) {
        PermissionLevel level = permissions[addr];
        return uint256(level) >= uint256(requiredLevel);
    }

    function getPermissionLevel(address addr) external view returns (PermissionLevel) {
        return permissions[addr];
    }

    function getPermissionLevelName(PermissionLevel level) external pure returns (string memory) {
        if (level == PermissionLevel.NONE) return "NONE";
        if (level == PermissionLevel.OPERATOR) return "OPERATOR";
        if (level == PermissionLevel.ADMIN) return "ADMIN";
        if (level == PermissionLevel.SUPER_ADMIN) return "SUPER_ADMIN";
        return "UNKNOWN";
    }

    function authorizeAll(
        address tokenBurner,
        address rewardManager,
        address nftTrading,
        address nftData,
        address nftMint,
        address breeding,
        address staking,
        address tokenContract
    ) external onlyOwner {
        require(tokenBurner != address(0), "TokenBurner address cannot be zero");
        require(rewardManager != address(0), "RewardManager address cannot be zero");
        require(nftData != address(0), "NFTData address cannot be zero");
        require(nftMint != address(0), "NFTMint address cannot be zero");
        require(tokenContract != address(0), "Token contract address cannot be zero");

        ITokenBurner(tokenBurner).setAuthorizedNFTContract(nftMint);
        ITokenBurner(tokenBurner).setTokenContract(tokenContract);
        IRewardManager(rewardManager).setAuthorizedNFTContract(nftMint, true);
        IRewardManager(rewardManager).setNFTContract(nftMint);

        if (nftTrading != address(0)) {
            INFTTrading(nftTrading).setNFTContract(nftMint);
            INFTTrading(nftTrading).setRewardManager(rewardManager);
        }

        INFTDataInterface(nftData).setAuthorizedNFTContract(nftMint);
        INFTMint(nftMint).setAddresses(tokenBurner, rewardManager);
        INFTMint(nftMint).setMetadataContract(nftData);
        INFTMint(nftMint).setTokenContract(tokenContract);

        if (breeding != address(0)) {
            IBreeding(breeding).setNFTContract(nftMint);
            INFTMint(nftMint).setBreedingContract(breeding);
        }

        if (staking != address(0)) {
            IStaking(staking).setNFTContract(nftMint);
            IStaking(staking).setTokenContract(tokenContract);
        }
    }
}