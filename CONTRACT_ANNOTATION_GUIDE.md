# 合约注释规范指南

## 文件头注释模板

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title [合约名称]
 * @dev [合约功能描述]
 * 
 * 功能：
 * - [功能1]
 * - [功能2]
 * - [功能3]
 * 
 * 访问控制：
 * - onlyOwner: 仅合约所有者
 * - onlyAuthorized: 所有者或授权合约
 * 
 * @author [作者]
 * @version [版本]
 */
```

## 状态变量注释模板

```solidity
// ============ 状态变量 ============

/// @dev [简要描述]
/// [详细说明，如果需要]
[类型] public [变量名];

/// @dev [映射描述]
/// key: [key描述]
/// value: [value描述]
mapping([keyType] => [valueType]) public [变量名];
```

## 事件注释模板

```solidity
// ============ 事件 ============

/**
 * @dev [事件描述]
 * @param [参数名] [参数描述]
 */
event [事件名]([参数列表]);
```

## 结构体注释模板

```solidity
// ============ 结构体 ============

/**
 * @dev [结构体描述]
 */
struct [结构体名] {
    [类型] [字段名]; // [字段描述]
}
```

## 修饰符注释模板

```solidity
// ============ 修饰符 ============

/**
 * @dev [修饰符描述]
 */
modifier [修饰符名]() {
    require([条件], "[错误消息]");
    _;
}
```

## 函数注释模板

### 初始化函数
```solidity
/**
 * @dev 初始化合约
 * @param [参数名] [参数描述]
 */
function initialize([参数列表]) external initializer {
```

### 设置函数
```solidity
/**
 * @dev 设置[功能]
 * @param [参数名] [参数描述]
 * @notice [注意事项]
 */
function set[功能]([参数类型] [参数名]) external onlyOwner {
```

### 查询函数（view/pure）
```solidity
/**
 * @dev [功能描述]
 * @param [参数名] [参数描述]
 * @return [返回值描述]
 */
function [函数名]([参数列表]) external view returns ([返回类型]) {
```

### 写函数
```solidity
/**
 * @dev [功能描述]
 * @param [参数名] [参数描述]
 * @notice [注意事项]
 * @custom:requirements [前置条件]
 * @custom:events [触发的事件]
 */
function [函数名]([参数列表]) external whenNotPaused nonReentrant returns ([返回类型]) {
```

### 内部函数
```solidity
/**
 * @dev [功能描述]
 * @param [参数名] [参数描述]
 * @return [返回值描述]
 */
function _[函数名]([参数列表]) internal [view/pure] returns ([返回类型]) {
```

## 各合约特定注释

### NFTMint.sol

```solidity
// ============ 铸造函数 ============

/**
 * @dev 铸造指定类型的NFT
 * @param to 接收地址
 * @param zodiacType 生肖类型 (0-119)
 * @return tokenId NFT ID
 * @notice 需要合约未暂停且允许公开铸造
 * @custom:events Mint
 */
function mint(address to, uint256 zodiacType) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256);

/**
 * @dev 普通铸造（随机）
 * @param to 接收地址
 * @return tokenId NFT ID
 * @notice 随机生成水/风/火属性的NFT
 * @custom:events Mint
 */
function mintNormal(address to) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256);

/**
 * @dev 稀有铸造（随机）
 * @param to 接收地址
 * @return tokenId NFT ID
 * @notice 随机生成光/暗属性的NFT
 * @custom:events Mint
 */
function mintRare(address to) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256);

// ============ 查询函数 ============

/**
 * @dev 获取NFT完整数据
 * @param tokenId NFT ID
 * @return tokenType_ 类型
 * @return attack 攻击力
 * @return defense 防御力
 * @return health 生命值
 * @return speed 速度
 * @return level 等级
 * @return rank 排名
 * @return name 名称
 * @return imageUrl 图片URL
 */
function getNFTData(uint256 tokenId) external view returns (...);
```

### Staking.sol

```solidity
// ============ 质押函数 ============

/**
 * @dev 质押NFT
 * @param tokenIds NFT ID数组
 * @notice 需要用户已授权合约转移NFT
 * @notice 自动触发每日奖励计算
 * @custom:requirements NFT未被质押、用户是NFT所有者
 * @custom:events Staked
 */
function stake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant;

/**
 * @dev 赎回NFT
 * @param tokenIds NFT ID数组
 * @notice 需要超过最短质押时间
 * @notice 自动结算待领取奖励
 * @custom:requirements 用户是质押者、超过锁定期
 * @custom:events Unstaked
 */
function unstake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant;

/**
 * @dev 领取奖励
 * @notice 实时计算所有质押NFT的奖励
 * @custom:requirements 有待领取奖励
 * @custom:events RewardClaimed
 */
function claimReward() external whenNotPaused nonReentrant;
```

### Battle.sol

```solidity
// ============ 战斗函数 ============

/**
 * @dev 挑战其他玩家
 * @param challengerId 挑战者NFT ID
 * @param challengedId 被挑战者NFT ID
 * @param challengerTeam 挑战者战队（6个NFT）
 * @param challengedTeam 被挑战者战队（6个NFT）
 * @param challengedAddress 被挑战者地址
 * @return success 是否成功
 * @return winner 获胜方 (1=挑战者, 2=被挑战者, 0=平局)
 * @notice 模拟战斗时 challengedAddress 为 address(0)
 * @custom:requirements 战队有效、NFT所有权正确
 * @custom:events BattleStarted, BattleEnded
 */
function challenge(...) external nonReentrant returns (bool, uint256);

/**
 * @dev 模拟战斗
 * @param team1 战队1
 * @param team2 战队2
 * @return 获胜方
 */
function simulateBattle(uint256[6] calldata team1, uint256[6] calldata team2) external view returns (uint8);
```

### Breeding.sol

```solidity
// ============ 繁殖函数 ============

/**
 * @dev 创建自繁殖对
 * @param fatherId 父亲NFT ID
 * @param motherId 母亲NFT ID
 * @param coOwnerId 共同拥有者NFT ID（可选）
 * @return pairId 繁殖对ID
 * @notice 双方必须同生肖、不同性别、等级≥5
 * @notice 冷却时间12小时
 * @custom:requirements 双方NFT未被繁殖中、用户是双方所有者
 * @custom:events BreedingPairCreated
 */
function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external nonReentrant whenNotPaused returns (uint256);

/**
 * @dev 完成繁殖
 * @param pairId 繁殖对ID
 * @return childId 子代NFT ID（给母方）
 * @return maleChildId 子代NFT ID（给父方，市场繁殖时）
 * @notice 自繁殖产生1个子代，市场繁殖产生2个子代
 * @custom:requirements 冷却时间结束
 * @custom:events BreedingCompleted, MaleChildGenerated
 */
function completeBreeding(uint256 pairId) external nonReentrant whenNotPaused returns (uint256, uint256);
```

### DividendManager.sol

```solidity
// ============ 分红函数 ============

/**
 * @dev 领取分红
 * @return amount 领取金额
 * @notice 基于用户权重和累计分红计算
 * @custom:requirements 用户有权重、有待领取分红
 * @custom:events DividendClaimed
 */
function claim() external nonReentrant whenNotPaused returns (uint256);

/**
 * @dev 更新用户权重
 * @param user 用户地址
 * @param level NFT等级
 * @param isAdd 是否增加（true=增加，false=减少）
 * @param element 元素类型（0-4）
 * @notice 自动结算用户当前未领取的分红
 */
function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external onlyAuthorized;
```

### ArenaRanking.sol

```solidity
// ============ 战斗函数 ============

/**
 * @dev 挑战模拟玩家
 * @param playerTeam 玩家战队（6个NFT）
 * @param mockIndex 模拟玩家索引
 * @return success 是否成功
 * @notice 每日10次挑战机会
 * @custom:requirements 战队已质押、有剩余挑战次数、冷却时间结束
 * @custom:events ChallengeResult
 */
function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool);

/**
 * @dev 挑战真实玩家
 * @param challengedPlayer 被挑战者地址
 * @param playerTeam 玩家战队
 * @return success 是否成功
 * @custom:requirements 双方有剩余挑战次数、被挑战者有战队
 * @custom:events ChallengeResult
 */
function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external returns (bool);

/**
 * @dev 质押NFT到竞技场
 * @param tokenIds NFT ID数组
 * @notice NFT将被锁定在竞技场合约中
 * @custom:events NFTsStaked
 */
function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused;

/**
 * @dev 设置战斗战队
 * @param tokenIds 战队NFT ID数组（6个）
 * @notice 所有NFT必须已质押
 * @custom:events BattleTeamSet
 */
function setBattleTeam(uint256[6] calldata tokenIds) external;
```

### NFTTrading.sol

```solidity
// ============ 交易函数 ============

/**
 * @dev 上架NFT
 * @param tokenId NFT ID
 * @param priceWei 价格（Wei）
 * @notice 需要用户授权合约转移NFT
 * @custom:requirements 价格是有效范围、用户是NFT所有者
 * @custom:events NFTListed
 */
function listNFT(uint256 tokenId, uint256 priceWei) external whenNotPaused nonReentrant;

/**
 * @dev 购买NFT
 * @param tokenId NFT ID
 * @notice 支付BNB购买，5%手续费
 * @custom:requirements NFT在售、支付金额足够
 * @custom:events NFTBought
 */
function buyNFT(uint256 tokenId) external payable whenNotPaused nonReentrant;

/**
 * @dev 下架NFT
 * @param tokenId NFT ID
 * @custom:events NFTDelisted
 */
function delistNFT(uint256 tokenId) external whenNotPaused nonReentrant;
```

### NFTUpdate.sol

```solidity
// ============ 升级函数 ============

/**
 * @dev 使用NFT升级
 * @param tokenId 要升级的NFT ID
 * @return newLevel 新等级
 * @notice 消耗同类型同等级的其他NFT
 * @notice 1→2消耗1个，2→3消耗2个，以此类推
 * @custom:requirements 有足夜消耗品NFT、等级<5
 * @custom:events CardBurned, CardUpgraded
 */
function upgradeWithNFT(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8);

/**
 * @dev 使用代币升级
 * @param tokenId 要升级的NFT ID
 * @return newLevel 新等级
 * @notice 消耗代币直接升级
 * @custom:events TokenUpgraded
 */
function upgradeWithToken(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8);

/**
 * @dev 使用USD价值升级
 * @param tokenId 要升级的NFT ID
 * @return newLevel 新等级
 * @notice 基于PancakeSwap价格计算代币数量
 * @notice 有价格波动保护机制
 * @custom:events USDValueUpgraded
 */
function upgradeWithUSDValue(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8);
```

### TokenBurner.sol

```solidity
// ============ 铸造入口 ============

/**
 * @dev 销毁代币并铸造NFT
 * @param user 用户地址
 * @param isRare 是否稀有铸造
 * @return success 是否成功
 * @notice 普通铸造消耗8888代币，稀有铸造消耗88888代币
 * @notice 代币被转移到黑洞地址销毁
 * @custom:events TokenBurned, NFTMinted
 */
function burnAndMint(address user, bool isRare) external onlyAuthorized nonReentrant whenNotPaused returns (bool);
```

### Authorizer.sol

```solidity
// ============ 合约管理 ============

/**
 * @dev 设置所有合约地址
 * @param _addresses 合约地址结构体
 * @notice 需要等待2天延迟期后才能执行
 * @notice 使用多重签名安全机制
 * @custom:events ContractAddressChangeScheduled
 */
function setAllContracts(ContractAddresses calldata _addresses) external onlyOwner whenNotPaused;

/**
 * @dev 执行合约地址设置
 * @param _addresses 合约地址结构体
 * @notice 必须在延迟期后、过期前执行
 * @custom:events ContractAddressesUpdated
 */
function executeContractAddresses(ContractAddresses calldata _addresses) external onlyOwner whenNotPaused;
```

## 注释最佳实践

1. **使用 NatSpec 格式**: `/** ... */`
2. **所有公共函数必须有注释**
3. **复杂逻辑需要详细说明**
4. **参数和返回值必须说明类型和含义**
5. **事件触发条件要说明**
6. **前置条件用 @custom:requirements 标记**
7. **安全考虑用 @notice 强调**

## 常用标签

- `@title`: 合约标题
- `@dev`: 开发者注释
- `@notice`: 用户注意事项
- `@param`: 参数说明
- `@return`: 返回值说明
- `@custom:requirements`: 前置条件
- `@custom:events`: 触发的事件
- `@author`: 作者
- `@version`: 版本
