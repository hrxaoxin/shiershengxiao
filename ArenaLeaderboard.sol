// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

contract ArenaLeaderboard is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    address public rankingContract;
    
    event LeaderboardUpdated(uint256 seasonId);

    modifier onlyAuthorized() {
        require(msg.sender == rankingContract, "ArenaLeaderboard: Not authorized");
        _;
    }

    function initialize(address _rankingContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        rankingContract = _rankingContract;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setRankingContract(address _rankingContract) external onlyOwner {
        rankingContract = _rankingContract;
    }

    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory) {
        return IArenaRanking(rankingContract).getLeaderboard(seasonId, limit);
    }

    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (
        LeaderboardEntry[] memory entries,
        uint256 totalPages,
        uint256 totalPlayers
    ) {
        return IArenaRanking(rankingContract).getLeaderboardByPage(seasonId, page, pageSize);
    }

    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        return IArenaRanking(rankingContract).getLeaderboardPageCount(seasonId, pageSize);
    }

    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        return IArenaRanking(rankingContract).getPlayersByRankRange(seasonId, startRank, endRank);
    }

    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        return IArenaRanking(rankingContract).getTopPlayers(seasonId, count);
    }

    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory) {
        return IArenaRanking(rankingContract).getSeasonHistory(startSeasonId, count);
    }

    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        return IArenaRanking(rankingContract).getRecentSeasons(count);
    }

    function isMockPlayer(address player) external view returns (bool) {
        return IArenaRanking(rankingContract).isMockPlayer(player);
    }

    function getMockPlayerRank(address player) external view returns (uint256) {
        return IArenaRanking(rankingContract).getMockPlayerRank(player);
    }

    function getSeasonInfo(uint256 seasonId) external view returns (
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isSettled,
        uint256 totalPlayers
    ) {
        return IArenaRanking(rankingContract).getSeasonInfo(seasonId);
    }

    function getPlayerSeasonStats(address player, uint256 seasonId) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        uint256 season,
        bool rewardClaimed
    ) {
        return IArenaRanking(rankingContract).getPlayerSeasonStats(player, seasonId);
    }

    function getPlayerRecord(address player) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 seasonId
    ) {
        return IArenaRanking(rankingContract).getPlayerRecord(player);
    }

    function getCurrentSeasonInfo() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        uint256 totalPlayers,
        uint256 rewardPool
    ) {
        return IArenaRanking(rankingContract).getCurrentSeasonInfo();
    }

    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        uint256 hasTeam,
        uint256 seasonId
    ) {
        return IArenaRanking(rankingContract).getPlayerChallengeStatus(player);
    }

    function getPlayerRank(address player) external view returns (uint256) {
        return IArenaRanking(rankingContract).getPlayerRank(player);
    }

    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        return IArenaRanking(rankingContract).getTotalPlayersInSeason(seasonId);
    }
}
