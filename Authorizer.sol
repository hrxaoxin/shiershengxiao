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
    address public currentAuthorizer;

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

    /**
     * @dev 检查一个地址是否是系统合约（在 authorizer 中注册的合约）
     * @param addr 要检查的地址
     * @return 是否是系统合约
     */
    function isSystemContract(address addr) external view returns (bool) {
        if (addr == address(0)) return false;
        if (addr == owner()) return true;
        if (addr == address(this)) return true;
        
        // 检查所有注册的合约地址
        return 
            addr == _addresses[keccak256("token")] ||
            addr == _addresses[keccak256("nftMintCore")] ||
            addr == _addresses[keccak256("nftMintMetadata")] ||
            addr == _addresses[keccak256("nftUpdate")] ||
            addr == _addresses[keccak256("nftData")] ||
            addr == _addresses[keccak256("tokenBurner")] ||
            addr == _addresses[keccak256("nftTrading")] ||
            addr == _addresses[keccak256("nftBuyback")] ||
            addr == _addresses[keccak256("staking")] ||
            addr == _addresses[keccak256("tokenStaking")] ||
            addr == _addresses[keccak256("rewardManager")] ||
            addr == _addresses[keccak256("dividendManager")] ||
            addr == _addresses[keccak256("poolManager")] ||
            addr == _addresses[keccak256("weightManager")] ||
            addr == _addresses[keccak256("breedingCore")] ||
            addr == _addresses[keccak256("breedingMarket")] ||
            addr == _addresses[keccak256("battle")] ||
            addr == _addresses[keccak256("arena")] ||
            addr == _addresses[keccak256("arenaPlayer")] ||
            addr == _addresses[keccak256("arenaReward")] ||
            addr == _addresses[keccak256("arenaLeaderboard")] ||
            addr == _addresses[keccak256("arenaBattle")] ||
            addr == _addresses[keccak256("priceOracle")];
    }

    /**
     * @dev 简单版设置单个合约地址（使用字符串名称）
     * @param name 合约名称，如 "nftTrading", "nftMintCore", "token" 等
     * @param value 合约地址
     */
    function setContractAddress(string calldata name, address value) external onlyOwner whenNotPaused {
        bytes32 key = keccak256(abi.encodePacked(name));
        _addresses[key] = value;
        emit ContractAddressUpdated(key, value);
    }

    /**
     * @dev 批量设置多个合约地址（使用字符串名称）
     * @param names 合约名称数组
     * @param values 合约地址数组
     */
    function setMultipleAddresses(string[] calldata names, address[] calldata values) external onlyOwner whenNotPaused {
        require(names.length == values.length, "Authorizer: arrays length mismatch");
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(names[i]));
            _addresses[key] = values[i];
            emit ContractAddressUpdated(key, values[i]);
        }
    }

    function setAllContracts(address[] calldata _addr) external onlyOwner whenNotPaused {
        _setAddresses(_addr);
        emit GlobalAddressesUpdated();
    }

    function _setAddresses(address[] calldata _addr) internal {
        _setCoreAddresses(_addr);
        _setNFTAddresses(_addr);
        _setStakingAddresses(_addr);
        _setBattleAddresses(_addr);
        _setBreedingAddresses(_addr);
        _setArenaAddresses(_addr);
        _setOtherAddresses(_addr);
    }

    function _setCoreAddresses(address[] calldata _addr) private {
        _addresses[keccak256("token")] = _addr[0];
        _addresses[keccak256("usdt")] = _addr[1];
        _addresses[keccak256("rewardManager")] = _addr[11];
        _addresses[keccak256("dividendManager")] = _addr[12];
        _addresses[keccak256("poolManager")] = _addr[13];
        _addresses[keccak256("priceOracle")] = _addr[14];
    }

    function _setNFTAddresses(address[] calldata _addr) private {
        _addresses[keccak256("nftMintCore")] = _addr[2];
        _addresses[keccak256("nftMintMetadata")] = _addr[3];
        _addresses[keccak256("nftUpdate")] = _addr[4];
        _addresses[keccak256("nftData")] = _addr[5];
        _addresses[keccak256("tokenBurner")] = _addr[6];
        _addresses[keccak256("nftTrading")] = _addr[7];
        _addresses[keccak256("nftBuyback")] = _addr[8];
    }

    function _setStakingAddresses(address[] calldata _addr) private {
        _addresses[keccak256("staking")] = _addr[9];
        _addresses[keccak256("tokenStaking")] = _addr[10];
        _addresses[keccak256("weightManager")] = _addr[20];
    }

    function _setBattleAddresses(address[] calldata _addr) private {
        _addresses[keccak256("battle")] = _addr[15];
        _addresses[keccak256("battleSkillData")] = _addr[16];
        _addresses[keccak256("battleHistory")] = _addr[17];
    }

    function _setBreedingAddresses(address[] calldata _addr) private {
        _addresses[keccak256("breedingCore")] = _addr[18];
        _addresses[keccak256("breedingMarket")] = _addr[19];
    }

    function _setArenaAddresses(address[] calldata _addr) private {
        _addresses[keccak256("arenaRankingManager")] = _addr[21];
        _addresses[keccak256("arenaRankingQuery")] = _addr[22];
        _addresses[keccak256("arenaReward")] = _addr[23];
        _addresses[keccak256("arenaLeaderboard")] = _addr[24];
        _addresses[keccak256("arenaPlayer")] = _addr[25];
        _addresses[keccak256("arenaBattle")] = _addr[26];
    }

    function _setOtherAddresses(address[] calldata _addr) private {
        _addresses[keccak256("feeReceiver")] = _addr[27];
        _addresses[keccak256("pancakeSwapRouter")] = _addr[28];
        _addresses[keccak256("flapSwapRouter")] = _addr[29];
        _addresses[keccak256("uniswapRouter")] = _addr[30];
        _addresses[keccak256("wbnb")] = _addr[31];
    }

    function setAllAuthorizers(
        address _expectedOldAuthorizer,
        address _newAuthorizer,
        address[] calldata _contracts
    ) external onlyOwner whenNotPaused {
        if (_expectedOldAuthorizer != currentAuthorizer) revert InvalidOldAuthorizer();
        if (_newAuthorizer == address(0)) revert InvalidAuthorizer();
        
        _setAddresses(_contracts);
        emit GlobalAddressesUpdated();
        
        currentAuthorizer = _newAuthorizer;
        AuthorizerLib.setupAllAuthorizers(_newAuthorizer, _contracts);
    }

    function getToken() external view returns (address) {
        return _addresses[keccak256("token")];
    }

    function getUSDT() external view returns (address) {
        return _addresses[keccak256("usdt")];
    }

    function getNFTMintCore() external view returns (address) {
        return _addresses[keccak256("nftMintCore")];
    }
    function getNFTMintMetadata() external view returns (address) {
        return _addresses[keccak256("nftMintMetadata")];
    }

    function getNFTUpdate() external view returns (address) {
        return _addresses[keccak256("nftUpdate")];
    }

    function getNFTData() external view returns (address) {
        return _addresses[keccak256("nftData")];
    }

    function getTokenBurner() external view returns (address) {
        return _addresses[keccak256("tokenBurner")];
    }

    function getNFTTrading() external view returns (address) {
        return _addresses[keccak256("nftTrading")];
    }

    function getNFTBuyback() external view returns (address) {
        return _addresses[keccak256("nftBuyback")];
    }

    function getStaking() external view returns (address) {
        return _addresses[keccak256("staking")];
    }

    function getTokenStaking() external view returns (address) {
        return _addresses[keccak256("tokenStaking")];
    }

    function getRewardManager() external view returns (address) {
        return _addresses[keccak256("rewardManager")];
    }

    function getDividendManager() external view returns (address) {
        return _addresses[keccak256("dividendManager")];
    }

    function getPoolManager() external view returns (address) {
        return _addresses[keccak256("poolManager")];
    }

    function getPriceOracle() external view returns (address) {
        return _addresses[keccak256("priceOracle")];
    }

    function getBattle() external view returns (address) {
        return _addresses[keccak256("battle")];
    }

    function getBattleSkillData() external view returns (address) {
        return _addresses[keccak256("battleSkillData")];
    }

    function getBattleHistory() external view returns (address) {
        return _addresses[keccak256("battleHistory")];
    }

    function getBreedingCore() external view returns (address) {
        return _addresses[keccak256("breedingCore")];
    }

    function getBreedingMarket() external view returns (address) {
        return _addresses[keccak256("breedingMarket")];
    }

    function getWeightManager() external view returns (address) {
        return _addresses[keccak256("weightManager")];
    }

    function getArenaRankingManager() external view returns (address) {
        return _addresses[keccak256("arenaRankingManager")];
    }

    function getArenaRankingQuery() external view returns (address) {
        return _addresses[keccak256("arenaRankingQuery")];
    }

    function getArenaReward() external view returns (address) {
        return _addresses[keccak256("arenaReward")];
    }

    function getArenaLeaderboard() external view returns (address) {
        return _addresses[keccak256("arenaLeaderboard")];
    }

    function getArenaPlayer() external view returns (address) {
        return _addresses[keccak256("arenaPlayer")];
    }

    function getArenaBattle() external view returns (address) {
        return _addresses[keccak256("arenaBattle")];
    }

    function getFeeReceiver() external view returns (address) {
        return _addresses[keccak256("feeReceiver")];
    }

    function getPancakeSwapRouter() external view returns (address) {
        return _addresses[keccak256("pancakeSwapRouter")];
    }

    function getFlapSwapRouter() external view returns (address) {
        return _addresses[keccak256("flapSwapRouter")];
    }

    function getUniswapRouter() external view returns (address) {
        return _addresses[keccak256("uniswapRouter")];
    }

    function getWBNB() external view returns (address) {
        return _addresses[keccak256("wbnb")];
    }
}