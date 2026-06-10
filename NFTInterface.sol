// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

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
 * - IArenaBattle / IArenaRanking / IArenaPlayer / IArenaReward / IArenaLeaderboard：竞技场各子合约
 * - IRewardManager / IDividendManager / IPriceOracle：奖励 & 预言机接口
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
 */

/**
 * @title INFTDataInterface
 * @dev NFT数据接口，提供NFT类型、等级、权重等数据查询
 */
interface INFTDataInterface {
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function setTokenLevel(uint256 tokenId, uint8 level) external;
    function calcUserWeight(address user) external view returns (uint256);
    function syncNFTData(uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to) external;
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
    function mintWithGrowth(address to, uint256 zodiacType, uint8 growth) external returns (uint256);
    function adminSetNFTLevel(uint256 tokenId, uint256 newLevel) external;
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
    function balanceOf(address owner) external view returns (uint256);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
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
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
}

/**
 * @title INFT
 * @dev 标准NFT接口，提供所有权查询、转移等功能
 */
interface INFT {
    function isRare(uint256 tokenId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/**
 * @title IBattle
 * @dev 战斗合约接口，提供战斗挑战功能
 */
interface IBattle {
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam,
        address challengedAddress
    ) external returns (bool, uint256);

    function challenge(
        uint256[6] calldata team1,
        uint256[6] calldata team2,
        address challenger,
        address opponent
    ) external returns (bool success, uint8 winner);
}

/**
 * @title IStaking
 * @dev NFT质押合约接口
 */
interface IStaking {
    function stake(uint256[] calldata tokenIds) external;
    function unstake(uint256[] calldata tokenIds) external;
    function claimReward() external;
    function stakingInfo(uint256 tokenId) external view returns (address, uint256, uint256, uint256, bool);
    function getUserStakedNFTs(address user) external view returns (uint256[] memory);
    function getPendingReward(address user) external view returns (uint256);
    function getUserStakingStats(address user) external view returns (uint256, uint256, uint256, uint256, uint256);
    function getPoolStats() external view returns (uint256, uint256, uint256);
    function paused() external view returns (bool);
}

/**
 * @title IBreeding
 * @dev NFT繁殖合约接口（基础版）
 */
interface IBreeding {
    function isNFTInActiveBreeding(uint256 tokenId) external view returns (bool);
}

interface IBreedingCore {
    function isInCooldown(uint256 tokenId) external view returns (bool);
    function isNFTInActiveBreeding(uint256 tokenId) external view returns (bool);
    function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external returns (uint256);
    function createMarketBreedingPairPublic(uint256 fatherId, uint256 motherId) external returns (uint256);
    function completeBreeding(uint256 pairId) external returns (uint256, uint256);
    function cancelBreeding(uint256 pairId) external;
    function selfBreedingCooldown() external view returns (uint256);
    function marketBreedingCooldown() external view returns (uint256);
    function selfBreedingFee() external view returns (uint256);
    function marketBreedingFee() external view returns (uint256);
    function getBreedingInfo(uint256 pairId) external view returns (uint256, uint256, address, address, uint256, uint256, uint256, uint256, bool);
    function getUserActiveOrders(address user) external view returns (uint256[] memory);
    function getUserBreedingStats(address user) external view returns (uint256, uint256, uint256, uint256, uint256);
    function getNFTBreedingCooldown(uint256 tokenId) external view returns (uint256);
    function getCooldownEndTime(uint256 tokenId) external view returns (uint256);
    function listForMarketBreeding(uint256 tokenId) external;
    function delistFromMarketBreeding(uint256 tokenId) external;
}

/**
 * @title 排行榜 / 赛季信息结构体（全局共用）
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

/**
 * @title IArenaRankingManager
 * @dev 竞技场排名管理合约接口（赛季管理 + 战斗挑战 + NFT质押）
 */
interface IArenaRankingManager {
    function currentSeasonId() external view returns (uint256);
    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool);
    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external returns (bool);
    function startNewSeason() external;
    function checkAndStartNewSeason() external;
    function settleSeason(uint256 seasonId) external;
    function stakeNFTs(uint256[] calldata tokenIds) external;
    function unstakeNFTs(uint256[] calldata tokenIds) external;
    function setBattleTeam(uint256[] calldata tokenIds) external;
    function setBattleTeam(uint256[6] calldata tokenIds) external;
    function clearBattleTeam() external;
    function rechargeChallengeAttempts() external;
    function setRewardType(uint8 _rewardType) external;
    function setSeasonRewardRate(uint256 rate) external;
    function setArenaMode(uint8 mode) external;
    function setMaxRechargeAttempts(uint256 _limit) external;
    function addRewardToPool() external payable;
}

/**
 * @title IArenaRankingQuery
 * @dev 竞技场排名查询合约接口（排行榜查询 + 奖励领取 + 状态读取）
 */
interface IArenaRankingQuery {
    function currentSeasonId() external view returns (uint256);
    function getPlayerRank(address player) external view returns (uint256);
    function getSeasonInfo(uint256 seasonId) external view returns (uint256, uint256, bool, bool, uint256);
    function getCurrentSeasonInfo() external view returns (uint256, uint256, uint256, bool, uint256, uint256);
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory);
    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory);
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory, uint256, uint256);
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256);
    function getPlayerRecord(address player) external view returns (uint256, uint256, uint256, uint256);
    function getMockPlayerRank(address player) external view returns (uint256);
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory, uint256[] memory);
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory);
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory);
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (uint256, uint256, uint256, uint256, bool);
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (address[] memory, uint256[] memory);
    function getSeasonReward(address player) external view returns (uint256);
    function getSeasonReward(address player, uint256 seasonId) external view returns (uint256);
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256);
    function getRemainingAttempts(address player) external view returns (uint256);
    function getPlayerBattleTeam(address player) external view returns (uint256[] memory);
    function getLastBattleTime(address player) external view returns (uint256);
    function getPlayerChallengeStatus(address player) external view returns (uint256, uint256, bool);
    function isSeasonRewardClaimed(address player, uint256 seasonId) external view returns (bool);
    function claimSeasonReward() external;
    function claimSeasonReward(uint256 seasonId) external returns (uint256);
    function rechargeCost() external pure returns (uint256);
}

/**
 * @title IArenaRanking
 * @dev 竞技场排名合约接口（兼容旧版，指向 ArenaRankingManager）
 */
interface IArenaRanking {
    function currentSeasonId() external view returns (uint256);
    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool);
    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external returns (bool);
    function getPlayerRank(address player) external view returns (uint256);
    function getSeasonInfo(uint256 seasonId) external view returns (uint256, uint256, bool, bool, uint256);
    function getCurrentSeasonInfo() external view returns (uint256, uint256, uint256, bool, uint256, uint256);
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory);
    function getPlayerRecord(address player) external view returns (uint256, uint256, uint256, uint256);
    function getMockPlayerRank(address player) external view returns (uint256);
    function getRealPlayerRank(uint256 seasonId, uint256 index) external view returns (uint256);
    function countRealPlayers(uint256 seasonId) external view returns (uint256);
    function isMockPlayer(address player) external pure returns (bool);
    function setRewardType(uint8 _rewardType) external;
    function setSeasonRewardRate(uint256 rate) external;
    function setArenaMode(uint8 mode) external;
    function setMaxRechargeAttempts(uint256 _limit) external;
    function startNewSeason() external;
    function checkAndStartNewSeason() external;
    function settleSeason(uint256 seasonId) external;
    function getSeasonRewardData(uint256 seasonId) external view returns (uint256, uint256, uint256);
    function getPlayerChallengeStatus(address player) external view returns (uint256, uint256, uint256, uint256);
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256);
    function getSeasonRankings(uint256 seasonId) external view returns (address[] memory);
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (address[] memory, uint256[] memory);
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory, uint256[] memory);
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory);
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory);
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (uint256, uint256, uint256, uint256, uint256, bool);
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory, uint256, uint256);
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256);
    function getSeasonReward(address player) external view returns (uint256);
    function getSeasonReward(address player, uint256 seasonId) external view returns (uint256);
}

/**
 * @title IArenaLeaderboard
 * @dev 竞技场排行榜只读接口
 */
interface IArenaLeaderboard {
    function updateRanking(address player, uint256 score, uint256 seasonId) external;
    function insertPlayerAtRank(address player, uint256 targetRank, uint256 seasonId) external;
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory);
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory, uint256, uint256);
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256);
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (address[] memory, uint256[] memory);
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory, uint256[] memory);
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory);
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory);
    function isMockPlayer(address player) external view returns (bool);
    function getMockPlayerRank(address player) external view returns (uint256);
    function getSeasonInfo(uint256 seasonId) external view returns (uint256, uint256, bool, bool, uint256);
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (uint256, uint256, uint256, uint256, bool);
    function getPlayerRecord(address player) external view returns (uint256, uint256, uint256, uint256);
    function getCurrentSeasonInfo() external view returns (uint256, uint256, uint256, bool);
    function getPlayerChallengeStatus(address player) external view returns (uint256, uint256, bool);
    function getPlayerRank(address player) external view returns (uint256);
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256);
    function getPlayerPower(address player) external view returns (uint256);
}

/**
 * @title IArenaPlayer
 * @dev 竞技场玩家/战队/NFT质押接口
 */
interface IArenaPlayer {
    function setBattleTeam(uint256[6] calldata tokenIds) external;
    function clearBattleTeam() external;
    function getPlayerBattleTeam(address player) external view returns (uint256[] memory);
    function stakeNFTs(uint256[] calldata tokenIds) external;
    function unstakeNFTs(uint256[] calldata tokenIds) external;
    function getUserStakedNFTs(address user) external view returns (uint256[] memory);
    function rechargeChallengeAttempts() external payable;
    function getRemainingAttempts(address player) external view returns (uint256);
    function getPlayerChallengeStatus(address player) external view returns (uint256, uint256, bool);
    function setMaxRechargeAttempts(uint256 _maxRechargeAttempts) external;
    function setRechargeCost(uint256 _rechargeCost) external;
    function updatePlayerBattleTime(address player, uint256 timestamp) external;
    function updatePlayerAttempts(address player, uint256 attempts) external;
    function updatePlayerResetTime(address player, uint256 timestamp) external;
    function generateMockTeam(uint256 seed) external view returns (uint256[6] memory);
    function isNFTStaked(uint256 tokenId) external view returns (bool);
    function getNFTStakedOwner(uint256 tokenId) external view returns (address);
}

/**
 * @title IArenaBattle
 * @dev 竞技场战斗合约接口
 */
interface IArenaBattle {
    function executeMockBattle(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool success, uint256 winner, uint256 battleId);
    function executeRealBattle(address challengedPlayer, uint256[6] calldata playerTeam, uint256[6] calldata challengedTeam) external returns (bool success, uint256 winner, uint256 battleId);
    function lockNFTsForBattle(uint256[6] calldata team, uint256 battleId) external;
    function unlockNFTsFromBattle(uint256[6] memory team) external;
    function isNFTLocked(uint256 tokenId) external view returns (bool);
    function setBaseRewardPerWin(uint256 _baseRewardPerWin) external;
    function getBattleIdCounter(address player) external view returns (uint256);
    function getLastBattleTime(address player) external view returns (uint256);
    function simulateBattle(uint256[6] memory playerTeam, uint256 mockIndex) external view returns (bool);
}

/**
 * @title IArenaReward
 * @dev 竞技场奖励合约接口
 */
interface IArenaReward {
    function calculateSeasonRewards(uint256 seasonId) external;
    function claimReward(uint256 seasonId) external;
    function claimSeasonReward() external;
    function claimSeasonReward(address player, uint256 seasonId) external returns (uint256);
    function getPendingRewardsByPlayer(address player, uint256 seasonId) external view returns (uint256);
    function getPendingRewardsBySeason(uint256 seasonId) external view returns (uint256);
    function getTotalPendingRewards(address player) external view returns (uint256);
    function isRewardClaimed(address player, uint256 seasonId) external view returns (bool);
    function rewardType() external view returns (uint8);
    function setRewardType(uint8 _rewardType) external;
    function setRewardRate(uint256 rate) external;
    function setMaxRewardRate(uint256 maxRate) external;
    function setRateStep(uint256 step) external;
    function checkNewDay() external;
    function updateTodayRewardAmount(uint256 amount) external;
    function updateTodayIncomingReward(uint256 amount) external;
    function calculateRewardForRank(uint256 rank) external view returns (uint256);
    function getRewardForRank(uint256 rank) external view returns (uint256);
    function emergencyWithdrawBNB(uint256 amount) external;
    function emergencyWithdrawTokens(uint256 amount) external;
    function addRewardToPool() external payable;
}

/**
 * @title IPoolManager
 * @dev 资金池管理接口
 */
interface IPoolManager {
    function addToNFTStakingPool(uint256 amount) external;
    function addToTokenStakingPool(uint256 amount) external;
    function addToArenaRewardPool(uint256 amount) external;
}

/**
 * @title IDexRouter
 */
interface IDexRouter {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function WETH() external pure returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IDEXRouter {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    
    function WETH() external pure returns (address);
    
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IPancakeSwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ISetNFTContract {
    function setNFTContract(address _nftContract) external;
}

interface ISetRewardTokenContract {
    function setRewardTokenContract(address _tokenContract) external;
}

interface ISetDividendPool {
    function setDividendPool(address _dividendManager) external;
}

interface ISetNFTStakingPool {
    function setNFTStakingPool(address _stakingAddress) external;
}

interface ISetTokenStakingPool {
    function setTokenStakingPool(address _tokenStakingAddress) external;
}

interface ISetTokenContract {
    function setTokenContract(address _tokenContract) external;
}

interface ISetArenaRewardPool {
    function setArenaRewardPool(address _arenaRankingAddress) external;
}

interface ISetArenaRewardContract {
    function setArenaRewardContract(address _arenaRewardContract) external;
}

interface ISetArenaLeaderboardContract {
    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external;
}

interface ISetArenaPlayerContract {
    function setArenaPlayerContract(address _arenaPlayerContract) external;
}

interface ISetArenaBattleContract {
    function setArenaBattleContract(address _arenaBattleContract) external;
}

interface ISetRankingContract {
    function setRankingContract(address _rankingContract) external;
}

interface ISetTokenAddress {
    function setTokenAddress(address _tokenContract) external;
}

interface ISetUSDTAddress {
    function setUSDTAddress(address _usdtAddress) external;
}

interface ISetMetadataContract {
    function setMetadataContract(address _metadataAddress) external;
}

interface ISetPancakeSwapPair {
    function setPancakeSwapPair(address _pairAddress) external;
}

interface ISetAuthorizedNFTContract {
    function setAuthorizedNFTContract(address _nftContract) external;
}

interface ISetTokenBurner {
    function setTokenBurner(address _tokenBurner) external;
}

interface ISetNFTDataContract {
    function setNFTDataContract(address _nftDataAddress) external;
}

interface ISetBattleContract {
    function setBattleContract(address _battleAddress) external;
}

interface ISetFeeReceiver {
    function setFeeReceiver(address _feeReceiver) external;
}

interface ISetRewardPool {
    function setRewardPool(address _rewardPool) external;
}

interface ISetPoolManager {
    function setPoolManager(address _poolManager) external;
}

interface ISetNFTUpdateContract {
    function setNFTUpdateContract(address _nftUpdate) external;
}

interface ISetRewardManagerContract {
    function setRewardManagerContract(address _rewardManager) external;
}

interface ISetBreedingContract {
    function setBreedingContract(address _breedingContract) external;
}

interface IBreedingMarket {
    function setBreedingCore(address _breedingCore) external;
}

/**
 * @title IDividendManager
 * @dev 分红池接口
 */
interface IDividendManager {
    function syncDividendPool() external;
    function calcUserDividend(address user) external view returns (uint256, uint256);
    function claimDividend(address user) external returns (uint256);
    function getDividend(address user) external view returns (uint256);
    function getUserPendingDividend(address user) external view returns (uint256);
    function dividendPoolBalance() external view returns (uint256);
    function totalDistributed() external view returns (uint256);
    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external;
}

/**
 * @title IRewardManager
 * @dev 奖励管理接口（BNB 归集、DEX 兑换、质押/竞技场/分红分配）
 */
interface IRewardManager {
    function distributeBNB() external;
    function addStakingReward(uint256 amount, uint256 poolType) external payable;
    function claimDividend(address user) external returns (uint256);
    function calcUserDividend(address user) external view returns (uint256, uint256);
    function getDividend(address user) external view returns (uint256);
    function getUserPendingDividend(address user) external view returns (uint256);
    function dividendPoolBalance() external view returns (uint256);
    function setDistributionPercents(uint256 _dividend, uint256 _nftStaking, uint256 _tokenStaking, uint256 _arena) external;
    function getDistributionPercents() external view returns (uint256, uint256, uint256, uint256);
    function getDistributionHistoryLength() external view returns (uint256);
    function getDistributionHistory(uint256 startIndex, uint256 count) external view returns (uint256[] memory);
    function getRecentDistributions(uint256 count) external view returns (uint256[] memory);
    function getRewardPoolStats() external view returns (uint256, uint256, uint256, uint256);
    function setDEXRouter(address _dexRouter, uint8 _dexType) external;
    function setAutoSwapEnabled(bool enabled) external;
    function setMinSwapAmount(uint256 amount) external;
    function setSlippage(uint256 _slippage) external;
    function setDividendPool(address _dividendPool) external;
    function setNFTStakingPool(address _pool) external;
    function setTokenStakingPool(address _pool) external;
    function setTokenContract(address _tokenContract) external;
    function setArenaRewardPool(address _pool) external;
    function setPoolManager(address _poolManager) external;
    function dexRouter() external view returns (address);
    function activeDEX() external view returns (uint8);
    function autoSwapEnabled() external view returns (bool);
    function slippage() external view returns (uint256);
    function emergencyWithdrawBNB(uint256 amount) external;
    function emergencyWithdrawTokens(uint256 amount) external;
    function pause(string memory reason) external;
    function unpause() external;
    function paused() external view returns (bool);
}

/**
 * @title IPriceOracle
 * @dev 代币/美元价格预言机接口
 */
interface IPriceOracle {
    function getTokenPriceUSD() external view returns (uint256);
    function updatePrices(uint256 _tokenPriceUSD, uint256 _ethPriceUSD) external;
    function proposeTokenPrice(uint256 _newPrice) external;
    function lastPriceUpdateTime() external view returns (uint256);
}

/**
 * @title INFTTrading
 * @dev NFT交易市场接口
 */
interface INFTTrading {
    function listNFT(uint256 tokenId, uint256 priceWei) external;
    function delistNFT(uint256 tokenId) external;
    function updatePrice(uint256 tokenId, uint256 newPriceWei) external;
    function buyNFT(uint256 tokenId) external payable;
    function getListingInfo(uint256 tokenId) external view returns (address, uint256, uint256);
    function getListedNFTs() external view returns (uint256[] memory);
    function getUserListings(address user) external view returns (uint256[] memory);
    function getUserListedCount(address user) external view returns (uint256);
    function getMarketStats() external view returns (uint256, uint256, uint256, uint256, uint256);
    function getListingsByPriceRange(uint256 minPrice, uint256 maxPrice) external view returns (uint256[] memory);
    function feePercent() external view returns (uint256);
    function setFeePercent(uint256 percent) external;
    function setFeeReceiver(address _feeReceiver) external;
    function setNFTContract(address _nftContract) external;
    function listings(uint256 tokenId) external view returns (address, uint256, uint256);
    function paused() external view returns (bool);
    function pause(string memory reason) external;
    function unpause() external;
    function emergencyWithdrawBNB(uint256 amount) external;
    function emergencyWithdrawNFT(uint256 tokenId) external;
}

/**
 * @title INFTUpdate
 * @dev NFT 升级接口
 */
interface INFTUpdate {
    function upgradeWithNFT(uint256 tokenId) external returns (uint8);
    function upgradeWithToken(uint256 tokenId) external returns (uint8);
    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8);
    function getTokenPriceFromPancakeSwap() external view returns (uint256);
    function level1UpgradeCost() external view returns (uint256);
    function level2UpgradeCost() external view returns (uint256);
    function level3UpgradeCost() external view returns (uint256);
    function level4UpgradeCost() external view returns (uint256);
    function usdUpgradeHidden() external view returns (bool);
}

/**
 * @title ITokenBurner
 * @dev 代币燃烧铸造接口
 */
interface ITokenBurner {
    function normalMintCost() external view returns (uint256);
    function rareMintCost() external view returns (uint256);
    function normalMintTenCost() external view returns (uint256);
    function rareMintTenCost() external view returns (uint256);
    function targetedMintCost() external view returns (uint256);
    function burnAndMint(address user, bool isRare) external returns (bool);
    function burnAndMintTen(address user, bool isRare) external returns (bool);
    function burnAndMintTargeted(address user, uint8 zodiac) external returns (bool);
}

/**
 * @title IERC20Extended
 * @dev 扩展ERC20代币接口
 */
interface IERC20Extended {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burnFrom(address account, uint256 amount) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function safeTransfer(address to, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}
