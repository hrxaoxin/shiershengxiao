// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";


/**
 * @title ArenaRanking
 * @dev 竞技场排名与赛季管理合约（优化版：支持自动化结算）
 *
 * 核心功能：
 * 1. 赛季管理：创建、启动、结算赛季，控制赛季时长和奖励分配
 * 2. 战斗系统：玩家与模拟玩家对战（PvE）、玩家间对战（PvP）
 * 3. 积分排名：根据战斗结果计算积分，维护赛季排行榜
 * 4. NFT质押：玩家质押NFT用于战斗，解除质押可回收
 * 5. 奖励分配：赛季结束后按排名分配代币或BNB奖励
 * 6. 每日挑战：限制每日挑战次数，支持消耗代币重置挑战次数
 *
 * 数据结构：
 * - PlayerRecord: 玩家战斗记录（积分、胜负、队伍等）
 * - SeasonInfo: 赛季信息（时间、状态、奖励池）
 * - LeaderboardEntry: 排行榜条目（地址、积分、胜负）
 * - MockPlayerInfo: 模拟玩家信息（用于PvE战斗）
 *
 * 战斗流程：
 * 1. 玩家质押NFT并设置战斗队伍（6个NFT）
 * 2. 选择挑战模拟玩家或真实玩家
 * 3. 调用Battle合约执行战斗逻辑
 * 4. 根据战斗结果更新积分和排名
 * 5. 赛季结束后结算并领取奖励
 *
 * 权限设计：
 * - onlyOwner: 合约所有者，可配置参数和升级合约
 * - onlyAuthorized: 所有者或授权器，可启动和结算赛季
 * - 公开函数: 玩家可执行的操作（挑战、质押、领取等）
 *
 * 安全机制：
 * - nonReentrant: 防止重入攻击（涉及代币转账的函数）
 * - whenNotPaused: 紧急暂停功能
 * - 冷却时间: 限制战斗频率，防止刷分
 * - 挑战次数限制: 每日挑战次数限制，防止刷分
 */
contract ArenaRanking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 玩家战斗记录结构体
     * 存储玩家在当前赛季的所有战斗相关数据
     * @param score 当前积分（决定排名）
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param draws 平局次数
     * @param lastBattleTime 上次战斗时间戳（用于冷却判断）
     * @param lastResetTime 上次重置挑战次数的时间
     * @param remainingAttempts 剩余挑战次数
     * @param battleTeam 战斗队伍（NFT ID数组，6个）
     * @param hasTeam 是否已设置战斗队伍
     * @param seasonId 当前赛季ID
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
     * @dev 模拟玩家信息结构体
     * 用于PvE战斗模式，存储模拟玩家的属性
     * @param team 模拟玩家的NFT队伍（6个ID）
     * @param score 模拟玩家积分（用于难度分级）
     * @param level NFT等级（影响战力）
     * @param growth NFT成长值（影响属性）
     * @param elementCounts 各属性NFT计数（用于多样化队伍）
     */
    struct MockPlayerInfo {
        uint256[6] team;
        uint256 score;
        uint256 level;
        uint256 growth;
        uint256[] elementCounts;
    }

    /**
     * @dev 赛季信息结构体
     * 存储赛季的完整信息，包括时间、状态和奖励配置
     * @param seasonId 赛季唯一ID
     * @param startTime 赛季开始时间戳
     * @param endTime 赛季结束时间戳
     * @param isActive 赛季是否进行中
     * @param isSettled 是否已结算（积分锁定）
     * @param rewardCalculated 是否已计算奖励分配
     * @param totalPlayers 参与赛季的玩家总数
     * @param rewardPool 通用奖励池（BNB或代币）
     * @param tokenRewardPool ERC20代币奖励池（备用）
     * @param pendingRewards 待领取奖励总额
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
     * @dev 排行榜条目结构体
     * 用于前端展示排行榜数据
     * @param playerAddress 玩家钱包地址
     * @param points 当前积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param isMock 是否为模拟玩家
     */
    struct LeaderboardEntry {
        address playerAddress;
        uint256 points;
        uint256 wins;
        uint256 losses;
        bool isMock;
    }

    /**
     * @dev 玩家记录映射（address => PlayerRecord）
     * 存储每个玩家在当前赛季的战斗数据
     */
    mapping(address => PlayerRecord) public players;
    /**
     * @dev 赛季信息映射（seasonId => SeasonInfo）
     * 存储所有历史赛季的信息
     */
    mapping(uint256 => SeasonInfo) public seasons;
    
    /**
     * @dev 赛季排名映射（seasonId => address[]）
     * 按积分从高到低存储玩家地址数组
     */
    mapping(uint256 => address[]) public seasonRankings;
    /**
     * @dev 玩家排名索引映射（seasonId => address => rankIndex）
     * 存储玩家在赛季排行榜中的位置（索引从0开始）
     */
    mapping(uint256 => mapping(address => uint256)) public playerRankIndex;
    /**
     * @dev 玩家赛季奖励映射（seasonId => address => rewardAmount）
     * 存储赛季结算后每个玩家的奖励金额
     */
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    
    /**
     * @dev 赛季奖励是否已领取
     * seasonId => player => claimed
     */
    mapping(uint256 => mapping(address => bool)) public seasonRewardsClaimed;
    
    uint256 public currentSeasonId;
    uint256 public seasonDuration = 1 days;
    
    address public authorizer;
    address public battleContract;
    address public nftContract;
    address public tokenContract;
    address public arenaRewardContract;
    address public arenaLeaderboardContract;
    address public arenaPlayerContract;
    address public arenaBattleContract;
    
    /**
     * @dev 竞技场模式：0 = 积分模式, 1 = 挑战模式（默认）
     */
    uint8 public arenaMode = 1;
    
    /**
     * @dev 模式控制类型：
     * 0 = 固定模式（使用arenaMode）
     * 1 = 随机模式（每个赛季随机选择）
     * 2 = 轮换模式（积分模式和挑战模式交替）
     */
    uint8 public modeControlType = 0;
    
    /**
     * @dev 上一个赛季使用的模式（用于轮换模式）
     */
    uint8 public lastSeasonMode = 1;
    
    /**
     * @dev Mock玩家奖励接收地址
     */
    address public mockRewardRecipient;
    
    event RewardTypeUpdated(uint8 oldType, uint8 newType);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event ArenaModeUpdated(uint8 oldMode, uint8 newMode);
    event ModeControlTypeUpdated(uint8 oldType, uint8 newType);
    event MockRewardRecipientUpdated(address oldAddress, address newAddress);
    event MockRewardDistributed(address indexed recipient, uint256 amount, uint256 seasonId);
    
    uint256 public constant DAILY_ATTEMPTS = 3;
    uint256 public constant MAX_RECHARGE_ATTEMPTS = 50;
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant RECHARGE_COST = 888;
    uint256 public constant RECHARGE_ATTEMPTS = 3;
    uint256 public constant MAX_LEADERBOARD_SIZE = type(uint256).max;
    uint256 public constant MAX_SEASONS_TO_KEEP = 20;
    uint256 public constant PRECISION = 10000;
    uint256 public constant MAX_MOCK_RANKING = 100;
    
    /**
     * @dev Mock玩家地址的基础地址
     * Mock玩家地址格式为: MOCK_PLAYER_BASE + index (0-999)
     */
    address public constant MOCK_PLAYER_BASE = address(0x000000000000000000000000000000000000dEaD);
    /**
     * @dev Mock玩家最大数量
     */
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;
    uint256 public maxRechargeAttempts = type(uint256).max;
    uint256 public seasonRewardRate;
    mapping(address => uint256) public lastBattleTime;
    mapping(address => uint256) public rechargeCount;

    event RechargeLimitUpdated(uint256 newLimit);

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
    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external onlyOwner {
        arenaLeaderboardContract = _arenaLeaderboardContract;
    }
    function setArenaPlayerContract(address _arenaPlayerContract) external onlyOwner {
        arenaPlayerContract = _arenaPlayerContract;
    }
    function setArenaBattleContract(address _arenaBattleContract) external onlyOwner {
        arenaBattleContract = _arenaBattleContract;
    }
    function setSeasonRewardRate(uint256 rate) external onlyOwner {
        require(rate > 0, "ArenaRanking: Reward rate must be greater than 0");
        seasonRewardRate = rate;
    }

    function setArenaMode(uint8 mode) external onlyOwner {
        require(mode == 0 || mode == 1, "ArenaRanking: Invalid mode (0 or 1)");
        uint8 oldMode = arenaMode;
        arenaMode = mode;
        emit ArenaModeUpdated(oldMode, mode);
    }

    function setMockRewardRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "ArenaRanking: Invalid recipient");
        address oldRecipient = mockRewardRecipient;
        mockRewardRecipient = recipient;
        emit MockRewardRecipientUpdated(oldRecipient, recipient);
    }

    function setModeControlType(uint8 controlType) external onlyOwner {
        require(controlType <= 2, "ArenaRanking: Invalid control type (0-2)");
        uint8 oldType = modeControlType;
        modeControlType = controlType;
        emit ModeControlTypeUpdated(oldType, controlType);
    }

    function configureArenaMode(uint8 controlType, uint8 preferredMode) external onlyOwner {
        require(controlType <= 2, "ArenaRanking: Invalid control type (0-2)");
        require(preferredMode == 0 || preferredMode == 1, "ArenaRanking: Invalid mode (0 or 1)");
        
        uint8 oldControlType = modeControlType;
        uint8 oldMode = arenaMode;
        
        modeControlType = controlType;
        arenaMode = preferredMode;
        
        emit ModeControlTypeUpdated(oldControlType, controlType);
        emit ArenaModeUpdated(oldMode, preferredMode);
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
        if (block.timestamp > record.lastResetTime + 24 hours) {
            _resetAttempts(player);
            rechargeCount[player] = 0;
        }
    }

    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external nonReentrant whenNotPaused returns (bool success) {
        require(arenaBattleContract != address(0), "ArenaRanking: ArenaBattle contract not set");
        
        (bool success_, uint256 winner, ) = IArenaBattle(arenaBattleContract).executeMockBattle(playerTeam, mockIndex);
        
        if (winner == 1) {
            if (arenaMode == 0) {
                _updateScorePointsMode(msg.sender, true, mockIndex);
            } else {
                _updateScoreChallengeMode(msg.sender, true, mockIndex);
            }
        } else if (winner == 2) {
            if (arenaMode == 0) {
                _updateScorePointsMode(msg.sender, false, mockIndex);
            } else {
                _updateScoreChallengeMode(msg.sender, false, mockIndex);
            }
        } else {
            _updateScoreOnDraw(msg.sender);
        }
        emit ChallengeResult(msg.sender, address(0), winner == 1, currentSeasonId);
        
        return success_;
    }

    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external nonReentrant whenNotPaused returns (bool success) {
        require(arenaBattleContract != address(0), "ArenaRanking: ArenaBattle contract not set");
        require(arenaPlayerContract != address(0), "ArenaRanking: ArenaPlayer contract not set");
        
        uint256[] memory challengedTeamArray = IArenaPlayer(arenaPlayerContract).getPlayerBattleTeam(challengedPlayer);
        require(challengedTeamArray.length == 6, "ArenaRanking: Target has no team");
        
        uint256[6] memory challengedTeam;
        for (uint256 i = 0; i < 6; i++) {
            challengedTeam[i] = challengedTeamArray[i];
        }
        
        (bool success_, uint256 winner, ) = IArenaBattle(arenaBattleContract).executeRealBattle(challengedPlayer, playerTeam, challengedTeam);
        
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

    function _updateScorePointsMode(address player, bool isWinner, uint256 mockIndex) internal {
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

        uint256 points = ArenaRankingLib.calculateDynamicPoints(mockIndex);

        if (isWinner) {
            record.score += points;
            record.wins++;
        } else {
            if (record.score > points) record.score -= points;
            else record.score = 0;
            record.losses++;
        }
        record.lastBattleTime = block.timestamp;

        _updateRanking(player, record.score);
        emit ScoreUpdated(player, record.score, currentSeasonId);
    }

    function _updateScoreChallengeMode(address player, bool isWinner, uint256 mockIndex) internal {
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
            currentSeason.totalPlayers++;
        }

        if (isWinner) {
            _insertPlayerAtRank(player, mockIndex);
            record.wins++;
        } else {
            record.losses++;
        }
        record.lastBattleTime = block.timestamp;
        record.score = 1000 + record.wins * 25 - record.losses * 10;
        
        emit ScoreUpdated(player, record.score, currentSeasonId);
    }

    function _insertPlayerAtRank(address player, uint256 targetRank) internal {
        uint256 seasonId = currentSeasonId;
        address[] storage rankings = seasonRankings[seasonId];
        
        uint256 currentIndex = playerRankIndex[seasonId][player];

        // Step 1: Remove from current position if already ranked
        if (currentIndex > 0) {
            // Shift elements left to fill the gap at currentIndex
            for (uint256 i = currentIndex; i + 1 < rankings.length; i++) {
                rankings[i] = rankings[i + 1];
                playerRankIndex[seasonId][rankings[i]] = i;
            }
            rankings.pop();
            playerRankIndex[seasonId][player] = 0;
        }

        // Step 2: Insert at targetRank
        if (targetRank >= rankings.length) {
            rankings.push(player);
            playerRankIndex[seasonId][player] = rankings.length - 1;
        } else {
            // First push to grow the array
            rankings.push(address(0));
            // Shift elements right from targetRank to the end
            for (uint256 i = rankings.length - 1; i > targetRank; i--) {
                rankings[i] = rankings[i - 1];
                playerRankIndex[seasonId][rankings[i]] = i;
            }
            rankings[targetRank] = player;
            playerRankIndex[seasonId][player] = targetRank;
        }
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
        require(arenaRewardContract != address(0), "ArenaRanking: Reward contract not set");
        IArenaReward(arenaRewardContract).setRewardType(_rewardType);
        emit RewardTypeUpdated(0, _rewardType);
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
        
        if (modeControlType == 1) {
            uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, currentSeasonId, tx.gasprice))) % 2;
            arenaMode = uint8(rand);
        } else if (modeControlType == 2) {
            arenaMode = lastSeasonMode == 0 ? 1 : 0;
            lastSeasonMode = arenaMode;
        }
        
        uint256 effectiveDuration = seasonDuration;
        if (effectiveDuration < 1 hours) {
            effectiveDuration = 1 hours;
        }
        
        seasons[currentSeasonId] = SeasonInfo({
            seasonId: currentSeasonId,
            startTime: block.timestamp,
            endTime: block.timestamp + effectiveDuration,
            isActive: true,
            isSettled: false,
            rewardCalculated: false,
            totalPlayers: 0,
            rewardPool: 0,
            tokenRewardPool: 0,
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
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).checkNewDay();
        }
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
     * @dev 检查是否是Mock玩家（使用特殊地址范围）
     * Mock玩家地址格式为: MOCK_PLAYER_BASE + index (0-999)
     */
    function _isMockPlayer(address player) internal pure returns (bool) {
        uint256 playerAddress = uint256(uint160(player));
        uint256 baseAddress = uint256(uint160(MOCK_PLAYER_BASE));
        return playerAddress >= baseAddress && 
               playerAddress < baseAddress + MAX_MOCK_PLAYERS_COUNT;
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
    
    function getPlayerRank(address player) external view returns (uint256) {
        return playerRankIndex[currentSeasonId][player] + 1;
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
    function getSeasonHistory(uint256 startSeasonId, uint256 count) public view returns (SeasonInfo[] memory) {
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
    
    function setSeasonDuration(uint256 duration) external onlyOwner {
        require(duration >= 1 days, "ArenaRanking: Duration too short");
        seasonDuration = duration;
    }

    function addRewardToPool() external payable onlyAuthorized {
        require(msg.value > 0, "ArenaRanking: No BNB sent");
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
        seasons[currentSeasonId].rewardPool += msg.value;
    }

    // 接收 BNB
    receive() external payable {
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
    }
    fallback() external payable {
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
    }

    /**
     * @dev 验证用户是否拥有战队中的所有NFT
     * @param owner 用户地址
     * @param team 战队NFT ID数组
     */
    function _validateTeamOwnership(address owner, uint256[6] calldata team) internal view {
        require(arenaPlayerContract != address(0), "ArenaRanking: ArenaPlayer contract not set");
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRanking: Invalid token ID");
            require(IArenaPlayer(arenaPlayerContract).getNFTStakedOwner(tokenId) == owner, "ArenaRanking: NFT not staked or not owner");
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
    /**
     * @dev 紧急提取BNB（仅限合约所有者）
     * @param amount 提取金额
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRanking: Amount must be > 0");
        require(amount <= address(this).balance, "ArenaRanking: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaRanking: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币（仅限合约所有者）
     * @param amount 提取金额
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRanking: Amount must be > 0");
        require(tokenContract != address(0), "ArenaRanking: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "ArenaRanking: Insufficient token balance");
        require(token.transfer(owner(), amount), "ArenaRanking: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    function setArenaRewardContract(address _arenaRewardContract) external onlyOwner {
        arenaRewardContract = _arenaRewardContract;
    }

    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).calculateSeasonRewards(seasonId);
        }
    }
}