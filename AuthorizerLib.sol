// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

library AuthorizerLib {
    event ContractSetupSuccess(string name);
    event ContractSetupFailed(string name, string reason);

    function setupBattleAndBreeding(
        address _battleAddress,
        address _breedingCoreAddress,
        address _breedingMarketAddress,
        address _nftMintCoreAddress,
        address _stakingAddress
    ) internal {
        if (_battleAddress != address(0)) {
            try ISetNFTContract(_battleAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Battle", reason);
            } catch {
                emit ContractSetupFailed("Battle", "Unknown");
            }
        }
        if (_breedingCoreAddress != address(0)) {
            try ISetNFTContract(_breedingCoreAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("BreedingCore-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingCore-NFT", reason);
            } catch {
                emit ContractSetupFailed("BreedingCore-NFT", "Unknown");
            }
            try ISetTokenContract(_breedingCoreAddress).setTokenContract(_stakingAddress) {
                emit ContractSetupSuccess("BreedingCore-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingCore-Token", reason);
            } catch {
                emit ContractSetupFailed("BreedingCore-Token", "Unknown");
            }
        }
        if (_breedingMarketAddress != address(0)) {
            try ISetBreedingContract(_breedingMarketAddress).setBreedingContract(_breedingCoreAddress) {
                emit ContractSetupSuccess("BreedingMarket-Core");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingMarket-Core", reason);
            } catch {
                emit ContractSetupFailed("BreedingMarket-Core", "Unknown");
            }
            try ISetNFTContract(_breedingMarketAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("BreedingMarket-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingMarket-NFT", reason);
            } catch {
                emit ContractSetupFailed("BreedingMarket-NFT", "Unknown");
            }
        }
        if (_nftMintCoreAddress != address(0) && _breedingCoreAddress != address(0)) {
            try ISetBreedingContract(_nftMintCoreAddress).setBreedingContract(_breedingCoreAddress) {
                emit ContractSetupSuccess("NFTMintCore-Breeding");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTMintCore-Breeding", reason);
            } catch {
                emit ContractSetupFailed("NFTMintCore-Breeding", "Unknown");
            }
        }
    }

    function setupStakingAndReward(
        address _stakingAddress,
        address _rewardManagerAddress,
        address _dividendManagerAddress,
        address _tokenStakingAddress,
        address _tokenAddress,
        address _arenaRankingManagerAddress,
        address _nftMintCoreAddress,
        address _nftBuybackAddress,
        address _poolManagerAddress
    ) internal {
        if (_stakingAddress != address(0)) {
            try ISetRewardTokenContract(_stakingAddress).setRewardTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("Staking-RewardToken");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Staking-RewardToken", reason);
            } catch {
                emit ContractSetupFailed("Staking-RewardToken", "Unknown");
            }
            try ISetNFTContract(_stakingAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("Staking-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Staking-NFT", reason);
            } catch {
                emit ContractSetupFailed("Staking-NFT", "Unknown");
            }
        }
        if (_rewardManagerAddress != address(0)) {
            try ISetDividendPool(_rewardManagerAddress).setDividendPool(_dividendManagerAddress) {
                emit ContractSetupSuccess("RewardManager-DividendPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-DividendPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-DividendPool", "Unknown");
            }
            try ISetNFTStakingPool(_rewardManagerAddress).setNFTStakingPool(_stakingAddress) {
                emit ContractSetupSuccess("RewardManager-NFTStakingPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-NFTStakingPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-NFTStakingPool", "Unknown");
            }
            try ISetTokenStakingPool(_rewardManagerAddress).setTokenStakingPool(_tokenStakingAddress) {
                emit ContractSetupSuccess("RewardManager-TokenStakingPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-TokenStakingPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-TokenStakingPool", "Unknown");
            }
            try ISetTokenContract(_rewardManagerAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("RewardManager-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-Token", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-Token", "Unknown");
            }
            try ISetArenaRewardPool(_rewardManagerAddress).setArenaRewardPool(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("RewardManager-ArenaRewardPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-ArenaRewardPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-ArenaRewardPool", "Unknown");
            }
            if (_nftBuybackAddress != address(0)) {
                try ISetNFTBuybackPool(_rewardManagerAddress).setNFTBuybackPool(_nftBuybackAddress) {
                    emit ContractSetupSuccess("RewardManager-NFTBuybackPool");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("RewardManager-NFTBuybackPool", reason);
                } catch {
                    emit ContractSetupFailed("RewardManager-NFTBuybackPool", "Unknown");
                }
            }
        }
        if (_dividendManagerAddress != address(0)) {
            try ISetTokenContract(_dividendManagerAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("DividendManager-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("DividendManager-Token", reason);
            } catch {
                emit ContractSetupFailed("DividendManager-Token", "Unknown");
            }
            try ISetRewardManagerContract(_dividendManagerAddress).setRewardManagerContract(_rewardManagerAddress) {
                emit ContractSetupSuccess("DividendManager-RewardManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("DividendManager-RewardManager", reason);
            } catch {
                emit ContractSetupFailed("DividendManager-RewardManager", "Unknown");
            }
        }
        if (_tokenStakingAddress != address(0)) {
            try ISetTokenAddress(_tokenStakingAddress).setTokenAddress(_tokenAddress) {
                emit ContractSetupSuccess("TokenStaking-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenStaking-Token", reason);
            } catch {
                emit ContractSetupFailed("TokenStaking-Token", "Unknown");
            }
        }
        if (_poolManagerAddress != address(0) && _rewardManagerAddress != address(0)) {
            try ISetPoolManager(_rewardManagerAddress).setPoolManager(_poolManagerAddress) {
                emit ContractSetupSuccess("RewardManager-PoolManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-PoolManager", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-PoolManager", "Unknown");
            }
        }
    }

    function setupPriceAndUpgrade(
        address _priceOracleAddress,
        address _tokenAddress,
        address _usdtAddress
    ) internal {
        if (_priceOracleAddress != address(0)) {
            try ISetTokenContract(_priceOracleAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("PriceOracle-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("PriceOracle-Token", reason);
            } catch {
                emit ContractSetupFailed("PriceOracle-Token", "Unknown");
            }
            try ISetUSDTContract(_priceOracleAddress).setUSDTContract(_usdtAddress) {
                emit ContractSetupSuccess("PriceOracle-USDT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("PriceOracle-USDT", reason);
            } catch {
                emit ContractSetupFailed("PriceOracle-USDT", "Unknown");
            }
        }
    }

    function setupNFTContracts(
        address _nftUpdateAddress,
        address _tokenBurnerAddress,
        address _nftMintCoreAddress,
        address _nftMintMetadataAddress,
        address _pancakeSwapRouterAddress,
        address _tokenAddress,
        address _dividendManagerAddress
    ) internal {
        if (_nftUpdateAddress != address(0)) {
            try ISetNFTContract(_nftUpdateAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("NFTUpdate-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-NFT", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-NFT", "Unknown");
            }
            try ISetMetadataContract(_nftUpdateAddress).setMetadataContract(_nftMintMetadataAddress) {
                emit ContractSetupSuccess("NFTUpdate-Metadata");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-Metadata", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-Metadata", "Unknown");
            }
            try ISetTokenContract(_nftUpdateAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("NFTUpdate-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-Token", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-Token", "Unknown");
            }
            try ISetPancakeSwapPair(_nftUpdateAddress).setPancakeSwapPair(_pancakeSwapRouterAddress) {
                emit ContractSetupSuccess("NFTUpdate-PancakeSwap");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-PancakeSwap", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-PancakeSwap", "Unknown");
            }
            if (_dividendManagerAddress != address(0)) {
                try ISetNFTUpdateContract(_dividendManagerAddress).setNFTUpdateContract(_nftUpdateAddress) {
                    emit ContractSetupSuccess("DividendManager-NFTUpdate");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("DividendManager-NFTUpdate", reason);
                } catch {
                    emit ContractSetupFailed("DividendManager-NFTUpdate", "Unknown");
                }
            }
        }
        if (_tokenBurnerAddress != address(0)) {
            try ISetNFTContract(_tokenBurnerAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("TokenBurner-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenBurner-NFT", reason);
            } catch {
                emit ContractSetupFailed("TokenBurner-NFT", "Unknown");
            }
            try ISetTokenContract(_tokenBurnerAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("TokenBurner-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenBurner-Token", reason);
            } catch {
                emit ContractSetupFailed("TokenBurner-Token", "Unknown");
            }
        }
        if (_nftMintCoreAddress != address(0)) {
            try ISetTokenBurner(_nftMintCoreAddress).setTokenBurnerContract(_tokenBurnerAddress) {
                emit ContractSetupSuccess("NFTMintCore-TokenBurner");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTMintCore-TokenBurner", reason);
            } catch {
                emit ContractSetupFailed("NFTMintCore-TokenBurner", "Unknown");
            }
        }
    }

    function setupNFTBuyback(
        address _nftBuybackAddress,
        address _nftMintCoreAddress,
        address _tokenAddress,
        address _tokenBurnerAddress,
        address _nftUpdateAddress,
        address _nftDataAddress
    ) internal {
        if (_nftBuybackAddress != address(0)) {
            try ISetNFTContract(_nftBuybackAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("NFTBuyback-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTBuyback-NFT", reason);
            } catch {
                emit ContractSetupFailed("NFTBuyback-NFT", "Unknown");
            }
            try ISetTokenContract(_nftBuybackAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("NFTBuyback-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTBuyback-Token", reason);
            } catch {
                emit ContractSetupFailed("NFTBuyback-Token", "Unknown");
            }
            if (_tokenBurnerAddress != address(0)) {
                try ISetTokenBurner(_nftBuybackAddress).setTokenBurnerContract(_tokenBurnerAddress) {
                    emit ContractSetupSuccess("NFTBuyback-TokenBurner");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTBuyback-TokenBurner", reason);
                } catch {
                    emit ContractSetupFailed("NFTBuyback-TokenBurner", "Unknown");
                }
            }
            if (_nftUpdateAddress != address(0)) {
                try ISetNFTUpdateContract(_nftBuybackAddress).setNFTUpdateContract(_nftUpdateAddress) {
                    emit ContractSetupSuccess("NFTBuyback-NFTUpdate");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTBuyback-NFTUpdate", reason);
                } catch {
                    emit ContractSetupFailed("NFTBuyback-NFTUpdate", "Unknown");
                }
            }
            if (_nftDataAddress != address(0)) {
                try ISetNFTDataContract(_nftBuybackAddress).setNFTDataContract(_nftDataAddress) {
                    emit ContractSetupSuccess("NFTBuyback-NFTData");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTBuyback-NFTData", reason);
                } catch {
                    emit ContractSetupFailed("NFTBuyback-NFTData", "Unknown");
                }
            }
        }
    }

    function setupOtherContracts(
        address _weightManagerAddress,
        address _battleHistoryAddress,
        address _nftTradingAddress,
        address _feeReceiverAddress,
        address _arenaRankingManagerAddress,
        address _arenaRankingQueryAddress,
        address _arenaRewardAddress,
        address _arenaLeaderboardAddress,
        address _arenaPlayerAddress,
        address _arenaBattleAddress,
        address _nftDataAddress,
        address _dividendManagerAddress,
        address _battleAddress,
        address _tokenAddress,
        address _nftMintCoreAddress
    ) internal {
        if (_weightManagerAddress != address(0)) {
            try ISetNFTDataContract(_weightManagerAddress).setNFTDataContract(_nftDataAddress) {
                emit ContractSetupSuccess("WeightManager-NFTData");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("WeightManager-NFTData", reason);
            } catch {
                emit ContractSetupFailed("WeightManager-NFTData", "Unknown");
            }
        }
        if (_nftDataAddress != address(0) && _dividendManagerAddress != address(0)) {
            try ISetDividendManager(_nftDataAddress).setDividendManager(_dividendManagerAddress) {
                emit ContractSetupSuccess("NFTData-DividendManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTData-DividendManager", reason);
            } catch {
                emit ContractSetupFailed("NFTData-DividendManager", "Unknown");
            }
        }
        if (_battleHistoryAddress != address(0)) {
            try ISetBattleContract(_battleHistoryAddress).setBattleContract(_battleAddress) {
                emit ContractSetupSuccess("BattleHistory-Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BattleHistory-Battle", reason);
            } catch {
                emit ContractSetupFailed("BattleHistory-Battle", "Unknown");
            }
        }
        if (_nftTradingAddress != address(0)) {
            try ISetNFTContract(_nftTradingAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("NFTTrading-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTTrading-NFT", reason);
            } catch {
                emit ContractSetupFailed("NFTTrading-NFT", "Unknown");
            }
            try ISetFeeReceiver(_nftTradingAddress).setFeeReceiver(_feeReceiverAddress) {
                emit ContractSetupSuccess("NFTTrading-FeeReceiver");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTTrading-FeeReceiver", reason);
            } catch {
                emit ContractSetupFailed("NFTTrading-FeeReceiver", "Unknown");
            }
        }
        if (_arenaRankingManagerAddress != address(0)) {
            try ISetTokenContract(_arenaRankingManagerAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("ArenaRankingManager-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingManager-Token", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingManager-Token", "Unknown");
            }
            try ISetBattleContract(_arenaRankingManagerAddress).setBattleContract(_battleAddress) {
                emit ContractSetupSuccess("ArenaRankingManager-Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingManager-Battle", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingManager-Battle", "Unknown");
            }
            if (_arenaRewardAddress != address(0)) {
                try ISetArenaRewardContract(_arenaRankingManagerAddress).setArenaRewardContract(_arenaRewardAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaReward");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaReward", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaReward", "Unknown");
                }
            }
            if (_arenaLeaderboardAddress != address(0)) {
                try ISetArenaLeaderboardContract(_arenaRankingManagerAddress).setArenaLeaderboardContract(_arenaLeaderboardAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaLeaderboard");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaLeaderboard", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaLeaderboard", "Unknown");
                }
            }
            if (_arenaPlayerAddress != address(0)) {
                try ISetArenaPlayerContract(_arenaRankingManagerAddress).setArenaPlayerContract(_arenaPlayerAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaPlayer");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaPlayer", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaPlayer", "Unknown");
                }
            }
            if (_arenaBattleAddress != address(0)) {
                try ISetArenaBattleContract(_arenaRankingManagerAddress).setArenaBattleContract(_arenaBattleAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaBattle");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaBattle", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaBattle", "Unknown");
                }
            }
        }
        if (_arenaRankingQueryAddress != address(0)) {
            if (_arenaRewardAddress != address(0)) {
                try ISetArenaRewardContract(_arenaRankingQueryAddress).setArenaRewardContract(_arenaRewardAddress) {
                    emit ContractSetupSuccess("ArenaRankingQuery-ArenaReward");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaReward", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaReward", "Unknown");
                }
            }
            if (_arenaLeaderboardAddress != address(0)) {
                try ISetArenaLeaderboardContract(_arenaRankingQueryAddress).setArenaLeaderboardContract(_arenaLeaderboardAddress) {
                    emit ContractSetupSuccess("ArenaRankingQuery-ArenaLeaderboard");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaLeaderboard", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaLeaderboard", "Unknown");
                }
            }
        }
        if (_arenaRewardAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaRewardAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaReward-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaReward-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaReward-ArenaRankingManager", "Unknown");
            }
        }
        if (_arenaLeaderboardAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaLeaderboardAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaLeaderboard-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaLeaderboard-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaLeaderboard-ArenaRankingManager", "Unknown");
            }
        }
        if (_arenaPlayerAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaPlayerAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaPlayer-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaPlayer-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaPlayer-ArenaRankingManager", "Unknown");
            }
            try ISetNFTContract(_arenaPlayerAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("ArenaPlayer-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaPlayer-NFT", reason);
            } catch {
                emit ContractSetupFailed("ArenaPlayer-NFT", "Unknown");
            }
        }
        if (_arenaBattleAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaBattleAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaBattle-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-ArenaRankingManager", "Unknown");
            }
            try ISetBattleContract(_arenaBattleAddress).setBattleContract(_battleAddress) {
                emit ContractSetupSuccess("ArenaBattle-Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-Battle", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-Battle", "Unknown");
            }
            try ISetNFTContract(_arenaBattleAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("ArenaBattle-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-NFT", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-NFT", "Unknown");
            }
        }
    }

    function batchSetAuthorizer(
        address[] memory _contracts,
        string[] memory _names,
        address _newAuthorizer
    ) internal {
        require(_contracts.length == _names.length, "AuthorizerLib: Arrays length mismatch");
        
        for (uint256 i = 0; i < _contracts.length; i++) {
            address contractAddr = _contracts[i];
            string memory name = _names[i];
            
            if (contractAddr != address(0)) {
                try ISetAuthorizer(contractAddr).setAuthorizer(_newAuthorizer) {
                    emit ContractSetupSuccess(name);
                } catch Error(string memory reason) {
                    emit ContractSetupFailed(name, reason);
                } catch {
                    emit ContractSetupFailed(name, "Unknown");
                }
            }
        }
    }

    function setupAllAuthorizers(
        address _newAuthorizer,
        address _nftMintCore, address _nftMintBatch, address _nftMintMetadata,
        address _nftData, address _nftUpdate, address _nftTrading, address _nftBuyback,
        address _staking, address _tokenStaking, address _rewardManager,
        address _dividendManager, address _poolManager, address _weightManager,
        address _battle, address _battleSkillData, address _battleHistory,
        address _breedingCore, address _breedingMarket, address _arenaRankingManager,
        address _arenaRankingQuery, address _arenaReward, address _arenaLeaderboard,
        address _arenaPlayer, address _arenaBattle, address _tokenBurner, address _priceOracle
    ) internal {
        if (_nftMintCore != address(0)) {
            try ISetAuthorizer(_nftMintCore).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTMintCore-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTMintCore-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTMintCore-Authorizer", "Unknown");
            }
        }
        if (_nftMintBatch != address(0)) {
            try ISetAuthorizer(_nftMintBatch).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTMintBatch-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTMintBatch-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTMintBatch-Authorizer", "Unknown");
            }
        }
        if (_nftMintMetadata != address(0)) {
            try ISetAuthorizer(_nftMintMetadata).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTMintMetadata-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTMintMetadata-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTMintMetadata-Authorizer", "Unknown");
            }
        }
        if (_nftData != address(0)) {
            try ISetAuthorizer(_nftData).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTData-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTData-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTData-Authorizer", "Unknown");
            }
        }
        if (_nftUpdate != address(0)) {
            try ISetAuthorizer(_nftUpdate).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTUpdate-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-Authorizer", "Unknown");
            }
        }
        if (_nftTrading != address(0)) {
            try ISetAuthorizer(_nftTrading).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTTrading-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTTrading-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTTrading-Authorizer", "Unknown");
            }
        }
        if (_nftBuyback != address(0)) {
            try ISetAuthorizer(_nftBuyback).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("NFTBuyback-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTBuyback-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("NFTBuyback-Authorizer", "Unknown");
            }
        }
        if (_staking != address(0)) {
            try ISetAuthorizer(_staking).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("Staking-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Staking-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("Staking-Authorizer", "Unknown");
            }
        }
        if (_tokenStaking != address(0)) {
            try ISetAuthorizer(_tokenStaking).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("TokenStaking-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenStaking-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("TokenStaking-Authorizer", "Unknown");
            }
        }
        if (_rewardManager != address(0)) {
            try ISetAuthorizer(_rewardManager).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("RewardManager-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-Authorizer", "Unknown");
            }
        }
        if (_dividendManager != address(0)) {
            try ISetAuthorizer(_dividendManager).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("DividendManager-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("DividendManager-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("DividendManager-Authorizer", "Unknown");
            }
        }
        if (_poolManager != address(0)) {
            try ISetAuthorizer(_poolManager).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("PoolManager-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("PoolManager-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("PoolManager-Authorizer", "Unknown");
            }
        }
        if (_weightManager != address(0)) {
            try ISetAuthorizer(_weightManager).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("WeightManager-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("WeightManager-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("WeightManager-Authorizer", "Unknown");
            }
        }
        if (_battle != address(0)) {
            try ISetAuthorizer(_battle).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("Battle-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Battle-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("Battle-Authorizer", "Unknown");
            }
        }
        if (_battleSkillData != address(0)) {
            try ISetAuthorizer(_battleSkillData).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("BattleSkillData-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BattleSkillData-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("BattleSkillData-Authorizer", "Unknown");
            }
        }
        if (_battleHistory != address(0)) {
            try ISetAuthorizer(_battleHistory).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("BattleHistory-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BattleHistory-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("BattleHistory-Authorizer", "Unknown");
            }
        }
        if (_breedingCore != address(0)) {
            try ISetAuthorizer(_breedingCore).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("BreedingCore-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingCore-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("BreedingCore-Authorizer", "Unknown");
            }
        }
        if (_breedingMarket != address(0)) {
            try ISetAuthorizer(_breedingMarket).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("BreedingMarket-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingMarket-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("BreedingMarket-Authorizer", "Unknown");
            }
        }
        if (_arenaRankingManager != address(0)) {
            try ISetAuthorizer(_arenaRankingManager).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("ArenaRankingManager-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingManager-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingManager-Authorizer", "Unknown");
            }
        }
        if (_arenaRankingQuery != address(0)) {
            try ISetAuthorizer(_arenaRankingQuery).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("ArenaRankingQuery-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingQuery-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingQuery-Authorizer", "Unknown");
            }
        }
        if (_arenaReward != address(0)) {
            try ISetAuthorizer(_arenaReward).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("ArenaReward-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaReward-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("ArenaReward-Authorizer", "Unknown");
            }
        }
        if (_arenaLeaderboard != address(0)) {
            try ISetAuthorizer(_arenaLeaderboard).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("ArenaLeaderboard-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaLeaderboard-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("ArenaLeaderboard-Authorizer", "Unknown");
            }
        }
        if (_arenaPlayer != address(0)) {
            try ISetAuthorizer(_arenaPlayer).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("ArenaPlayer-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaPlayer-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("ArenaPlayer-Authorizer", "Unknown");
            }
        }
        if (_arenaBattle != address(0)) {
            try ISetAuthorizer(_arenaBattle).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("ArenaBattle-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-Authorizer", "Unknown");
            }
        }
        if (_tokenBurner != address(0)) {
            try ISetAuthorizer(_tokenBurner).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("TokenBurner-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenBurner-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("TokenBurner-Authorizer", "Unknown");
            }
        }
        if (_priceOracle != address(0)) {
            try ISetAuthorizer(_priceOracle).setAuthorizer(_newAuthorizer) {
                emit ContractSetupSuccess("PriceOracle-Authorizer");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("PriceOracle-Authorizer", reason);
            } catch {
                emit ContractSetupFailed("PriceOracle-Authorizer", "Unknown");
            }
        }
    }
}