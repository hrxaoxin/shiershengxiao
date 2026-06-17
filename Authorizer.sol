// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";
import "./AuthorizerLib.sol";

contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    error InvalidAuthorizer();
    error ContractPaused();
    error InvalidOldAuthorizer();
    error ContractNotSet(bytes32 key);

    bool public paused;
    string public pauseReason;

    mapping(bytes32 => address) private _addresses;
    /**
     * @dev 当前设置的 authorizer 地址（用于验证旧的 authorizer）
     */
    address public currentAuthorizer;

    /**
     * @dev 全局合约地址结构（用于快速查询）
     */
    AuthorizerLib.ContractAddresses public globalAddresses;

    event Paused(address account, string reason);
    event Unpaused(address account);
    event ContractAddressUpdated(bytes32 key, address value);
    event GlobalAddressesUpdated();

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getAddress(bytes32 key) external view returns (address) {
        return _addresses[key];
    }

    function setAddress(bytes32 key, address value) external onlyOwner whenNotPaused {
        _addresses[key] = value;
        emit ContractAddressUpdated(key, value);
    }

    function setAllContracts(AuthorizerLib.ContractAddresses calldata _addr) external onlyOwner whenNotPaused {
        _addresses[keccak256("token")] = _addr.token;
        _addresses[keccak256("usdt")] = _addr.usdt;
        _addresses[keccak256("nftMintCore")] = _addr.nftMintCore;
        _addresses[keccak256("nftMintBatch")] = _addr.nftMintBatch;
        _addresses[keccak256("nftMintMetadata")] = _addr.nftMintMetadata;
        _addresses[keccak256("nftUpdate")] = _addr.nftUpdate;
        _addresses[keccak256("nftData")] = _addr.nftData;
        _addresses[keccak256("tokenBurner")] = _addr.tokenBurner;
        _addresses[keccak256("nftTrading")] = _addr.nftTrading;
        _addresses[keccak256("nftBuyback")] = _addr.nftBuyback;
        _addresses[keccak256("staking")] = _addr.staking;
        _addresses[keccak256("tokenStaking")] = _addr.tokenStaking;
        _addresses[keccak256("rewardManager")] = _addr.rewardManager;
        _addresses[keccak256("dividendManager")] = _addr.dividendManager;
        _addresses[keccak256("poolManager")] = _addr.poolManager;
        _addresses[keccak256("priceOracle")] = _addr.priceOracle;
        _addresses[keccak256("battle")] = _addr.battle;
        _addresses[keccak256("battleSkillData")] = _addr.battleSkillData;
        _addresses[keccak256("battleHistory")] = _addr.battleHistory;
        _addresses[keccak256("breedingCore")] = _addr.breedingCore;
        _addresses[keccak256("breedingMarket")] = _addr.breedingMarket;
        _addresses[keccak256("weightManager")] = _addr.weightManager;
        _addresses[keccak256("arenaRankingManager")] = _addr.arenaRankingManager;
        _addresses[keccak256("arenaRankingQuery")] = _addr.arenaRankingQuery;
        _addresses[keccak256("arenaReward")] = _addr.arenaReward;
        _addresses[keccak256("arenaLeaderboard")] = _addr.arenaLeaderboard;
        _addresses[keccak256("arenaPlayer")] = _addr.arenaPlayer;
        _addresses[keccak256("arenaBattle")] = _addr.arenaBattle;
        _addresses[keccak256("feeReceiver")] = _addr.feeReceiver;
        _addresses[keccak256("pancakeSwapRouter")] = _addr.pancakeSwapRouter;

        // 更新全局合约地址结构（用于快速查询）
        globalAddresses = _addr;
        emit GlobalAddressesUpdated();
    }

    function setAllAuthorizers(
        address _expectedOldAuthorizer,
        address _newAuthorizer,
        AuthorizerLib.ContractAddresses calldata _contracts
    ) external onlyOwner whenNotPaused {
        if (_expectedOldAuthorizer != currentAuthorizer) revert InvalidOldAuthorizer();
        if (_newAuthorizer == address(0)) revert InvalidAuthorizer();
        
        // 更新全局合约地址结构
        globalAddresses = _contracts;
        emit GlobalAddressesUpdated();
        
        currentAuthorizer = _newAuthorizer;
        AuthorizerLib.setupAllAuthorizers(_newAuthorizer, _contracts);
    }

    /**
     * @dev 获取全局合约地址结构
     */
    function getGlobalAddresses() external view returns (AuthorizerLib.ContractAddresses memory) {
        return globalAddresses;
    }

    /**
     * @dev 获取指定合约地址
     * @param key 合约名称的 keccak256 hash
     */
    function getAddress(bytes32 key) external view returns (address) {
        return _addresses[key];
    }

    /**
     * @dev 设置单个合约地址
     */
    function setAddress(bytes32 key, address value) external onlyOwner whenNotPaused {
        _addresses[key] = value;
        emit ContractAddressUpdated(key, value);
    }

    // ==================== 便捷查询函数 ====================

    function getToken() external view returns (address) {
        return globalAddresses.token;
    }

    function getUSDT() external view returns (address) {
        return globalAddresses.usdt;
    }

    function getNFTMintCore() external view returns (address) {
        return globalAddresses.nftMintCore;
    }

    function getNFTMintBatch() external view returns (address) {
        return globalAddresses.nftMintBatch;
    }

    function getNFTMintMetadata() external view returns (address) {
        return globalAddresses.nftMintMetadata;
    }

    function getNFTUpdate() external view returns (address) {
        return globalAddresses.nftUpdate;
    }

    function getNFTData() external view returns (address) {
        return globalAddresses.nftData;
    }

    function getTokenBurner() external view returns (address) {
        return globalAddresses.tokenBurner;
    }

    function getNFTTrading() external view returns (address) {
        return globalAddresses.nftTrading;
    }

    function getNFTBuyback() external view returns (address) {
        return globalAddresses.nftBuyback;
    }

    function getStaking() external view returns (address) {
        return globalAddresses.staking;
    }

    function getTokenStaking() external view returns (address) {
        return globalAddresses.tokenStaking;
    }

    function getRewardManager() external view returns (address) {
        return globalAddresses.rewardManager;
    }

    function getDividendManager() external view returns (address) {
        return globalAddresses.dividendManager;
    }

    function getPoolManager() external view returns (address) {
        return globalAddresses.poolManager;
    }

    function getPriceOracle() external view returns (address) {
        return globalAddresses.priceOracle;
    }

    function getBattle() external view returns (address) {
        return globalAddresses.battle;
    }

    function getBattleSkillData() external view returns (address) {
        return globalAddresses.battleSkillData;
    }

    function getBattleHistory() external view returns (address) {
        return globalAddresses.battleHistory;
    }

    function getBreedingCore() external view returns (address) {
        return globalAddresses.breedingCore;
    }

    function getBreedingMarket() external view returns (address) {
        return globalAddresses.breedingMarket;
    }

    function getWeightManager() external view returns (address) {
        return globalAddresses.weightManager;
    }

    function getArenaRankingManager() external view returns (address) {
        return globalAddresses.arenaRankingManager;
    }

    function getArenaRankingQuery() external view returns (address) {
        return globalAddresses.arenaRankingQuery;
    }

    function getArenaReward() external view returns (address) {
        return globalAddresses.arenaReward;
    }

    function getArenaLeaderboard() external view returns (address) {
        return globalAddresses.arenaLeaderboard;
    }

    function getArenaPlayer() external view returns (address) {
        return globalAddresses.arenaPlayer;
    }

    function getArenaBattle() external view returns (address) {
        return globalAddresses.arenaBattle;
    }

    function getFeeReceiver() external view returns (address) {
        return globalAddresses.feeReceiver;
    }

    function getPancakeSwapRouter() external view returns (address) {
        return globalAddresses.pancakeSwapRouter;
    }
}