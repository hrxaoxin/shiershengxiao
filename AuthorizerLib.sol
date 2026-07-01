// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

/**
 * @title AuthorizerLib
 * @dev 授权管理器工具库，提供合约地址管理的辅助函数
 *
 * 功能：
 * 1. 批量地址验证：检查多个地址是否都已设置
 * 2. 地址转换工具：提供地址到键值的转换
 * 3. 合约地址结构：定义所有游戏合约的地址结构
 *
 * 主要合约分组：
 * - 代币类：token, usdt, wbnb
 * - NFT核心类：nftMintCore, nftMintMetadata, nftData
 * - 游戏核心类：battle, battleSkillData, battleHistory, staking
 * - 奖励类：rewardManager, dividendManager, poolManager, nftBuyback
 * - 竞技场类：arenaRankingManager, arenaRankingQuery, arenaPlayer, arenaBattle, arenaLeaderboard
 * - DEX类：pancakeSwapRouter, flapSwapRouter, uniswapRouter
 */
library AuthorizerLib {
    struct ContractAddresses {
        address token;
        address usdt;
        address wbnb;
        address nftMintCore;
        address nftMintMetadata;
        address nftUpdate;
        address nftData;
        address tokenBurner;
        address nftTrading;
        address nftBuyback;
        address staking;
        address stakingLP;
        address tokenStaking;
        address tokenStakingLP;
        address rewardManager;
        address dividendManager;
        address dividendManagerLP;
        address poolManager;
        address priceOracle;
        address battle;
        address battleSkillData;
        address battleHistory;
        address breedingCore;
        address breedingMarket;
        address weightManager;
        address arenaRankingManager;
        address arenaRankingQuery;
        address arenaReward;
        address arenaRewardLP;
        address arenaLeaderboard;
        address arenaPlayer;
        address arenaBattle;
        address feeReceiver;
        address pancakeSwapRouter;
        address flapSwapRouter;
        address uniswapRouter;
    }

    uint256 constant INDEX_TOKEN = 0;
    uint256 constant INDEX_USDT = 1;
    uint256 constant INDEX_WBNB = 2;
    uint256 constant INDEX_NFT_MINT_CORE = 3;
    uint256 constant INDEX_NFT_MINT_METADATA = 4;
    uint256 constant INDEX_NFT_UPDATE = 5;
    uint256 constant INDEX_NFT_DATA = 6;
    uint256 constant INDEX_TOKEN_BURNER = 7;
    uint256 constant INDEX_NFT_TRADING = 8;
    uint256 constant INDEX_NFT_BUYBACK = 9;
    uint256 constant INDEX_STAKING = 10;
    uint256 constant INDEX_STAKING_LP = 11;
    uint256 constant INDEX_TOKEN_STAKING = 12;
    uint256 constant INDEX_TOKEN_STAKING_LP = 13;
    uint256 constant INDEX_REWARD_MANAGER = 14;
    uint256 constant INDEX_DIVIDEND_MANAGER = 15;
    uint256 constant INDEX_DIVIDEND_MANAGER_LP = 16;
    uint256 constant INDEX_POOL_MANAGER = 17;
    uint256 constant INDEX_PRICE_ORACLE = 18;
    uint256 constant INDEX_BATTLE = 19;
    uint256 constant INDEX_BATTLE_SKILL_DATA = 20;
    uint256 constant INDEX_BATTLE_HISTORY = 21;
    uint256 constant INDEX_BREEDING_CORE = 22;
    uint256 constant INDEX_BREEDING_MARKET = 23;
    uint256 constant INDEX_WEIGHT_MANAGER = 24;
    uint256 constant INDEX_ARENA_RANKING_MANAGER = 25;
    uint256 constant INDEX_ARENA_RANKING_QUERY = 26;
    uint256 constant INDEX_ARENA_REWARD = 27;
    uint256 constant INDEX_ARENA_REWARD_LP = 28;
    uint256 constant INDEX_ARENA_LEADERBOARD = 29;
    uint256 constant INDEX_ARENA_PLAYER = 30;
    uint256 constant INDEX_ARENA_BATTLE = 31;
    uint256 constant INDEX_FEE_RECEIVER = 32;
    uint256 constant INDEX_PANCAKE_SWAP_ROUTER = 33;
    uint256 constant INDEX_FLAP_SWAP_ROUTER = 34;
    uint256 constant INDEX_UNISWAP_ROUTER = 35;

    function setupAllAuthorizers(address _newAuthorizer, address[] calldata _addr) external {
        _setupNFT(_newAuthorizer, _addr);
        _setupStaking(_newAuthorizer, _addr);
        _setupBattle(_newAuthorizer, _addr);
        _setupBreeding(_newAuthorizer, _addr);
        _setupArena(_newAuthorizer, _addr);
        _setupOther(_newAuthorizer, _addr);
    }

    function _setupNFT(address _newAuthorizer, address[] calldata _addr) private {
        if (_addr[3] != address(0)) ISetAuthorizer(_addr[3]).setAuthorizer(_newAuthorizer);
        if (_addr[4] != address(0)) ISetAuthorizer(_addr[4]).setAuthorizer(_newAuthorizer);
        if (_addr[5] != address(0)) ISetAuthorizer(_addr[5]).setAuthorizer(_newAuthorizer);
        if (_addr[6] != address(0)) ISetAuthorizer(_addr[6]).setAuthorizer(_newAuthorizer);
        if (_addr[7] != address(0)) ISetAuthorizer(_addr[7]).setAuthorizer(_newAuthorizer);
        if (_addr[8] != address(0)) ISetAuthorizer(_addr[8]).setAuthorizer(_newAuthorizer);
        if (_addr[9] != address(0)) ISetAuthorizer(_addr[9]).setAuthorizer(_newAuthorizer);
    }

    function _setupStaking(address _newAuthorizer, address[] calldata _addr) private {
        if (_addr[10] != address(0)) ISetAuthorizer(_addr[10]).setAuthorizer(_newAuthorizer);
        if (_addr[11] != address(0)) ISetAuthorizer(_addr[11]).setAuthorizer(_newAuthorizer);
        if (_addr[12] != address(0)) ISetAuthorizer(_addr[12]).setAuthorizer(_newAuthorizer);
        if (_addr[13] != address(0)) ISetAuthorizer(_addr[13]).setAuthorizer(_newAuthorizer);
        if (_addr[14] != address(0)) ISetAuthorizer(_addr[14]).setAuthorizer(_newAuthorizer);
        if (_addr[15] != address(0)) ISetAuthorizer(_addr[15]).setAuthorizer(_newAuthorizer);
        if (_addr[16] != address(0)) ISetAuthorizer(_addr[16]).setAuthorizer(_newAuthorizer);
        if (_addr[24] != address(0)) ISetAuthorizer(_addr[24]).setAuthorizer(_newAuthorizer);
    }

    function _setupBattle(address _newAuthorizer, address[] calldata _addr) private {
        if (_addr[19] != address(0)) ISetAuthorizer(_addr[19]).setAuthorizer(_newAuthorizer);
        if (_addr[20] != address(0)) ISetAuthorizer(_addr[20]).setAuthorizer(_newAuthorizer);
        if (_addr[21] != address(0)) ISetAuthorizer(_addr[21]).setAuthorizer(_newAuthorizer);
    }

    function _setupBreeding(address _newAuthorizer, address[] calldata _addr) private {
        if (_addr[22] != address(0)) ISetAuthorizer(_addr[22]).setAuthorizer(_newAuthorizer);
        if (_addr[23] != address(0)) ISetAuthorizer(_addr[23]).setAuthorizer(_newAuthorizer);
    }

    function _setupArena(address _newAuthorizer, address[] calldata _addr) private {
        if (_addr[25] != address(0)) ISetAuthorizer(_addr[25]).setAuthorizer(_newAuthorizer);
        if (_addr[26] != address(0)) ISetAuthorizer(_addr[26]).setAuthorizer(_newAuthorizer);
        if (_addr[27] != address(0)) ISetAuthorizer(_addr[27]).setAuthorizer(_newAuthorizer);
        if (_addr[28] != address(0)) ISetAuthorizer(_addr[28]).setAuthorizer(_newAuthorizer);
        if (_addr[29] != address(0)) ISetAuthorizer(_addr[29]).setAuthorizer(_newAuthorizer);
        if (_addr[30] != address(0)) ISetAuthorizer(_addr[30]).setAuthorizer(_newAuthorizer);
        if (_addr[31] != address(0)) ISetAuthorizer(_addr[31]).setAuthorizer(_newAuthorizer);
    }

    function _setupOther(address _newAuthorizer, address[] calldata _addr) private {
        if (_addr[18] != address(0)) ISetAuthorizer(_addr[18]).setAuthorizer(_newAuthorizer);
    }
}