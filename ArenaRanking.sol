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
        uint256 draws;
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
        uint256 rewardPool; // 通用奖励池，根据rewardType使用
        uint256 tokenRewardPool; // ERC20代币奖励池（备用）
        uint256 pendingRewards;
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
    
    /**
     * @dev NFT战斗锁定状态
     * tokenId => battleId (0表示未锁定)
     */
    mapping(uint256 => uint256) public nftBattleLocked;

    uint256 public currentSeasonId;
    uint256 public seasonDuration = 1 days;
    uint256 public rewardRate = 100; // 1% (100/10000)
    uint256 public maxRewardRate = 200; // 最大奖励率 2%
    uint256 public rateStep = 10; // 每次调整步长 0.1%
    
    address public authorizer;
    address public battleContract;
    address public nftContract;
    address public tokenContract;
    
    /**
     * @dev 奖励类型：0 = BNB, 1 = ERC20代币
     */
    uint8 public rewardType = 1;
    
    event RewardTypeUpdated(uint8 oldType, uint8 newType);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    
    uint256 public constant DAILY_ATTEMPTS = 3;
    uint256 public constant MAX_RECHARGE_ATTEMPTS = 50;
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant RECHARGE_COST = 888;
    uint256 public constant RECHARGE_ATTEMPTS = 3;
    uint256 public constant MAX_LEADERBOARD_SIZE = type(uint256).max;
    uint256 public constant MAX_SEASONS_TO_KEEP = 20;
    uint256 public constant PRECISION = 10000;
    
    /**
     * @dev 每日流入奖励追踪（用于动态调整奖励率）
     */
    uint256 public todayIncomingReward;
    uint256 public todayRewardAmount;
    uint256 public todayStart;
    
    /**
     * @dev Mock玩家地址的特殊前缀和后缀
     * 格式: 0x000000000000000000000000000000000000DEAD
     */
    address public constant MOCK_PLAYER_PREFIX = address(0x0000000000000000000000000000000000000000);
    address public constant MOCK_PLAYER_SUFFIX = address(0x000000000000000000000000000000000000DEAD);
    uint256 public maxRechargeAttempts = type(uint256).max;
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
    }

    function _checkAndResetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        if (block.timestamp >= record.lastResetTime + 24 hours) {
            _resetAttempts(player);
            rechargeCount[player] = 0;
        }
    }

    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external whenNotPaused returns (bool success) {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        require(battleContract != address(0), "ArenaRanking: Battle contract not set");
        require(mockIndex < 10, "ArenaRanking: Invalid mock player index");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaRanking: Battle cooldown");

        PlayerRecord storage record = players[msg.sender];
        _checkAndResetAttempts(msg.sender);
        require(record.remainingAttempts > 0, "ArenaRanking: No attempts left");
        record.remainingAttempts--;
        lastBattleTime[msg.sender] = block.timestamp;

        _validateTeamStaked(msg.sender, playerTeam);

        uint256 battleId = block.timestamp;
        _lockNFTsForBattle(playerTeam, battleId);

        try IBattle(battleContract).challenge(
            playerTeam[0],
            uint256(mockIndex + 1) * 1000,
            playerTeam,
            _generateMockTeam(mockIndex),
            address(0)
        ) returns (bool success_, uint256 winner) {
            if (winner == 1) {
                _updateScore(msg.sender, true);
            } else if (winner == 0) {
                _updateScoreOnDraw(msg.sender);
            }
            emit ChallengeResult(msg.sender, address(0), winner == 1, currentSeasonId);
            success = success_;
        } finally {
            _unlockNFTsFromBattle(playerTeam);
        }

        return success;
    }

    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external whenNotPaused returns (bool success) {
        require(nftContract != address(0), "ArenaRanking: NFT contract not set");
        require(battleContract != address(0), "ArenaRanking: Battle contract not set");
        require(challengedPlayer != address(0), "ArenaRanking: Invalid challenged address");
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
        challengedRecord.remainingAttempts--;
        lastBattleTime[msg.sender] = block.timestamp;
        lastBattleTime[challengedPlayer] = block.timestamp;

        _validateTeamStaked(msg.sender, playerTeam);

        uint256[6] memory challengedTeam = challengedRecord.battleTeam;
        require(challengedRecord.hasTeam && challengedTeam.length == TEAM_SIZE, "ArenaRanking: Target has no team");
        
        _validateTeamStaked(challengedPlayer, challengedTeam);

        uint256 battleId = block.timestamp;
        _lockNFTsForBattle(playerTeam, battleId);
        _lockNFTsForBattle(challengedTeam, battleId);

        try IBattle(battleContract).challenge(
            playerTeam[0],
            challengedTeam[0],
            playerTeam,
            challengedTeam,
            challengedPlayer
        ) returns (bool success_, uint256 winner) {
            if (winner == 1) {
                _updateScore(msg.sender, true);
                _updateScore(challengedPlayer, false);
            } else if (winner == 2) {
                _updateScore(msg.sender, false);
                _updateScore(challengedPlayer, true);
            } else {
                _updateScoreOnDraw(msg.sender);
                _updateScoreOnDraw(challengedPlayer);
            }
            emit ChallengeResult(msg.sender, challengedPlayer, winner == 1, currentSeasonId);
            success = success_;
        } finally {
            _unlockNFTsFromBattle(playerTeam);
            _unlockNFTsFromBattle(challengedTeam);
        }

        return success;
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
            record.draws = 0;
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

    function _updateScoreOnDraw(address player) internal {
        SeasonInfo storage currentSeason = seasons[currentSeasonId];
        require(currentSeason.isActive, "ArenaRanking: Season not active");

        PlayerRecord storage record = players[player];
        
        if (record.seasonId != currentSeasonId) {
            record.seasonId = currentSeasonId;
            record.score = 1000;
            record.wins = 0;
            record.losses = 0;
            record.draws = 0;
            record.lastBattleTime = block.timestamp;
            record.lastResetTime = block.timestamp;
            record.remainingAttempts = DAILY_ATTEMPTS;
            seasonRankings[currentSeasonId].push(player);
            playerRankIndex[currentSeasonId][player] = seasonRankings[currentSeasonId].length - 1;
            currentSeason.totalPlayers++;
        }

        record.draws++;
        record.lastBattleTime = block.timestamp;
        
        emit ScoreUpdated(player, record.score, currentSeasonId);
    }

    function _updateRanking(address player, uint256 newScore) internal {
        uint256 seasonId = currentSeasonId;
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
    }

    function _removeFromRanking(address player) internal {
        uint256 seasonId = currentSeasonId;
        uint256 currentIndex = playerRankIndex[seasonId][player];
        
        if (currentIndex == 0) {
            return;
        }
        
        address[] storage rankings = seasonRankings[seasonId];
        uint256 lastIndex = rankings.length - 1;
        
        if (currentIndex <= lastIndex) {
            address lastPlayer = rankings[lastIndex];
            rankings[currentIndex] = lastPlayer;
            playerRankIndex[seasonId][lastPlayer] = currentIndex;
            rankings.pop();
            playerRankIndex[seasonId][player] = 0;
        }
    }

    function _clearSeasonData(address player) internal {
        PlayerRecord storage record = players[player];
        
        _removeFromRanking(player);
        
        record.score = 0;
        record.wins = 0;
        record.losses = 0;
        record.seasonId = currentSeasonId;
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
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRanking: Invalid tokenIds count");
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
        
        bool shouldClearSeasonData = false;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(nftStakedOwner[tokenId] != address(0), "ArenaRanking: NFT not staked");
            require(nftStakedOwner[tokenId] == msg.sender, "ArenaRanking: Not owner of staked NFT");
            require(nftBattleLocked[tokenId] == 0, "ArenaRanking: NFT locked in battle");
            
            // 检查该 NFT 是否在战斗队伍中
            bool inTeam = false;
            for (uint256 j = 0; j < record.battleTeam.length; j++) {
                if (record.battleTeam[j] == tokenId) {
                    inTeam = true;
                    break;
                }
            }
            
            if (inTeam) {
                shouldClearSeasonData = true;
            }
            
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
        
        if (shouldClearSeasonData || userStakedNFTs[msg.sender].length == 0) {
            _clearSeasonData(msg.sender);
            delete record.battleTeam;
            record.hasTeam = false;
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
        
        _clearSeasonData(msg.sender);
        
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
    
    /**
     * @dev 设置奖励类型（仅合约所有者）
     * @param _rewardType 0 = BNB, 1 = ERC20代币
     */
    function setRewardType(uint8 _rewardType) external onlyOwner {
        require(_rewardType == 0 || _rewardType == 1, "ArenaRanking: Invalid reward type");
        uint8 oldType = rewardType;
        rewardType = _rewardType;
        emit RewardTypeUpdated(oldType, _rewardType);
    }

    function startNewSeason() external onlyAuthorized {
        _tryStartNewSeason();
    }

    function _tryStartNewSeason() internal {
        require(block.timestamp >= seasons[currentSeasonId].endTime, "ArenaRanking: Current season not ended");
        _settleCurrentSeason();
        _cleanupOldSeasons();
        _startNewSeason();
    }

    function checkAndStartNewSeason() external whenNotPaused {
        if (block.timestamp >= seasons[currentSeasonId].endTime) {
            _tryStartNewSeason();
        }
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
            rewardPool: 0,
            pendingRewards: 0
        });
        emit SeasonStarted(currentSeasonId, block.timestamp);
    }

    function _settleCurrentSeason() internal {
        SeasonInfo storage season = seasons[currentSeasonId];
        season.isActive = false;
        season.isSettled = true;
        emit SeasonSettled(currentSeasonId, block.timestamp);
    }

    function _cleanupOldSeasons() internal {
        uint256 seasonsToRemove = currentSeasonId > MAX_SEASONS_TO_KEEP ? 
            currentSeasonId - MAX_SEASONS_TO_KEEP : 0;
        
        for (uint256 i = 1; i <= seasonsToRemove; i++) {
            delete seasonRankings[i];
            delete seasons[i];
        }
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

    function _checkNewDay() internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;

        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingReward = 0;
            todayRewardAmount = 0;
            _adjustRewardRate();
        }
    }

    function _adjustRewardRate() internal {
        if (todayRewardAmount > 0 && todayIncomingReward > todayRewardAmount) {
            uint256 multiple = todayIncomingReward / todayRewardAmount;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;
            uint256 steps = multiple - 1;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);

            if (newRate != rewardRate) {
                uint256 oldRate = rewardRate;
                rewardRate = newRate;
                emit RewardRateUpdated(oldRate, rewardRate);
            }
        }
    }

    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        SeasonInfo storage season = seasons[seasonId];
        if (season.rewardCalculated) return;
        
        _checkNewDay();
        
        uint256 availableBalance = 0;
        if (rewardType == 0) {
            uint256 contractBalance = address(this).balance;
            uint256 totalPendingRewards = _getTotalPendingRewards();
            availableBalance = contractBalance > totalPendingRewards ? contractBalance - totalPendingRewards : 0;
        } else {
            require(tokenContract != address(0), "ArenaRanking: Token contract not set");
            IERC20 token = IERC20(tokenContract);
            uint256 contractBalance = token.balanceOf(address(this));
            uint256 totalPendingRewards = _getTotalPendingRewards();
            availableBalance = contractBalance > totalPendingRewards ? contractBalance - totalPendingRewards : 0;
        }
        
        todayRewardAmount = availableBalance * rewardRate / PRECISION;
        season.rewardPool = todayRewardAmount;
        
        uint256 totalPlayers = seasonRankings[seasonId].length;
        uint256 totalRealPlayers = _countRealPlayers(seasonId);
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = seasonRankings[seasonId][i];
            
            if (_isMockPlayer(player)) {
                continue;
            }
            
            uint256 rank = _getRealPlayerRank(seasonId, i);
            uint256 reward = _calculateRankReward(rank, season.rewardPool, totalRealPlayers);
            playerSeasonRewards[seasonId][player] = reward;
            totalDistributed += reward;
        }
        
        season.pendingRewards += totalDistributed;
        season.rewardCalculated = true;
        emit SeasonRewardsCalculated(seasonId, season.rewardPool, totalDistributed);
    }
    
    function _countRealPlayers(uint256 seasonId) internal view returns (uint256) {
        uint256 total = 0;
        uint256 totalPlayers = seasonRankings[seasonId].length;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = seasonRankings[seasonId][i];
            if (!_isMockPlayer(player)) {
                total++;
            }
        }
        
        return total;
    }
    
    function _getRealPlayerRank(uint256 seasonId, uint256 index) internal view returns (uint256) {
        uint256 rank = 0;
        
        for (uint256 i = 0; i <= index; i++) {
            address player = seasonRankings[seasonId][i];
            if (!_isMockPlayer(player)) {
                rank++;
            }
        }
        
        return rank;
    }
    
    /**
     * @dev 检查是否是Mock玩家（使用特殊地址范围
     * Mock玩家地址格式为: 0x000000000000000000000000000000000000DEAD + index
     */
    function _isMockPlayer(address player) internal pure returns (bool) {
        // Mock玩家地址必须在特殊范围内：
        // 前缀: 0x000000000000000000000000000000000000DEAD 
        // 到: 0x000000000000000000000000000000000000DEAD + 999
        return uint256(uint160(player)) >= 0x000000000000000000000000000000000000DEAD && 
               uint256(uint160(player)) <= 0x000000000000000000000000000000000000DEAD + 999;
    }
    
    /**
     * @dev 获取所有赛季的待支付奖励总额
     */
    function _getTotalPendingRewards() internal view returns (uint256) {
        uint256 totalPending = 0;
        for (uint256 i = 1; i <= currentSeasonId; i++) {
            totalPending += seasons[i].pendingRewards;
        }
        return totalPending;
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
        
        // 更新待领取额度
        seasons[seasonNumber].pendingRewards -= reward;

        if (rewardType == 0) {
            // BNB奖励
            require(address(this).balance >= reward, "ArenaRanking: Insufficient BNB balance");
            (bool success, ) = payable(msg.sender).call{value: reward}("");
            require(success, "ArenaRanking: BNB transfer failed");
        } else {
            // ERC20代币奖励
            require(tokenContract != address(0), "ArenaRanking: Token contract not set");
            IERC20 token = IERC20(tokenContract);
            require(token.balanceOf(address(this)) >= reward, "ArenaRanking: Insufficient token balance");
            token.safeTransfer(msg.sender, reward);
        }
        
        emit RewardClaimed(msg.sender, reward, seasonNumber);
    }

    function claimSeasonReward() external {
        claimReward(currentSeasonId);
    }

    function getPendingRewardsBySeason(uint256 seasonNumber) external view returns (uint256) {
        if (!seasons[seasonNumber].isSettled) return 0;
        
        PlayerRecord storage record = players[msg.sender];
        if (record.seasonId != seasonNumber) return 0;
        
        uint256 totalRealPlayers = _countRealPlayers(seasonNumber);
        uint256 rank = _getRealPlayerRank(seasonNumber, playerRankIndex[seasonNumber][msg.sender]);
        
        return _calculateRankReward(rank, seasons[seasonNumber].rewardPool, totalRealPlayers);
    }

    function getPendingRewardsByPlayer(address player) external view returns (uint256) {
        PlayerRecord storage record = players[player];
        if (!seasons[record.seasonId].isSettled) return 0;
        
        uint256 seasonId = record.seasonId;
        uint256 totalRealPlayers = _countRealPlayers(seasonId);
        uint256 rank = _getRealPlayerRank(seasonId, playerRankIndex[seasonId][player]);
        
        return _calculateRankReward(rank, seasons[seasonId].rewardPool, totalRealPlayers);
    }

    function getPlayerRank(address player) external view returns (uint256) {
        return playerRankIndex[currentSeasonId][player] + 1;
    }

    function _calculateRankReward(uint256 rank, uint256 pool, uint256 totalRealPlayers) internal pure returns (uint256) {
        if (totalRealPlayers == 0 || pool == 0 || rank > totalRealPlayers) return 0;
        
        uint256 basisPoints = 10000;
        
        if (totalRealPlayers <= 3) {
            return _calculateRewardForSmallGroup(rank, pool, totalRealPlayers);
        }
        
        if (totalRealPlayers <= 10) {
            return _calculateRewardForMediumGroup(rank, pool, totalRealPlayers);
        }
        
        return _calculateRewardForLargeGroup(rank, pool, totalRealPlayers);
    }
    
    function _calculateRewardForSmallGroup(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        uint256 basisPoints = 10000;
        
        if (totalPlayers == 1) {
            return pool;
        } else if (totalPlayers == 2) {
            if (rank == 1) return pool * 6000 / basisPoints;
            return pool * 4000 / basisPoints;
        } else {
            if (rank == 1) return pool * 4500 / basisPoints;
            if (rank == 2) return pool * 3000 / basisPoints;
            return pool * 2500 / basisPoints;
        }
    }
    
    function _calculateRewardForMediumGroup(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        uint256 basisPoints = 10000;
        
        uint256[] memory ratios = [2000, 1500, 1200, 1000, 800, 700, 600, 500, 400, 300];
        
        uint256 sum = 0;
        for (uint256 i = 0; i < totalPlayers; i++) {
            sum += ratios[i];
        }
        
        return pool * ratios[rank - 1] / sum;
    }
    
    function _calculateRewardForLargeGroup(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        uint256 basisPoints = 10000;
        
        uint256 guaranteedPool = pool * 1000 / basisPoints;
        uint256 tierPool = pool * 9000 / basisPoints;
        
        uint256 guaranteedReward = guaranteedPool / totalPlayers;
        
        uint256 tierReward = _calculateTierBasedReward(rank, tierPool, totalPlayers);
        
        return guaranteedReward + tierReward;
    }
    
    function _calculateTierBasedReward(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        if (rank > totalPlayers || pool == 0) return 0;
        
        uint256 tier1Size = totalPlayers > 100 ? 100 : totalPlayers;
        uint256 tier2Size = totalPlayers > 500 ? 400 : (totalPlayers > 100 ? totalPlayers - 100 : 0);
        uint256 tier3Size = totalPlayers > 1000 ? 500 : (totalPlayers > 500 ? totalPlayers - 500 : 0);
        uint256 tier4Size = totalPlayers > 1000 ? totalPlayers - 1000 : 0;
        
        uint256 tier1Pool = pool * 5000 / 9000;
        uint256 tier2Pool = pool * 2500 / 9000;
        uint256 tier3Pool = pool * 1000 / 9000;
        uint256 tier4Pool = pool * 500 / 9000;
        
        if (rank <= tier1Size) {
            return _calculateTier1Reward(rank, tier1Pool, tier1Size);
        } else if (rank <= tier1Size + tier2Size) {
            return _calculateTier2Reward(rank - tier1Size, tier2Pool, tier2Size);
        } else if (rank <= tier1Size + tier2Size + tier3Size) {
            return _calculateTier3Reward(rank - tier1Size - tier2Size, tier3Pool, tier3Size);
        } else {
            return _calculateTier4Reward(rank - tier1Size - tier2Size - tier3Size, tier4Pool, tier4Size);
        }
    }
    
    function _calculateTier1Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (rank == 1) return pool * 2500 / 5000;
        if (rank == 2) return pool * 1500 / 5000;
        if (rank == 3) return pool * 600 / 5000;
        
        uint256 remaining = pool * 400 / 5000;
        uint256 remainingPlayers = total > 3 ? total - 3 : 0;
        
        if (remainingPlayers == 0) return 0;
        
        uint256 baseWeight = 100;
        uint256 decay = 1;
        uint256 sumWeight = 0;
        
        for (uint256 i = 0; i < remainingPlayers; i++) {
            uint256 weight = baseWeight > i * decay ? baseWeight - i * decay : 10;
            sumWeight += weight;
        }
        
        uint256 currentWeight = baseWeight > (rank - 4) * decay ? baseWeight - (rank - 4) * decay : 10;
        
        return remaining * currentWeight / sumWeight;
    }
    
    function _calculateTier2Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;
        
        uint256 baseWeight = 50;
        uint256 decay = 0.5;
        uint256 sumWeight = 0;
        
        for (uint256 i = 0; i < total; i++) {
            uint256 weight = baseWeight > i * decay ? baseWeight - i * decay : 10;
            sumWeight += weight;
        }
        
        uint256 currentWeight = baseWeight > (rank - 1) * decay ? baseWeight - (rank - 1) * decay : 10;
        
        return pool * currentWeight / sumWeight;
    }
    
    function _calculateTier3Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;
        
        uint256 weight = total - rank + 1;
        uint256 sumWeight = total * (total + 1) / 2;
        
        return pool * weight / sumWeight;
    }
    
    function _calculateTier4Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;
        
        return pool / total;
    }

    function getSeasonInfo(uint256 seasonId) external view returns (uint256 startTime, uint256 endTime, bool isActive, bool isSettled, uint256 totalPlayers) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        SeasonInfo memory s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }
    
    /**
     * @dev 获取赛季历史记录
     * @param startSeasonId 起始赛季ID
     * @param count 获取数量
     * @return 赛季信息数组
     */
    function getSeasonHistory(uint256 startSeasonId, uint256 count) external view returns (SeasonInfo[] memory) {
        require(startSeasonId > 0, "ArenaRanking: Invalid start season");
        require(startSeasonId <= currentSeasonId, "ArenaRanking: Start season exceeds current");
        
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
     * @dev 获取最近的赛季历史记录
     * @param count 获取数量
     * @return 赛季信息数组
     */
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        if (currentSeasonId == 0) {
            return new SeasonInfo[](0);
        }
        
        uint256 startSeasonId = currentSeasonId >= count ? currentSeasonId - count + 1 : 1;
        return getSeasonHistory(startSeasonId, count);
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

    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (
        LeaderboardEntry[] memory entries,
        uint256 totalPages,
        uint256 totalPlayers
    ) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        require(page > 0, "ArenaRanking: Page must be > 0");
        require(pageSize > 0 && pageSize <= 100, "ArenaRanking: Invalid page size");
        
        uint256 len = seasonRankings[seasonId].length;
        totalPlayers = len;
        
        if (len == 0) {
            entries = new LeaderboardEntry[](0);
            totalPages = 0;
            return (entries, totalPages, totalPlayers);
        }
        
        totalPages = (len + pageSize - 1) / pageSize;
        
        uint256 startIndex = (page - 1) * pageSize;
        if (startIndex >= len) {
            entries = new LeaderboardEntry[](0);
            return (entries, totalPages, totalPlayers);
        }
        
        uint256 endIndex = startIndex + pageSize;
        if (endIndex > len) endIndex = len;
        
        uint256 count = endIndex - startIndex;
        entries = new LeaderboardEntry[](count);
        
        uint256 entryIndex = 0;
        for (uint256 i = startIndex; i < endIndex; i++) {
            address player = seasonRankings[seasonId][i];
            PlayerRecord memory record = players[player];
            entries[entryIndex] = LeaderboardEntry({
                playerAddress: player,
                points: record.score,
                wins: record.wins,
                losses: record.losses,
                isMock: false
            });
            entryIndex++;
        }
        
        return (entries, totalPages, totalPlayers);
    }

    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        require(pageSize > 0, "ArenaRanking: Page size must be > 0");
        
        uint256 len = seasonRankings[seasonId].length;
        if (len == 0) return 0;
        
        return (len + pageSize - 1) / pageSize;
    }

    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        require(seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        return seasonRankings[seasonId].length;
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
        uint256 totalRealPlayers = _countRealPlayers(currentSeasonId);
        return _calculateRankReward(rank, seasons[currentSeasonId].rewardPool, totalRealPlayers);
    }

    function getRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaRanking: Rank must be > 0");
        uint256 totalRealPlayers = _countRealPlayers(currentSeasonId);
        return _calculateRankReward(rank, seasons[currentSeasonId].rewardPool, totalRealPlayers);
    }

    function calculateSeasonRewards(uint256 seasonNumber) external onlyAuthorized {
        require(seasons[seasonNumber].isSettled, "ArenaRanking: Season not settled");
        require(!seasons[seasonNumber].rewardCalculated, "ArenaRanking: Already calculated");
        
        _checkNewDay();
        
        SeasonInfo storage season = seasons[seasonNumber];
        address[] storage rankings = seasonRankings[seasonNumber];
        
        uint256 contractBalance = address(this).balance;
        uint256 availableBalance = contractBalance - season.pendingRewards;
        todayRewardAmount = availableBalance * rewardRate / PRECISION;
        season.rewardPool = todayRewardAmount;
        
        uint256 totalReward = season.rewardPool;
        require(totalReward > 0, "ArenaRanking: No reward in pool");
        
        uint256 totalRealPlayers = _countRealPlayers(seasonNumber);
        uint256 distributed = 0;
        uint256 maxRank = rankings.length;
        
        for (uint256 i = 0; i < maxRank; i++) {
            address player = rankings[i];
            
            if (_isMockPlayer(player)) {
                continue;
            }
            
            uint256 rank = _getRealPlayerRank(seasonNumber, i);
            uint256 rankReward = _calculateRankReward(rank, totalReward, totalRealPlayers);
            
            playerSeasonRewards[seasonNumber][player] = rankReward;
            distributed += rankReward;
        }
        
        season.pendingRewards += distributed;
        season.rewardCalculated = true;
        emit SeasonRewardsCalculated(seasonNumber, totalReward, distributed);
    }

    function setSeasonDuration(uint256 duration) external onlyOwner {
        require(duration >= 1 days, "ArenaRanking: Duration too short");
        seasonDuration = duration;
    }

    function addRewardToPool() external payable onlyAuthorized {
        require(msg.value > 0, "ArenaRanking: No BNB sent");
        _checkNewDay();
        todayIncomingReward += msg.value;
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
    receive() external payable {
        _checkNewDay();
        todayIncomingReward += msg.value;
    }
    fallback() external payable {
        _checkNewDay();
        todayIncomingReward += msg.value;
    }

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
            require(nftBattleLocked[tokenId] == 0, "ArenaRanking: NFT locked in battle");
        }
    }
    
    /**
     * @dev 锁定NFT用于战斗
     */
    function _lockNFTsForBattle(uint256[6] calldata team, uint256 battleId) internal {
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            if (tokenId > 0) {
                nftBattleLocked[tokenId] = battleId;
            }
        }
    }
    
    /**
     * @dev 解锁战斗中的NFT
     */
    function _unlockNFTsFromBattle(uint256[6] calldata team) internal {
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            if (tokenId > 0) {
                nftBattleLocked[tokenId] = 0;
            }
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