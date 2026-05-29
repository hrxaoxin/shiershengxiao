# 合约部署与地址配置指南

## 1. 部署前准备

在部署任何合约之前，请确保：

- 安装 Hardhat/Truffle 部署框架
- 配置好 BSC 主网或测试网的 RPC 节点
- 拥有足够的 BNB 作为 gas 费用
- 准备好部署账户的私钥（安全存储）

## 2. 合约部署顺序

请按照以下顺序部署合约：

```
1. ZodiacToken (代币合约)
2. NFTMint (NFT 铸造合约)
3. NFTUpdate (NFT 升级合约)
4. Staking (NFT 质押合约)
5. TokenStaking (代币质押合约)
6. Breeding (NFT 孕育合约)
7. Battle (战斗计算合约)
8. Arena (竞技场合约)
9. NFTTrading (NFT 交易合约)
10. DividendManager (分红管理合约)
11. RewardManager (奖励管理合约)
12. WeightManager (权重管理合约)
13. PoolManager (资金池管理合约)
14. TokenBurner (代币销毁合约)
15. Authorizer (权限管理合约)
```

## 3. 更新 config.js 配置

部署完成后，请更新 `config.js` 中的 `CONTRACT_ADDRESSES` 配置：

```javascript
const CONTRACT_ADDRESSES = {
    tokenContract: "0x...",           // ZodiacToken 地址
    rewardManager: "0x...",          // RewardManager 地址
    dividendManager: "0x...",        // DividendManager 地址
    weightManager: "0x...",          // WeightManager 地址
    poolManager: "0x...",            // PoolManager 地址
    tokenBurner: "0x...",            // TokenBurner 地址
    nftMint: "0x...",                // NFTMint 地址
    nftUpdate: "0x...",              // NFTUpdate 地址
    nftTrading: "0x...",             // NFTTrading 地址
    breeding: "0x...",               // Breeding 地址
    staking: "0x...",                // Staking 地址
    tokenStaking: "0x...",           // TokenStaking 地址
    arena: "0x...",                  // Arena 地址
    battle: "0x...",                 // Battle 地址
    authorizer: "0x..."              // Authorizer 地址
};
```

## 4. 合约间依赖关系

部署后需要进行以下配置（通过合约的 `initialize` 或相关 setter 方法）：

- **Authorizer**: 设置其他合约的管理员权限
- **Arena**: 设置 Battle、NFTMint 和 TokenContract 地址
- **Staking**: 设置 RewardTokenContract 地址
- **Breeding**: 设置 NFTMintContract 地址
- **DividendManager**: 设置 TokenContract 和 Authorizer 地址
- **NFTTrading**: 设置 DividendPool 和 RewardPool 地址

## 5. 环境变量配置（可选）

可以使用环境变量来覆盖默认地址：

```javascript
window.ZODIAC_TOKENCONTRACT_ADDRESS = "0x...";
window.ZODIAC_REWARDMANAGER_ADDRESS = "0x...";
// ... 其他合约环境变量
```

环境变量命名规则：`ZODIAC_{合约名大写}_ADDRESS`

## 6. 验证部署

部署完成后，请运行以下验证步骤：

1. 在 BscScan 上验证所有合约源代码
2. 调用每个合约的基本 view 方法确认功能正常
3. 在 config.js 中更新地址并删除 validateContractAddresses 中的测试地址警告
4. 测试前端与合约的交互
