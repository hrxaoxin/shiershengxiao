// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    enum PermissionLevel { NONE, OPERATOR, ADMIN, SUPER_ADMIN }

    mapping(address => PermissionLevel) public permissions;

    event AddressAuthorized(address indexed addr, PermissionLevel level, uint256 timestamp);
    event AddressUnauthorized(address indexed addr, uint256 timestamp);
    event PermissionUpdated(address indexed addr, PermissionLevel oldLevel, PermissionLevel newLevel, uint256 timestamp);

    constructor() { _disableInitializers(); }

    function initialize(address initialOwner) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        transferOwnership(initialOwner);
        permissions[initialOwner] = PermissionLevel.SUPER_ADMIN;
        emit AddressAuthorized(initialOwner, PermissionLevel.SUPER_ADMIN, block.timestamp);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _authorize(address addr, PermissionLevel level) internal {
        require(addr != address(0), "Zero address");
        PermissionLevel oldLevel = permissions[addr];
        permissions[addr] = level;
        if (oldLevel == PermissionLevel.NONE) {
            emit AddressAuthorized(addr, level, block.timestamp);
        } else {
            emit PermissionUpdated(addr, oldLevel, level, block.timestamp);
        }
    }

    function authorize(address addr, PermissionLevel level) external onlyOwner { _authorize(addr, level); }

    function batchAuthorize(address[] calldata addrs, PermissionLevel[] calldata levels) external onlyOwner {
        require(addrs.length == levels.length, "Length mismatch");
        for (uint256 i = 0; i < addrs.length; i++) { _authorize(addrs[i], levels[i]); }
    }

    function _unauthorize(address addr) internal {
        require(permissions[addr] != PermissionLevel.NONE, "Not authorized");
        permissions[addr] = PermissionLevel.NONE;
        emit AddressUnauthorized(addr, block.timestamp);
    }

    function unauthorize(address addr) external onlyOwner { _unauthorize(addr); }

    function batchUnauthorize(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) { _unauthorize(addrs[i]); }
    }

    function isAuthorized(address addr) external view returns (bool) { return permissions[addr] != PermissionLevel.NONE; }

    function hasPermission(address addr, PermissionLevel requiredLevel) external view returns (bool) {
        return uint256(permissions[addr]) >= uint256(requiredLevel);
    }

    function getPermissionLevel(address addr) external view returns (PermissionLevel) { return permissions[addr]; }

    function getPermissionLevelName(PermissionLevel level) external pure returns (string memory) {
        if (level == PermissionLevel.NONE) return "NONE";
        if (level == PermissionLevel.OPERATOR) return "OPERATOR";
        if (level == PermissionLevel.ADMIN) return "ADMIN";
        if (level == PermissionLevel.SUPER_ADMIN) return "SUPER_ADMIN";
        return "UNKNOWN";
    }

    function authCore(address burner, address reward, address nftData, address mint, address token) external onlyOwner {
        require(burner != address(0) && reward != address(0) && nftData != address(0) && mint != address(0) && token != address(0), "Zero addr");
        
        ITokenBurner(burner).setAuthorizedNFTContract(mint);
        ITokenBurner(burner).setTokenContract(token);
        
        IRewardManagerExt(reward).setAuthorizedNFTContract(mint, true);
        IRewardManagerExt(reward).setNFTContract(mint);
        IRewardManagerExt(reward).setNFTDataContract(nftData);
        IRewardManagerExt(reward).setAuthorizer(address(this));
        
        INFTDataInterface(nftData).setAuthorizedNFTContract(mint);
        
        INFTMint(mint).setAddresses(burner, reward);
        INFTMint(mint).setMetadataContract(nftData);
        INFTMint(mint).setTokenContract(token);
    }

    function authRewardSub(address reward, address staking, address tokenStaking, address arena) external onlyOwner {
        if (staking != address(0)) IRewardManagerExt(reward).setStakingContract(staking);
        if (tokenStaking != address(0)) IRewardManagerExt(reward).setTokenStakingContract(tokenStaking);
        if (arena != address(0)) IRewardManagerExt(reward).setArenaContract(arena);
    }

    function authTrading(address trading, address mint, address reward) external onlyOwner {
        if (trading != address(0)) {
            INFTTrading(trading).setNFTContract(mint);
            INFTTrading(trading).setRewardManager(reward);
        }
    }

    function authBreeding(address breeding, address mint, address arena) external onlyOwner {
        if (breeding != address(0)) {
            IBreeding(breeding).setNFTContract(mint);
            INFTMint(mint).setBreedingContract(breeding);
            IBreeding(breeding).setAuthorizer(address(this));
            if (arena != address(0)) IBreeding(breeding).setArenaRankingContract(arena);
        }
    }

    function authStaking(address staking, address mint, address token, address arena) external onlyOwner {
        if (staking != address(0)) {
            IStaking(staking).setNFTContract(mint);
            IStaking(staking).setTokenContract(token);
            IStaking(staking).setAuthorizer(address(this));
            if (arena != address(0)) IStaking(staking).setArenaRankingContract(arena);
        }
    }

    function authUpdate(address update, address mint, address nftData, address token, address pair) external onlyOwner {
        if (update != address(0)) {
            INFTMint(mint).setNFTUpdateContract(update);
            INFTUpdate(update).setNFTContract(mint);
            INFTUpdate(update).setMetadataContract(nftData);
            INFTUpdate(update).setTokenContract(token);
            INFTUpdate(update).setAuthorizer(address(this));
            if (pair != address(0)) INFTUpdate(update).setPancakeSwapPair(pair);
        }
    }

    function authTokenStaking(address tokenStaking, address token) external onlyOwner {
        if (tokenStaking != address(0)) ITokenStaking(tokenStaking).setTokenContract(token);
    }

    function authBattle(address battle, address mint) external onlyOwner {
        if (battle != address(0)) IBattle(battle).setNFTContract(mint);
    }

    function authArena(address arena, address battle) external onlyOwner {
        if (arena != address(0) && battle != address(0)) IArenaRanking(arena).setBattleContract(battle);
    }
}
