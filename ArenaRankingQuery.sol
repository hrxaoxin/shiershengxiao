// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

/**
 * @title ArenaRankingQuery
 * @dev 竞技场排名查询合约（查询与奖励模块）
 * 
 * 核心职责：
 * 1. 排行榜查询：获取玩家排名、积分、前N名玩家等
 * 2. 赛季信息查询：获取赛季状态、开始、结束时间、奖励池等
 * 3. 玩家信息查询：获取玩家战绩、当前队伍、剩余挑战次数等
 * 4. 奖励领取：玩家领取赛季结束后的排名奖励
 * 
 * 与 ArenaRankingManager 的关系：
 * - ArenaRankingManager：负责写入操作（战斗、质押、赛季管理）
 * - ArenaRankingQuery：负责读取操作（查询、奖励领取）
 * - 两个合约共享相同的状态变量设计，通过 Authorizer 配置关联
 * 
 * 查询功能：
 * - getLeaderboard()：获取赛季排行榜
 * - getLeaderboardByPage()：分页获取排行榜
 * - getTopPlayers()：获取前N名玩家
 * - getPlayerRank()：获取指定玩家的排名
 * - getSeasonInfo()：获取指定赛季的详细信息
 * - getPlayerRecord()：获取玩家的战斗记录
 * 
 * 奖励机制：
 * - 赛季结束后，根据玩家排名分配奖励
 * - 奖励来源：赛季奖励池
 * - 玩家需主动调用 claimSeasonReward() 领取奖励
 * - 奖励会直接转入玩家钱包
 * 
 * 与其他合约的交互：
 * - ArenaLeaderboard：读取排行榜数据
 * - ArenaReward：调用奖励领取逻辑
 * - ArenaRankingManager：共享状态数据
 * 
 * 安全机制：
 * - ReentrancyGuard：防止奖励领取时的重入攻击
 * - Pausable：可暂停奖励领取
 * 
 * 权限控制：
 * - onlyOwner：设置合约地址
 * - onlyAuthorized：设置关联合约地址
 * 
 * 注意：此合约是 ArenaRanking 的拆分版本，专门负责查询操作
 * 写入操作由 ArenaRankingManager 合约提供
 */
contract ArenaRankingQuery is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 玩家记录结构体
     * @param score 玩家当前积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param draws 平局次数
     * @param lastBattleTime 上次战斗时间
     * @param lastResetTime 上次重置时间（用于每日次数重置）
     * @param remainingAttempts 剩余挑战次数
     * @param battleTeam 战斗队伍（NFT ID 数组，最多6个）
     * @param hasTeam 是否已设置战斗队伍
     * @param seasonId 当前所在赛季ID
     */
    struct PlayerRecord {
        uint256 score;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 lastBattleTime;
        uint256 lastResetTime;
        uint256 remainingAttempts;
        uint256[6] battleTeam;
        bool hasTeam;
        uint256 seasonId;
    }

    /**
     * @dev 赛季信息结构体
     * @param seasonId 赛季ID
     * @param startTime 赛季开始时间
     * @param endTime 赛季结束时间
     * @param isActive 赛季是否进行中
     * @param isSettled 赛季是否已结算
     * @param rewardCalculated 奖励是否已计算
     * @param totalPlayers 赛季总玩家数
     * @param rewardPool BNB 奖励池
     * @param tokenRewardPool 代币奖励池
     * @param pendingRewards 待发放奖励
     */
    struct SeasonInfo {
        uint256 seasonId;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isSettled;
        bool rewardCalculated;
        uint256 totalPlayers;
        uint256 rewardPool;
        uint256 tokenRewardPool;
        uint256 pendingRewards;
    }

    /**
     * @dev 玩家记录映射
     * address => PlayerRecord
     */
    mapping(address => PlayerRecord) public players;
    /**
     * @dev 赛季信息映射
     * seasonId => SeasonInfo
     */
    mapping(uint256 => SeasonInfo) public seasons;
    /**
     * @dev 玩家赛季奖励映射
     * seasonId => player => reward
     */
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    /**
     * @dev 玩家赛季奖励是否已领取
     * seasonId => player => claimed
     */
    mapping(uint256 => mapping(address => bool)) public seasonRewardsClaimed;
    
    /**
     * @dev 当前赛季ID
     */
    uint256 public currentSeasonId;
    
    /**
     * @dev 授权合约地址（Authorizer）- 通过此地址获取所有关联合约地址
     */
    address public authorizer;
    
    /**
     * @dev 模拟玩家基础地址
     */
    address public constant MOCK_PLAYER_BASE = address(0x000000000000000000000000000000000000dEaD);
    /**
     * @dev 最大模拟玩家数量
     */
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;

    /**
     * @dev 奖励领取事件
     * @param player 领取奖励的玩家地址
     * @param amount 领取的奖励金额
     * @param seasonId 赛季ID
     */
    event RewardClaimed(address indexed player, uint256 amount, uint256 seasonId);

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "ArenaRankingQuery: Invalid authorizer address");
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
        currentSeasonId = 1;
        seasons[1] = SeasonInfo({
            seasonId: 1,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            isActive: true,
            isSettled: false,
            rewardCalculated: false,
            totalPlayers: 0,
            rewardPool: 0,
            tokenRewardPool: 0,
            pendingRewards: 0
        });
    }

    /**
     * @dev 暂停合约
     * @notice 仅限owner调用，暂停后将阻止大部分操作
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaRankingQuery: Not authorized");
        _;
    }

    /**
     * @dev UUPS 升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaRankingQuery: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 内部函数：判断是否为模拟玩家地址
     * @param player 玩家地址
     * @return 是否为模拟玩家
     */
    function _isMockPlayer(address player) internal pure returns (bool) {
        uint256 playerAddress = uint256(uint160(player));
        uint256 baseAddress = uint256(uint160(MOCK_PLAYER_BASE));
        uint256 maxAddress = baseAddress + MAX_MOCK_PLAYERS_COUNT;
        if (maxAddress <= baseAddress) {
            return false;
        }
        return playerAddress >= baseAddress && playerAddress < maxAddress;
    }

    /**
     * @dev 获取玩家排名
     * @param player 玩家地址
     * @return 排名位置（从1开始）
     */
    /**
     * @dev 获取玩家排名
     * @param player 玩家地址
     * @return 排名位置（从1开始，未上榜返回0）
     */
    function getPlayerRank(address player) external view returns (uint256) {
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getPlayerRank(player);
        }
        return 0;
    }

    /**
     * @dev 获取赛季信息
     * @param seasonId 赛季 ID
     * @return startTime 开始时间, endTime 结束时间, isActive 是否进行中, isSettled 是否已结算, totalPlayers 玩家数
     */
    function getSeasonInfo(uint256 seasonId) external view returns (uint256 startTime, uint256 endTime, bool isActive, bool isSettled, uint256 totalPlayers) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRankingQuery: Invalid season");
        SeasonInfo memory s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }

    /**
     * @dev 获取当前赛季信息
     * @return seasonId 赛季ID, startTime 开始时间, endTime 结束时间, isActive 是否进行中, totalPlayers 玩家数, rewardPool 奖励池
     */
    function getCurrentSeasonInfo() external view returns (uint256 seasonId, uint256 startTime, uint256 endTime, bool isActive, uint256 totalPlayers, uint256 rewardPool) {
        SeasonInfo storage s = seasons[currentSeasonId];
        return (currentSeasonId, s.startTime, s.endTime, s.isActive, s.totalPlayers, s.rewardPool);
    }

    /**
     * @dev 获取赛季排行榜
     * @param seasonId 赛季 ID
     * @param limit 返回数量限制
     * @return 排行榜条目数组
     */
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory) {
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract == address(0)) {
            return new LeaderboardEntry[](0);
        }
        return IArenaLeaderboard(arenaLeaderboardContract).getLeaderboard(seasonId, limit);
    }

    /**
     * @dev 获取玩家记录
     * @param player 玩家地址
     * @return score 积分, wins 胜利次数, losses 失败次数, seasonId 赛季 ID
     */
    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        PlayerRecord memory p = players[player];
        return (p.score, p.wins, p.losses, p.seasonId);
    }

    /**
     * @dev 获取赛季历史记录
     * @param startSeasonId 起始赛季 ID
     * @param count 赛季数量
     * @return 赛季信息数组
     */
    function getSeasonHistory(uint256 startSeasonId, uint256 count) public view returns (SeasonInfo[] memory) {
        require(startSeasonId > 0, "ArenaRankingQuery: Invalid start season");
        require(startSeasonId <= currentSeasonId, "ArenaRankingQuery: Start season exceeds current");
        
        uint256 endSeasonId = startSeasonId + count - 1;
        if (endSeasonId > currentSeasonId) {
            endSeasonId = currentSeasonId;
        }
        
        uint256 resultCount = endSeasonId - startSeasonId + 1;
        SeasonInfo[] memory result = new SeasonInfo[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = seasons[startSeasonId + i];
        }
        
        return result;
    }

    /**
     * @dev 获取模拟玩家排名
     * @param player 玩家地址
     * @return 排名位置（从1开始）
     */
    function getMockPlayerRank(address player) external view returns (uint256) {
        if (!_isMockPlayer(player)) return 0;
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getMockPlayerRank(player);
        }
        return 0;
    }

    /**
     * @dev 获取当前赛季排行榜（重载）
     * @param limit 返回数量限制
     * @return 排行榜条目数组
     */
    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory) {
        return this.getLeaderboard(currentSeasonId, limit);
    }

    /**
     * @dev 分页获取排行榜
     * @param seasonId 赛季 ID
     * @param page 页码（从1开始）
     * @param pageSize 每页大小
     * @return entries 排行榜条目, totalPages 总页数, totalPlayers 总玩家数
     */
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory entries, uint256 totalPages, uint256 totalPlayers) {
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract == address(0)) {
            return (new LeaderboardEntry[](0), 0, 0);
        }
        (entries, totalPages, totalPlayers) = IArenaLeaderboard(arenaLeaderboardContract).getLeaderboardByPage(seasonId, page, pageSize);
    }

    /**
     * @dev 获取排行榜总页数
     * @param seasonId 赛季 ID
     * @param pageSize 每页大小
     * @return 总页数
     */
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getLeaderboardPageCount(seasonId, pageSize);
        }
        return 0;
    }

    /**
     * @dev 获取赛季前 N 名玩家
     * @param seasonId 赛季 ID
     * @param count 数量
     * @return playerAddrs 玩家地址数组, scores 积分数组
     */
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory playerAddrs, uint256[] memory scores) {
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getTopPlayers(seasonId, count);
        }
        return (new address[](0), new uint256[](0));
    }

    /**
     * @dev 获取当前赛季奖励
     * @param player 玩家地址
     * @return 奖励金额
     */
    function getSeasonReward(address player) external view returns (uint256) {
        return playerSeasonRewards[currentSeasonId][player];
    }

    /**
     * @dev 获取指定赛季奖励
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return 奖励金额
     */
    function getSeasonReward(address player, uint256 seasonId) external view returns (uint256) {
        return playerSeasonRewards[seasonId][player];
    }

    /**
     * @dev 获取最近 N 个赛季信息
     * @param count 赛季数量
     * @return 赛季信息数组（从最近到最早）
     */
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        if (count == 0 || count > currentSeasonId) count = currentSeasonId;
        SeasonInfo[] memory result = new SeasonInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = seasons[currentSeasonId - count + i + 1];
        }
        return result;
    }

    /**
     * @dev 获取赛季总玩家数
     * @param seasonId 赛季 ID
     * @return 玩家数量
     */
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        return seasons[seasonId].totalPlayers;
    }

    /**
     * @dev 获取玩家剩余挑战次数
     * @param player 玩家地址
     * @return 剩余挑战次数
     */
    function getRemainingAttempts(address player) external view returns (uint256) {
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        if (arenaPlayerContract == address(0)) {
            PlayerRecord memory p = players[player];
            if (p.lastResetTime == 0 || block.timestamp > p.lastResetTime + 24 hours) {
                return 3;
            }
            return p.remainingAttempts;
        }
        return IArenaPlayer(arenaPlayerContract).getRemainingAttempts(player);
    }

    /**
     * @dev 获取玩家战斗队伍
     * @param player 玩家地址
     * @return 队伍 NFT ID 数组（6个）
     */
    function getPlayerBattleTeam(address player) external view returns (uint256[] memory) {
        PlayerRecord memory p = players[player];
        uint256[] memory team = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            team[i] = p.battleTeam[i];
        }
        return team;
    }

    /**
     * @dev 获取玩家上次战斗时间
     * @param player 玩家地址
     * @return 时间戳
     */
    function getLastBattleTime(address player) external view returns (uint256) {
        return players[player].lastBattleTime;
    }

    /**
     * @dev 获取充值挑战次数的成本
     * @return 代币数量（wei单位）
     */
    function rechargeCost() external view returns (uint256) {
        address arenaPlayer = IAuthorizer(authorizer).getArenaPlayer();
        if (arenaPlayer != address(0)) {
            return IArenaPlayer(arenaPlayer).rechargeCost();
        }
        return 888 * 10**18;
    }

    /**
     * @dev 检查赛季奖励是否已领取
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return 是否已领取
     */
    function isSeasonRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        return seasonRewardsClaimed[seasonId][player];
    }

    /**
     * @dev 获取玩家赛季统计数据
     * @param player 玩家地址
     * @param seasonNumber 赛季编号
     * @return score 积分, wins 胜利次数, losses 失败次数, rank 排名, rewardClaimed 奖励是否已领取
     */
    function getPlayerSeasonStats(address player, uint256 seasonNumber) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        bool rewardClaimed
    ) {
        PlayerRecord memory p = players[player];
        if (p.seasonId == seasonNumber) {
            score = p.score;
            wins = p.wins;
            losses = p.losses;
        } else {
            score = 0;
            wins = 0;
            losses = 0;
        }
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract != address(0)) {
            rank = IArenaLeaderboard(arenaLeaderboardContract).getPlayerRank(player);
        } else {
            rank = 0;
        }
        rewardClaimed = seasonRewardsClaimed[seasonNumber][player];
    }

    /**
     * @dev 获取指定排名范围内的玩家
     * @param seasonId 赛季 ID
     * @param startRank 起始排名
     * @param endRank 结束排名
     * @return playerAddrs 玩家地址数组, scores 积分数组
     */
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        address arenaLeaderboardContract = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getPlayersByRankRange(seasonId, startRank, endRank);
        }
        return (new address[](0), new uint256[](0));
    }

    /**
     * @dev 获取玩家挑战状态
     * @param player 玩家地址
     * @return remainingAttempts 剩余挑战次数, lastBattleTime 上次战斗时间, hasTeam 是否已设置队伍
     */
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    ) {
        PlayerRecord memory p = players[player];
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        if (arenaPlayerContract != address(0)) {
            remainingAttempts = IArenaPlayer(arenaPlayerContract).getRemainingAttempts(player);
        } else {
            remainingAttempts = p.remainingAttempts > 0 ? p.remainingAttempts : 3;
        }
        lastBattleTime = p.lastBattleTime;
        hasTeam = p.hasTeam;
    }

    /**
     * @dev 领取当前赛季奖励
     * @notice 用户调用此函数领取当前赛季的排名奖励
     */
    function claimSeasonReward() external nonReentrant whenNotPaused {
        _claimSeasonReward(currentSeasonId);
    }

    /**
     * @dev 领取指定赛季奖励
     * @param seasonId 赛季 ID
     * @return 领取的奖励金额
     */
    function claimSeasonReward(uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        return _claimSeasonReward(seasonId);
    }

    /**
     * @dev 内部函数：领取指定赛季奖励
     * @param seasonId 赛季 ID
     * @return 领取的奖励金额
     * @notice 实际执行奖励领取的内部逻辑
     */
    function _claimSeasonReward(uint256 seasonId) internal returns (uint256) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRankingQuery: Invalid season");
        require(!seasonRewardsClaimed[seasonId][msg.sender], "ArenaRankingQuery: Already claimed");
        address arenaRewardLPContract = IAuthorizer(authorizer).getArenaRewardLP();
        require(arenaRewardLPContract != address(0), "ArenaRankingQuery: ArenaRewardLP not set");
        uint256 amount = IArenaRewardLP(arenaRewardLPContract).claimLPReward(seasonId);
        seasonRewardsClaimed[seasonId][msg.sender] = true;
        emit RewardClaimed(msg.sender, amount, seasonId);
        return amount;
    }

    function resetContractData() external onlyOwnerOrAuthorizer {
        currentSeasonId = 1;
        
        seasons[1] = SeasonInfo({
            seasonId: 1,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            isActive: true,
            isSettled: false,
            rewardCalculated: false,
            totalPlayers: 0,
            rewardPool: 0,
            tokenRewardPool: 0,
            pendingRewards: 0
        });
        
        emit ContractDataReset(msg.sender, block.timestamp);
    }

    event ContractDataReset(address indexed operator, uint256 timestamp);
}