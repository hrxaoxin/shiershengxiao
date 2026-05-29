// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArenaRanking
 * @dev 竞技场排名与赛季管理合约（优化版：支持自动化结算）
 */
contract ArenaRanking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    struct PlayerRecord {
        uint256 score;
        uint256 wins;
        uint256 losses;
        uint256 lastBattleTime;
        uint256 lastResetTime;
        uint256 remainingAttempts;
        uint256[] battleTeam;
        bool hasTeam;
        uint256 seasonId;
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

    struct LeaderboardEntry {
        address playerAddress;
        uint256 points;
        uint256 wins;
        uint256 losses;
        bool isMock;
    }

    mapping(address => PlayerRecord) public players;
    mapping(uint256 => SeasonInfo) public seasons;
    
    mapping(uint256 => address[]) public seasonRankings;
    mapping(uint256 => mapping(address => uint256)) public playerRankIndex;

    uint256 public currentSeasonId;
    uint256 public seasonDuration = 7 days;
    uint256 public baseRewardPerWin = 10 ether;
    
    address public rewardTokenContract;
    address public authorizer;
    address public battleContract;
    address public nftContract;
    address public tokenContract;
    
    uint256 public constant DAILY_ATTEMPTS = 10;
    uint256 public rechargeCost;
    uint256 public seasonRewardRate;

    function initialize(address _battleContract, address _nftContract, address _tokenContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        battleContract = _battleContract;
        nftContract = _nftContract;
        tokenContract = _tokenContract;
        _startNewSeason();
    }

    function setAuthorizer(address a) external onlyOwner { authorizer = a; }
    function setBattleContract(address a) external onlyOwner { battleContract = a; }
    function setNFTContract(address a) external onlyOwner { nftContract = a; }
    function setTokenContract(address a) external onlyOwner { tokenContract = a; }
    function setRechargeCost(uint256 cost) external onlyOwner { rechargeCost = cost; }
    function setSeasonRewardRate(uint256 rate) external onlyOwner { seasonRewardRate = rate; }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaRanking: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    event ScoreUpdated(address indexed player, uint256 newScore, uint256 seasonId);
    event SeasonStarted(uint256 indexed seasonId, uint256 startTime);
    event SeasonSettled(uint256 indexed seasonId, uint256 endTime);
    event RewardClaimed(address indexed player, uint256 amount, uint256 seasonId);
    event ChallengeResult(address indexed challenger, bool isVictory);

    function _resetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        record.lastResetTime = block.timestamp;
        record.remainingAttempts = DAILY_ATTEMPTS;
    }

    function _checkAndResetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        if (block.timestamp >= record.lastResetTime + 24 hours) {
            _resetAttempts(player);
        }
    }

    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external returns (bool success) {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        
        PlayerRecord storage record = players[msg.sender];
        _checkAndResetAttempts(msg.sender);
        require(record.remainingAttempts > 0, "ArenaRanking: No attempts left");
        record.remainingAttempts--;

        _validateTeamOwnership(msg.sender, playerTeam);

        (bool success_, uint256 winner, ) = IBattle(battleContract).challenge(
            playerTeam[0],
            uint256(mockIndex + 1) * 1000,
            playerTeam,
            _generateMockTeam(mockIndex)
        );

        _updateScore(msg.sender, winner == 1);
        emit ChallengeResult(msg.sender, winner == 1);
        return success_;
    }

    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external returns (bool success) {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        require(challengedPlayer != msg.sender, "ArenaRanking: Cannot challenge self");
        
        PlayerRecord storage challengerRecord = players[msg.sender];
        PlayerRecord storage challengedRecord = players[challengedPlayer];
        
        _checkAndResetAttempts(msg.sender);
        require(challengerRecord.remainingAttempts > 0, "ArenaRanking: No attempts left");
        challengerRecord.remainingAttempts--;

        _validateTeamOwnership(msg.sender, playerTeam);

        uint256[6] memory challengedTeam = challengedRecord.battleTeam;
        require(challengedRecord.hasTeam && challengedTeam.length == 6, "ArenaRanking: Target has no team");

        (bool success_, uint256 winner, ) = IBattle(battleContract).challenge(
            playerTeam[0],
            challengedTeam[0],
            playerTeam,
            challengedTeam
        );

        _updateScore(msg.sender, winner == 1);
        _updateScore(challengedPlayer, winner == 2);
        emit ChallengeResult(msg.sender, winner == 1);
        return success_;
    }

    function _updateScore(address player, bool isWinner) internal {
        SeasonInfo storage currentSeason = seasons[currentSeasonId];
        require(currentSeason.isActive, "ArenaRanking: Season not active");

        PlayerRecord storage record = players[player];
        
        if (record.seasonId != currentSeasonId) {
            record.seasonId = currentSeasonId;
            record.score = 1000;
            record.wins = 0;
            record.losses = 0;
            record.lastBattleTime = block.timestamp;
            record.lastResetTime = block.timestamp;
            record.remainingAttempts = DAILY_ATTEMPTS;
            seasonRankings[currentSeasonId].push(player);
            playerRankIndex[currentSeasonId][player] = seasonRankings[currentSeasonId].length - 1;
            currentSeason.totalPlayers++;
        }

        if (isWinner) {
            record.score += 25;
            record.wins++;
        } else {
            if (record.score > 25) record.score -= 25;
            else record.score = 0;
            record.losses++;
        }
        record.lastBattleTime = block.timestamp;

        _updateRanking(player, record.score);
        emit ScoreUpdated(player, record.score, currentSeasonId);
    }

    function _updateRanking(address player, uint256 newScore) internal {
        uint256 seasonId = currentSeasonId;
        uint256 currentIndex = playerRankIndex[seasonId][player];
        address[] storage rankings = seasonRankings[seasonId];

        for (int256 i = int256(currentIndex); i > 0; i--) {
            address prevPlayer = rankings[uint256(i - 1)];
            if (players[prevPlayer].score >= newScore) break;
            
            rankings[uint256(i)] = prevPlayer;
            playerRankIndex[seasonId][prevPlayer] = uint256(i);
            rankings[uint256(i - 1)] = player;
            playerRankIndex[seasonId][player] = uint256(i - 1);
        }
    }

    function _generateMockTeam(uint256 mockIndex) internal pure returns (uint256[6] memory) {
        uint256[6] memory team;
        for (uint256 i = 0; i < 6; i++) {
            team[i] = mockIndex * 100 + i + 1;
        }
        return team;
    }

    function setBattleTeam(uint256[6] calldata tokenIds) external {
        PlayerRecord storage record = players[msg.sender];
        record.battleTeam = tokenIds;
        record.hasTeam = true;
    }

    function clearBattleTeam() external {
        PlayerRecord storage record = players[msg.sender];
        delete record.battleTeam;
        record.hasTeam = false;
    }

    function rechargeChallengeAttempts() external payable {
        require(msg.value >= rechargeCost, "ArenaRanking: Insufficient payment");
        PlayerRecord storage record = players[msg.sender];
        record.remainingAttempts += DAILY_ATTEMPTS;
    }

    function startNewSeason() external onlyAuthorized {
        require(block.timestamp >= seasons[currentSeasonId].endTime, "ArenaRanking: Current season not ended");
        _settleCurrentSeason();
        _startNewSeason();
    }

    function _startNewSeason() internal {
        currentSeasonId++;
        seasons[currentSeasonId] = SeasonInfo({
            seasonId: currentSeasonId,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            isSettled: false,
            totalPlayers: 0,
            rewardPool: 0
        });
        emit SeasonStarted(currentSeasonId, block.timestamp);
    }

    function _settleCurrentSeason() internal {
        SeasonInfo storage season = seasons[currentSeasonId];
        season.isActive = false;
        season.isSettled = true;
        emit SeasonSettled(currentSeasonId, block.timestamp);
    }

    function settleSeason(uint256 seasonId) external onlyAuthorized {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        require(!seasons[seasonId].isSettled, "ArenaRanking: Already settled");
        
        if (seasonId == currentSeasonId) {
            seasons[seasonId].isActive = false;
        }
        seasons[seasonId].isSettled = true;
        emit SeasonSettled(seasonId, block.timestamp);
    }

    function claimReward(uint256 seasonNumber) external {
        require(seasons[seasonNumber].isSettled, "ArenaRanking: Season not settled");

        PlayerRecord storage record = players[msg.sender];
        require(record.seasonId == seasonNumber, "ArenaRanking: No record in this season");

        uint256 rank = playerRankIndex[seasonNumber][msg.sender] + 1;
        require(rank > 0, "ArenaRanking: Player not found in rankings");

        uint256 reward = _calculateRankReward(rank, seasons[seasonNumber].rewardPool);
        require(reward > 0, "ArenaRanking: No reward for this rank");

        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= reward, "ArenaRanking: Insufficient reward balance");
        
        require(rewardToken.transfer(msg.sender, reward), "ArenaRanking: Transfer failed");
        
        emit RewardClaimed(msg.sender, reward, seasonNumber);
    }

    function claimSeasonReward() external {
        claimReward(currentSeasonId);
    }

    function getPendingRewards(uint256 seasonNumber) external view returns (uint256) {
        if (!seasons[seasonNumber].isSettled) return 0;
        
        PlayerRecord storage record = players[msg.sender];
        if (record.seasonId != seasonNumber) return 0;
        
        uint256 rank = playerRankIndex[seasonNumber][msg.sender] + 1;
        if (rank == 0) return 0;
        
        return _calculateRankReward(rank, seasons[seasonNumber].rewardPool);
    }

    function getPendingRewards(address player) external view returns (uint256) {
        PlayerRecord storage record = players[player];
        if (!seasons[record.seasonId].isSettled) return 0;
        
        uint256 rank = playerRankIndex[record.seasonId][player] + 1;
        if (rank == 0) return 0;
        
        return _calculateRankReward(rank, seasons[record.seasonId].rewardPool);
    }

    function getPlayerRank(address player) external view returns (uint256) {
        return playerRankIndex[currentSeasonId][player] + 1;
    }

    function _calculateRankReward(uint256 rank, uint256 pool) internal pure returns (uint256) {
        if (rank == 1) return pool * 30 / 100;
        if (rank == 2) return pool * 20 / 100;
        if (rank == 3) return pool * 15 / 100;
        if (rank <= 10) return pool * 5 / 100;
        if (rank <= 50) return pool * 2 / 100;
        return 0;
    }

    function getSeasonInfo(uint256 seasonId) external view returns (uint256 startTime, uint256 endTime, bool isActive, bool isSettled, uint256 totalPlayers) {
        SeasonInfo memory s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }

    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        PlayerRecord memory r = players[player];
        return (r.score, r.wins, r.losses, r.seasonId);
    }

    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory playerAddrs, uint256[] memory scores) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        uint256 len = seasonRankings[seasonId].length;
        if (count > len) count = len;
        
        playerAddrs = new address[](count);
        scores = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            playerAddrs[i] = seasonRankings[seasonId][i];
            scores[i] = players[playerAddrs[i]].score;
        }
        return (playerAddrs, scores);
    }

    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory) {
        uint256 len = seasonRankings[currentSeasonId].length;
        if (limit > len) limit = len;
        
        LeaderboardEntry[] memory entries = new LeaderboardEntry[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            address player = seasonRankings[currentSeasonId][i];
            PlayerRecord memory record = players[player];
            entries[i] = LeaderboardEntry({
                playerAddress: player,
                points: record.score,
                wins: record.wins,
                losses: record.losses,
                isMock: false
            });
        }
        return entries;
    }

    function getPlayerBattleTeam(address player) external view returns (uint256[6] memory) {
        PlayerRecord storage record = players[player];
        uint256[6] memory team;
        if (record.hasTeam && record.battleTeam.length >= 6) {
            for (uint256 i = 0; i < 6; i++) {
                team[i] = record.battleTeam[i];
            }
        }
        return team;
    }

    function getRemainingAttempts(address player) external view returns (uint256) {
        PlayerRecord storage record = players[player];
        PlayerRecord memory temp = record;
        if (block.timestamp >= temp.lastResetTime + 24 hours) {
            return DAILY_ATTEMPTS;
        }
        return temp.remainingAttempts;
    }

    function playerScores(address player) external view returns (uint256) {
        return players[player].score;
    }

    function playerInfo(address player) external view returns (uint256, uint256, uint256) {
        PlayerRecord storage record = players[player];
        return (record.score, record.wins, record.losses);
    }

    function getCurrentRewardPool() external view returns (uint256) {
        return seasons[currentSeasonId].rewardPool;
    }

    function getSeasonReward(address player) external view returns (uint256) {
        return getPendingRewards(player);
    }

    function seasonRewardsClaimed(address player) external view returns (bool) {
        return pendingRewards[currentSeasonId][player] == 0;
    }

    function currentSeason() external view returns (uint256, uint256, uint256, bool) {
        SeasonInfo storage season = seasons[currentSeasonId];
        return (currentSeasonId, season.startTime, season.endTime, season.isActive);
    }

    function calculateRewardForRank(uint256 rank) external view returns (uint256) {
        return _calculateRankReward(rank, seasons[currentSeasonId].rewardPool);
    }

    function getRewardForRank(uint256 rank) external view returns (uint256) {
        return _calculateRankReward(rank, seasons[currentSeasonId].rewardPool);
    }

    function calculateSeasonRewards(uint256 seasonNumber) external onlyAuthorized {
    }

    function setRewardTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "ArenaRanking: Invalid token address");
        rewardTokenContract = _tokenContract;
    }

    function setSeasonDuration(uint256 duration) external onlyOwner {
        require(duration >= 1 days, "ArenaRanking: Duration too short");
        seasonDuration = duration;
    }

    function addRewardToPool(uint256 amount) external onlyAuthorized {
        require(rewardTokenContract != address(0), "ArenaRanking: Reward token not set");
        require(IERC20(rewardTokenContract).transferFrom(msg.sender, address(this), amount), "ArenaRanking: Transfer failed");
        seasons[currentSeasonId].rewardPool += amount;
    }

    /**
     * @dev 验证用户是否拥有战队中的所有NFT
     * @param owner 用户地址
     * @param team 战队NFT ID数组
     */
    function _validateTeamOwnership(address owner, uint256[6] calldata team) internal view {
        INFT nft = INFT(nftContract);
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nft.ownerOf(tokenId) == owner, "ArenaRanking: Not owner of token");
        }
    }
}

interface IBattle {
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam
    ) external returns (bool, uint256, uint256[] memory);
}

interface INFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}