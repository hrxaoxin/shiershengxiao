// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";


/**
 * @title ArenaRanking
 * @dev 竞技场排名与赛季管理合约（优化版：支持自动化结算）
 */
contract ArenaRanking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

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
        bool rewardCalculated;
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
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    
    /**
     * @dev 赛季奖励是否已领取
     * seasonId => player => claimed
     */
    mapping(uint256 => mapping(address => bool)) public seasonRewardsClaimed;
    
    /**
     * @dev NFT 质押状态
     * tokenId => owner (如果质押则为合约地址)
     */
    mapping(uint256 => address) public nftStakedOwner;
    
    /**
     * @dev 用户质押的 NFT 列表
     * user => tokenId[]
     */
    mapping(address => uint256[]) public userStakedNFTs;

    uint256 public currentSeasonId;
    uint256 public seasonDuration = 7 days;
    
    address public authorizer;
    address public battleContract;
    address public nftContract;
    address public tokenContract;
    
    uint256 public constant DAILY_ATTEMPTS = 3;
    uint256 public constant MAX_RECHARGE_ATTEMPTS = 50;
    uint256 public constant BATTLE_COOLDOWN = 60 seconds;
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant RECHARGE_COST = 888;
    uint256 public constant RECHARGE_ATTEMPTS = 3;
    uint256 public maxRechargeAttempts = 10;
    uint256 public seasonRewardRate;
    mapping(address => uint256) public lastBattleTime;
    mapping(address => uint256) public rechargeCount;

    event RechargeLimitUpdated(uint256 newLimit);
    event ChallengeRecharged(address indexed player, uint256 attempts, uint256 totalRemaining);
    event NFTsStaked(address indexed player, uint256[] tokenIds);
    event NFTsUnstaked(address indexed player, uint256[] tokenIds);
    event BattleTeamSet(address indexed player, uint256[] tokenIds);
    event BattleTeamCleared(address indexed player);

    function initialize(address _battleContract, address _nftContract, address _tokenContract, address _authorizer) external initializer {
        require(_battleContract != address(0), "ArenaRanking: Invalid battle contract address");
        require(_nftContract != address(0), "ArenaRanking: Invalid NFT contract address");
        require(_tokenContract != address(0), "ArenaRanking: Invalid token contract address");
        require(_authorizer != address(0), "ArenaRanking: Invalid authorizer address");
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        battleContract = _battleContract;
        nftContract = _nftContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
        _startNewSeason();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "ArenaRanking: Invalid authorizer address");
        authorizer = a;
    }
    function setBattleContract(address a) external onlyOwner {
        require(a != address(0), "ArenaRanking: Invalid battle contract address");
        battleContract = a;
    }
    function setNFTContract(address a) external onlyOwner {
        require(a != address(0), "ArenaRanking: Invalid NFT contract address");
        nftContract = a;
    }
    function setTokenContract(address a) external onlyOwner {
        require(a != address(0), "ArenaRanking: Invalid token contract address");
        tokenContract = a;
    }
    function setSeasonRewardRate(uint256 rate) external onlyOwner { 
        seasonRewardRate = rate; 
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaRanking: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    event ScoreUpdated(address indexed player, uint256 newScore, uint256 seasonId);
    event SeasonStarted(uint256 indexed seasonId, uint256 startTime);
    event SeasonSettled(uint256 indexed seasonId, uint256 endTime);
    event RewardClaimed(address indexed player, uint256 amount, uint256 seasonId);
    event ChallengeResult(address indexed challenger, address indexed challenged, bool isVictory, uint256 seasonId);
    event SeasonRewardsCalculated(uint256 indexed seasonNumber, uint256 totalReward, uint256 distributed);

    function _resetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        record.lastResetTime = block.timestamp;
        record.remainingAttempts = DAILY_ATTEMPTS;
        rechargeCount[player] = 0;
    }

    function _checkAndResetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        if (block.timestamp >= record.lastResetTime + 24 hours) {
            _resetAttempts(player);
        }
    }

    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external whenNotPaused returns (bool success) {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaRanking: Battle cooldown");

        PlayerRecord storage record = players[msg.sender];
        _checkAndResetAttempts(msg.sender);
        require(record.remainingAttempts > 0, "ArenaRanking: No attempts left");
        record.remainingAttempts--;
        lastBattleTime[msg.sender] = block.timestamp;

        _validateTeamStaked(msg.sender, playerTeam);

        (bool success_, uint256 winner) = IBattle(battleContract).challenge(
            playerTeam[0],
            uint256(mockIndex + 1) * 1000,
            playerTeam,
            _generateMockTeam(mockIndex),
            address(0)
        );

        _updateScore(msg.sender, winner == 1);
        emit ChallengeResult(msg.sender, address(0), winner == 1, currentSeasonId);
        return success_;
    }

    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external whenNotPaused returns (bool success) {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        require(challengedPlayer != msg.sender, "ArenaRanking: Cannot challenge self");

        SeasonInfo storage currentSeason = seasons[currentSeasonId];
        require(currentSeason.isActive, "ArenaRanking: Season not active");
        require(block.timestamp < currentSeason.endTime, "ArenaRanking: Season ended");

        PlayerRecord storage challengerRecord = players[msg.sender];
        PlayerRecord storage challengedRecord = players[challengedPlayer];

        require(userStakedNFTs[msg.sender].length > 0, "ArenaRanking: No staked NFTs");

        _checkAndResetAttempts(msg.sender);
        _checkAndResetAttempts(challengedPlayer);
        require(challengerRecord.remainingAttempts > 0, "ArenaRanking: No attempts left");
        require(challengedRecord.remainingAttempts > 0, "ArenaRanking: Target has no attempts left");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaRanking: Battle cooldown");
        require(block.timestamp >= lastBattleTime[challengedPlayer] + BATTLE_COOLDOWN, "ArenaRanking: Target in battle cooldown");
        challengerRecord.remainingAttempts--;
        lastBattleTime[msg.sender] = block.timestamp;

        _validateTeamStaked(msg.sender, playerTeam);

        uint256[6] memory challengedTeam = challengedRecord.battleTeam;
        require(challengedRecord.hasTeam && challengedTeam.length == TEAM_SIZE, "ArenaRanking: Target has no team");
        
        _validateTeamStaked(challengedPlayer, challengedTeam);

        (bool success_, uint256 winner) = IBattle(battleContract).challenge(
            playerTeam[0],
            challengedTeam[0],
            playerTeam,
            challengedTeam,
            challengedPlayer
        );

        _updateScore(msg.sender, winner == 1);
        _updateScore(challengedPlayer, winner == 2);
        emit ChallengeResult(msg.sender, challengedPlayer, winner == 1, currentSeasonId);
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

        while (currentIndex < rankings.length - 1) {
            address nextPlayer = rankings[currentIndex + 1];
            if (players[nextPlayer].score <= newScore) break;
            
            rankings[currentIndex] = nextPlayer;
            playerRankIndex[seasonId][nextPlayer] = currentIndex;
            rankings[currentIndex + 1] = player;
            playerRankIndex[seasonId][player] = currentIndex + 1;
            currentIndex++;
        }
    }

    uint256 public constant MAX_MOCK_PLAYERS = 1000;
    uint256 public constant MOCK_ID_OFFSET = 10000;
    uint256 public constant MOCK_ID_MULTIPLIER = 1000;

    function _generateMockTeam(uint256 mockIndex) internal pure returns (uint256[TEAM_SIZE] memory) {
        require(mockIndex < MAX_MOCK_PLAYERS, "ArenaRanking: Invalid mock index");
        uint256[TEAM_SIZE] memory team;
        uint256 baseId = (mockIndex + MOCK_ID_OFFSET) * MOCK_ID_MULTIPLIER;
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            team[i] = baseId + i + 1;
        }
        return team;
    }

    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nft.ownerOf(tokenId) == msg.sender, "ArenaRanking: Not owner of token");
            require(nftStakedOwner[tokenId] == address(0), "ArenaRanking: NFT already staked");
            require(nft.isApprovedForAll(msg.sender, address(this)), "ArenaRanking: Contract not approved for transfer");
            
            nft.safeTransferFrom(msg.sender, address(this), tokenId);
            nftStakedOwner[tokenId] = msg.sender;
            userStakedNFTs[msg.sender].push(tokenId);
        }
        
        emit NFTsStaked(msg.sender, tokenIds);
    }

    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        PlayerRecord storage record = players[msg.sender];
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nftStakedOwner[tokenId] != address(0), "ArenaRanking: NFT not staked");
            require(nftStakedOwner[tokenId] == msg.sender, "ArenaRanking: Not owner of staked NFT");
            
            // 检查该 NFT 是否在战斗队伍中
            bool inTeam = false;
            for (uint256 j = 0; j < record.battleTeam.length; j++) {
                if (record.battleTeam[j] == tokenId) {
                    inTeam = true;
                    break;
                }
            }
            require(!inTeam, "ArenaRanking: NFT is in battle team");
            
            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            nftStakedOwner[tokenId] = address(0);
            
            // 从用户质押列表中移除
            uint256[] storage stakedList = userStakedNFTs[msg.sender];
            for (uint256 j = 0; j < stakedList.length; j++) {
                if (stakedList[j] == tokenId) {
                    stakedList[j] = stakedList[stakedList.length - 1];
                    stakedList.pop();
                    break;
                }
            }
        }
        
        emit NFTsUnstaked(msg.sender, tokenIds);
    }

    function setBattleTeam(uint256[6] calldata tokenIds) external {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        
        PlayerRecord storage record = players[msg.sender];
        require(!record.hasTeam, "ArenaRanking: Already has a team");
        
        // 检查 NFT 是否已质押给合约
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nftStakedOwner[tokenId] == msg.sender, "ArenaRanking: NFT not staked or not owner");
            
            // 检查重复
            for (uint256 j = i + 1; j < 6; j++) {
                require(tokenIds[j] != tokenId, "ArenaRanking: Duplicate token in team");
            }
        }
        
        record.battleTeam = tokenIds;
        record.hasTeam = true;
        
        emit BattleTeamSet(msg.sender, tokenIds);
    }

    function clearBattleTeam() external {
        PlayerRecord storage record = players[msg.sender];
        delete record.battleTeam;
        record.hasTeam = false;
        
        emit BattleTeamCleared(msg.sender);
    }

    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        require(user != address(0), "ArenaRanking: Invalid user address");
        return userStakedNFTs[user];
    }

    function rechargeChallengeAttempts() external whenNotPaused {
        require(tokenContract != address(0), "ArenaRanking: Token contract not set");
        require(rechargeCount[msg.sender] < maxRechargeAttempts, "ArenaRanking: Max recharge limit reached");

        PlayerRecord storage record = players[msg.sender];
        uint256 newAttempts = RECHARGE_ATTEMPTS;
        require(record.remainingAttempts + newAttempts <= MAX_RECHARGE_ATTEMPTS, "ArenaRanking: Would exceed max attempts");

        uint256 burnAmount = RECHARGE_COST * 1e18;
        IERC20 token = IERC20(tokenContract);
        
        uint256 currentAllowance = token.allowance(msg.sender, address(this));
        require(currentAllowance >= burnAmount, "ArenaRanking: Insufficient token allowance");

        token.burnFrom(msg.sender, burnAmount);

        rechargeCount[msg.sender]++;
        record.remainingAttempts += newAttempts;

        emit ChallengeRecharged(msg.sender, newAttempts, record.remainingAttempts);
    }

    function setMaxRechargeAttempts(uint256 _limit) external onlyOwner {
        require(_limit >= 1 && _limit <= MAX_RECHARGE_ATTEMPTS, "ArenaRanking: Invalid limit");
        maxRechargeAttempts = _limit;
        emit RechargeLimitUpdated(_limit);
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
            rewardCalculated: false,
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
        
        _calculateSeasonRewardsInternal(seasonId);
        
        emit SeasonSettled(seasonId, block.timestamp);
    }

    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        SeasonInfo storage season = seasons[seasonId];
        if (season.rewardCalculated) return;
        
        uint256 totalPlayers = seasonRankings[seasonId].length;
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = seasonRankings[seasonId][i];
            uint256 rank = i + 1;
            uint256 reward = _calculateRankReward(rank, season.rewardPool);
            playerSeasonRewards[seasonId][player] = reward;
            totalDistributed += reward;
        }
        
        season.rewardCalculated = true;
        emit SeasonRewardsCalculated(seasonId, season.rewardPool, totalDistributed);
    }
    
    function claimReward(uint256 seasonNumber) external nonReentrant {
        require(seasons[seasonNumber].isSettled, "ArenaRanking: Season not settled");
        require(!seasonRewardsClaimed[seasonNumber][msg.sender], "ArenaRanking: Already claimed");

        PlayerRecord storage record = players[msg.sender];
        require(record.seasonId == seasonNumber, "ArenaRanking: No record in this season");

        require(playerRankIndex[seasonNumber][msg.sender] > 0 || 
                seasonRankings[seasonNumber].length > 0 && seasonRankings[seasonNumber][0] == msg.sender,
                "ArenaRanking: Player not found in rankings");

        // 使用赛季结算时预计算的奖励值，避免因 rewardPool 变化导致奖励错误
        uint256 reward = playerSeasonRewards[seasonNumber][msg.sender];
        require(seasons[seasonNumber].rewardCalculated, "ArenaRanking: Season rewards not calculated");
        require(reward > 0, "ArenaRanking: No reward to claim");

        seasonRewardsClaimed[seasonNumber][msg.sender] = true;

        // 使用预计算的奖励池总量进行安全检查
        uint256 totalSeasonReward = seasons[seasonNumber].rewardPool;
        require(address(this).balance >= totalSeasonReward, "ArenaRanking: Insufficient contract balance for season rewards");

        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "ArenaRanking: BNB transfer failed");
        
        emit RewardClaimed(msg.sender, reward, seasonNumber);
    }

    function claimSeasonReward() external {
        claimReward(currentSeasonId);
    }

    function getPendingRewardsBySeason(uint256 seasonNumber) external view returns (uint256) {
        if (!seasons[seasonNumber].isSettled) return 0;
        
        PlayerRecord storage record = players[msg.sender];
        if (record.seasonId != seasonNumber) return 0;
        
        uint256 rank = playerRankIndex[seasonNumber][msg.sender] + 1;
        
        return _calculateRankReward(rank, seasons[seasonNumber].rewardPool);
    }

    function getPendingRewardsByPlayer(address player) external view returns (uint256) {
        PlayerRecord storage record = players[player];
        if (!seasons[record.seasonId].isSettled) return 0;
        
        uint256 rank = playerRankIndex[record.seasonId][player] + 1;
        
        return _calculateRankReward(rank, seasons[record.seasonId].rewardPool);
    }

    function getPlayerRank(address player) external view returns (uint256) {
        return playerRankIndex[currentSeasonId][player] + 1;
    }

    function _calculateRankReward(uint256 rank, uint256 pool) internal pure returns (uint256) {
        uint256 basisPoints = 10000; // 10000个基点 = 100%
        if (rank == 1) return pool * 2000 / basisPoints;    // 第1名20%
        if (rank == 2) return pool * 1500 / basisPoints;    // 第2名15%
        if (rank == 3) return pool * 1000 / basisPoints;    // 第3名10%
        if (rank <= 10) return pool * 300 / basisPoints;    // 4-10名各3% (7人×3%=21%)
        if (rank <= 50) return pool * 85 / basisPoints;     // 11-50名各0.85% (40人×0.85%=34%)
        return 0;
    }

    function getSeasonInfo(uint256 seasonId) external view returns (uint256 startTime, uint256 endTime, bool isActive, bool isSettled, uint256 totalPlayers) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        SeasonInfo memory s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }

    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        require(player != address(0), "ArenaRanking: Invalid player address");
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
        return getPendingRewardsByPlayer(player);
    }

    function isSeasonRewardClaimed(address player) external view returns (bool) {
        return seasonRewardsClaimed[currentSeasonId][player];
    }

    function currentSeason() external view returns (uint256, uint256, uint256, bool) {
        SeasonInfo storage season = seasons[currentSeasonId];
        return (currentSeasonId, season.startTime, season.endTime, season.isActive);
    }

    function calculateRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaRanking: Rank must be > 0");
        return _calculateRankReward(rank, seasons[currentSeasonId].rewardPool);
    }

    function getRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaRanking: Rank must be > 0");
        return _calculateRankReward(rank, seasons[currentSeasonId].rewardPool);
    }

    function calculateSeasonRewards(uint256 seasonNumber) external onlyAuthorized {
        require(seasons[seasonNumber].isSettled, "ArenaRanking: Season not settled");
        require(!seasons[seasonNumber].rewardCalculated, "ArenaRanking: Already calculated");
        
        SeasonInfo storage season = seasons[seasonNumber];
        address[] storage rankings = seasonRankings[seasonNumber];
        
        uint256 totalReward = season.rewardPool;
        require(totalReward > 0, "ArenaRanking: No reward in pool");
        
        uint256 distributed = 0;
        uint256 maxRank = rankings.length;
        
        for (uint256 i = 0; i < maxRank; i++) {
            address player = rankings[i];
            uint256 rank = i + 1;
            uint256 rankReward = _calculateRankReward(rank, totalReward);
            
            playerSeasonRewards[seasonNumber][player] = rankReward;
            distributed += rankReward;
        }
        
        season.rewardCalculated = true;
        emit SeasonRewardsCalculated(seasonNumber, totalReward, distributed);
    }

    function setSeasonDuration(uint256 duration) external onlyOwner {
        require(duration >= 1 days, "ArenaRanking: Duration too short");
        seasonDuration = duration;
    }

    function addRewardToPool() external payable onlyAuthorized {
        require(msg.value > 0, "ArenaRanking: No BNB sent");
        seasons[currentSeasonId].rewardPool += msg.value;
    }
    
    // 提取 BNB（仅用于紧急情况）
    function emergencyWithdrawBNB() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "ArenaRanking: No BNB to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ArenaRanking: BNB transfer failed");
    }

    // 接收 BNB
    receive() external payable {}
    fallback() external payable {}

    /**
     * @dev 验证用户是否拥有战队中的所有NFT
     * @param owner 用户地址
     * @param team 战队NFT ID数组
     */
    function _validateTeamOwnership(address owner, uint256[6] calldata team) internal view {
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nftStakedOwner[tokenId] == owner, "ArenaRanking: NFT not staked or not owner");
        }
    }

    function _validateTeamStaked(address owner, uint256[6] calldata team) internal view {
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nftStakedOwner[tokenId] == owner, "ArenaRanking: NFT not staked or not owner");
        }
    }

    /**
     * @dev 获取玩家的完整赛季统计
     * @param player 玩家地址
     * @param seasonNumber 赛季编号
     * @return score 积分
     * @return wins 胜场
     * @return losses 负场
     * @return rank 排名
     * @return pendingReward 待领取奖励
     * @return claimed 是否已领取
     */
    function getPlayerSeasonStats(address player, uint256 seasonNumber) external view returns (
        uint256 score,
        uint256 wins,
        uint256 losses,
        uint256 rank,
        uint256 pendingReward,
        bool claimed
    ) {
        require(seasonNumber <= currentSeasonId, "ArenaRanking: Invalid season");

        PlayerRecord storage record = players[player];
        score = record.score;
        wins = record.wins;
        losses = record.losses;

        if (seasonNumber == record.seasonId) {
            rank = playerRankIndex[seasonNumber][player] + 1;
            pendingReward = playerSeasonRewards[seasonNumber][player];
            claimed = seasonRewardsClaimed[seasonNumber][player];
        } else {
            rank = 0;
            pendingReward = 0;
            claimed = true;
        }
    }

    /**
     * @dev 获取赛季排名范围的用户
     * @param seasonId 赛季编号
     * @param startRank 起始排名
     * @param endRank 结束排名
     * @return players 玩家地址数组
     * @return scores 积分数组
     */
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddresses,
        uint256[] memory scores
    ) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        require(startRank > 0 && startRank <= endRank, "ArenaRanking: Invalid rank range");

        uint256 len = seasonRankings[seasonId].length;
        if (endRank > len) endRank = len;

        uint256 count = endRank - startRank + 1;
        playerAddresses = new address[](count);
        scores = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = startRank - 1; i < endRank; i++) {
            address player = seasonRankings[seasonId][i];
            playerAddresses[index] = player;
            scores[index] = players[player].score;
            index++;
        }
    }

    /**
     * @dev 获取当前赛季信息
     * @return seasonId 赛季编号
     * @return startTime 开始时间
     * @return endTime 结束时间
     * @return isActive 是否进行中
     * @return totalPlayers 参与玩家数
     * @return rewardPool 奖励池
     */
    function getCurrentSeasonInfo() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        uint256 totalPlayers,
        uint256 rewardPool
    ) {
        SeasonInfo storage season = seasons[currentSeasonId];
        return (
            currentSeasonId,
            season.startTime,
            season.endTime,
            season.isActive,
            season.totalPlayers,
            season.rewardPool
        );
    }

    /**
     * @dev 获取玩家挑战状态
     * @param player 玩家地址
     * @return remainingAttempts 剩余挑战次数
     * @return nextResetTime 下次重置时间
     * @return lastBattleTime 上次战斗时间
     * @return cooldownRemaining 冷却剩余时间
     */
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 nextResetTime,
        uint256 playerLastBattleTime,
        uint256 cooldownRemaining
    ) {
        PlayerRecord storage record = players[player];

        if (block.timestamp >= record.lastResetTime + 24 hours) {
            remainingAttempts = DAILY_ATTEMPTS;
            nextResetTime = record.lastResetTime + 24 hours;
        } else {
            remainingAttempts = record.remainingAttempts;
            nextResetTime = record.lastResetTime + 24 hours;
        }

        playerLastBattleTime = lastBattleTime[player];
        if (playerLastBattleTime == 0) {
            cooldownRemaining = 0;
        } else if (block.timestamp >= playerLastBattleTime + BATTLE_COOLDOWN) {
            cooldownRemaining = 0;
        } else {
            cooldownRemaining = playerLastBattleTime + BATTLE_COOLDOWN - block.timestamp;
        }
    }
}

interface IBattle {
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam,
        address challengedAddress
    ) external returns (bool, uint256);
}

interface INFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burnFrom(address account, uint256 amount) external;
    function allowance(address owner, address spender) external view returns (uint256);
}