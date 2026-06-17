// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

library AuthorizerLib {
    struct ContractAddresses {
        address token;
        address usdt;
        address nftMintCore;
        address nftMintBatch;
        address nftMintMetadata;
        address nftUpdate;
        address nftData;
        address tokenBurner;
        address nftTrading;
        address nftBuyback;
        address staking;
        address tokenStaking;
        address rewardManager;
        address dividendManager;
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
        address arenaLeaderboard;
        address arenaPlayer;
        address arenaBattle;
        address feeReceiver;
        address pancakeSwapRouter;
        address flapSwapRouter;
        address uniswapRouter;
        address wbnb;
    }

    /**
     * @dev 设置所有合约的 authorizer 地址
     * 注意：业务合约之间的互信地址不再通过此函数设置，
     * 各业务合约应通过 Authorizer 合约动态获取其他合约地址
     */
    function setupAllAuthorizers(address _newAuthorizer, ContractAddresses calldata _addr) external {
        if (_addr.nftMintCore != address(0)) {
            ISetAuthorizer(_addr.nftMintCore).setAuthorizer(_newAuthorizer);
        }
        if (_addr.nftMintBatch != address(0)) {
            ISetAuthorizer(_addr.nftMintBatch).setAuthorizer(_newAuthorizer);
        }
        if (_addr.nftMintMetadata != address(0)) {
            ISetAuthorizer(_addr.nftMintMetadata).setAuthorizer(_newAuthorizer);
        }
        if (_addr.nftData != address(0)) {
            ISetAuthorizer(_addr.nftData).setAuthorizer(_newAuthorizer);
        }
        if (_addr.nftUpdate != address(0)) {
            ISetAuthorizer(_addr.nftUpdate).setAuthorizer(_newAuthorizer);
        }
        if (_addr.nftTrading != address(0)) {
            ISetAuthorizer(_addr.nftTrading).setAuthorizer(_newAuthorizer);
        }
        if (_addr.nftBuyback != address(0)) {
            ISetAuthorizer(_addr.nftBuyback).setAuthorizer(_newAuthorizer);
        }
        if (_addr.staking != address(0)) {
            ISetAuthorizer(_addr.staking).setAuthorizer(_newAuthorizer);
        }
        if (_addr.tokenStaking != address(0)) {
            ISetAuthorizer(_addr.tokenStaking).setAuthorizer(_newAuthorizer);
        }
        if (_addr.rewardManager != address(0)) {
            ISetAuthorizer(_addr.rewardManager).setAuthorizer(_newAuthorizer);
        }
        if (_addr.dividendManager != address(0)) {
            ISetAuthorizer(_addr.dividendManager).setAuthorizer(_newAuthorizer);
        }
        if (_addr.poolManager != address(0)) {
            ISetAuthorizer(_addr.poolManager).setAuthorizer(_newAuthorizer);
        }
        if (_addr.weightManager != address(0)) {
            ISetAuthorizer(_addr.weightManager).setAuthorizer(_newAuthorizer);
        }
        if (_addr.battle != address(0)) {
            ISetAuthorizer(_addr.battle).setAuthorizer(_newAuthorizer);
        }
        if (_addr.battleSkillData != address(0)) {
            ISetAuthorizer(_addr.battleSkillData).setAuthorizer(_newAuthorizer);
        }
        if (_addr.battleHistory != address(0)) {
            ISetAuthorizer(_addr.battleHistory).setAuthorizer(_newAuthorizer);
        }
        if (_addr.breedingCore != address(0)) {
            ISetAuthorizer(_addr.breedingCore).setAuthorizer(_newAuthorizer);
        }
        if (_addr.breedingMarket != address(0)) {
            ISetAuthorizer(_addr.breedingMarket).setAuthorizer(_newAuthorizer);
        }
        if (_addr.arenaRankingManager != address(0)) {
            ISetAuthorizer(_addr.arenaRankingManager).setAuthorizer(_newAuthorizer);
        }
        if (_addr.arenaRankingQuery != address(0)) {
            ISetAuthorizer(_addr.arenaRankingQuery).setAuthorizer(_newAuthorizer);
        }
        if (_addr.arenaReward != address(0)) {
            ISetAuthorizer(_addr.arenaReward).setAuthorizer(_newAuthorizer);
        }
        if (_addr.arenaLeaderboard != address(0)) {
            ISetAuthorizer(_addr.arenaLeaderboard).setAuthorizer(_newAuthorizer);
        }
        if (_addr.arenaPlayer != address(0)) {
            ISetAuthorizer(_addr.arenaPlayer).setAuthorizer(_newAuthorizer);
        }
        if (_addr.arenaBattle != address(0)) {
            ISetAuthorizer(_addr.arenaBattle).setAuthorizer(_newAuthorizer);
        }
        if (_addr.tokenBurner != address(0)) {
            ISetAuthorizer(_addr.tokenBurner).setAuthorizer(_newAuthorizer);
        }
        if (_addr.priceOracle != address(0)) {
            ISetAuthorizer(_addr.priceOracle).setAuthorizer(_newAuthorizer);
        }
    }
}
