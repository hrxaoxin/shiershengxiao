﻿// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";
import "./AddressLib.sol";

/**
 * @title ArenaLeaderboard
 * @dev 竞技场排行榜合约，管理玩家的赛季排名和战绩
 * 
 * 核心职责：
 * 1. 排行榜管理：记录和更新玩家在每个赛季的积分和排名
 * 2. 赛季管理：创建、结束赛季，跟踪赛季状态
 * 3. 排名查询：提供按页查询、获取玩家排名等功能
 * 
 * 排名机制：
 * - 按积分从高到低排名
 * - 相同积分按先来后到排名
 * - 排行榜大小限制为 1000 名
 * 
 * 与其他合约的交互：
 * - ArenaRanking / ArenaRankingManager：战斗后更新玩家排名
 * - ArenaBattle：战斗结果影响排名变化
 * - ArenaReward：赛季奖励基于排行榜排名分配
 * 
 * 安全机制：
 * - UUPS 升级：支持合约升级
 * - 权限控制：只有授权合约才能更新排名
 * 
 * 权限控制：
 * - onlyOwner：结束赛季、升级合约
 * - onlyAuthorized：设置排名合约地址、更新排名
 */
contract ArenaLeaderboard is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 最大排行榜大小
     */
    uint256 public constant MAX_LEADERBOARD_SIZE = 1000;
    
    /**
     * @dev 赛季信息结构（仅用于返回值）：
     * @param startTime 赛季开始时间
     * @param endTime 赛季结束时间
     * @param isActive 赛季是否进行中
     * @param isSettled 赛季是否已结算
     * @param totalPlayers 赛季总玩家数
     * @param rewardPool 奖励池金额
     */
    struct SeasonInfo {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isSettled;
        uint256 totalPlayers;
        uint256 rewardPool;
    }
    
    /**
     * @dev 玩家记录结构：
     * @param score 玩家积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param draws 平局次数
     * @param seasonId 当前赛季 ID
     */
    struct PlayerRecord {
        uint256 score;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 seasonId;
    }
    
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    /**
     * @dev 玩家记录映射
     */
    mapping(uint256 => mapping(address => PlayerRecord)) public players;
    /**
     * @dev 赛季排名数组
     */
    mapping(uint256 => mapping(uint256 => address[])) public seasonRankings;
    /**
     * @dev 玩家在赛季中的排名索引
     */
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public playerRankIndex;
    
    /**
     * @dev 纪元版本号，用于快速重置合约数据
     * @notice 循环复用，MAX_EPOCHS次后回到0，存储槽位复用防止膨胀
     */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    /**
     * @dev 分数更新事件
     */
    event ScoreUpdated(address indexed player, uint256 score, uint256 seasonId);
    /**
     * @dev 排名更新事件
     */
    event RankingUpdated(address indexed player, uint256 rank, uint256 seasonId);
    /**
     * @dev 赛季创建事件
     */
    event SeasonCreated(uint256 seasonId, uint256 startTime, uint256 endTime);
    /**
     * @dev 排行榜更新事件
     */
    event LeaderboardUpdated(uint256 seasonId);

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     * @param oldEpoch 重置前的纪元号
     * @param newEpoch 重置后的纪元号
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);
    
    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "ArenaLeaderboard: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaLeaderboard: Not authorized");
        _;
    }
    
    /// @dev 构造函数：禁用初始化器，防止实现合约被直接部署后被初始化攻击
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(
        address _authorizerAddress
    ) external initializer {
        require(_authorizerAddress != address(0), "ArenaLeaderboard: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizerAddress;
        epoch = 1;
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
        require(_authorizerAddress != address(0), "ArenaLeaderboard: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }
    
    /**
     * @dev 结束当前赛季（仅所有者）
     * @notice 赛季状态由 ArenaRankingManager 管理，此函数仅保留兼容性
     */
    function endSeason() external onlyOwner {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName(AddressLib.ARENA_RANKING_MANAGER);
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        require(currentSeasonId > 0, "ArenaLeaderboard: No active season");
        // 修复：委托ArenaRankingManager执行赛季结算
        IArenaRanking(arenaRankingManager).settleSeason(currentSeasonId);
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }
    
    /**
     * @dev 更新玩家排名
     * @param player 玩家地址
     * @param newScore 新积分
     * @param seasonId 赛季 ID
     * @notice 当玩家积分变化时调用，自动调整排行榜顺序
     */
    function updateRanking(address player, uint256 newScore, uint256 seasonId) external {
        _checkSeasonActive(seasonId);
        
        uint256 currentEpoch = _currentEpoch();
        PlayerRecord storage record = players[currentEpoch][player];
        
        if (record.seasonId != seasonId) {
            record.seasonId = seasonId;
            record.score = newScore;
            record.wins = 0;
            record.losses = 0;
            record.draws = 0;
            seasonRankings[currentEpoch][seasonId].push(player);
            playerRankIndex[currentEpoch][seasonId][player] = seasonRankings[currentEpoch][seasonId].length - 1;
        } else {
            record.score = newScore;
        }
        
        _updateRankingInternal(player, newScore, seasonId);
        emit ScoreUpdated(player, newScore, seasonId);
    }

    function _checkSeasonActive(uint256 seasonId) internal view {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName(AddressLib.ARENA_RANKING_MANAGER);
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        require(IArenaRanking(arenaRankingManager).currentSeasonId() >= seasonId, "ArenaLeaderboard: Season not active");
    }
    
    function _updateRankingInternal(address player, uint256 newScore, uint256 seasonId) internal {
        uint256 currentEpoch = _currentEpoch();
        uint256 currentIndex = playerRankIndex[currentEpoch][seasonId][player];
        address[] storage rankings = seasonRankings[currentEpoch][seasonId];
        
        // 修复：移除currentIndex==0的错误条件，排行榜满时如果玩家在榜尾则不需要额外处理，
        // 排序逻辑会自然地将不合格的玩家移出排行榜
        if (rankings.length > MAX_LEADERBOARD_SIZE) {
            // 超出的元素会在后续while循环和截断逻辑中处理
        }
        
        if (currentIndex > 0) {
            address prevPlayer = rankings[currentIndex - 1];
            if (players[currentEpoch][prevPlayer].score >= newScore) {
                return;
            }
        }
        
        if (currentIndex < rankings.length - 1) {
            address nextPlayer = rankings[currentIndex + 1];
            if (players[currentEpoch][nextPlayer].score <= newScore) {
                return;
            }
        }
        
        while (currentIndex > 0) {
            address prevPlayer = rankings[currentIndex - 1];
            if (players[currentEpoch][prevPlayer].score >= newScore) break;
            
            rankings[currentIndex] = prevPlayer;
            playerRankIndex[currentEpoch][seasonId][prevPlayer] = currentIndex;
            rankings[currentIndex - 1] = player;
            playerRankIndex[currentEpoch][seasonId][player] = currentIndex - 1;
            currentIndex--;
        }
        
        while (currentIndex < rankings.length - 1 && currentIndex < MAX_LEADERBOARD_SIZE - 1) {
            address nextPlayer = rankings[currentIndex + 1];
            if (players[currentEpoch][nextPlayer].score <= newScore) break;
            
            rankings[currentIndex] = nextPlayer;
            playerRankIndex[currentEpoch][seasonId][nextPlayer] = currentIndex;
            rankings[currentIndex + 1] = player;
            playerRankIndex[currentEpoch][seasonId][player] = currentIndex + 1;
            currentIndex++;
        }
        
        if (rankings.length > MAX_LEADERBOARD_SIZE) {
            address removedPlayer = rankings[MAX_LEADERBOARD_SIZE];
            playerRankIndex[currentEpoch][seasonId][removedPlayer] = 0;
            rankings.pop();
        }
        
        emit RankingUpdated(player, currentIndex + 1, seasonId);
    }
    
    /**
     * @dev 在指定排名位置插入玩家
     * @param player 玩家地址
     * @param targetRank 目标排名（从0开始）
     * @param seasonId 赛季 ID
     * @notice 用于系统操作，将玩家插入到指定排名位置
     */
    function insertPlayerAtRank(address player, uint256 targetRank, uint256 seasonId) external {
        _checkSeasonActive(seasonId);
        
        uint256 currentEpoch = _currentEpoch();
        PlayerRecord storage record = players[currentEpoch][player];
        if (record.seasonId != seasonId) {
            record.seasonId = seasonId;
            record.score = 1000;
            record.wins = 0;
            record.losses = 0;
            record.draws = 0;
        }
        
        address[] storage rankings = seasonRankings[currentEpoch][seasonId];
        uint256 currentIndex = playerRankIndex[currentEpoch][seasonId][player];
        
        // 修复：通过验证rankings[currentIndex]==player来确认玩家是否已在排行榜中
        // 避免索引0被误认为"不在排行榜中"（索引0=第1名）
        if (currentIndex < rankings.length && rankings[currentIndex] == player) {
            for (uint256 i = currentIndex; i + 1 < rankings.length; i++) {
                rankings[i] = rankings[i + 1];
                playerRankIndex[currentEpoch][seasonId][rankings[i]] = i;
            }
            rankings.pop();
            playerRankIndex[currentEpoch][seasonId][player] = 0;
        }
        
        // 修复：确保 targetRank 在有效范围内
        if (targetRank >= rankings.length) {
            // 添加到末尾
            rankings.push(player);
            playerRankIndex[currentEpoch][seasonId][player] = rankings.length - 1;
        } else {
            // 插入到指定位置
            rankings.push(address(0)); // 先扩展数组
            for (uint256 i = rankings.length - 1; i > targetRank; i--) {
                rankings[i] = rankings[i - 1];
                playerRankIndex[currentEpoch][seasonId][rankings[i]] = i;
            }
            rankings[targetRank] = player;
            playerRankIndex[currentEpoch][seasonId][player] = targetRank;
        }
        
        emit RankingUpdated(player, targetRank + 1, seasonId);
    }
    
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory) {
        uint256 currentEpoch = _currentEpoch();
        address[] memory rankings = seasonRankings[currentEpoch][seasonId];
        uint256 size = limit < rankings.length ? limit : rankings.length;
        LeaderboardEntry[] memory result = new LeaderboardEntry[](size);
        for (uint256 i = 0; i < size; i++) {
            address player = rankings[i];
            PlayerRecord storage record = players[currentEpoch][player];
            result[i] = LeaderboardEntry({
                playerAddress: player,
                points: record.score,
                wins: record.wins,
                losses: record.losses,
                isMock: false
            });
        }
        return result;
    }
    
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (
        LeaderboardEntry[] memory entries,
        uint256 totalPages,
        uint256 totalPlayers
    ) {
        uint256 currentEpoch = _currentEpoch();
        address[] memory rankings = seasonRankings[currentEpoch][seasonId];
        uint256 start = page * pageSize;
        if (start >= rankings.length) {
            return (new LeaderboardEntry[](0), 0, rankings.length);
        }
        uint256 end = start + pageSize;
        if (end > rankings.length) {
            end = rankings.length;
        }
        entries = new LeaderboardEntry[](end - start);
        for (uint256 i = start; i < end; i++) {
            address player = rankings[i];
            PlayerRecord storage record = players[currentEpoch][player];
            entries[i - start] = LeaderboardEntry({
                playerAddress: player,
                points: record.score,
                wins: record.wins,
                losses: record.losses,
                isMock: false
            });
        }
        totalPages = (rankings.length + pageSize - 1) / pageSize;
        totalPlayers = rankings.length;
    }
    
    /**
     * @dev 获取排行榜总页数
     * @param seasonId 赛季 ID
     * @param pageSize 每页大小
     * @return 总页数
     */
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        address[] storage rankings = seasonRankings[currentEpoch][seasonId];
        return (rankings.length + pageSize - 1) / pageSize;
    }
    
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        uint256 currentEpoch = _currentEpoch();
        address[] memory rankings = seasonRankings[currentEpoch][seasonId];
        if (startRank >= rankings.length) {
            return (new address[](0), new uint256[](0));
        }
        uint256 end = endRank < rankings.length ? endRank : rankings.length;
        playerAddrs = new address[](end - startRank);
        scores = new uint256[](end - startRank);
        for (uint256 i = startRank; i < end; i++) {
            playerAddrs[i - startRank] = rankings[i];
            scores[i - startRank] = players[currentEpoch][rankings[i]].score;
        }
        return (playerAddrs, scores);
    }

    /**
     * @dev 获取前N名玩家
     * @param seasonId 赛季 ID
     * @param count 数量
     * @return playerAddrs 玩家地址数组, scores 积分数组
     */
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        uint256 currentEpoch = _currentEpoch();
        address[] memory rankings = seasonRankings[currentEpoch][seasonId];
        uint256 size = count < rankings.length ? count : rankings.length;
        playerAddrs = new address[](size);
        scores = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            playerAddrs[i] = rankings[i];
            scores[i] = players[currentEpoch][rankings[i]].score;
        }
        return (playerAddrs, scores);
    }
    
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName(AddressLib.ARENA_RANKING_MANAGER);
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        
        SeasonInfo[] memory result = new SeasonInfo[](count);
        uint256 currentId = IArenaRanking(arenaRankingManager).currentSeasonId();
        
        for (uint256 i = 0; i < count; i++) {
            uint256 seasonId = startSeasonId + i;
            if (seasonId > currentId) break;
            
            (uint256 st, uint256 et, bool active, bool settled, uint256 tp) = IArenaRanking(arenaRankingManager).getSeasonInfo(seasonId);
            result[i] = SeasonInfo({
                startTime: st,
                endTime: et,
                isActive: active,
                isSettled: settled,
                totalPlayers: tp,
                rewardPool: 0
            });
        }
        return result;
    }
    
    /**
     * @dev 获取最近赛季
     * @param count 赛季数量
     * @return 赛季信息数组（从最近到最早）
     */
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName(AddressLib.ARENA_RANKING_MANAGER);
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        
        uint256 currentId = IArenaRanking(arenaRankingManager).currentSeasonId();
        uint256 size = count < currentId ? count : currentId;
        SeasonInfo[] memory result = new SeasonInfo[](size);
        
        for (uint256 i = 0; i < size; i++) {
            uint256 seasonId = currentId - i;
            (uint256 st, uint256 et, bool active, bool settled, uint256 tp) = IArenaRanking(arenaRankingManager).getSeasonInfo(seasonId);
            result[i] = SeasonInfo({
                startTime: st,
                endTime: et,
                isActive: active,
                isSettled: settled,
                totalPlayers: tp,
                rewardPool: 0
            });
        }
        return result;
    }
    
    function isMockPlayer(address player) external view returns (bool) {
        return false;
    }
    
    function getMockPlayerRank(address player) external view returns (uint256) {
        return 0;
    }
    
    function getSeasonInfo(uint256 seasonId) external view returns (
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isSettled,
        uint256 totalPlayers
    ) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        return IArenaRanking(arenaRankingManager).getSeasonInfo(seasonId);
    }
    
    /**
     * @dev 获取玩家赛季统计
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return score 积分, wins 胜利次数, losses 失败次数, rank 排名, rewardClaimed 奖励是否已领取
     */
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        bool rewardClaimed
    ) {
        uint256 currentEpoch = _currentEpoch();
        PlayerRecord storage record = players[currentEpoch][player];
        if (record.seasonId != seasonId) {
            return (0, 0, 0, 0, false);
        }
        rank = playerRankIndex[currentEpoch][seasonId][player];
        return (record.score, record.wins, record.losses, rank, false);
    }
    
    function getPlayerRecord(address player) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 seasonId
    ) {
        uint256 currentEpoch = _currentEpoch();
        PlayerRecord storage record = players[currentEpoch][player];
        return (record.score, record.wins, record.losses, record.seasonId);
    }
    
    /**
     * @dev 获取当前赛季信息
     * @return seasonId 赛季ID, startTime 开始时间, endTime 结束时间, isActive 是否进行中
     */
    function getCurrentSeasonInfo() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        uint256 totalPlayers;
        uint256 rewardPool;
        (seasonId, startTime, endTime, isActive, totalPlayers, rewardPool) = IArenaRanking(arenaRankingManager).getCurrentSeasonInfo();
    }
    
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    ) {
        uint256 currentEpoch = _currentEpoch();
        PlayerRecord storage record = players[currentEpoch][player];
        remainingAttempts = 0;
        lastBattleTime = 0;
        hasTeam = record.seasonId != 0;
    }
    
    function getPlayerRank(address player) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        return playerRankIndex[currentEpoch][currentSeasonId][player];
    }
    
    /**
     * @dev 获取赛季总玩家数
     * @param seasonId 赛季 ID
     * @return 玩家数量
     */
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        require(arenaRankingManager != address(0), "ArenaLeaderboard: Ranking manager not set");
        (, , , , uint256 totalPlayers) = IArenaRanking(arenaRankingManager).getSeasonInfo(seasonId);
        return totalPlayers;
    }
    
    /**
     * @dev 获取玩家赛季奖励
     * @param player 玩家地址
     * @return 奖励金额
     * @notice ArenaLeaderboard中始终返回0，奖励由ArenaReward计算
     */
    function getSeasonReward(address player) external view returns (uint256) {
        return 0;
    }

    /**
     * @dev 重置合约数据
     * @notice 清空排行榜数据，仅owner或authorizer可调用
     * @dev 使用纪元模式实现O(1)重置，所有旧数据自动失效
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}