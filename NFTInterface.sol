// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBEP20 {
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IToken is IBEP20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @title NFTInterface
 * @dev NFT合约接口集合，供 Staking、ArenaRanking、WeightManager 等合约调用
 *
 * 本文件定义了系统中所有核心合约的接口，使跨合约调用类型安全、ABI 一致。
 * 所有接口均以 `I` 前缀命名（INFTDataInterface、INFTMint、INFT、IBattle、
 * IStaking、IBreeding、IERC20Extended），部署时业务合约通过这些接口与主合约交互。
 *
 * 接口一览：
 * - INFTDataInterface：NFT 元数据查询接口（类型、等级、铸造时间）
 * - INFTMint：NFT 铸造合约接口（mint、burn、查询供应量）
 * - INFT：完整的 ERC721 + 扩展接口（ownerOf、balanceOf、safeTransferFrom 等）
 * - IBattle：战斗合约接口（发起战斗、查询战绩）
 * - IStaking：NFT 质押合约接口（stake、unstake、claimReward）
 * - IBreeding：繁殖合约接口（createBreedingPair、completeBreeding）
 * - IERC20Extended：游戏代币合约接口（扩展 ERC20，支持 mint/burn 控制）
 *
 * 使用方法：
 *   import "./NFTInterface.sol";
 *   contract MyContract {
 *       INFT public nft;
 *       function doSomething(uint256 tokenId) external {
 *           address owner = nft.ownerOf(tokenId);
 *           ...
 *       }
 *   }
 *
 * 注意：修改接口签名会导致所有引用合约需要重新编译部署，
 * 建议新增功能时新增函数签名而不是修改已有签名。
 */

/**
 * @title INFTDataInterface
 * @dev NFT数据接口，提供NFT类型、等级、权重等数据查询
 */
interface INFTDataInterface {
    /**
     * @dev 获取NFT的生肖类型
     * @param tokenId NFT ID
     * @return 生肖类型值（编码了元素、生肖、性别信息）
     */
    function tokenType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT的等级
     * @param tokenId NFT ID
     * @return 等级值（1-100）
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 设置NFT的等级
     * @param tokenId NFT ID
     * @param level 新等级值
     */
    function setTokenLevel(uint256 tokenId, uint8 level) external;

    /**
     * @dev 计算用户的NFT总权重
     * @param user 用户地址
     * @return 权重值
     */
    function calcUserWeight(address user) external view returns (uint256);
}

/**
 * @title INFTMint
 * @dev NFT铸造接口，提供铸造和查询功能
 */
interface INFTMint {
    function mint(address to, uint256 zodiacType) external returns (uint256);
    function mintNormal(address to) external returns (uint256);
    function mintRare(address to) external returns (uint256);
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function tokenGrowth(uint256 tokenId) external view returns (uint8);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isRare(uint256 tokenId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function mintForBreeding(address to, uint256 zodiacType, uint8 growth) external returns (uint256);
    function adminSetNFTLevel(uint256 tokenId, uint256 newLevel) external;
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
}

interface INFTMintCore {
    function elementProbabilities() external view returns (uint256[5] memory);
    function rareElementProbabilities() external view returns (uint256[2] memory);
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function tokenGrowth(uint256 tokenId) external view returns (uint8);
    function _exists(uint256 tokenId) external view returns (bool);
    function owner() external view returns (address);
    function tokenBurnerContract() external view returns (address);
    function mint(address to, uint256 zodiacType) external returns (uint256);
    function mintWithGrowth(address to, uint256 zodiacType, uint8 growth) external returns (uint256);
    function generateSecureRandom() external returns (uint256);
}

/**
 * @title INFT
 * @dev 标准NFT接口，提供所有权查询、转移等功能
 */
interface INFT {
    /**
     * @dev 查询NFT是否为稀有NFT
     * @param tokenId NFT ID
     * @return 是否为稀有NFT
     */
    function isRare(uint256 tokenId) external view returns (bool);

    /**
     * @dev 转移NFT（需授权）
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 安全转移NFT（需授权，支持接收合约）
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 获取NFT的生肖类型
     * @param tokenId NFT ID
     * @return 生肖类型值
     */
    function tokenType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT的等级
     * @param tokenId NFT ID
     * @return 等级值
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 获取NFT的所有者
     * @param tokenId NFT ID
     * @return 所有者地址
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev 获取某用户的NFT余额
     * @param owner 用户地址
     * @return NFT数量
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev 按索引获取用户拥有的NFT ID
     * @param owner 用户地址
     * @param index 索引（从0开始）
     * @return NFT ID
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /**
     * @dev 获取用户所有NFT ID列表
     * @param owner 用户地址
     * @return NFT ID数组
     */
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);

    /**
     * @dev 检查是否授权给操作符
     * @param owner 所有者地址
     * @param operator 操作符地址
     * @return 是否授权
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/**
 * @title IBattle
 * @dev 战斗合约接口，提供战斗挑战功能
 */
interface IBattle {
    /**
     * @dev 发起挑战
     * @param challengerId 挑战者代表NFT ID
     * @param challengedId 被挑战者代表NFT ID
     * @param challengerTeam 挑战者队伍（6个NFT）
     * @param challengedTeam 被挑战者队伍（6个NFT）
     * @param challengedAddress 被挑战者地址（address(0)表示模拟战斗）
     * @return success 是否成功
     * @return winner 获胜方（1=挑战者，2=被挑战者，0=平局）
     */
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam,
        address challengedAddress
    ) external returns (bool, uint256);
}

/**
 * @title IStaking
 * @dev NFT质押合约接口，提供质押信息查询功能
 */
interface IStaking {
    /**
     * @dev 获取NFT质押信息
     * @param tokenId NFT ID
     * @return owner 所有者地址
     * @return stakeTime 质押时间
     * @return lastClaimTime 上次领取时间
     * @return accumulatedReward 累积奖励
     * @return isRare 是否稀有NFT
     */
    function stakingInfo(uint256 tokenId) external view returns (address, uint256, uint256, uint256, bool);
}

/**
 * @title IBreeding
 * @dev NFT繁殖合约接口，提供繁殖状态查询功能
 */
interface IBreeding {
    /**
     * @dev 检查NFT是否正在繁殖中
     * @param tokenId NFT ID
     * @return 是否正在繁殖中
     */
    function isNFTInActiveBreeding(uint256 tokenId) external view returns (bool);
}

interface IBreedingCore {
    /**
     * @dev 检查NFT是否在冷却期
     * @param tokenId NFT ID
     * @return 是否在冷却期
     */
    function isInCooldown(uint256 tokenId) external view returns (bool);

    /**
     * @dev 检查NFT是否正在繁殖中
     * @param tokenId NFT ID
     * @return 是否正在繁殖中
     */
    function isNFTInActiveBreeding(uint256 tokenId) external view returns (bool);
}

/**
 * @title IArenaRanking
 * @dev 竞技场排名合约接口，提供排名和奖励相关数据查询
 */

struct LeaderboardEntry {
    address playerAddress;
    uint256 points;
    uint256 wins;
    uint256 losses;
    bool isMock;
}

struct SeasonInfo {
    uint256 seasonId;
    uint256 startTime;
    uint256 endTime;
    bool isActive;
    bool isSettled;
    uint256 totalPlayers;
    uint256 rewardPool;
}

interface IArenaRanking {
    /**
     * @dev 获取赛季奖励数据
     * @param seasonId 赛季ID
     * @return rewardPool BNB奖励池
     * @return tokenRewardPool 代币奖励池
     * @return totalPlayers 总玩家数
     */
    function getSeasonRewardData(uint256 seasonId) external view returns (uint256, uint256, uint256);

    /**
     * @dev 获取赛季排名列表
     * @param seasonId 赛季ID
     * @return 玩家地址数组
     */
    function getSeasonRankings(uint256 seasonId) external view returns (address[] memory);

    /**
     * @dev 判断是否为模拟玩家
     * @param player 玩家地址
     * @return 是否为模拟玩家
     */
    function isMockPlayer(address player) external pure returns (bool);

    /**
     * @dev 统计真实玩家数量
     * @param seasonId 赛季ID
     * @return 真实玩家数量
     */
    function countRealPlayers(uint256 seasonId) external view returns (uint256);

    /**
     * @dev 获取真实玩家排名
     * @param seasonId 赛季ID
     * @param index 排名索引
     * @return 真实排名
     */
    function getRealPlayerRank(uint256 seasonId, uint256 index) external view returns (uint256);

    /**
     * @dev 获取当前赛季ID
     * @return 当前赛季ID
     */
    function getCurrentSeasonId() external view returns (uint256);

    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory);
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory, uint256, uint256);
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256);
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (address[] memory, uint256[] memory);
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory, uint256[] memory);
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory);
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory);
    function getPlayerRecord(address player) external view returns (uint256, uint256, uint256, uint256);
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (uint256, uint256, uint256, uint256, uint256, bool);
    function getSeasonInfo(uint256 seasonId) external view returns (uint256, uint256, bool, bool, uint256);
    function getPlayerRank(address player) external view returns (uint256);
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256);
    function getCurrentSeasonInfo() external view returns (uint256, uint256, uint256, bool, uint256, uint256);
    function getPlayerChallengeStatus(address player) external view returns (uint256, uint256, uint256, uint256);
}

/**
 * @title IArenaReward
 * @dev 竞技场奖励合约接口，提供奖励计算和领取功能
 */
interface IArenaReward {
    /**
     * @dev 计算赛季奖励
     * @param seasonId 赛季ID
     */
    function calculateSeasonRewards(uint256 seasonId) external;

    /**
     * @dev 领取奖励
     * @param seasonId 赛季ID
     */
    function claimReward(uint256 seasonId) external;

    /**
     * @dev 查询待领取奖励
     * @param player 玩家地址
     * @param seasonId 赛季ID
     * @return 待领取奖励金额
     */
    function getPendingRewardsByPlayer(address player, uint256 seasonId) external view returns (uint256);

    /**
     * @dev 查询奖励是否已领取
     * @param player 玩家地址
     * @param seasonId 赛季ID
     * @return 是否已领取
     */
    function isRewardClaimed(address player, uint256 seasonId) external view returns (bool);

    /**
     * @dev 设置奖励类型
     * @param _rewardType 奖励类型
     */
    function setRewardType(uint8 _rewardType) external;

    /**
     * @dev 检查新的一天
     */
    function checkNewDay() external;

    /**
     * @dev 更新今日奖励金额
     * @param amount 金额
     */
    function updateTodayRewardAmount(uint256 amount) external;

    /**
     * @dev 更新今日流入奖励
     * @param amount 金额
     */
    function updateTodayIncomingReward(uint256 amount) external;

    /**
     * @dev 计算排名奖励
     * @param rank 排名
     * @return 奖励金额
     */
    function calculateRewardForRank(uint256 rank) external view returns (uint256);

    /**
     * @dev 获取排名奖励
     * @param rank 排名
     * @return 奖励金额
     */
    function getRewardForRank(uint256 rank) external view returns (uint256);

    /**
     * @dev 设置奖励率
     * @param rate 奖励率
     */
    function setRewardRate(uint256 rate) external;

    /**
     * @dev 设置最大奖励率
     * @param maxRate 最大奖励率
     */
    function setMaxRewardRate(uint256 maxRate) external;

    /**
     * @dev 设置奖励率步长
     * @param step 步长
     */
    function setRateStep(uint256 step) external;
}

/**
 * @title IArenaLeaderboard
 * @dev 竞技场排行榜合约接口，提供排行榜查询和玩家数据查询功能
 */
interface IArenaLeaderboard {
    /**
     * @dev 获取排行榜
     * @param seasonId 赛季ID
     * @param limit 限制数量
     * @return 排行榜条目数组
     */
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory);

    /**
     * @dev 分页获取排行榜
     * @param seasonId 赛季ID
     * @param page 页码
     * @param pageSize 每页大小
     * @return entries 排行榜条目数组
     * @return totalPages 总页数
     * @return totalPlayers 总玩家数
     */
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory entries, uint256 totalPages, uint256 totalPlayers);

    /**
     * @dev 获取排行榜页数
     * @param seasonId 赛季ID
     * @param pageSize 每页大小
     * @return 总页数
     */
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256);

    /**
     * @dev 获取排名范围内的玩家
     * @param seasonId 赛季ID
     * @param startRank 起始排名
     * @param endRank 结束排名
     * @return playerAddrs 玩家地址数组
     * @return scores 分数数组
     */
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    );

    /**
     * @dev 获取顶级玩家
     * @param seasonId 赛季ID
     * @param count 数量
     * @return playerAddrs 玩家地址数组
     * @return scores 分数数组
     */
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    );

    /**
     * @dev 获取赛季历史
     * @param startSeasonId 起始赛季ID
     * @param count 数量
     * @return 赛季信息数组
     */
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory);

    /**
     * @dev 获取最近赛季
     * @param count 数量
     * @return 赛季信息数组
     */
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory);

    /**
     * @dev 判断是否为Mock玩家
     * @param player 玩家地址
     * @return 是否为Mock玩家
     */
    function isMockPlayer(address player) external view returns (bool);

    /**
     * @dev 获取Mock玩家排名
     * @param player 玩家地址
     * @return 排名
     */
    function getMockPlayerRank(address player) external view returns (uint256);

    /**
     * @dev 获取赛季信息
     * @param seasonId 赛季ID
     * @return startTime 开始时间
     * @return endTime 结束时间
     * @return isActive 是否活跃
     * @return isSettled 是否结算
     * @return totalPlayers 总玩家数
     */
    function getSeasonInfo(uint256 seasonId) external view returns (
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isSettled,
        uint256 totalPlayers
    );

    /**
     * @dev 获取玩家赛季统计
     * @param player 玩家地址
     * @param seasonId 赛季ID
     * @return score 分数
     * @return wins 胜场
     * @return losses 败场
     * @return rank 排名
     * @return rewardClaimed 奖励是否领取
     */
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        bool rewardClaimed
    );

    /**
     * @dev 获取玩家记录
     * @param player 玩家地址
     * @return score 分数
     * @return wins 胜场
     * @return losses 败场
     * @return seasonId 赛季ID
     */
    function getPlayerRecord(address player) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 seasonId
    );

    /**
     * @dev 获取当前赛季信息
     * @return seasonId 赛季ID
     * @return startTime 开始时间
     * @return endTime 结束时间
     * @return isActive 是否活跃
     */
    function getCurrentSeasonInfo() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    );

    /**
     * @dev 获取玩家挑战状态
     * @param player 玩家地址
     * @return remainingAttempts 剩余挑战次数
     * @return lastBattleTime 上次战斗时间
     * @return hasTeam 是否有战队
     */
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    );

    /**
     * @dev 获取玩家排名
     * @param player 玩家地址
     * @param seasonId 赛季ID
     * @return 排名
     */
    function getPlayerRank(address player, uint256 seasonId) external view returns (uint256);

    /**
     * @dev 获取赛季总玩家数
     * @param seasonId 赛季ID
     * @return 总玩家数
     */
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256);

    /**
     * @dev 获取玩家战斗力
     * @param player 玩家地址
     * @return 战斗力
     */
    function getPlayerPower(address player) external view returns (uint256);
}

/**
 * @title IArenaPlayer
 * @dev 竞技场玩家合约接口，提供玩家和战队管理功能
 */
interface IArenaPlayer {
    /**
     * @dev 设置战斗队伍
     * @param tokenIds NFT ID数组（固定6个）
     */
    function setBattleTeam(uint256[6] calldata tokenIds) external;

    /**
     * @dev 清空战斗队伍
     */
    function clearBattleTeam() external;

    /**
     * @dev 获取玩家战斗队伍
     * @param player 玩家地址
     * @return 队伍NFT ID数组
     */
    function getPlayerBattleTeam(address player) external view returns (uint256[] memory);

    /**
     * @dev 质押NFT
     * @param tokenIds NFT ID数组
     */
    function stakeNFTs(uint256[] calldata tokenIds) external;

    /**
     * @dev 解除质押NFT
     * @param tokenIds NFT ID数组
     */
    function unstakeNFTs(uint256[] calldata tokenIds) external;

    /**
     * @dev 获取用户质押的NFT
     * @param user 用户地址
     * @return NFT ID数组
     */
    function getUserStakedNFTs(address user) external view returns (uint256[] memory);

    /**
     * @dev 充值挑战次数
     */
    function rechargeChallengeAttempts() external payable;

    /**
     * @dev 获取剩余挑战次数
     * @param player 玩家地址
     * @return 剩余次数
     */
    function getRemainingAttempts(address player) external view returns (uint256);

    /**
     * @dev 获取玩家挑战状态
     * @param player 玩家地址
     * @return remainingAttempts 剩余挑战次数
     * @return lastBattleTime 上次战斗时间
     * @return hasTeam 是否有队伍
     */
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    );

    /**
     * @dev 设置最大充值次数
     * @param _maxRechargeAttempts 最大次数
     */
    function setMaxRechargeAttempts(uint256 _maxRechargeAttempts) external;

    /**
     * @dev 设置充值费用
     * @param _rechargeCost 充值费用
     */
    function setRechargeCost(uint256 _rechargeCost) external;

    /**
     * @dev 更新玩家战斗时间
     * @param player 玩家地址
     * @param timestamp 时间戳
     */
    function updatePlayerBattleTime(address player, uint256 timestamp) external;

    /**
     * @dev 更新玩家挑战次数
     * @param player 玩家地址
     * @param attempts 次数
     */
    function updatePlayerAttempts(address player, uint256 attempts) external;

    /**
     * @dev 生成Mock队伍
     * @param seed 种子
     * @return Mock队伍
     */
    function generateMockTeam(uint256 seed) external view returns (uint256[6] memory);

    /**
     * @dev 获取NFT质押的所有者
     * @param tokenId NFT ID
     * @return 质押者地址
     */
    function getNFTStakedOwner(uint256 tokenId) external view returns (address);
}

/**
 * @title IArenaBattle
 * @dev 竞技场战斗合约接口，提供战斗执行功能
 */
interface IArenaBattle {
    /**
     * @dev 执行Mock战斗
     * @param playerTeam 玩家队伍
     * @param mockIndex Mock索引
     * @return success 是否成功
     * @return winner 获胜方（1=玩家，2=Mock，0=平局）
     * @return battleId 战斗ID
     */
    function executeMockBattle(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool success, uint256 winner, uint256 battleId);

    /**
     * @dev 执行真实战斗
     * @param challengedPlayer 被挑战玩家
     * @param playerTeam 玩家队伍
     * @param challengedTeam 被挑战者队伍
     * @return success 是否成功
     * @return winner 获胜方（1=挑战者，2=被挑战者，0=平局）
     * @return battleId 战斗ID
     */
    function executeRealBattle(address challengedPlayer, uint256[6] calldata playerTeam, uint256[6] calldata challengedTeam) external returns (bool success, uint256 winner, uint256 battleId);

    /**
     * @dev 锁定NFT用于战斗
     * @param team 队伍
     * @param battleId 战斗ID
     */
    function lockNFTsForBattle(uint256[6] calldata team, uint256 battleId) external;

    /**
     * @dev 解锁NFT
     * @param team 队伍
     */
    function unlockNFTsFromBattle(uint256[6] memory team) external;

    /**
     * @dev 检查NFT是否锁定
     * @param tokenId NFT ID
     * @return 是否锁定
     */
    function isNFTLocked(uint256 tokenId) external view returns (bool);

    /**
     * @dev 设置基础奖励
     * @param _baseRewardPerWin 每胜奖励
     */
    function setBaseRewardPerWin(uint256 _baseRewardPerWin) external;
}

/**
 * @title IERC20Extended
 * @dev 扩展ERC20代币接口，提供额外功能
 */
interface IERC20Extended {
    /**
     * @dev 转移代币
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 转移数量
     * @return 是否成功
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @dev 销毁代币
     * @param account 账户地址
     * @param amount 销毁数量
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @dev 查询授权额度
     * @param owner 所有者地址
     * @param spender 花费者地址
     * @return 授权额度
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev 安全转移代币
     * @param to 转入地址
     * @param amount 转移数量
     */
    function safeTransfer(address to, uint256 amount) external;

    /**
     * @dev 查询余额
     * @param account 账户地址
     * @return 余额
     */
    function balanceOf(address account) external view returns (uint256);
}