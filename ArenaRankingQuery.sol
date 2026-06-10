// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

contract ArenaRankingQuery is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    constructor() {
        _disableInitializers();
    }

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

    mapping(address => PlayerRecord) public players;
    mapping(uint256 => SeasonInfo) public seasons;
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    mapping(uint256 => mapping(address => bool)) public seasonRewardsClaimed;
    
    uint256 public currentSeasonId;
    
    address public authorizer;
    address public arenaRewardContract;
    address public arenaLeaderboardContract;
    
    uint256 public constant DAILY_ATTEMPTS = 3;
    address public constant MOCK_PLAYER_BASE = address(0x000000000000000000000000000000000000dEaD);
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;

    event RewardClaimed(address indexed player, uint256 amount, uint256 seasonId);

    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "ArenaRankingQuery: Invalid authorizer address");
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizer;
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaRankingQuery: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "ArenaRankingQuery: Invalid authorizer address");
        authorizer = a;
    }

    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external onlyAuthorized {
        arenaLeaderboardContract = _arenaLeaderboardContract;
    }

    function setArenaRewardContract(address _arenaRewardContract) external onlyAuthorized {
        arenaRewardContract = _arenaRewardContract;
    }

    function _isMockPlayer(address player) internal pure returns (bool) {
        uint256 playerAddress = uint256(uint160(player));
        uint256 baseAddress = uint256(uint160(MOCK_PLAYER_BASE));
        uint256 maxAddress = baseAddress + MAX_MOCK_PLAYERS_COUNT;
        if (maxAddress <= baseAddress) {
            return false;
        }
        return playerAddress >= baseAddress && playerAddress < maxAddress;
    }

    function getPlayerRank(address player) external view returns (uint256) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getPlayerRank(player);
        }
        return 0;
    }

    function getSeasonInfo(uint256 seasonId) external view returns (uint256 startTime, uint256 endTime, bool isActive, bool isSettled, uint256 totalPlayers) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRankingQuery: Invalid season");
        SeasonInfo memory s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }

    function getCurrentSeasonInfo() external view returns (uint256 seasonId, uint256 startTime, uint256 endTime, bool isActive, uint256 totalPlayers, uint256 rewardPool) {
        SeasonInfo storage s = seasons[currentSeasonId];
        return (currentSeasonId, s.startTime, s.endTime, s.isActive, s.totalPlayers, s.rewardPool);
    }

    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory) {
        if (arenaLeaderboardContract == address(0)) {
            return new LeaderboardEntry[](0);
        }
        return IArenaLeaderboard(arenaLeaderboardContract).getLeaderboard(seasonId, limit);
    }

    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        PlayerRecord storage p = players[player];
        return (p.score, p.wins, p.losses, p.seasonId);
    }

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

    function getMockPlayerRank(address player) external view returns (uint256) {
        if (!_isMockPlayer(player)) return 0;
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getMockPlayerRank(player);
        }
        return 0;
    }

    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory) {
        return this.getLeaderboard(currentSeasonId, limit);
    }

    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory entries, uint256 totalPages, uint256 totalPlayers) {
        if (arenaLeaderboardContract == address(0)) {
            return (new LeaderboardEntry[](0), 0, 0);
        }
        (entries, totalPages, totalPlayers) = IArenaLeaderboard(arenaLeaderboardContract).getLeaderboardByPage(seasonId, page, pageSize);
    }

    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getLeaderboardPageCount(seasonId, pageSize);
        }
        return 0;
    }

    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory playerAddrs, uint256[] memory scores) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getTopPlayers(seasonId, count);
        }
        return (new address[](0), new uint256[](0));
    }

    function getSeasonReward(address player) external view returns (uint256) {
        return playerSeasonRewards[currentSeasonId][player];
    }

    function getSeasonReward(address player, uint256 seasonId) external view returns (uint256) {
        return playerSeasonRewards[seasonId][player];
    }

    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        if (count == 0 || count > currentSeasonId) count = currentSeasonId;
        SeasonInfo[] memory result = new SeasonInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = seasons[currentSeasonId - count + i + 1];
        }
        return result;
    }

    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        return seasons[seasonId].totalPlayers;
    }

    function getRemainingAttempts(address player) external view returns (uint256) {
        PlayerRecord storage p = players[player];
        if (p.lastResetTime == 0) {
            return DAILY_ATTEMPTS;
        }
        if (block.timestamp > p.lastResetTime + 24 hours) {
            return DAILY_ATTEMPTS;
        }
        return p.remainingAttempts;
    }

    function getPlayerBattleTeam(address player) external view returns (uint256[] memory) {
        PlayerRecord storage p = players[player];
        uint256[] memory team = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            team[i] = p.battleTeam[i];
        }
        return team;
    }

    function getLastBattleTime(address player) external view returns (uint256) {
        return players[player].lastBattleTime;
    }

    function rechargeCost() external pure returns (uint256) {
        return 888;
    }

    function isSeasonRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        return seasonRewardsClaimed[seasonId][player];
    }

    function getPlayerSeasonStats(address player, uint256 seasonNumber) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        bool rewardClaimed
    ) {
        PlayerRecord storage p = players[player];
        if (p.seasonId == seasonNumber) {
            score = p.score;
            wins = p.wins;
            losses = p.losses;
        } else {
            score = 0;
            wins = 0;
            losses = 0;
        }
        if (arenaLeaderboardContract != address(0)) {
            rank = IArenaLeaderboard(arenaLeaderboardContract).getPlayerRank(player);
        } else {
            rank = 0;
        }
        rewardClaimed = seasonRewardsClaimed[seasonNumber][player];
    }

    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getPlayersByRankRange(seasonId, startRank, endRank);
        }
        return (new address[](0), new uint256[](0));
    }

    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    ) {
        PlayerRecord storage p = players[player];
        remainingAttempts = p.remainingAttempts > 0 ? p.remainingAttempts : DAILY_ATTEMPTS;
        lastBattleTime = p.lastBattleTime;
        hasTeam = p.hasTeam;
    }

    function claimSeasonReward() external nonReentrant whenNotPaused {
        _claimSeasonReward(currentSeasonId);
    }

    function claimSeasonReward(uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        return _claimSeasonReward(seasonId);
    }

    function _claimSeasonReward(uint256 seasonId) internal returns (uint256) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRankingQuery: Invalid season");
        require(!seasonRewardsClaimed[seasonId][msg.sender], "ArenaRankingQuery: Already claimed");
        require(arenaRewardContract != address(0), "ArenaRankingQuery: ArenaReward not set");
        uint256 amount = IArenaReward(arenaRewardContract).claimSeasonReward(msg.sender, seasonId);
        seasonRewardsClaimed[seasonId][msg.sender] = true;
        emit RewardClaimed(msg.sender, amount, seasonId);
        return amount;
    }
}