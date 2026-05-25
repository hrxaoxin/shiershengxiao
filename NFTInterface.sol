// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTInterface
 * @dev NFT主合约接口定义，定义与其他合约交互的标准接口
 *
 * 本接口遵循ERC165标准，用于合约间的互操作性
 * 其他合约（如战斗、繁殖、交易等模块）通过此接口与NFT合约交互
 *
 * 主要功能：
 * - 查询NFT信息（类型、等级、属性等）
 * - 管理NFT所有权
 * - 铸造新NFT
 * - 升级NFT
 * - 处理NFT繁殖
 */
interface INFT {
    /**
     * @dev 铸造新NFT
     * @param to 接收NFT的地址
     * @param zodiacType NFT类型（0-119）
     * @return uint256 新铸造的NFT ID
     */
    function mint(address to, uint256 zodiacType) external returns (uint256);

    /**
     * @dev 批量铸造NFT
     * @param to 接收NFT的地址
     * @param zodiacTypes NFT类型数组
     * @return uint256[] 新铸造的NFT ID数组
     */
    function mintBatch(address to, uint256[] calldata zodiacTypes) external returns (uint256[] memory);

    /**
     * @dev 获取NFT类型
     * @param tokenId NFT ID
     * @return uint256 NFT类型（0-119）
     */
    function getNFTType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT信息
     * @param tokenId NFT ID
     * @return tuple (类型, 等级, 铸造时间)
     */
    function getNFTInfo(uint256 tokenId) external view returns (uint256, uint8, uint256);

    /**
     * @dev 检查NFT是否为稀有属性
     * @param tokenId NFT ID
     * @return bool 是否为稀有（暗/光属性）
     */
    function isRare(uint256 tokenId) external view returns (bool);

    /**
     * @dev 检查NFT是否为5级
     * @param tokenId NFT ID
     * @return bool 是否为5级
     */
    function isMaxLevel(uint256 tokenId) external view returns (bool);

    /**
     * @dev 获取NFT当前等级
     * @param tokenId NFT ID
     * @return uint8 等级（1-5）
     */
    function getNFTLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 设置NFT等级（内部使用，由升级模块调用）
     * @param tokenId NFT ID
     * @param newLevel 新等级
     */
    function setNFTLevel(uint256 tokenId, uint256 newLevel) external;

    /**
     * @dev 获取NFT所有者
     * @param tokenId NFT ID
     * @return address 所有者地址
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev 安全转移NFT（带回调）
     * @param from 发送方地址
     * @param to 接收方地址
     * @param tokenId NFT ID
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 转移NFT
     * @param from 发送方地址
     * @param to 接收方地址
     * @param tokenId NFT ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 批量查询NFT信息
     * @param tokenIds NFT ID数组
     * @return tuple[] NFT信息数组
     */
    function getNFTInfoBatch(uint256[] calldata tokenIds) external view returns (uint256[] memory);

    /**
     * @dev 获取合约名称
     * @return string 合约名称
     */
    function name() external view returns (string memory);

    /**
     * @dev 获取合约符号
     * @return string 合约符号
     */
    function symbol() external view returns (string memory);
}

/**
 * @title IBreeding
 * @dev 繁殖合约接口
 *
 * 定义繁殖相关的功能：
 * - 创建繁殖对（自繁殖/市场繁殖）
 * - 完成繁殖获取子代
 * - 查询繁殖信息
 */
interface IBreeding {
    /**
     * @dev 创建自繁殖对
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param coOwnerId 共有人NFT ID（用于分成）
     * @return uint256 繁殖对ID
     */
    function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external returns (uint256);

    /**
     * @dev 创建市场繁殖对
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 公NFT所有者
     * @param femaleOwner 母NFT所有者
     * @param maleCoOwnerId 公NFT共有人
     * @param femaleCoOwnerId 母NFT共有人
     * @return uint256 繁殖对ID
     */
    function createMarketBreedingPair(
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner,
        uint256 maleCoOwnerId,
        uint256 femaleCoOwnerId
    ) external returns (uint256);

    /**
     * @dev 完成繁殖获取子代
     * @param pairId 繁殖对ID
     * @return uint256 子代NFT ID
     */
    function completeBreeding(uint256 pairId) external returns (uint256);

    /**
     * @dev 取消繁殖
     * @param pairId 繁殖对ID
     */
    function cancelBreeding(uint256 pairId) external;

    /**
     * @dev 获取繁殖信息
     * @param pairId 繁殖对ID
     * @return tuple 繁殖详情
     */
    function getBreedingInfo(uint256 pairId) external view returns (
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner,
        uint256 startTime,
        uint256 breedingType,
        uint256 status
    );
}

/**
 * @title IBattle
 * @dev 战斗合约接口
 *
 * 定义战斗相关的功能：
 * - 创建战斗房间
 * - 执行战斗
 * - 获取战斗结果
 */
interface IBattle {
    /**
     * @dev 挑战对手
     * @param challengerId 挑战者NFT ID
     * @param challengedId 被挑战者NFT ID
     * @param challengerTeam 挑战者队伍（6个NFT ID）
     * @param challengedTeam 被挑战者队伍（6个NFT ID）
     * @return tuple 战斗结果
     */
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam
    ) external returns (bool, uint256, uint256[] memory);

    /**
     * @dev 模拟战斗（不改变状态）
     * @param team1 队伍1
     * @param team2 队伍2
     * @return uint8 获胜队伍
     */
    function simulateBattle(uint256[6] calldata team1, uint256[6] calldata team2) external view returns (uint8);

    /**
     * @dev 获取战斗记录数量
     * @return uint256 战斗记录数
     */
    function getBattleLogCount() external view returns (uint256);

    /**
     * @dev 获取战斗记录
     * @param index 记录索引
     * @return tuple 战斗详情
     */
    function getBattleLog(uint256 index) external view returns (
        uint256 battleId,
        uint256 challengerId,
        uint256 challengedId,
        uint8 winner,
        uint256 timestamp
    );
}

/**
 * @title IArenaRanking
 * @dev 竞技场排名合约接口
 *
 * 定义竞技场排名功能：
 * - 每日挑战
     * - 排名更新
     * - 奖励领取
 */
interface IArenaRanking {
    /**
     * @dev 挑战虚拟玩家
     * @param playerTeam 玩家队伍（6个NFT ID）
     * @param mockIndex 虚拟玩家索引
     * @return bool 是否获胜
     */
    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool);

    /**
     * @dev 挑战真实玩家
     * @param playerTeam 玩家队伍
     * @param challengedPlayer 被挑战玩家地址
     * @return bool 是否获胜
     */
    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external returns (bool);

    /**
     * @dev 获取玩家排名
     * @param player 玩家地址
     * @return uint256 排名（1-based）
     */
    function getPlayerRank(address player) external view returns (uint256);

    /**
     * @dev 获取排名信息
     * @param startIndex 起始索引
     * @param endIndex 结束索引
     * @return tuple[] 排名信息数组
     */
    function getRankings(uint256 startIndex, uint256 endIndex) external view returns (
        address[] memory players,
        uint256[] memory scores,
        uint256[] memory tiers
    );

    /**
     * @dev 领取每日奖励
     */
    function claimDailyReward() external;

    /**
     * @dev 获取当前赛季信息
     * @return tuple 赛季信息
     */
    function getSeasonInfo() external view returns (uint256, uint256, uint256);
}

/**
 * @title IStaking
 * @dev NFT质押合约接口
 *
 * 定义NFT质押功能：
 * - 质押NFT
 * - 解除质押
 * - 领取奖励
 */
interface IStaking {
    /**
     * @dev 质押NFT
     * @param tokenIds NFT ID数组
     */
    function stake(uint256[] calldata tokenIds) external;

    /**
     * @dev 解除质押
     * @param tokenIds NFT ID数组
     */
    function unstake(uint256[] calldata tokenIds) external;

    /**
     * @dev 领取质押奖励
     */
    function claimReward() external;

    /**
     * @dev 获取质押信息
     * @param tokenId NFT ID
     * @return tuple 质押详情
     */
    function getStakingInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 stakeTime,
        uint256 lastClaimTime,
        uint256 accumulatedReward
    );

    /**
     * @dev 获取用户质押的NFT列表
     * @param user 用户地址
     * @return uint256[] 质押的NFT ID数组
     */
    function getUserStakedNFTs(address user) external view returns (uint256[] memory);

    /**
     * @dev 获取待领取奖励
     * @param user 用户地址
     * @return uint256 奖励数量
     */
    function getPendingReward(address user) external view returns (uint256);
}

/**
 * @title ITokenStaking
 * @dev 代币质押合约接口
 *
 * 定义代币质押功能：
 * - 质押代币
 * - 解除质押
 * - 领取奖励
 */
interface ITokenStaking {
    /**
     * @dev 质押代币
     * @param amount 质押数量
     */
    function stake(uint256 amount) external;

    /**
     * @dev 解除质押
     * @param amount 解除数量
     */
    function unstake(uint256 amount) external;

    /**
     * @dev 领取奖励
     */
    function claimReward() external;

    /**
     * @dev 获取质押信息
     * @param user 用户地址
     * @return tuple 质押详情
     */
    function getStakingInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 lastClaimTime,
        uint256 accumulatedReward
    );

    /**
     * @dev 获取待领取奖励
     * @param user 用户地址
     * @return uint256 奖励数量
     */
    function getPendingReward(address user) external view returns (uint256);
}

/**
 * @title IRewardManager
 * @dev 奖励管理合约接口
 *
 * 定义奖励分发功能：
 * - 分发战斗奖励
 * - 分发质押奖励
 * - 分发交易分红
 */
interface IRewardManager {
    /**
     * @dev 分发战斗奖励
     * @param winner 获胜者地址
     * @param loser 失败者地址
     * @param battleType 战斗类型
     */
    function distributeBattleReward(address winner, address loser, uint256 battleType) external;

    /**
     * @dev 添加质押池奖励
     * @param amount 奖励数量
     * @param poolType 池子类型（NFT质押/代币质押/竞技场）
     */
    function addStakingReward(uint256 amount, uint256 poolType) external;

    /**
     * @dev 领取分红
     * @param user 用户地址
     * @return uint256 分红数量
     */
    function claimDividend(address user) external returns (uint256);

    /**
     * @dev 获取用户可领取分红
     * @param user 用户地址
     * @return uint256 分红数量
     */
    function getDividend(address user) external view returns (uint256);
}

/**
 * @title IDividendManager
 * @dev 分红管理合约接口
 *
 * 定义交易分红功能：
 * - 添加分红池
 * - 领取分红
 * - 计算用户份额
 */
interface IDividendManager {
    /**
     * @dev 添加到分红池
     * @param amount 数量
     */
    function addDividendPool(uint256 amount) external;

    /**
     * @dev 领取分红
     * @return uint256 领取数量
     */
    function claim() external returns (uint256);

    /**
     * @dev 获取可领取分红
     * @param user 用户地址
     * @return uint256 分红数量
     */
    function getClaimableDividend(address user) external view returns (uint256);

    /**
     * @dev 获取用户权重
     * @param user 用户地址
     * @return uint256 用户权重
     */
    function getUserWeight(address user) external view returns (uint256);

    /**
     * @dev 获取总权重
     * @return uint256 总权重
     */
    function getTotalWeight() external view returns (uint256);
}

/**
 * @title IPoolManager
 * @dev 资金池管理合约接口
 *
 * 定义资金池功能：
 * - 添加到池子
 * - 从池子提取
 * - 查询池子余额
 */
interface IPoolManager {
    /**
     * @dev 添加到NFT质押池
     * @param amount 数量
     */
    function addToNFTStakingPool(uint256 amount) external;

    /**
     * @dev 添加到代币质押池
     * @param amount 数量
     */
    function addToTokenStakingPool(uint256 amount) external;

    /**
     * @dev 添加到竞技场奖励池
     * @param amount 数量
     */
    function addToArenaRewardPool(uint256 amount) external;

    /**
     * @dev 从NFT质押池提取
     * @param amount 数量
     */
    function withdrawFromNFTStakingPool(uint256 amount) external;

    /**
     * @dev 从代币质押池提取
     * @param amount 数量
     */
    function withdrawFromTokenStakingPool(uint256 amount) external;

    /**
     * @dev 获取池子余额
     * @param poolType 池子类型
     * @return uint256 余额
     */
    function getPoolBalance(uint256 poolType) external view returns (uint256);

    /**
     * @dev 紧急提取（仅管理员）
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 数量
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external;
}

/**
 * @title INFTTrading
 * @dev NFT交易合约接口
 *
 * 定义NFT交易市场功能：
 * - 上架NFT
 * - 下架NFT
 * - 购买NFT
 * - 设置价格
 */
interface INFTTrading {
    /**
     * @dev 上架NFT
     * @param tokenId NFT ID
     * @param priceWei 价格（以Wei为单位）
     */
    function listNFT(uint256 tokenId, uint256 priceWei) external;

    /**
     * @dev 下架NFT
     * @param tokenId NFT ID
     */
    function delistNFT(uint256 tokenId) external;

    /**
     * @dev 购买NFT
     * @param tokenId NFT ID
     */
    function buyNFT(uint256 tokenId) external payable;

    /**
     * @dev 更新NFT价格
     * @param tokenId NFT ID
     * @param newPriceWei 新价格
     */
    function updatePrice(uint256 tokenId, uint256 newPriceWei) external;

    /**
     * @dev 获取挂牌信息
     * @param tokenId NFT ID
     * @return tuple 挂牌详情
     */
    function getListingInfo(uint256 tokenId) external view returns (
        address seller,
        uint256 priceWei,
        uint256 listTime
    );

    /**
     * @dev 获取在售NFT列表
     * @return uint256[] 在售NFT ID数组
     */
    function getListedNFTs() external view returns (uint256[] memory);
}

/**
 * @title IUpgradeModule
 * @dev 升级模块接口
 *
 * 定义NFT升级功能：
 * - 使用NFT升级
 * - 使用代币升级
 * - 使用USDT升级
 */
interface IUpgradeModule {
    /**
     * @dev 使用NFT升级
     * @param tokenId 主NFT ID
     */
    function upgradeWithNFT(uint256 tokenId) external;

    /**
     * @dev 使用代币升级
     * @param tokenId NFT ID
     */
    function upgradeWithToken(uint256 tokenId) external;

    /**
     * @dev 使用USDT升级
     * @param tokenId NFT ID
     */
    function upgradeWithUSDValue(uint256 tokenId) external;

    /**
     * @dev 获取升级费用（代币）
     * @param currentLevel 当前等级
     * @return uint256 升级费用
     */
    function getUpgradeCost(uint256 currentLevel) external view returns (uint256);

    /**
     * @dev 获取升级所需NFT数量
     * @param currentLevel 当前等级
     * @return uint256 所需NFT数量
     */
    function getUpgradeMaterialCount(uint256 currentLevel) external view returns (uint256);

    /**
     * @dev 检查是否可以升级
     * @param tokenId NFT ID
     * @return bool 是否可以升级
     */
    function canUpgrade(uint256 tokenId) external view returns (bool);

    /**
     * @dev 获取NFT当前等级
     * @param tokenId NFT ID
     * @return uint256 当前等级
     */
    function getNFTLevel(uint256 tokenId) external view returns (uint256);
}

/**
 * @title IMintModule
 * @dev 铸造模块接口
 *
 * 定义NFT铸造功能：
 * - 普通铸造
 * - 稀有铸造
 * - 十连铸造
 * - 指定生肖铸造
 */
interface IMintModule {
    /**
     * @dev 普通铸造
     * @param to 接收地址
     * @return uint256 铸造的NFT ID
     */
    function mint(address to) external returns (uint256);

    /**
     * @dev 稀有铸造
     * @param to 接收地址
     * @return uint256 铸造的NFT ID
     */
    function mintRare(address to) external returns (uint256);

    /**
     * @dev 普通十连铸造
     * @param to 接收地址
     * @return uint256[] 铸造的NFT ID数组
     */
    function mintBatch(address to) external returns (uint256[] memory);

    /**
     * @dev 稀有十连铸造
     * @param to 接收地址
     * @return uint256[] 铸造的NFT ID数组
     */
    function mintRareBatch(address to) external returns (uint256[] memory);

    /**
     * @dev 指定生肖铸造
     * @param to 接收地址
     * @param zodiac 生肖索引（0-11）
     * @return uint256[] 铸造的NFT ID数组（10个）
     */
    function mintZodiac(address to, uint256 zodiac) external returns (uint256[] memory);

    /**
     * @dev 获取铸造费用
     * @param mintType 铸造类型（0普通, 1稀有, 2十连普通, 3十连稀有, 4指定生肖）
     * @param zodiac 生肖索引（指定生肖铸造时使用）
     * @return uint256 铸造费用（代币）
     */
    function getMintCost(uint256 mintType, uint256 zodiac) external view returns (uint256);
}

/**
 * @title IPriceOracle
 * @dev 价格预言机接口
 *
 * 定义代币价格查询功能：
 * - 获取代币/USD价格
 * - 获取ETH/USD价格
 * - 获取铸造费用（USD计价）
 */
interface IPriceOracle {
    /**
     * @dev 获取代币价格（USD）
     * @return uint256 价格（精度18位）
     */
    function getTokenPrice() external view returns (uint256);

    /**
     * @dev 获取ETH价格（USD）
     * @return uint256 价格（精度18位）
     */
    function getETHPrice() external view returns (uint256);

    /**
     * @dev 计算USDT换算（用于升级费用计算）
     * @param tokenAmount 代币数量
     * @return uint256 等值USDT
     */
    function calculateUSDTEquivalent(uint256 tokenAmount) external view returns (uint256);

    /**
     * @dev 计算代币换算（用于显示）
     * @param usdtAmount USDT数量
     * @return uint256 等值代币
     */
    function calculateTokenEquivalent(uint256 usdtAmount) external view returns (uint256);
}

/**
 * @title IAuthorizer
 * @dev 权限管理接口
 *
 * 定义基于权重的权限系统：
 * - 设置权限
 * - 检查权限
 * - 获取权重
 */
interface IAuthorizer {
    /**
     * @dev 授予权限
     * @param user 用户地址
     * @param weight 权重值
     */
    function grantPermission(address user, uint256 weight) external;

    /**
     * @dev 撤销权限
     * @param user 用户地址
     */
    function revokePermission(address user) external;

    /**
     * @dev 检查是否有权限
     * @param user 用户地址
     * @param weightRequired 所需权重
     * @return bool 是否有权限
     */
    function hasPermission(address user, uint256 weightRequired) external view returns (bool);

    /**
     * @dev 获取用户权重
     * @param user 用户地址
     * @return uint256 权重值
     */
    function getWeight(address user) external view returns (uint256);

    /**
     * @dev 获取总权重
     * @return uint256 总权重
     */
    function getTotalWeight() external view returns (uint256);
}
