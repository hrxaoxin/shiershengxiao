// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

/**
 * @title ArenaRankingManager
 * @dev 竞技场排名管理合约（赛季与战斗管理模块）
 * 
 * 核心职责：
 * 1. 赛季生命周期管理：创建、启动、结算赛季
 * 2. 战斗挑战系统：PvE（模拟玩家）、PvP（真实玩家）挑战
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
    using SafeERC20 for IERC20;

    /**
     * @dev 玩家记录结构：
     * @param score 玩家当前积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param draws 平局次数
     * @param lastBattleTime 上次战斗时间
     * @param lastResetTime 上次重置时间
     * @param remainingAttempts 剩余挑战次数
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
        uint256 seasonId;
    }

    /**
     * @dev 模拟玩家信息结构：
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
     * @dev 赛季信息结构：
     * @param seasonId 赛季ID
     * @param startTime 赛季开始时间
     * @param endTime 赛季结束时间
     * @param isActive 是否活跃状态
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

    /**
     * @dev 初始化合约
     * @notice 初始化函数，设置授权者地址并启动第一个赛季
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(
        address _authorizerAddress
    ) external initializer {
        require(_authorizerAddress != address(0), "ArenaRankingManager: Invalid authorizer address");
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
        _startNewSeason();
    }

    /**
     * @dev 暂停合约
     * @notice 暂停所有非管理员操作（仅owner可调用）
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停合约
     * @notice 恢复所有操作（仅owner可调用）
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 权限校验修饰符：owner或授权者或系统合约
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaRankingManager: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权校验
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaRankingManager: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置赛季奖励比例
     * @param rate 奖励比例（万分比）
     */
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
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        require(arenaReward != address(0), "ArenaRankingManager: Reward contract not set");
        uint8 oldRewardType = IArenaReward(arenaReward).rewardType();
        IArenaReward(arenaReward).setRewardType(_rewardType);
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
        address arenaPlayer = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayer != address(0), "ArenaRankingManager: ArenaPlayer contract not set");
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRankingManager: Invalid token ID");
            require(IArenaPlayer(arenaPlayer).getNFTStakedOwner(tokenId) == owner, "ArenaRankingManager: NFT not staked or not owner");
        }
    }

    /**
     * @dev 挑战模拟玩家（PvE 模式）
     * @param playerTeam 玩家战斗队伍（6个 NFT ID）
     * @param mockIndex 模拟玩家索引（1-1000）
     * @return success 挑战是否成功
     */
    function challengeMockPlayer(uint256[6] calldata playerTeam, uint256 mockIndex) external nonReentrant whenNotPaused returns (bool success) {
        address arenaBattle = IAuthorizer(authorizer).getArenaBattle();
        require(arenaBattle != address(0), "ArenaRankingManager: ArenaBattle contract not set");
        require(mockIndex > 0, "ArenaRankingManager: Invalid mock index");
        _checkAndResetAttempts(msg.sender);
        PlayerRecord storage record = players[msg.sender];
        require(_hasBattleTeam(msg.sender), "ArenaRankingManager: Must set battle team first");
        require(record.remainingAttempts > 0, "ArenaRankingManager: No remaining attempts");
        _validateTeamOwnership(msg.sender, playerTeam);
        record.remainingAttempts--;
        (bool ok, uint256 winner, ) = IArenaBattle(arenaBattle).executeMockBattle(playerTeam, mockIndex);
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
        address arenaBattle = IAuthorizer(authorizer).getArenaBattle();
        require(arenaBattle != address(0), "ArenaRankingManager: ArenaBattle contract not set");
        require(challengedPlayer != address(0), "ArenaRankingManager: Zero challenged player");
        require(challengedPlayer != msg.sender, "ArenaRankingManager: Cannot challenge self");
        _checkAndResetAttempts(msg.sender);
        PlayerRecord storage challengerRecord = players[msg.sender];
        require(_hasBattleTeam(msg.sender), "ArenaRankingManager: Must set battle team first");
        require(challengerRecord.remainingAttempts > 0, "ArenaRankingManager: No remaining attempts");
        _validateTeamOwnership(msg.sender, playerTeam);
        challengerRecord.remainingAttempts--;
        require(_hasBattleTeam(challengedPlayer), "ArenaRankingManager: Challenged player has no team");
        uint256[6] memory defenderTeam = _getBattleTeam(challengedPlayer);
        (bool ok, uint256 winner, ) = IArenaBattle(arenaBattle).executeRealBattle(
            challengedPlayer, playerTeam, defenderTeam
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
     * @notice 由owner或授权者手动触发启动新赛季
     */
    function startNewSeason() external onlyOwnerOrAuthorizer {
        _tryStartNewSeason();
    }

    /**
     * @dev 内部函数：尝试启动新赛季
     * @notice 检查当前赛季是否结束，然后结算、清理并启动新赛季
     */
    function _tryStartNewSeason() internal {
        require(block.timestamp >= seasons[currentSeasonId].endTime, "ArenaRankingManager: Current season not ended");
        _settleCurrentSeason();
        _cleanupOldSeasons();
        _startNewSeason();
    }

    /**
     * @dev 检查并启动新赛季（公共接口）
     * @notice 如果当前赛季已结束，自动启动新赛季（任何人可调用）
     */
    function checkAndStartNewSeason() external whenNotPaused {
        if (block.timestamp >= seasons[currentSeasonId].endTime) {
            _tryStartNewSeason();
        }
    }

    /**
     * @dev 内部函数：启动新赛季
     * @notice 创建新赛季信息，根据模式控制类型设置竞技场模式
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
     * @notice 标记当前赛季为已结束和已结算状态
     */
    function _settleCurrentSeason() internal {
        SeasonInfo storage season = seasons[currentSeasonId];
        season.isActive = false;
        season.isSettled = true;
        emit SeasonSettled(currentSeasonId, block.timestamp);
    }

    /**
     * @dev 内部函数：清理旧赛季数据
     * @notice 保留最近的 MAX_SEASONS_TO_KEEP 个赛季数据，删除更早的赛季
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
     * @notice 由owner或授权者手动结算指定赛季，并计算奖励
     */
    function settleSeason(uint256 seasonId) external onlyOwnerOrAuthorizer {
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
     * @dev 内部函数：检查是否进入新的一天
     * @notice 用于奖励结算时检查新的一天是否开始
     */
    function _checkNewDay() internal {
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        if (arenaReward != address(0)) {
            IArenaReward(arenaReward).checkNewDay();
        }
    }

    /**
     * @dev 内部函数：计算赛季奖励
     * @param seasonId 赛季 ID
     * @notice 调用ArenaReward合约计算指定赛季的奖励
     */
    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        if (arenaReward != address(0)) {
            IArenaReward(arenaReward).calculateSeasonRewards(seasonId);
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
     * @notice 所有者或授权者向当前赛季奖励池添加BNB
     */
    function addRewardToPool() external payable onlyOwnerOrAuthorizer {
        require(msg.value > 0, "ArenaRankingManager: No BNB sent");
        _checkNewDay();
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        if (arenaReward != address(0)) {
            IArenaReward(arenaReward).updateTodayIncomingReward(msg.value);
        }
        seasons[currentSeasonId].rewardPool += msg.value;
    }

    /**
     * @dev 接收 ETH/BNB 的回调函数
     * @notice 接收ETH时自动更新当日收入奖励和当前赛季奖励池
     */
    receive() external payable {
        _checkNewDay();
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        if (arenaReward != address(0)) {
            IArenaReward(arenaReward).updateTodayIncomingReward(msg.value);
        }
    }

    /**
     * @dev 处理未识别调用的回调函数
     * @notice 当调用数据不匹配任何函数时，自动更新当日收入奖励和当前赛季奖励池
     */
    fallback() external payable {
        _checkNewDay();
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        if (arenaReward != address(0)) {
            IArenaReward(arenaReward).updateTodayIncomingReward(msg.value);
        }
    }

    /**
     * @dev 获取当前赛季奖励池
     * @return 当前赛季的奖励池金额（BNB）
     */
    function getCurrentRewardPool() external view returns (uint256) {
        return seasons[currentSeasonId].rewardPool;
    }

    /**
     * @dev 获取当前赛季信息
     * @return seasonId 赛季ID
     * @return startTime 赛季开始时间
     * @return endTime 赛季结束时间
     * @return isActive 赛季是否活跃
     * @return rewardPool 奖励池金额
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
     * @dev 获取指定赛季的奖励数据（供ArenaReward使用）
     * @param seasonId 赛季ID
     * @return rewardPool BNB奖励池
     * @return tokenRewardPool 代币奖励池（返回0，因为当前使用BNB）
     * @return totalPlayers 总玩家数
     */
    function getSeasonRewardData(uint256 seasonId) external view returns (uint256 rewardPool, uint256 tokenRewardPool, uint256 totalPlayers) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRankingManager: Invalid season ID");
        SeasonInfo storage season = seasons[seasonId];
        rewardPool = season.rewardPool;
        tokenRewardPool = season.tokenRewardPool;
        totalPlayers = season.totalPlayers;
    }

    /**
     * @dev 紧急提取 BNB
     * @param amount 提取金额
     * @notice 仅所有者可调用，用于紧急情况下的资金提取
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRankingManager: Amount must be > 0");
        require(amount <= address(this).balance, "ArenaRankingManager: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaRankingManager: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币
     * @param amount 提取金额
     * @notice 仅所有者可调用，用于紧急情况下的代币提取
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRankingManager: Amount must be > 0");
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "ArenaRankingManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "ArenaRankingManager: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 充值挑战次数
     * @notice 玩家使用代币充值挑战次数（RECHARGE_COST代币获得RECHARGE_ATTEMPTS次挑战）
     */
    function rechargeChallengeAttempts() external nonReentrant whenNotPaused {
        address arenaPlayer = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayer != address(0), "ArenaRankingManager: ArenaPlayer not set");
        IArenaPlayer(arenaPlayer).rechargeChallengeAttempts();
    }

    /**
     * @dev 质押 NFT
     * @param tokenIds 要质押的 NFT ID 数组（1-6 个）
     * @notice 将玩家的NFT质押到竞技场系统，用于战斗队伍配置
     */
    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        address arenaPlayer = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayer != address(0), "ArenaRankingManager: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRankingManager: Invalid token count");
        IArenaPlayer(arenaPlayer).stakeNFTs(tokenIds);
    }

    /**
     * @dev 解除质押 NFT
     * @param tokenIds 要解除质押的 NFT ID 数组（1-6 个）
     * @notice 将已质押的NFT从竞技场系统解除质押
     */
    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        address arenaPlayer = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayer != address(0), "ArenaRankingManager: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRankingManager: Invalid token count");
        IArenaPlayer(arenaPlayer).unstakeNFTs(tokenIds);
    }

    /**
     * @dev 清除战斗队伍
     * @notice 清除玩家当前设置的战斗队伍（代理调用ArenaPlayer）
     */
    function clearBattleTeam() external nonReentrant whenNotPaused {
        address arenaPlayer = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayer != address(0), "ArenaRankingManager: ArenaPlayer not set");
        IArenaPlayer(arenaPlayer).clearBattleTeam();
    }

    /**
     * @dev 内部函数：检查玩家是否设置了战斗队伍
     * @param player 玩家地址
     * @return 是否有已设置的战斗队伍
     * @notice 从ArenaPlayer合约获取玩家的战斗队伍信息
     */
    function _hasBattleTeam(address player) internal view returns (bool) {
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        if (arenaPlayerContract == address(0)) {
            return false;
        }
        uint256[] memory team = IArenaPlayer(arenaPlayerContract).getPlayerBattleTeam(player);
        return team.length > 0 && team[0] > 0;
    }

    /**
     * @dev 内部函数：获取玩家的战斗队伍
     * @param player 玩家地址
     * @return 战斗队伍（6个NFT ID数组）
     * @notice 从ArenaPlayer合约获取玩家的战斗队伍信息
     */
    function _getBattleTeam(address player) internal view returns (uint256[6] memory) {
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer contract not set");
        uint256[] memory team = IArenaPlayer(arenaPlayerContract).getPlayerBattleTeam(player);
        uint256[6] memory fixedTeam;
        for (uint256 i = 0; i < team.length && i < 6; i++) {
            fixedTeam[i] = team[i];
        }
        return fixedTeam;
    }

    /**
     * @dev 每次胜利的基础奖励（积分）
     * @notice 玩家每次战斗胜利获得的基础积分奖励
     */
    uint256 public baseRewardPerWin = 100;

    /**
     * @dev 设置每次胜利的基础奖励
     * @param _reward 奖励积分
     * @notice 仅所有者可设置每次胜利获得的基础积分
     */
    function setBaseRewardPerWin(uint256 _reward) external onlyOwner {
        baseRewardPerWin = _reward;
    }
}

// IArenaPlayer interface 已从 NFTInterface.sol 导入，无需重复定义
