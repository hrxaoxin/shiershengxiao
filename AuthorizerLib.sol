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
    }

    function setupAllContracts(ContractAddresses calldata _addr) external {
        // battle
        if (_addr.battle != address(0)) {
            ISetNFTContract(_addr.battle).setNFTContract(_addr.nftMintCore);
        }
        
        // breedingCore
        if (_addr.breedingCore != address(0)) {
            ISetNFTContract(_addr.breedingCore).setNFTContract(_addr.nftMintCore);
            ISetTokenContract(_addr.breedingCore).setTokenContract(_addr.staking);
        }
        
        // breedingMarket
        if (_addr.breedingMarket != address(0)) {
            ISetBreedingContract(_addr.breedingMarket).setBreedingContract(_addr.breedingCore);
            ISetNFTContract(_addr.breedingMarket).setNFTContract(_addr.nftMintCore);
        }
        
        // nftMintCore + breedingCore
        if (_addr.nftMintCore != address(0) && _addr.breedingCore != address(0)) {
            ISetBreedingContract(_addr.nftMintCore).setBreedingContract(_addr.breedingCore);
        }

        // staking
        if (_addr.staking != address(0)) {
            ISetRewardTokenContract(_addr.staking).setRewardTokenContract(_addr.token);
            ISetNFTContract(_addr.staking).setNFTContract(_addr.nftMintCore);
        }
        
        // rewardManager
        if (_addr.rewardManager != address(0)) {
            ISetDividendPool(_addr.rewardManager).setDividendPool(_addr.dividendManager);
            ISetNFTStakingPool(_addr.rewardManager).setNFTStakingPool(_addr.staking);
            ISetTokenStakingPool(_addr.rewardManager).setTokenStakingPool(_addr.tokenStaking);
            ISetTokenContract(_addr.rewardManager).setTokenContract(_addr.token);
            ISetArenaRewardPool(_addr.rewardManager).setArenaRewardPool(_addr.arenaRankingManager);
            if (_addr.nftBuyback != address(0)) {
                ISetNFTBuybackPool(_addr.rewardManager).setNFTBuybackPool(_addr.nftBuyback);
            }
            if (_addr.poolManager != address(0)) {
                ISetPoolManager(_addr.rewardManager).setPoolManager(_addr.poolManager);
            }
        }
        
        // dividendManager
        if (_addr.dividendManager != address(0)) {
            ISetTokenContract(_addr.dividendManager).setTokenContract(_addr.token);
            ISetRewardManagerContract(_addr.dividendManager).setRewardManagerContract(_addr.rewardManager);
            if (_addr.nftUpdate != address(0)) {
                ISetNFTUpdateContract(_addr.dividendManager).setNFTUpdateContract(_addr.nftUpdate);
            }
        }
        
        // tokenStaking
        if (_addr.tokenStaking != address(0)) {
            ISetTokenAddress(_addr.tokenStaking).setTokenAddress(_addr.token);
        }

        // priceOracle
        if (_addr.priceOracle != address(0)) {
            ISetTokenContract(_addr.priceOracle).setTokenContract(_addr.token);
            ISetUSDTContract(_addr.priceOracle).setUSDTContract(_addr.usdt);
        }

        // nftUpdate
        if (_addr.nftUpdate != address(0)) {
            ISetNFTContract(_addr.nftUpdate).setNFTContract(_addr.nftMintCore);
            ISetMetadataContract(_addr.nftUpdate).setMetadataContract(_addr.nftMintMetadata);
            ISetTokenContract(_addr.nftUpdate).setTokenContract(_addr.token);
            ISetPancakeSwapPair(_addr.nftUpdate).setPancakeSwapPair(_addr.pancakeSwapRouter);
        }
        
        // tokenBurner
        if (_addr.tokenBurner != address(0)) {
            ISetNFTContract(_addr.tokenBurner).setNFTContract(_addr.nftMintCore);
            ISetTokenContract(_addr.tokenBurner).setTokenContract(_addr.token);
        }
        
        // nftMintCore + tokenBurner
        if (_addr.nftMintCore != address(0) && _addr.tokenBurner != address(0)) {
            ISetTokenBurner(_addr.nftMintCore).setTokenBurnerContract(_addr.tokenBurner);
        }

        // nftBuyback
        if (_addr.nftBuyback != address(0)) {
            ISetNFTContract(_addr.nftBuyback).setNFTContract(_addr.nftMintCore);
            ISetTokenContract(_addr.nftBuyback).setTokenContract(_addr.token);
            if (_addr.tokenBurner != address(0)) {
                ISetTokenBurner(_addr.nftBuyback).setTokenBurnerContract(_addr.tokenBurner);
            }
            if (_addr.nftUpdate != address(0)) {
                ISetNFTUpdateContract(_addr.nftBuyback).setNFTUpdateContract(_addr.nftUpdate);
            }
            if (_addr.nftData != address(0)) {
                ISetNFTDataContract(_addr.nftBuyback).setNFTDataContract(_addr.nftData);
            }
        }

        // weightManager + nftData
        if (_addr.weightManager != address(0) && _addr.nftData != address(0)) {
            ISetNFTDataContract(_addr.weightManager).setNFTDataContract(_addr.nftData);
        }
        
        // nftData + dividendManager
        if (_addr.nftData != address(0) && _addr.dividendManager != address(0)) {
            ISetDividendManager(_addr.nftData).setDividendManager(_addr.dividendManager);
        }
        
        // battleHistory
        if (_addr.battleHistory != address(0)) {
            ISetBattleContract(_addr.battleHistory).setBattleContract(_addr.battle);
        }
        
        // nftTrading
        if (_addr.nftTrading != address(0)) {
            ISetNFTContract(_addr.nftTrading).setNFTContract(_addr.nftMintCore);
            ISetFeeReceiver(_addr.nftTrading).setFeeReceiver(_addr.feeReceiver);
        }

        // arenaRankingManager
        if (_addr.arenaRankingManager != address(0)) {
            ISetTokenContract(_addr.arenaRankingManager).setTokenContract(_addr.token);
            ISetBattleContract(_addr.arenaRankingManager).setBattleContract(_addr.battle);
            if (_addr.arenaReward != address(0)) {
                ISetArenaRewardContract(_addr.arenaRankingManager).setArenaRewardContract(_addr.arenaReward);
            }
            if (_addr.arenaLeaderboard != address(0)) {
                ISetArenaLeaderboardContract(_addr.arenaRankingManager).setArenaLeaderboardContract(_addr.arenaLeaderboard);
            }
            if (_addr.arenaPlayer != address(0)) {
                ISetArenaPlayerContract(_addr.arenaRankingManager).setArenaPlayerContract(_addr.arenaPlayer);
            }
            if (_addr.arenaBattle != address(0)) {
                ISetArenaBattleContract(_addr.arenaRankingManager).setArenaBattleContract(_addr.arenaBattle);
            }
        }
        
        // arenaRankingQuery
        if (_addr.arenaRankingQuery != address(0)) {
            if (_addr.arenaReward != address(0)) {
                ISetArenaRewardContract(_addr.arenaRankingQuery).setArenaRewardContract(_addr.arenaReward);
            }
            if (_addr.arenaLeaderboard != address(0)) {
                ISetArenaLeaderboardContract(_addr.arenaRankingQuery).setArenaLeaderboardContract(_addr.arenaLeaderboard);
            }
        }
        
        // arenaReward
        if (_addr.arenaReward != address(0)) {
            ISetArenaRankingManagerContract(_addr.arenaReward).setArenaRankingManagerContract(_addr.arenaRankingManager);
        }
        
        // arenaLeaderboard
        if (_addr.arenaLeaderboard != address(0)) {
            ISetArenaRankingManagerContract(_addr.arenaLeaderboard).setArenaRankingManagerContract(_addr.arenaRankingManager);
        }
        
        // arenaPlayer
        if (_addr.arenaPlayer != address(0)) {
            ISetArenaRankingManagerContract(_addr.arenaPlayer).setArenaRankingManagerContract(_addr.arenaRankingManager);
            ISetNFTContract(_addr.arenaPlayer).setNFTContract(_addr.nftMintCore);
        }
        
        // arenaBattle
        if (_addr.arenaBattle != address(0)) {
            ISetArenaRankingManagerContract(_addr.arenaBattle).setArenaRankingManagerContract(_addr.arenaRankingManager);
            ISetBattleContract(_addr.arenaBattle).setBattleContract(_addr.battle);
            ISetNFTContract(_addr.arenaBattle).setNFTContract(_addr.nftMintCore);
        }
    }

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
