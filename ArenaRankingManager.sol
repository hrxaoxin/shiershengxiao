// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

/**
 * @title ArenaRankingManager
 * @dev 竞技场排名管理合约（赛季与战斗管理模块）
 * 
 * 核心职责：
 * 1. 赛季生命周期管理：创建、启动、结算赛季
 * 2. 战斗挑战系统：PvE（模拟玩家）和 PvP（真实玩家）挑战
 * 3. NFT 质押管理：用户质押 NFT 用于战斗队伍
 * 4. 战斗队伍配置：设置和清除战斗队伍
 * 
 * 赛季系统：
 * - 每个赛季持续一定时间（默认1天，可配置）
 * - 赛季结束时结算，分配奖励
 * - 支持赛季历史查询
 * 
 * 战斗系统：
 * - PvE 模式：挑战模拟玩家（mock players），根据难度获得不同分数
 * - PvP 模式：挑战真实玩家，胜者获得积分
 * - 每日挑战次数限制（默认3次），可通过代币充值增加
 * - 战斗冷却时间（默认30秒）
 * 
 * 分数计算：
 * - 挑战胜利：+10~25分（根据对手分数差异）
 * - 挑战失败：-5~10分（根据对手分数差异）
 * - 平局：不变
 * 
 * 与其他合约的交互：
 * - ArenaBattle：执行实际战斗逻辑
 * - ArenaLeaderboard：更新排行榜数据
 * - ArenaPlayer：管理玩家 NFT 质押和挑战次数
 * - ArenaReward：发放赛季奖励
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - 非流动性设计：战斗不转移 NFT 所有权
 * 
 * 权限控制：
 * - onlyOwner：设置合约地址、配置参数
 * - onlyAuthorized：启动赛季、结算赛季
 * 
 * 注意：此合约是 ArenaRanking 的拆分版本，专门负责写入操作
 * 查询功能由 ArenaRankingQuery 合约提供
 */
contract ArenaRankingManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
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
     * @param lastResetTime 上次重置时间
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
     * @dev 模拟玩家信息结构体
     * @param team 模拟玩家队伍（6个NFT ID）
     * @param score 模拟玩家分数
     * @param level 模拟玩家等级
     * @param growth 模拟玩家成长值
     * @param elementCounts 各属性数量统计
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
     * @param seasonId 赛季ID
     * @param startTime 赛季开始时间
     * @param endTime 赛季结束时间
     * @param isActive 是否活跃中
     * @param isSettled 是否已结算
     * @param rewardCalculated 奖励是否已计算
     * @param totalPlayers 赛季参与玩家数
     * @param rewardPool BNB奖励池
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
     * @dev 玩家记录映射（地址 -> 玩家记录）
     */
    mapping(address => PlayerRecord) public players;
    /**
     * @dev 赛季信息映射（赛季ID -> 赛季信息）
     */
    mapping(uint256 => SeasonInfo) public seasons;
    /**
     * @dev 玩家赛季奖励映射（赛季ID -> 地址 -> 奖励金额）
     */
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    /**
     * @dev 赛季奖励领取状态映射（赛季ID -> 地址 -> 是否已领取）
     */
    mapping(uint256 => mapping(address => bool)) public seasonRewardsClaimed;
    
    /**
     * @dev 当前赛季ID
     */
    uint256 public currentSeasonId;
    /**
     * @dev 赛季持续时间（默认1天）
     */
    uint256 public seasonDuration = 1 days;
    
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    /**
     * @dev 战斗核心合约地址
     */
    address public battleContract;
    /**
     * @dev NFT合约地址
     */
    address public nftContract;
    /**
     * @dev 代币合约地址
     */
    address public tokenContract;
    /**
     * @dev 竞技场奖励合约地址
     */
    address public arenaRewardContract;
    /**
     * @dev 竞技场排行榜合约地址
     */
    address public arenaLeaderboardContract;
    /**
     * @dev 竞技场玩家合约地址
     */
    address public arenaPlayerContract;
    /**
     * @dev 竞技场战斗合约地址
     */
    address public arenaBattleContract;
    
    /**
     * @dev 竞技场模式：0=单人模式，1=组队模式
     */
    uint8 public arenaMode = 1;
    /**
     * @dev 模式控制类型：0=禁用，1=手动，2=自动
     */
    uint8 public modeControlType = 0;
    /**
     * @dev 上赛季模式（用于模式切换时的记录）
     */
    uint8 public lastSeasonMode = 1;
    /**
     * @dev 模拟玩家奖励接收地址（从玩家挑战模拟玩家获得的奖励）
     */
    address public mockRewardRecipient;
    
    /**
     * @dev 每日挑战次数限制
     */
    uint256 public constant DAILY_ATTEMPTS = 3;
    /**
     * @dev 最大充值次数上限
     */
    uint256 public constant MAX_RECHARGE_ATTEMPTS = 50;
    /**
     * @dev 战斗冷却时间（两次战斗间隔）
     */
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    /**
     * @dev 战斗队伍规模（最多6个NFT）
     */
    uint256 public constant TEAM_SIZE = 6;
    /**
     * @dev 充值挑战次数的代币消耗
     */
    uint256 public constant RECHARGE_COST = 888;
    /**
     * @dev 每次充值获得的挑战次数
     */
    uint256 public constant RECHARGE_ATTEMPTS = 3;
    /**
     * @dev 排行榜最大显示数量
     */
    uint256 public constant MAX_LEADERBOARD_SIZE = 1000;
    /**
     * @dev 保留的最大赛季数（超过后自动清理历史数据）
     */
    uint256 public constant MAX_SEASONS_TO_KEEP = 20;
    /**
     * @dev 精度常量（万分比计算使用）
     */
    uint256 public constant PRECISION = 10000;
    /**
     * @dev 模拟玩家排行榜最大显示数量
     */
    uint256 public constant MAX_MOCK_RANKING = 100;
    /**
     * @dev 模拟玩家基础地址（用于生成模拟玩家唯一标识）
     */
    address public constant MOCK_PLAYER_BASE = address(0x000000000000000000000000000000000000dEaD);
    /**
     * @dev 模拟玩家总数
     */
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;
    
    /**
     * @dev 单用户最大充值次数限制（可配置，默认为无限制）
     */
    uint256 public maxRechargeAttempts = type(uint256).max;
    /**
     * @dev 赛季奖励比例（万分比）
     */
    uint256 public seasonRewardRate;
    /**
     * @dev 玩家上次战斗时间映射（用于冷却检查）
     */
    mapping(address => uint256) public lastBattleTime;
    /**
     * @dev 玩家充值次数映射（当日充值计数）
     */
    mapping(address => uint256) public rechargeCount;
    /**
     * @dev 战斗ID计数器（用于生成唯一战斗记录ID）
     */
    uint256 public battleIdCounter;

    /**
     * @dev 充值限制更新事件
     */
    event RechargeLimitUpdated(uint256 newLimit);
    /**
     * @dev 奖励类型更新事件
     */
    event RewardTypeUpdated(uint8 oldType, uint8 newType);
    /**
     * @dev 奖励比例更新事件
     */
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    /**
     * @dev 竞技场模式更新事件
     */
    event ArenaModeUpdated(uint8 oldMode, uint8 newMode);
    /**
     * @dev 模式控制类型更新事件
     */
    event ModeControlTypeUpdated(uint8 oldType, uint8 newType);
    /**
     * @dev 模拟玩家奖励接收地址更新事件
     */
    event MockRewardRecipientUpdated(address oldAddress, address newAddress);
    /**
     * @dev 模拟玩家奖励分发事件
     */
    event MockRewardDistributed(address indexed recipient, uint256 amount, uint256 seasonId);
    /**
     * @dev 玩家分数更新事件
     */
    event ScoreUpdated(address indexed player, uint256 newScore, uint256 seasonId);
    /**
     * @dev 赛季开始事件
     */
    event SeasonStarted(uint256 indexed seasonId, uint256 startTime);
    /**
     * @dev 赛季结算事件
     */
    event SeasonSettled(uint256 indexed seasonId, uint256 endTime);
    /**
     * @dev 奖励领取事件
     */
    event RewardClaimed(address indexed player, uint256 amount, uint256 seasonId);
    /**
     * @dev 挑战结果事件
     */
    event ChallengeResult(address indexed challenger, address indexed challenged, bool isVictory, uint256 seasonId);
    /**
     * @dev 赛季奖励计算完成事件
     */
    event SeasonRewardsCalculated(uint256 indexed seasonNumber, uint256 totalReward, uint256 distributed);
    /**
     * @dev 紧急提取BNB事件
     */
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    /**
     * @dev 紧急提取代币事件
     */
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    function initialize(address _battleContract, address _nftContract, address _tokenContract, address _authorizer) external initializer {
        require(_battleContract != address(0), "ArenaRankingManager: Invalid battle contract address");
        require(_nftContract != address(0), "ArenaRankingManager: Invalid NFT contract address");
        require(_tokenContract != address(0), "ArenaRankingManager: Invalid token contract address");
        require(_authorizer != address(0), "ArenaRankingManager: Invalid authorizer address");
        
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

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaRankingManager: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "ArenaRankingManager: Invalid authorizer address");
        authorizer = a;
    }

    function setBattleContract(address a) external onlyAuthorized {
        require(a != address(0), "ArenaRankingManager: Invalid battle contract address");
        battleContract = a;
    }

    function setNFTContract(address a) external onlyAuthorized {
        require(a != address(0), "ArenaRankingManager: Invalid NFT contract address");
        nftContract = a;
    }

    function setTokenContract(address a) external onlyAuthorized {
        require(a != address(0), "ArenaRankingManager: Invalid token contract address");
        tokenContract = a;
    }

    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external onlyAuthorized {
        arenaLeaderboardContract = _arenaLeaderboardContract;
    }

    function setArenaPlayerContract(address _arenaPlayerContract) external onlyAuthorized {
        arenaPlayerContract = _arenaPlayerContract;
    }

    function setArenaRewardContract(address _arenaRewardContract) external onlyAuthorized {
        arenaRewardContract = _arenaRewardContract;
    }

    function setArenaBattleContract(address _arenaBattleContract) external onlyAuthorized {
        arenaBattleContract = _arenaBattleContract;
    }

    function setSeasonRewardRate(uint256 rate) external onlyOwner {
        require(rate > 0, "ArenaRankingManager: Reward rate must be greater than 0");
        seasonRewardRate = rate;
    }

    /**
     * @dev 设置竞技场模式
     * @param mode 模式值：0 = 单人模式, 1 = 组队模式
     */
    function setArenaMode(uint8 mode) external onlyOwner {
        require(mode == 0 || mode == 1, "ArenaRankingManager: Invalid mode (0 or 1)");
        uint8 oldMode = arenaMode;
        arenaMode = mode;
        emit ArenaModeUpdated(oldMode, mode);
    }

    /**
     * @dev 设置模拟玩家奖励接收地址
     * @param recipient 奖励接收地址
     */
    function setMockRewardRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "ArenaRankingManager: Invalid recipient");
        address oldRecipient = mockRewardRecipient;
        mockRewardRecipient = recipient;
        emit MockRewardRecipientUpdated(oldRecipient, recipient);
    }

    /**
     * @dev 设置模式控制类型
     * @param controlType 控制类型：0 = 禁用, 1 = 手动, 2 = 自动
     */
    function setModeControlType(uint8 controlType) external onlyOwner {
        require(controlType <= 2, "ArenaRankingManager: Invalid control type (0-2)");
        uint8 oldType = modeControlType;
        modeControlType = controlType;
        emit ModeControlTypeUpdated(oldType, controlType);
    }

    /**
     * @dev 配置竞技场模式（批量设置）
     * @param controlType 控制类型：0 = 禁用, 1 = 手动, 2 = 自动
     * @param preferredMode 偏好模式：0 = 单人模式, 1 = 组队模式
     */
    function configureArenaMode(uint8 controlType, uint8 preferredMode) external onlyOwner {
        require(controlType <= 2, "ArenaRankingManager: Invalid control type (0-2)");
        require(preferredMode == 0 || preferredMode == 1, "ArenaRankingManager: Invalid mode (0 or 1)");
        
        uint8 oldControlType = modeControlType;
        uint8 oldMode = arenaMode;
        
        modeControlType = controlType;
        arenaMode = preferredMode;
        
        emit ModeControlTypeUpdated(oldControlType, controlType);
        emit ArenaModeUpdated(oldMode, preferredMode);
    }

    /**
     * @dev 设置最大充值次数限制
     * @param _limit 最大充值次数（1-10）
     */
    function setMaxRechargeAttempts(uint256 _limit) external onlyOwner {
        require(_limit >= 1 && _limit <= MAX_RECHARGE_ATTEMPTS, "ArenaRankingManager: Invalid limit");
        maxRechargeAttempts = _limit;
        emit RechargeLimitUpdated(_limit);
    }

    /**
     * @dev 设置奖励类型
     * @param _rewardType 奖励类型：0 = BNB, 1 = 代币
     */
    function setRewardType(uint8 _rewardType) external onlyOwner {
        require(_rewardType == 0 || _rewardType == 1, "ArenaRankingManager: Invalid reward type");
        require(arenaRewardContract != address(0), "ArenaRankingManager: Reward contract not set");
        uint8 oldRewardType = IArenaReward(arenaRewardContract).rewardType();
        IArenaReward(arenaRewardContract).setRewardType(_rewardType);
        emit RewardTypeUpdated(oldRewardType, _rewardType);
    }

    /**
     * @dev 内部函数：重置玩家的挑战次数
     * @param player 玩家地址
     */
    function _resetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        record.lastResetTime = block.timestamp;
        record.remainingAttempts = DAILY_ATTEMPTS;
    }

    /**
     * @dev 内部函数：检查并重置玩家挑战次数（每日重置）
     * @param player 玩家地址
     */
    function _checkAndResetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        if (record.lastResetTime == 0 || block.timestamp > record.lastResetTime + 24 hours) {
            _resetAttempts(player);
            rechargeCount[player] = 0;
        }
    }

    /**
     * @dev 内部函数：验证队伍 NFT 所有权
     * @param owner 玩家地址
     * @param team 队伍 NFT ID 数组
     */
    function _validateTeamOwnership(address owner, uint256[6] calldata team) internal view {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer contract not set");
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRankingManager: Invalid token ID");
            require(IArenaPlayer(arenaPlayerContract).getNFTStakedOwner(tokenId) == owner, "ArenaRankingManager: NFT not staked or not owner");
        }
    }

    /**
     * @dev 挑战模拟玩家（PvE 模式）
     * @param playerTeam 玩家战斗队伍（6个 NFT ID）
     * @param mockIndex 模拟玩家索引（1-1000）
     * @return success 挑战是否成功
     */
    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external nonReentrant whenNotPaused returns (bool success) {
        require(arenaBattleContract != address(0), "ArenaRankingManager: ArenaBattle contract not set");
        require(mockIndex > 0, "ArenaRankingManager: Invalid mock index");
        _checkAndResetAttempts(msg.sender);
        PlayerRecord storage record = players[msg.sender];
        require(record.hasTeam, "ArenaRankingManager: Must set battle team first");
        require(record.remainingAttempts > 0, "ArenaRankingManager: No remaining attempts");
        _validateTeamOwnership(msg.sender, playerTeam);
        record.remainingAttempts--;
        (bool ok, uint256 winner, ) = IArenaBattle(arenaBattleContract).executeMockBattle(playerTeam, mockIndex);
        require(ok, "ArenaRankingManager: Challenge mock player failed");
        emit ChallengeResult(msg.sender, address(0), winner == 1, currentSeasonId);
        return ok;
    }

    /**
     * @dev 挑战真实玩家（PvP 模式）
     * @param challengedPlayer 被挑战玩家地址
     * @param playerTeam 挑战者的战斗队伍（6个 NFT ID）
     * @return success 挑战是否成功
     */
    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external nonReentrant whenNotPaused returns (bool success) {
        require(arenaBattleContract != address(0), "ArenaRankingManager: ArenaBattle contract not set");
        require(challengedPlayer != address(0), "ArenaRankingManager: Zero challenged player");
        require(challengedPlayer != msg.sender, "ArenaRankingManager: Cannot challenge self");
        _checkAndResetAttempts(msg.sender);
        PlayerRecord storage challengerRecord = players[msg.sender];
        require(challengerRecord.hasTeam, "ArenaRankingManager: Must set battle team first");
        require(challengerRecord.remainingAttempts > 0, "ArenaRankingManager: No remaining attempts");
        _validateTeamOwnership(msg.sender, playerTeam);
        challengerRecord.remainingAttempts--;
        PlayerRecord storage defenderRecord = players[challengedPlayer];
        require(defenderRecord.hasTeam, "ArenaRankingManager: Challenged player has no team");
        (bool ok, uint256 winner, ) = IArenaBattle(arenaBattleContract).executeRealBattle(
            challengedPlayer, playerTeam, defenderRecord.battleTeam
        );
        require(ok, "ArenaRankingManager: Challenge real player failed");
        emit ChallengeResult(msg.sender, challengedPlayer, winner == 1, currentSeasonId);
        return ok;
    }

    /**
     * @dev 内部函数：清除玩家赛季数据（新赛季开始时调用）
     * @param player 玩家地址
     */
    function _clearSeasonData(address player) internal {
        PlayerRecord storage record = players[player];
        record.score = 0;
        record.wins = 0;
        record.losses = 0;
        record.seasonId = currentSeasonId;
    }

    /**
     * @dev 启动新赛季（需授权）
     */
    function startNewSeason() external onlyAuthorized {
        _tryStartNewSeason();
    }

    /**
     * @dev 内部函数：尝试启动新赛季
     * 检查当前赛季是否结束，然后结算、清理并启动新赛季
     */
    function _tryStartNewSeason() internal {
        require(block.timestamp >= seasons[currentSeasonId].endTime, "ArenaRankingManager: Current season not ended");
        _settleCurrentSeason();
        _cleanupOldSeasons();
        _startNewSeason();
    }

    /**
     * @dev 检查并启动新赛季（公共接口）
     * 如果当前赛季已结束，自动启动新赛季
     */
    function checkAndStartNewSeason() external whenNotPaused {
        if (block.timestamp >= seasons[currentSeasonId].endTime) {
            _tryStartNewSeason();
        }
    }

    /**
     * @dev 内部函数：启动新赛季
     */
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

    /**
     * @dev 内部函数：结算当前赛季
     */
    function _settleCurrentSeason() internal {
        SeasonInfo storage season = seasons[currentSeasonId];
        season.isActive = false;
        season.isSettled = true;
        emit SeasonSettled(currentSeasonId, block.timestamp);
    }

    /**
     * @dev 内部函数：清理旧赛季数据
     * 保留最近的 MAX_SEASONS_TO_KEEP 个赛季数据，删除更早的赛季
     */
    function _cleanupOldSeasons() internal {
        uint256 seasonsToRemove = currentSeasonId > MAX_SEASONS_TO_KEEP ? 
            currentSeasonId - MAX_SEASONS_TO_KEEP : 0;
        
        for (uint256 i = 1; i <= seasonsToRemove; i++) {
            delete seasons[i];
        }
    }

    /**
     * @dev 结算指定赛季
     * @param seasonId 赛季 ID
     */
    function settleSeason(uint256 seasonId) external onlyAuthorized {
        require(seasonId <= currentSeasonId, "ArenaRankingManager: Invalid season");
        require(!seasons[seasonId].isSettled, "ArenaRankingManager: Already settled");
        
        if (seasonId == currentSeasonId) {
            seasons[seasonId].isActive = false;
        }
        seasons[seasonId].isSettled = true;
        
        _calculateSeasonRewardsInternal(seasonId);
        
        emit SeasonSettled(seasonId, block.timestamp);
    }

    /**
     * @dev 内部函数：检查是否进入新的一天（用于奖励结算）
     */
    function _checkNewDay() internal {
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).checkNewDay();
        }
    }

    /**
     * @dev 内部函数：计算赛季奖励
     * @param seasonId 赛季 ID
     */
    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).calculateSeasonRewards(seasonId);
        }
    }

    /**
     * @dev 设置赛季持续时间
     * @param duration 赛季持续时间（秒），最小为 1 天
     */
    function setSeasonDuration(uint256 duration) external onlyOwner {
        require(duration >= 1 days, "ArenaRankingManager: Duration too short");
        seasonDuration = duration;
    }

    /**
     * @dev 向奖励池添加 BNB
     */
    function addRewardToPool() external payable onlyAuthorized {
        require(msg.value > 0, "ArenaRankingManager: No BNB sent");
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
        seasons[currentSeasonId].rewardPool += msg.value;
    }

    /**
     * @dev 接收 ETH/BNB 的 fallback 函数
     */
    receive() external payable {
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
    }

    /**
     * @dev fallback 函数（处理未识别的调用）
     */
    fallback() external payable {
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
    }

    /**
     * @dev 获取当前赛季奖励池
     * @return 当前赛季的奖励池金额
     */
    function getCurrentRewardPool() external view returns (uint256) {
        return seasons[currentSeasonId].rewardPool;
    }

    /**
     * @dev 获取当前赛季信息
     * @return seasonId 赛季ID
     * @return startTime 赛季开始时间
     * @return endTime 赛季结束时间
     * @return isActive 是否活跃
     * @return rewardPool 奖励池
     */
    function currentSeason() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        uint256 rewardPool
    ) {
        SeasonInfo storage season = seasons[currentSeasonId];
        return (
            season.seasonId,
            season.startTime,
            season.endTime,
            season.isActive,
            season.rewardPool
        );
    }

    /**
     * @dev 紧急提取 BNB（仅所有者）
     * @param amount 提取金额
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRankingManager: Amount must be > 0");
        require(amount <= address(this).balance, "ArenaRankingManager: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaRankingManager: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币（仅所有者）
     * @param amount 提取金额
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRankingManager: Amount must be > 0");
        require(tokenContract != address(0), "ArenaRankingManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "ArenaRankingManager: Insufficient token balance");
        token.transfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 充值挑战次数
     */
    function rechargeChallengeAttempts() external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer not set");
        IArenaPlayer(arenaPlayerContract).rechargeChallengeAttempts();
    }

    /**
     * @dev 质押 NFT
     * @param tokenIds 要质押的 NFT ID 数组（1-6 个）
     */
    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRankingManager: Invalid token count");
        IArenaPlayer(arenaPlayerContract).stakeNFTs(tokenIds);
    }

    /**
     * @dev 解除质押 NFT
     * @param tokenIds 要解除质押的 NFT ID 数组（1-6 个）
     */
    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRankingManager: Invalid token count");
        IArenaPlayer(arenaPlayerContract).unstakeNFTs(tokenIds);
    }

    /**
     * @dev 设置战斗队伍（动态数组版本）
     * @param tokenIds 战斗队伍的 NFT ID 数组（必须恰好 6 个）
     */
    function setBattleTeam(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(tokenIds.length == 6, "ArenaRankingManager: Team must have exactly 6 NFTs");
        uint256[6] memory fixedTeam;
        for (uint256 i = 0; i < 6; i++) {
            fixedTeam[i] = tokenIds[i];
        }
        _setBattleTeamInternal(fixedTeam);
    }

    /**
     * @dev 设置战斗队伍（固定数组版本）
     * @param tokenIds 战斗队伍的 NFT ID 数组（6 个）
     */
    function setBattleTeam(uint256[6] calldata tokenIds) external nonReentrant whenNotPaused {
        _setBattleTeamInternal(tokenIds);
    }

    /**
     * @dev 内部函数：设置战斗队伍
     * @param tokenIds 战斗队伍的 NFT ID 数组（6 个）
     */
    function _setBattleTeamInternal(uint256[6] memory tokenIds) internal {
        for (uint256 i = 0; i < 6; i++) {
            if (tokenIds[i] == 0) continue;
            require(INFTMint(nftContract).ownerOf(tokenIds[i]) == msg.sender, "ArenaRankingManager: Not owner");
            for (uint256 j = i + 1; j < 6; j++) {
                if (tokenIds[j] != 0) {
                    require(tokenIds[j] != tokenIds[i], "ArenaRankingManager: Duplicate token");
                }
            }
        }
        PlayerRecord storage record = players[msg.sender];
        for (uint256 i = 0; i < 6; i++) {
            record.battleTeam[i] = tokenIds[i];
        }
        record.hasTeam = true;
    }

    /**
     * @dev 清除战斗队伍
     */
    function clearBattleTeam() external nonReentrant whenNotPaused {
        PlayerRecord storage record = players[msg.sender];
        for (uint256 i = 0; i < 6; i++) {
            record.battleTeam[i] = 0;
        }
        record.hasTeam = false;
    }

    /**
     * @dev 每次胜利的基础奖励（积分）
     */
    uint256 public baseRewardPerWin = 100;

    /**
     * @dev 设置每次胜利的基础奖励
     * @param _reward 奖励积分值
     */
    function setBaseRewardPerWin(uint256 _reward) external onlyOwner {
        baseRewardPerWin = _reward;
    }
}