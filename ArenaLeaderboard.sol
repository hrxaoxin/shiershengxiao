// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

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
 * - 按积分从高到低排序
 * - 相同积分按先来后到排序
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
     * @dev 赛季信息结构体
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
     * @dev 玩家记录结构体
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
     * @dev 当前赛季 ID
     */
    uint256 public currentSeasonId;
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    /**
     * @dev 排名合约地址
     */
    address public rankingContract;
    /**
     * @dev 赛季信息映射
     */
    mapping(uint256 => SeasonInfo) public seasons;
    /**
     * @dev 玩家记录映射
     */
    mapping(address => PlayerRecord) public players;
    /**
     * @dev 赛季排名数组
     */
    mapping(uint256 => address[]) public seasonRankings;
    /**
     * @dev 玩家在赛季中的排名索引
     */
    mapping(uint256 => mapping(address => uint256)) public playerRankIndex;
    
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
     * @dev 授权检查修饰器
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaLeaderboard: Not authorized");
        _;
    }
    
    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "ArenaLeaderboard: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
        _createSeason();
    }
    
    /**
     * @dev UUPS 升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaLeaderboard: Invalid authorizer address");
        authorizer = _authorizer;
    }
    
    /**
     * @dev 设置排名合约地址
     * @param _rankingContract 排名合约地址
     */
    function setRankingContract(address _rankingContract) external onlyAuthorized {
        rankingContract = _rankingContract;
    }
    
    /**
     * @dev 内部函数：创建新赛季
     */
    function _createSeason() internal {
        currentSeasonId++;
        seasons[currentSeasonId] = SeasonInfo({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            isActive: true,
            isSettled: false,
            totalPlayers: 0,
            rewardPool: 0
        });
        emit SeasonCreated(currentSeasonId, block.timestamp, block.timestamp + 7 days);
    }
    
    /**
     * @dev 结束当前赛季（仅所有者）
     */
    function endSeason() external onlyOwner {
        SeasonInfo storage season = seasons[currentSeasonId];
        require(season.isActive, "ArenaLeaderboard: Season not active");
        season.isActive = false;
        season.isSettled = true;
        _createSeason();
    }
    
    /**
     * @dev 更新玩家排名
     * @param player 玩家地址
     * @param newScore 新积分
     * @param seasonId 赛季 ID
     */
    function updateRanking(address player, uint256 newScore, uint256 seasonId) external {
        SeasonInfo storage season = seasons[seasonId];
        require(season.isActive, "ArenaLeaderboard: Season not active");
        
        PlayerRecord storage record = players[player];
        
        if (record.seasonId != seasonId) {
            record.seasonId = seasonId;
            record.score = newScore;
            record.wins = 0;
            record.losses = 0;
            record.draws = 0;
            seasonRankings[seasonId].push(player);
            playerRankIndex[seasonId][player] = seasonRankings[seasonId].length - 1;
            season.totalPlayers++;
        } else {
            record.score = newScore;
        }
        
        _updateRankingInternal(player, newScore, seasonId);
        emit ScoreUpdated(player, newScore, seasonId);
    }
    
    function _updateRankingInternal(address player, uint256 newScore, uint256 seasonId) internal {
        uint256 currentIndex = playerRankIndex[seasonId][player];
        address[] storage rankings = seasonRankings[seasonId];
        
        if (currentIndex == 0 && rankings.length >= MAX_LEADERBOARD_SIZE) {
            return;
        }
        
        if (currentIndex > 0) {
            address prevPlayer = rankings[currentIndex - 1];
            if (players[prevPlayer].score >= newScore) {
                return;
            }
        }
        
        if (currentIndex < rankings.length - 1) {
            address nextPlayer = rankings[currentIndex + 1];
            if (players[nextPlayer].score <= newScore) {
                return;
            }
        }
        
        while (currentIndex > 0) {
            address prevPlayer = rankings[currentIndex - 1];
            if (players[prevPlayer].score >= newScore) break;
            
            rankings[currentIndex] = prevPlayer;
            playerRankIndex[seasonId][prevPlayer] = currentIndex;
            rankings[currentIndex - 1] = player;
            playerRankIndex[seasonId][player] = currentIndex - 1;
            currentIndex--;
        }
        
        while (currentIndex < rankings.length - 1 && currentIndex < MAX_LEADERBOARD_SIZE - 1) {
            address nextPlayer = rankings[currentIndex + 1];
            if (players[nextPlayer].score <= newScore) break;
            
            rankings[currentIndex] = nextPlayer;
            playerRankIndex[seasonId][nextPlayer] = currentIndex;
            rankings[currentIndex + 1] = player;
            playerRankIndex[seasonId][player] = currentIndex + 1;
            currentIndex++;
        }
        
        if (rankings.length > MAX_LEADERBOARD_SIZE) {
            address removedPlayer = rankings[MAX_LEADERBOARD_SIZE];
            playerRankIndex[seasonId][removedPlayer] = 0;
            rankings.pop();
        }
        
        emit RankingUpdated(player, currentIndex + 1, seasonId);
    }
    
    function insertPlayerAtRank(address player, uint256 targetRank, uint256 seasonId) external {
        SeasonInfo storage season = seasons[seasonId];
        require(season.isActive, "ArenaLeaderboard: Season not active");
        
        PlayerRecord storage record = players[player];
        if (record.seasonId != seasonId) {
            record.seasonId = seasonId;
            record.score = 1000;
            record.wins = 0;
            record.losses = 0;
            record.draws = 0;
            season.totalPlayers++;
        }
        
        address[] storage rankings = seasonRankings[seasonId];
        uint256 currentIndex = playerRankIndex[seasonId][player];
        
        // 先从当前位置移除（如果已经在排行榜中）
        if (currentIndex > 0 && currentIndex < rankings.length) {
            for (uint256 i = currentIndex; i + 1 < rankings.length; i++) {
                rankings[i] = rankings[i + 1];
                playerRankIndex[seasonId][rankings[i]] = i;
            }
            rankings.pop();
            playerRankIndex[seasonId][player] = 0;
        }
        
        // 修复：确保 targetRank 在有效范围内
        if (targetRank >= rankings.length) {
            // 添加到末尾
            rankings.push(player);
            playerRankIndex[seasonId][player] = rankings.length - 1;
        } else {
            // 插入到指定位置
            rankings.push(address(0)); // 先扩展数组
            for (uint256 i = rankings.length - 1; i > targetRank; i--) {
                rankings[i] = rankings[i - 1];
                playerRankIndex[seasonId][rankings[i]] = i;
            }
            rankings[targetRank] = player;
            playerRankIndex[seasonId][player] = targetRank;
        }
        
        emit RankingUpdated(player, targetRank + 1, seasonId);
    }
    
    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory) {
        address[] memory rankings = seasonRankings[seasonId];
        uint256 size = limit < rankings.length ? limit : rankings.length;
        LeaderboardEntry[] memory result = new LeaderboardEntry[](size);
        for (uint256 i = 0; i < size; i++) {
            address player = rankings[i];
            PlayerRecord storage record = players[player];
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
        address[] memory rankings = seasonRankings[seasonId];
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
            PlayerRecord storage record = players[player];
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
    
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        address[] storage rankings = seasonRankings[seasonId];
        return (rankings.length + pageSize - 1) / pageSize;
    }
    
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        address[] memory rankings = seasonRankings[seasonId];
        if (startRank >= rankings.length) {
            return (new address[](0), new uint256[](0));
        }
        uint256 end = endRank < rankings.length ? endRank : rankings.length;
        playerAddrs = new address[](end - startRank);
        scores = new uint256[](end - startRank);
        for (uint256 i = startRank; i < end; i++) {
            playerAddrs[i - startRank] = rankings[i];
            scores[i - startRank] = players[rankings[i]].score;
        }
        return (playerAddrs, scores);
    }

    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        address[] memory rankings = seasonRankings[seasonId];
        uint256 size = count < rankings.length ? count : rankings.length;
        playerAddrs = new address[](size);
        scores = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            playerAddrs[i] = rankings[i];
            scores[i] = players[rankings[i]].score;
        }
        return (playerAddrs, scores);
    }
    
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory) {
        SeasonInfo[] memory result = new SeasonInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 seasonId = startSeasonId + i;
            if (seasonId > currentSeasonId) break;
            result[i] = seasons[seasonId];
        }
        return result;
    }
    
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        uint256 size = count < currentSeasonId ? count : currentSeasonId;
        SeasonInfo[] memory result = new SeasonInfo[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = seasons[currentSeasonId - i];
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
        SeasonInfo storage s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }
    
    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        bool rewardClaimed
    ) {
        PlayerRecord storage record = players[player];
        if (record.seasonId != seasonId) {
            return (0, 0, 0, 0, false);
        }
        rank = playerRankIndex[seasonId][player];
        return (record.score, record.wins, record.losses, rank, false);
    }
    
    function getPlayerRecord(address player) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 seasonId
    ) {
        PlayerRecord storage record = players[player];
        return (record.score, record.wins, record.losses, record.seasonId);
    }
    
    function getCurrentSeasonInfo() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        SeasonInfo storage s = seasons[currentSeasonId];
        return (currentSeasonId, s.startTime, s.endTime, s.isActive);
    }
    
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    ) {
        // 修复：返回值数量和类型需要与 IArenaPlayer 接口匹配
        // remainingAttempts 和 lastBattleTime 在 ArenaLeaderboard 中不存储，返回 0
        PlayerRecord storage record = players[player];
        remainingAttempts = 0;
        lastBattleTime = 0;
        hasTeam = record.seasonId != 0;
    }
    
    function getPlayerRank(address player) external view returns (uint256) {
        return playerRankIndex[currentSeasonId][player];
    }
    
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        return seasons[seasonId].totalPlayers;
    }
    
    function getSeasonReward(address player) external view returns (uint256) {
        return 0;
    }
}
