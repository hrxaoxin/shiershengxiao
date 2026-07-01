// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";
import "./AuthorizerLib.sol";

/**
 * @title Authorizer
 * @dev 授权管理器合约，统一管理所有合约地址的注册和验证
 *
 * 核心职责：
 * 1. 地址管理：存储和提供所有游戏合约的地址映射
 * 2. 系统合约验证：验证调用者是否为合法的系统合约
 * 3. 全局暂停：支持全局暂停所有合约操作
 *
 * 主要地址类型：
 * - 代币相关：token, usdt, wbnb
 * - NFT相关：nftMintCore, nftMintMetadata, nftData, nftUpdate
 * - 质押相关：staking, tokenStaking
 * - 奖励相关：rewardManager, dividendManager, poolManager, nftBuyback
 * - 战斗相关：battle, battleSkillData, battleHistory
 * - 繁殖相关：breedingCore, breedingMarket
 * - 竞技场相关：arenaRankingManager, arenaRankingQuery, arenaPlayer, arenaBattle, arenaLeaderboard
 * - DEX相关：pancakeSwapRouter, flapSwapRouter, uniswapRouter
 *
 * 安全特性：
 * - 仅Owner可以更新合约地址
 * - 系统合约白名单验证
 * - 可全局暂停所有操作
 */
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

    /**
     * @dev 暂停合约，停止所有操作
     * 仅合约所有者可调用，用于紧急情况下暂停服务
     * @param reason 暂停原因，将被记录在事件日志中
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消合约暂停，恢复所有操作
     * 仅合约所有者可调用
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 初始化合约
     * 初始化OpenZeppelin升级组件
     */
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @dev UUPS升级授权函数
     * 仅允许合约所有者升级合约实现
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 通过key获取合约地址
     * @param key 合约地址的keccak256哈希key
     * @return 地址
     */
    function getAddress(bytes32 key) external view returns (address) {
        return _addresses[key];
    }

    /**
     * @dev 设置单个合约地址
     * @param key 合约地址的keccak256哈希key
     * @param value 合约地址
     */
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
            addr == _addresses[keccak256("stakingLP")] ||
            addr == _addresses[keccak256("tokenStaking")] ||
            addr == _addresses[keccak256("tokenStakingLP")] ||
            addr == _addresses[keccak256("rewardManager")] ||
            addr == _addresses[keccak256("dividendManager")] ||
            addr == _addresses[keccak256("dividendManagerLP")] ||
            addr == _addresses[keccak256("poolManager")] ||
            addr == _addresses[keccak256("weightManager")] ||
            addr == _addresses[keccak256("breedingCore")] ||
            addr == _addresses[keccak256("breedingMarket")] ||
            addr == _addresses[keccak256("battle")] ||
            addr == _addresses[keccak256("arena")] ||
            addr == _addresses[keccak256("arenaPlayer")] ||
            addr == _addresses[keccak256("arenaReward")] ||
            addr == _addresses[keccak256("arenaRewardLP")] ||
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

    /**
     * @dev 设置所有合约地址（使用固定顺序数组）
     * @param _addr 地址数组，按固定顺序填充所有合约地址
     */
    function setAllContracts(address[] calldata _addr) external onlyOwner whenNotPaused {
        _setAddresses(_addr);
        emit GlobalAddressesUpdated();
    }

    /**
     * @dev 内部函数：设置所有合约地址
     * 调用各个分类设置函数
     * @param _addr 地址数组
     */
    function _setAddresses(address[] calldata _addr) internal {
        _setCoreAddresses(_addr);
        _setNFTAddresses(_addr);
        _setStakingAddresses(_addr);
        _setBattleAddresses(_addr);
        _setBreedingAddresses(_addr);
        _setArenaAddresses(_addr);
        _setOtherAddresses(_addr);
    }

    /**
     * @dev 内部函数：设置核心合约地址
     * @param _addr 地址数组
     */
    function _setCoreAddresses(address[] calldata _addr) private {
        _addresses[keccak256("token")] = _addr[0];
        _addresses[keccak256("usdt")] = _addr[1];
        _addresses[keccak256("wbnb")] = _addr[2];
        _addresses[keccak256("rewardManager")] = _addr[14];
        _addresses[keccak256("dividendManager")] = _addr[15];
        _addresses[keccak256("poolManager")] = _addr[17];
        _addresses[keccak256("priceOracle")] = _addr[18];
    }

    /**
     * @dev 内部函数：设置NFT相关合约地址
     * @param _addr 地址数组
     */
    function _setNFTAddresses(address[] calldata _addr) private {
        _addresses[keccak256("nftMintCore")] = _addr[3];
        _addresses[keccak256("nftMintMetadata")] = _addr[4];
        _addresses[keccak256("nftUpdate")] = _addr[5];
        _addresses[keccak256("nftData")] = _addr[6];
        _addresses[keccak256("tokenBurner")] = _addr[7];
        _addresses[keccak256("nftTrading")] = _addr[8];
        _addresses[keccak256("nftBuyback")] = _addr[9];
    }

    /**
     * @dev 内部函数：设置质押相关合约地址
     * @param _addr 地址数组
     */
    function _setStakingAddresses(address[] calldata _addr) private {
        _addresses[keccak256("staking")] = _addr[10];
        _addresses[keccak256("stakingLP")] = _addr[11];
        _addresses[keccak256("tokenStaking")] = _addr[12];
        _addresses[keccak256("tokenStakingLP")] = _addr[13];
        _addresses[keccak256("weightManager")] = _addr[24];
    }

    /**
     * @dev 内部函数：设置战斗相关合约地址
     * @param _addr 地址数组
     */
    function _setBattleAddresses(address[] calldata _addr) private {
        _addresses[keccak256("battle")] = _addr[19];
        _addresses[keccak256("battleSkillData")] = _addr[20];
        _addresses[keccak256("battleHistory")] = _addr[21];
    }

    /**
     * @dev 内部函数：设置繁殖相关合约地址
     * @param _addr 地址数组
     */
    function _setBreedingAddresses(address[] calldata _addr) private {
        _addresses[keccak256("breedingCore")] = _addr[22];
        _addresses[keccak256("breedingMarket")] = _addr[23];
    }

    /**
     * @dev 内部函数：设置竞技场相关合约地址
     * @param _addr 地址数组
     */
    function _setArenaAddresses(address[] calldata _addr) private {
        _addresses[keccak256("arenaRankingManager")] = _addr[25];
        _addresses[keccak256("arenaRankingQuery")] = _addr[26];
        _addresses[keccak256("arenaReward")] = _addr[27];
        _addresses[keccak256("arenaRewardLP")] = _addr[28];
        _addresses[keccak256("arenaLeaderboard")] = _addr[29];
        _addresses[keccak256("arenaPlayer")] = _addr[30];
        _addresses[keccak256("arenaBattle")] = _addr[31];
    }

    /**
     * @dev 内部函数：设置其他合约地址
     * @param _addr 地址数组
     */
    function _setOtherAddresses(address[] calldata _addr) private {
        _addresses[keccak256("dividendManagerLP")] = _addr[16];
        _addresses[keccak256("feeReceiver")] = _addr[32];
        _addresses[keccak256("pancakeSwapRouter")] = _addr[33];
        _addresses[keccak256("flapSwapRouter")] = _addr[34];
        _addresses[keccak256("uniswapRouter")] = _addr[35];
    }

    /**
     * @dev 设置所有授权者和合约地址
     * 用于完全更新授权系统
     * @param _expectedOldAuthorizer 预期的前一个授权者地址
     * @param _newAuthorizer 新的授权者地址
     * @param _contracts 合约地址数组
     */
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

    /**
     * @dev 获取代币合约地址
     * @return 代币合约地址
     */
    function getToken() external view returns (address) {
        return _addresses[keccak256("token")];
    }

    /**
     * @dev 获取USDT合约地址
     * @return USDT合约地址
     */
    function getUSDT() external view returns (address) {
        return _addresses[keccak256("usdt")];
    }

    /**
     * @dev 获取NFT铸造核心合约地址
     * @return NFT铸造核心合约地址
     */
    function getNFTMintCore() external view returns (address) {
        return _addresses[keccak256("nftMintCore")];
    }

    /**
     * @dev 获取NFT元数据合约地址
     * @return NFT元数据合约地址
     */
    function getNFTMintMetadata() external view returns (address) {
        return _addresses[keccak256("nftMintMetadata")];
    }

    /**
     * @dev 获取NFT升级合约地址
     * @return NFT升级合约地址
     */
    function getNFTUpdate() external view returns (address) {
        return _addresses[keccak256("nftUpdate")];
    }

    /**
     * @dev 获取NFT数据合约地址
     * @return NFT数据合约地址
     */
    function getNFTData() external view returns (address) {
        return _addresses[keccak256("nftData")];
    }

    /**
     * @dev 获取代币销毁合约地址
     * @return 代币销毁合约地址
     */
    function getTokenBurner() external view returns (address) {
        return _addresses[keccak256("tokenBurner")];
    }

    /**
     * @dev 获取NFT交易合约地址
     * @return NFT交易合约地址
     */
    function getNFTTrading() external view returns (address) {
        return _addresses[keccak256("nftTrading")];
    }

    /**
     * @dev 获取NFT回购合约地址
     * @return NFT回购合约地址
     */
    function getNFTBuyback() external view returns (address) {
        return _addresses[keccak256("nftBuyback")];
    }

    /**
     * @dev 获取NFT质押合约地址
     * @return NFT质押合约地址
     */
    function getStaking() external view returns (address) {
        return _addresses[keccak256("staking")];
    }

    /**
     * @dev 获取质押LP奖励合约地址
     * @return 质押LP奖励合约地址
     */
    function getStakingLP() external view returns (address) {
        return _addresses[keccak256("stakingLP")];
    }

    /**
     * @dev 获取代币质押合约地址
     * @return 代币质押合约地址
     */
    function getTokenStaking() external view returns (address) {
        return _addresses[keccak256("tokenStaking")];
    }

    /**
     * @dev 获取奖励管理合约地址
     * @return 奖励管理合约地址
     */
    function getRewardManager() external view returns (address) {
        return _addresses[keccak256("rewardManager")];
    }

    /**
     * @dev 获取分红管理合约地址
     * @return 分红管理合约地址
     */
    function getDividendManager() external view returns (address) {
        return _addresses[keccak256("dividendManager")];
    }

    /**
     * @dev 获取资金池管理合约地址
     * @return 资金池管理合约地址
     */
    function getPoolManager() external view returns (address) {
        return _addresses[keccak256("poolManager")];
    }

    /**
     * @dev 获取价格预言机合约地址
     * @return 价格预言机合约地址
     */
    function getPriceOracle() external view returns (address) {
        return _addresses[keccak256("priceOracle")];
    }

    /**
     * @dev 获取战斗合约地址
     * @return 战斗合约地址
     */
    function getBattle() external view returns (address) {
        return _addresses[keccak256("battle")];
    }

    /**
     * @dev 获取战斗技能数据合约地址
     * @return 战斗技能数据合约地址
     */
    function getBattleSkillData() external view returns (address) {
        return _addresses[keccak256("battleSkillData")];
    }

    /**
     * @dev 获取战斗历史合约地址
     * @return 战斗历史合约地址
     */
    function getBattleHistory() external view returns (address) {
        return _addresses[keccak256("battleHistory")];
    }

    /**
     * @dev 获取繁殖核心合约地址
     * @return 繁殖核心合约地址
     */
    function getBreedingCore() external view returns (address) {
        return _addresses[keccak256("breedingCore")];
    }

    /**
     * @dev 获取繁殖市场合约地址
     * @return 繁殖市场合约地址
     */
    function getBreedingMarket() external view returns (address) {
        return _addresses[keccak256("breedingMarket")];
    }

    /**
     * @dev 获取权重管理合约地址
     * @return 权重管理合约地址
     */
    function getWeightManager() external view returns (address) {
        return _addresses[keccak256("weightManager")];
    }

    /**
     * @dev 获取竞技场排名管理合约地址
     * @return 竞技场排名管理合约地址
     */
    function getArenaRankingManager() external view returns (address) {
        return _addresses[keccak256("arenaRankingManager")];
    }

    /**
     * @dev 获取竞技场排名查询合约地址
     * @return 竞技场排名查询合约地址
     */
    function getArenaRankingQuery() external view returns (address) {
        return _addresses[keccak256("arenaRankingQuery")];
    }

    /**
     * @dev 获取竞技场奖励合约地址
     * @return 竞技场奖励合约地址
     */
    function getArenaReward() external view returns (address) {
        return _addresses[keccak256("arenaReward")];
    }

    /**
     * @dev 获取竞技场奖励LP合约地址
     * @return 竞技场奖励LP合约地址
     */
    function getArenaRewardLP() external view returns (address) {
        return _addresses[keccak256("arenaRewardLP")];
    }

    /**
     * @dev 获取代币质押LP合约地址
     * @return 代币质押LP合约地址
     */
    function getTokenStakingLP() external view returns (address) {
        return _addresses[keccak256("tokenStakingLP")];
    }

    /**
     * @dev 获取分红管理LP合约地址
     * @return 分红管理LP合约地址
     */
    function getDividendManagerLP() external view returns (address) {
        return _addresses[keccak256("dividendManagerLP")];
    }

    /**
     * @dev 获取竞技场排行榜合约地址
     * @return 竞技场排行榜合约地址
     */
    function getArenaLeaderboard() external view returns (address) {
        return _addresses[keccak256("arenaLeaderboard")];
    }

    /**
     * @dev 获取竞技场玩家合约地址
     * @return 竞技场玩家合约地址
     */
    function getArenaPlayer() external view returns (address) {
        return _addresses[keccak256("arenaPlayer")];
    }

    /**
     * @dev 获取竞技场战斗合约地址
     * @return 竞技场战斗合约地址
     */
    function getArenaBattle() external view returns (address) {
        return _addresses[keccak256("arenaBattle")];
    }

    /**
     * @dev 获取费用接收地址
     * @return 费用接收地址
     */
    function getFeeReceiver() external view returns (address) {
        return _addresses[keccak256("feeReceiver")];
    }

    /**
     * @dev 获取PancakeSwap路由地址
     * @return PancakeSwap路由地址
     */
    function getPancakeSwapRouter() external view returns (address) {
        return _addresses[keccak256("pancakeSwapRouter")];
    }

    /**
     * @dev 获取FlapSwap路由地址
     * @return FlapSwap路由地址
     */
    function getFlapSwapRouter() external view returns (address) {
        return _addresses[keccak256("flapSwapRouter")];
    }

    /**
     * @dev 获取Uniswap路由地址
     * @return Uniswap路由地址
     */
    function getUniswapRouter() external view returns (address) {
        return _addresses[keccak256("uniswapRouter")];
    }

    /**
     * @dev 获取WBNB合约地址
     * @return WBNB合约地址
     */
    function getWBNB() external view returns (address) {
        return _addresses[keccak256("wbnb")];
    }

    function resetAllContractData() external onlyOwner {
        address[] memory contracts = new address[](31);
        
        contracts[0] = _addresses[keccak256("nftMintCore")];
        contracts[1] = _addresses[keccak256("nftMintMetadata")];
        contracts[2] = _addresses[keccak256("nftUpdate")];
        contracts[3] = _addresses[keccak256("nftData")];
        contracts[4] = _addresses[keccak256("tokenBurner")];
        contracts[5] = _addresses[keccak256("nftTrading")];
        contracts[6] = _addresses[keccak256("nftBuyback")];
        contracts[7] = _addresses[keccak256("staking")];
        contracts[8] = _addresses[keccak256("stakingLP")];
        contracts[9] = _addresses[keccak256("tokenStaking")];
        contracts[10] = _addresses[keccak256("tokenStakingLP")];
        contracts[11] = _addresses[keccak256("rewardManager")];
        contracts[12] = _addresses[keccak256("dividendManager")];
        contracts[13] = _addresses[keccak256("dividendManagerLP")];
        contracts[14] = _addresses[keccak256("poolManager")];
        contracts[15] = _addresses[keccak256("priceOracle")];
        contracts[16] = _addresses[keccak256("weightManager")];
        contracts[17] = _addresses[keccak256("battle")];
        contracts[18] = _addresses[keccak256("battleSkillData")];
        contracts[19] = _addresses[keccak256("battleHistory")];
        contracts[20] = _addresses[keccak256("breedingCore")];
        contracts[21] = _addresses[keccak256("breedingMarket")];
        contracts[22] = _addresses[keccak256("arenaRankingManager")];
        contracts[23] = _addresses[keccak256("arenaRankingQuery")];
        contracts[24] = _addresses[keccak256("arenaPlayer")];
        contracts[25] = _addresses[keccak256("arenaBattle")];
        contracts[26] = _addresses[keccak256("arenaLeaderboard")];
        contracts[27] = _addresses[keccak256("arenaReward")];
        contracts[28] = _addresses[keccak256("arenaRewardLP")];
        contracts[29] = _addresses[keccak256("FlapPricePay")];
        contracts[30] = _addresses[keccak256("FlapPriceQuerier")];
        
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] != address(0)) {
                try IResetContractData(contracts[i]).resetContractData() {
                    emit ContractResetSuccess(contracts[i]);
                } catch {
                    emit ContractResetFailed(contracts[i]);
                }
            }
        }
        
        emit AllContractDataReset(msg.sender, block.timestamp);
    }

    event ContractResetSuccess(address indexed contractAddress);
    event ContractResetFailed(address indexed contractAddress);
    event AllContractDataReset(address indexed operator, uint256 timestamp);
}