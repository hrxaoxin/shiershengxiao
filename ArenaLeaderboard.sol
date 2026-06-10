// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

contract ArenaLeaderboard is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    uint256 public constant MAX_LEADERBOARD_SIZE = 1000;
    
    struct SeasonInfo {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isSettled;
        uint256 totalPlayers;
        uint256 rewardPool;
    }
    
    struct PlayerRecord {
        uint256 score;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 seasonId;
    }
    
    uint256 public currentSeasonId;
    address public authorizer;
    address public rankingContract;
    mapping(uint256 => SeasonInfo) public seasons;
    mapping(address => PlayerRecord) public players;
    mapping(uint256 => address[]) public seasonRankings;
    mapping(uint256 => mapping(address => uint256)) public playerRankIndex;
    
    event ScoreUpdated(address indexed player, uint256 score, uint256 seasonId);
    event RankingUpdated(address indexed player, uint256 rank, uint256 seasonId);
    event SeasonCreated(uint256 seasonId, uint256 startTime, uint256 endTime);
    event LeaderboardUpdated(uint256 seasonId);
    
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaLeaderboard: Not authorized");
        _;
    }
    
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _createSeason();
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaLeaderboard: Invalid authorizer address");
        authorizer = _authorizer;
    }
    
    function setRankingContract(address _rankingContract) external onlyAuthorized {
        rankingContract = _rankingContract;
    }
    
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
    
    function endSeason() external onlyOwner {
        SeasonInfo storage season = seasons[currentSeasonId];
        require(season.isActive, "ArenaLeaderboard: Season not active");
        season.isActive = false;
        season.isSettled = true;
        _createSeason();
    }
    
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
