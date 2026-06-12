# Authorizer setAllContracts 部署参数

## ContractAddresses 结构体字段顺序（共33个参数）

```javascript
[
  0.  tokenAddress,               // 代币合约
  1.  usdtAddress,                // USDT合约
  2.  mintModuleAddress,          // NFTMintBatch代理
  3.  upgradeModuleAddress,       // NFTUpdate代理
  4.  priceOracleAddress,         // PriceOracle代理
  5.  battleAddress,              // Battle代理
  6.  breedingCoreAddress,         // BreedingCore代理
  7.  breedingMarketAddress,       // BreedingMarket代理
  8.  stakingAddress,             // Staking代理
  9.  tokenStakingAddress,         // TokenStaking代理
  10. rewardManagerAddress,         // RewardManager代理
  11. dividendManagerAddress,       // DividendManager代理
  12. poolManagerAddress,           // PoolManager代理
  13. tradingAddress,              // NFTTrading代理
  14. arenaRankingAddress,          // ArenaRankingManager代理
  15. arenaRankingManagerAddress,   // ArenaRankingManager代理
  16. arenaRankingQueryAddress,     // ArenaRankingQuery代理
  17. arenaRewardAddress,            // ArenaReward代理
  18. arenaLeaderboardAddress,       // ArenaLeaderboard代理
  19. arenaPlayerAddress,             // ArenaPlayer代理
  20. arenaBattleAddress,             // ArenaBattle代理
  21. nftMintAddress,                  // NFTMintCore代理
  22. nftMintDelegatorAddress,          // NFTMintCore代理
  23. nftUpdateAddress,                  // NFTUpdate代理
  24. nftDataAddress,                    // NFTData代理
  25. tokenBurnerAddress,               // TokenBurner代理
  26. weightManagerAddress,              // WeightManager代理
  27. battleHistoryAddress,               // BattleHistory代理
  28. nftTradingAddress,                  // NFTTrading代理
  29. nftBuybackAddress,                   // NFTBuyback代理
  30. feeReceiverAddress,                  // 费用接收地址
  31. pancakeSwapPairAddress,               // PancakeSwap Router
  32. metadataContractAddress               // NFTMintMetadata代理
]
```

---

## 实际参数值（根据合约.txt）

```javascript
[
  "0x1234567890abcdef1234567890abcdef12345678",  // 0. tokenAddress - 代币合约
  "0x55d398326f99059fF775485246999027B3197955",  // 1. usdtAddress - USDT合约
  "0x1887e7cC8303E26aD4BD23486881333A7C121184",  // 2. mintModuleAddress - NFTMintBatch代理
  "0xD2908D072983503Cd54f68D7FD992aD5ea60A054",  // 3. upgradeModuleAddress - NFTUpdate代理
  "0xA9CBAbF288e821C4b19D1DAd8750c3dF2e53b5d9",  // 4. priceOracleAddress - PriceOracle代理
  "0xC233Fcde95E16dE7B852f6a8E5509306A6512c3A",  // 5. battleAddress - Battle代理
  "0x6F7C43971810bBF189E36546155C7C8912728A6B",  // 6. breedingCoreAddress - BreedingCore代理
  "0x8e8bEB884f419E04b50eeedeca2Fd8e8522e125b",  // 7. breedingMarketAddress - BreedingMarket代理
  "0x35B1b1441a29eB5EAF7527fa88f7Cd94CEE0eB14",  // 8. stakingAddress - Staking代理
  "0xB3fe1F4E2E94253468BDFC6690Dba4A9871e750c",  // 9. tokenStakingAddress - TokenStaking代理
  "0x5813AE83ddeD8cF4D2a070A4B695510CaE1b481b",  // 10. rewardManagerAddress - RewardManager代理
  "0x5480Cd670DB16b4ec635B54B9FBbA2643c1Fa1F0",  // 11. dividendManagerAddress - DividendManager代理
  "0x561fd60b26b860aE84298C646eA8797c76BdeC84",  // 12. poolManagerAddress - PoolManager代理
  "0xe7DE02a826C3894dA7DEA2A4e526b1128B013F78",  // 13. tradingAddress - NFTTrading代理
  "0x3b4D0Ad0e53cc7588aF127d2456B9D688B2186d6",  // 14. arenaRankingAddress - ArenaRankingManager代理
  "0x3b4D0Ad0e53cc7588aF127d2456B9D688B2186d6",  // 15. arenaRankingManagerAddress - ArenaRankingManager代理
  "0xb7952f622e9622da4d46bF2a80f6695a18D70EA3",  // 16. arenaRankingQueryAddress - ArenaRankingQuery代理
  "0x0a6D0f7fEDeC99a716C63930372ecfA75948092a",  // 17. arenaRewardAddress - ArenaReward代理
  "0x5337fdfDedE8B651f313BEC33500B11Fb3EEeeB0",  // 18. arenaLeaderboardAddress - ArenaLeaderboard代理
  "0x96A5A17d0C475e5802a0dE8Ac4bDE43a69a86EbA",  // 19. arenaPlayerAddress - ArenaPlayer代理
  "0x741F560216721b5060CF0752caEd9ebE902743AC",  // 20. arenaBattleAddress - ArenaBattle代理
  "0xAc3dFE1683BC680ECC84b3B433CD067748e9ADC2",  // 21. nftMintAddress - NFTMintCore代理
  "0xAc3dFE1683BC680ECC84b3B433CD067748e9ADC2",  // 22. nftMintDelegatorAddress - NFTMintCore代理
  "0xD2908D072983503Cd54f68D7FD992aD5ea60A054",  // 23. nftUpdateAddress - NFTUpdate代理
  "0xeD96F81BcE06ca980d8c296Ce3D41A741957397A",  // 24. nftDataAddress - NFTData代理
  "0xd1436Ca12ebff0d0626fb9841e75F25289277bb3",  // 25. tokenBurnerAddress - TokenBurner代理
  "0x9f5DFfDDE0364A8C6f29A494B818D681716180Ac",  // 26. weightManagerAddress - WeightManager代理
  "0x30Dc6b0eE830DbEBb2726E17d9aA0c364b3F846C",  // 27. battleHistoryAddress - BattleHistory代理
  "0xe7DE02a826C3894dA7DEA2A4e526b1128B013F78",  // 28. nftTradingAddress - NFTTrading代理
  "0xBA2451b5164fD5510C0b5722a056761A25F61be6",  // 29. nftBuybackAddress - NFTBuyback代理
  "0xCB02ec8A0b5F73cea1b29375202443b2eB80A91D",  // 30. feeReceiverAddress - 费用接收地址
  "0x10ed43c718714eb63d5aa57b78b54704e256024e",  // 31. pancakeSwapPairAddress - PancakeSwap Router
  "0xF3eeC923f3371F2b93658ad9430F1046B77B706c"   // 32. metadataContractAddress - NFTMintMetadata代理
]
```

---

## Remix 部署说明

### 1. 选择 Authorizer 代理合约

在 Remix 中部署时，选择：
- **Contract**: `Authorizer` (不是 `AuthorizerImplementation`)
- **At Address**: `0xf62b3B852FB863ADd01f28968d21EB14226E7108`

### 2. 调用 setAllContracts

展开合约的 `setAllContracts` 函数，输入以下参数：

```javascript
(
  "0x1234567890abcdef1234567890abcdef12345678",  // tokenAddress
  "0x55d398326f99059fF775485246999027B3197955",  // usdtAddress
  "0x1887e7cC8303E26aD4BD23486881333A7C121184",  // mintModuleAddress
  "0xD2908D072983503Cd54f68D7FD992aD5ea60A054",  // upgradeModuleAddress
  "0xA9CBAbF288e821C4b19D1DAd8750c3dF2e53b5d9",  // priceOracleAddress
  "0xC233Fcde95E16dE7B852f6a8E5509306A6512c3A",  // battleAddress
  "0x6F7C43971810bBF189E36546155C7C8912728A6B",  // breedingCoreAddress
  "0x8e8bEB884f419E04b50eeedeca2Fd8e8522e125b",  // breedingMarketAddress
  "0x35B1b1441a29eB5EAF7527fa88f7Cd94CEE0eB14",  // stakingAddress
  "0xB3fe1F4E2E94253468BDFC6690Dba4A9871e750c",  // tokenStakingAddress
  "0x5813AE83ddeD8cF4D2a070A4B695510CaE1b481b",  // rewardManagerAddress
  "0x5480Cd670DB16b4ec635B54B9FBbA2643c1Fa1F0",  // dividendManagerAddress
  "0x561fd60b26b860aE84298C646eA8797c76BdeC84",  // poolManagerAddress
  "0xe7DE02a826C3894dA7DEA2A4e526b1128B013F78",  // tradingAddress
  "0x3b4D0Ad0e53cc7588aF127d2456B9D688B2186d6",  // arenaRankingAddress
  "0x3b4D0Ad0e53cc7588aF127d2456B9D688B2186d6",  // arenaRankingManagerAddress
  "0xb7952f622e9622da4d46bF2a80f6695a18D70EA3",  // arenaRankingQueryAddress
  "0x0a6D0f7fEDeC99a716C63930372ecfA75948092a",  // arenaRewardAddress
  "0x5337fdfDedE8B651f313BEC33500B11Fb3EEeeB0",  // arenaLeaderboardAddress
  "0x96A5A17d0C475e5802a0dE8Ac4bDE43a69a86EbA",  // arenaPlayerAddress
  "0x741F560216721b5060CF0752caEd9ebE902743AC",  // arenaBattleAddress
  "0xAc3dFE1683BC680ECC84b3B433CD067748e9ADC2",  // nftMintAddress
  "0xAc3dFE1683BC680ECC84b3B433CD067748e9ADC2",  // nftMintDelegatorAddress
  "0xD2908D072983503Cd54f68D7FD992aD5ea60A054",  // nftUpdateAddress
  "0xeD96F81BcE06ca980d8c296Ce3D41A741957397A",  // nftDataAddress
  "0xd1436Ca12ebff0d0626fb9841e75F25289277bb3",  // tokenBurnerAddress
  "0x9f5DFfDDE0364A8C6f29A494B818D681716180Ac",  // weightManagerAddress
  "0x30Dc6b0eE830DbEBb2726E17d9aA0c364b3F846C",  // battleHistoryAddress
  "0xe7DE02a826C3894dA7DEA2A4e526b1128B013F78",  // nftTradingAddress
  "0xBA2451b5164fD5510C0b5722a056761A25F61be6",  // nftBuybackAddress
  "0xCB02ec8A0b5F73cea1b29375202443b2eB80A91D",  // feeReceiverAddress
  "0x10ed43c718714eb63d5aa57b78b54704e256024e",  // pancakeSwapPairAddress
  "0xF3eeC923f3371F2b93658ad9430F1046B77B706c"   // metadataContractAddress
)
```

### 3. 点击 "Transact" 按钮

确保当前钱包地址是 Authorizer 合约的 owner (`0x1FDf5ef4eb643c6FC0c25BF0fB61b4Ff2f93Ba93`)
