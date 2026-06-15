// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";
import "./AuthorizerLib.sol";

// Authorizer: 合约地址注册表和权限管理
contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    bool public paused;
    string public pauseReason;

    // 地址键常量（不占用 storage）
    bytes32 constant TOKEN = keccak256("token");
    bytes32 constant USDT = keccak256("usdt");
    bytes32 constant NFT_MINT_CORE = keccak256("nftMintCore");
    bytes32 constant NFT_MINT_BATCH = keccak256("nftMintBatch");
    bytes32 constant NFT_MINT_METADATA = keccak256("nftMintMetadata");
    bytes32 constant NFT_UPDATE = keccak256("nftUpdate");
    bytes32 constant NFT_DATA = keccak256("nftData");
    bytes32 constant TOKEN_BURNER = keccak256("tokenBurner");
    bytes32 constant NFT_TRADING = keccak256("nftTrading");
    bytes32 constant NFT_BUYBACK = keccak256("nftBuyback");
    bytes32 constant STAKING = keccak256("staking");
    bytes32 constant TOKEN_STAKING = keccak256("tokenStaking");
    bytes32 constant REWARD_MANAGER = keccak256("rewardManager");
    bytes32 constant DIVIDEND_MANAGER = keccak256("dividendManager");
    bytes32 constant POOL_MANAGER = keccak256("poolManager");
    bytes32 constant PRICE_ORACLE = keccak256("priceOracle");
    bytes32 constant BATTLE = keccak256("battle");
    bytes32 constant BATTLE_SKILL_DATA = keccak256("battleSkillData");
    bytes32 constant BATTLE_HISTORY = keccak256("battleHistory");
    bytes32 constant BREEDING_CORE = keccak256("breedingCore");
    bytes32 constant BREEDING_MARKET = keccak256("breedingMarket");
    bytes32 constant WEIGHT_MANAGER = keccak256("weightManager");
    bytes32 constant ARENA_RANKING_MANAGER = keccak256("arenaRankingManager");
    bytes32 constant ARENA_RANKING_QUERY = keccak256("arenaRankingQuery");
    bytes32 constant ARENA_REWARD = keccak256("arenaReward");
    bytes32 constant ARENA_LEADERBOARD = keccak256("arenaLeaderboard");
    bytes32 constant ARENA_PLAYER = keccak256("arenaPlayer");
    bytes32 constant ARENA_BATTLE = keccak256("arenaBattle");
    bytes32 constant FEE_RECEIVER = keccak256("feeReceiver");
    bytes32 constant PANCAKE_SWAP_ROUTER = keccak256("pancakeSwapRouter");

    // 使用 mapping 存储所有地址（减少 getter 函数）
    mapping(bytes32 => address) private _addresses;

    event Paused(address account, string reason);
    event Unpaused(address account);
    event ContractAddressUpdated(bytes32 key, address value);

    modifier whenNotPaused() {
        require(!paused, "P");
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

    // ========== Getter 函数（保持向后兼容）==========
    function tokenAddress() external view returns (address) { return _addresses[TOKEN]; }
    function usdtAddress() external view returns (address) { return _addresses[USDT]; }
    function nftMintCoreAddress() external view returns (address) { return _addresses[NFT_MINT_CORE]; }
    function nftMintBatchAddress() external view returns (address) { return _addresses[NFT_MINT_BATCH]; }
    function nftMintMetadataAddress() external view returns (address) { return _addresses[NFT_MINT_METADATA]; }
    function nftUpdateAddress() external view returns (address) { return _addresses[NFT_UPDATE]; }
    function nftDataAddress() external view returns (address) { return _addresses[NFT_DATA]; }
    function tokenBurnerAddress() external view returns (address) { return _addresses[TOKEN_BURNER]; }
    function nftTradingAddress() external view returns (address) { return _addresses[NFT_TRADING]; }
    function nftBuybackAddress() external view returns (address) { return _addresses[NFT_BUYBACK]; }
    function stakingAddress() external view returns (address) { return _addresses[STAKING]; }
    function tokenStakingAddress() external view returns (address) { return _addresses[TOKEN_STAKING]; }
    function rewardManagerAddress() external view returns (address) { return _addresses[REWARD_MANAGER]; }
    function dividendManagerAddress() external view returns (address) { return _addresses[DIVIDEND_MANAGER]; }
    function poolManagerAddress() external view returns (address) { return _addresses[POOL_MANAGER]; }
    function priceOracleAddress() external view returns (address) { return _addresses[PRICE_ORACLE]; }
    function battleAddress() external view returns (address) { return _addresses[BATTLE]; }
    function battleSkillDataAddress() external view returns (address) { return _addresses[BATTLE_SKILL_DATA]; }
    function battleHistoryAddress() external view returns (address) { return _addresses[BATTLE_HISTORY]; }
    function breedingCoreAddress() external view returns (address) { return _addresses[BREEDING_CORE]; }
    function breedingMarketAddress() external view returns (address) { return _addresses[BREEDING_MARKET]; }
    function weightManagerAddress() external view returns (address) { return _addresses[WEIGHT_MANAGER]; }
    function arenaRankingManagerAddress() external view returns (address) { return _addresses[ARENA_RANKING_MANAGER]; }
    function arenaRankingQueryAddress() external view returns (address) { return _addresses[ARENA_RANKING_QUERY]; }
    function arenaRewardAddress() external view returns (address) { return _addresses[ARENA_REWARD]; }
    function arenaLeaderboardAddress() external view returns (address) { return _addresses[ARENA_LEADERBOARD]; }
    function arenaPlayerAddress() external view returns (address) { return _addresses[ARENA_PLAYER]; }
    function arenaBattleAddress() external view returns (address) { return _addresses[ARENA_BATTLE]; }
    function feeReceiverAddress() external view returns (address) { return _addresses[FEE_RECEIVER]; }
    function pancakeSwapRouterAddress() external view returns (address) { return _addresses[PANCAKE_SWAP_ROUTER]; }

    // ========== 设置单个地址（用于紧急更新）==========
    function setAddress(bytes32 key, address value) external onlyOwner whenNotPaused {
        _addresses[key] = value;
        emit ContractAddressUpdated(key, value);
    }

    // ========== 批量设置所有合约地址 ==========
    // 使用 AuthorizerLib 的结构体定义
    using AuthorizerLib for AuthorizerLib.ContractAddresses;

    function setAllContracts(AuthorizerLib.ContractAddresses calldata _addr) external onlyOwner whenNotPaused {
        // 设置所有地址到 mapping
        _addresses[TOKEN] = _addr.token;
        _addresses[USDT] = _addr.usdt;
        _addresses[NFT_MINT_CORE] = _addr.nftMintCore;
        _addresses[NFT_MINT_BATCH] = _addr.nftMintBatch;
        _addresses[NFT_MINT_METADATA] = _addr.nftMintMetadata;
        _addresses[NFT_UPDATE] = _addr.nftUpdate;
        _addresses[NFT_DATA] = _addr.nftData;
        _addresses[TOKEN_BURNER] = _addr.tokenBurner;
        _addresses[NFT_TRADING] = _addr.nftTrading;
        _addresses[NFT_BUYBACK] = _addr.nftBuyback;
        _addresses[STAKING] = _addr.staking;
        _addresses[TOKEN_STAKING] = _addr.tokenStaking;
        _addresses[REWARD_MANAGER] = _addr.rewardManager;
        _addresses[DIVIDEND_MANAGER] = _addr.dividendManager;
        _addresses[POOL_MANAGER] = _addr.poolManager;
        _addresses[PRICE_ORACLE] = _addr.priceOracle;
        _addresses[BATTLE] = _addr.battle;
        _addresses[BATTLE_SKILL_DATA] = _addr.battleSkillData;
        _addresses[BATTLE_HISTORY] = _addr.battleHistory;
        _addresses[BREEDING_CORE] = _addr.breedingCore;
        _addresses[BREEDING_MARKET] = _addr.breedingMarket;
        _addresses[WEIGHT_MANAGER] = _addr.weightManager;
        _addresses[ARENA_RANKING_MANAGER] = _addr.arenaRankingManager;
        _addresses[ARENA_RANKING_QUERY] = _addr.arenaRankingQuery;
        _addresses[ARENA_REWARD] = _addr.arenaReward;
        _addresses[ARENA_LEADERBOARD] = _addr.arenaLeaderboard;
        _addresses[ARENA_PLAYER] = _addr.arenaPlayer;
        _addresses[ARENA_BATTLE] = _addr.arenaBattle;
        _addresses[FEE_RECEIVER] = _addr.feeReceiver;
        _addresses[PANCAKE_SWAP_ROUTER] = _addr.pancakeSwapRouter;

        // 调用统一设置函数（传递结构体避免 Stack too deep）
        AuthorizerLib.setupAllContracts(_addr);
    }

    // ========== 设置所有合约的 authorizer 地址 ==========
    function setAllAuthorizers(address _newAuthorizer) external onlyOwner whenNotPaused {
        require(_newAuthorizer != address(0), "IA");
        // 构建结构体避免 Stack too deep
        AuthorizerLib.ContractAddresses memory addr;
        addr.nftMintCore = _addresses[NFT_MINT_CORE];
        addr.nftMintBatch = _addresses[NFT_MINT_BATCH];
        addr.nftMintMetadata = _addresses[NFT_MINT_METADATA];
        addr.nftData = _addresses[NFT_DATA];
        addr.nftUpdate = _addresses[NFT_UPDATE];
        addr.nftTrading = _addresses[NFT_TRADING];
        addr.nftBuyback = _addresses[NFT_BUYBACK];
        addr.staking = _addresses[STAKING];
        addr.tokenStaking = _addresses[TOKEN_STAKING];
        addr.rewardManager = _addresses[REWARD_MANAGER];
        addr.dividendManager = _addresses[DIVIDEND_MANAGER];
        addr.poolManager = _addresses[POOL_MANAGER];
        addr.weightManager = _addresses[WEIGHT_MANAGER];
        addr.battle = _addresses[BATTLE];
        addr.battleSkillData = _addresses[BATTLE_SKILL_DATA];
        addr.battleHistory = _addresses[BATTLE_HISTORY];
        addr.breedingCore = _addresses[BREEDING_CORE];
        addr.breedingMarket = _addresses[BREEDING_MARKET];
        addr.arenaRankingManager = _addresses[ARENA_RANKING_MANAGER];
        addr.arenaRankingQuery = _addresses[ARENA_RANKING_QUERY];
        addr.arenaReward = _addresses[ARENA_REWARD];
        addr.arenaLeaderboard = _addresses[ARENA_LEADERBOARD];
        addr.arenaPlayer = _addresses[ARENA_PLAYER];
        addr.arenaBattle = _addresses[ARENA_BATTLE];
        addr.tokenBurner = _addresses[TOKEN_BURNER];
        addr.priceOracle = _addresses[PRICE_ORACLE];
        AuthorizerLib.setupAllAuthorizers(_newAuthorizer, addr);
    }

    receive() external payable {}
    fallback() external payable {}
}