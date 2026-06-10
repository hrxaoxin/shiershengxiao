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
    
    function setArenaBattleContract(address _arenaBattleContract) external onlyAuthorized {
        arenaBattleContract = _arenaBattleContract;
    }
    
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
    uint256 public constant MAX_LEADERBOARD_SIZE = 1000;
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
    uint256 public battleIdCounter;

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
    function setBattleContract(address a) external onlyAuthorized {
        require(a != address(0), "ArenaRanking: Invalid battle contract address");
        battleContract = a;
    }
    function setNFTContract(address a) external onlyAuthorized {
        require(a != address(0), "ArenaRanking: Invalid NFT contract address");
        nftContract = a;
    }
    function setTokenContract(address a) external onlyAuthorized {
        require(a != address(0), "ArenaRanking: Invalid token contract address");
        tokenContract = a;
    }
    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external onlyAuthorized {
        arenaLeaderboardContract = _arenaLeaderboardContract;
    }
    function setArenaPlayerContract(address _arenaPlayerContract) external onlyAuthorized {
        arenaPlayerContract = _arenaPlayerContract;
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
        
        (bool success_, ) = arenaBattleContract.call(
            abi.encodeWithSignature("challengeMockPlayer(uint256)", mockIndex)
        );
        require(success_, "ArenaRanking: Challenge mock player failed");
        
        return success_;
    }

    function challengeRealPlayer(address challengedPlayer, uint256[6] calldata playerTeam) external nonReentrant whenNotPaused returns (bool success) {
        require(arenaBattleContract != address(0), "ArenaRanking: ArenaBattle contract not set");
        
        (bool success_, ) = arenaBattleContract.call(
            abi.encodeWithSignature("challengeRealPlayer(address)", challengedPlayer)
        );
        require(success_, "ArenaRanking: Challenge real player failed");
        
        return success_;
    }

    function _clearSeasonData(address player) internal {
        PlayerRecord storage record = players[player];
        
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
        if (arenaLeaderboardContract == address(0)) {
            return seasons[seasonId].totalPlayers;
        }
        return IArenaLeaderboard(arenaLeaderboardContract).getTotalPlayersInSeason(seasonId);
    }
    
    function _getRealPlayerRank(uint256 seasonId, uint256 index) internal view returns (uint256) {
        if (arenaLeaderboardContract == address(0)) {
            return index + 1;
        }
        return index + 1;
    }

    /**
     * @dev 检查是否是Mock玩家（使用特殊地址范围）
     * Mock玩家地址格式为: MOCK_PLAYER_BASE + index (0-999)
     */
    function _isMockPlayer(address player) internal pure returns (bool) {
        uint256 playerAddress = uint256(uint160(player));
        uint256 baseAddress = uint256(uint160(MOCK_PLAYER_BASE));
        uint256 maxAddress = baseAddress + MAX_MOCK_PLAYERS_COUNT;
        // 防止溢出：确保 maxAddress 不会绕回，只有当 baseAddress + MAX_MOCK_PLAYERS_COUNT 未溢出时才进入此范围判断
        if (maxAddress <= baseAddress) {
            return false;
        }
        return playerAddress >= baseAddress && playerAddress < maxAddress;
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
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getPlayerRank(player);
        }
        return 0;
    }

    function getSeasonInfo(uint256 seasonId) external view returns (uint256 startTime, uint256 endTime, bool isActive, bool isSettled, uint256 totalPlayers) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        SeasonInfo memory s = seasons[seasonId];
        return (s.startTime, s.endTime, s.isActive, s.isSettled, s.totalPlayers);
    }

    /**
     * @dev 获取当前赛季信息（返回6个字段）
     */
    function getCurrentSeasonInfo() external view returns (uint256 seasonId, uint256 startTime, uint256 endTime, bool isActive, uint256 totalPlayers, uint256 rewardPool) {
        SeasonInfo storage s = seasons[currentSeasonId];
        return (currentSeasonId, s.startTime, s.endTime, s.isActive, s.totalPlayers, s.rewardPool);
    }

    function getLeaderboard(uint256 seasonId, uint256 limit) external view returns (LeaderboardEntry[] memory) {
        if (arenaLeaderboardContract == address(0)) {
            return new LeaderboardEntry[](0);
        }
        (bool success, bytes memory data) = arenaLeaderboardContract.staticcall(
            abi.encodeWithSignature("getLeaderboard(uint256,uint256)", seasonId, limit)
        );
        require(success, "ArenaRanking: Leaderboard call failed");
        
        uint256 count;
        assembly {
            count := mload(add(data, 32))
        }
        
        LeaderboardEntry[] memory result = new LeaderboardEntry[](count);
        
        uint256 offset = 64;
        for (uint256 i = 0; i < count; i++) {
            address playerAddress;
            uint256 points;
            uint256 wins;
            uint256 losses;
            bool isMock;
            
            assembly {
                playerAddress := mload(add(data, offset))
                points := mload(add(data, add(offset, 32)))
                wins := mload(add(data, add(offset, 64)))
                losses := mload(add(data, add(offset, 96)))
                isMock := mload(add(data, add(offset, 128)))
            }
            
            result[i] = LeaderboardEntry({
                playerAddress: playerAddress,
                points: points,
                wins: wins,
                losses: losses,
                isMock: isMock
            });
            
            offset += 160;
        }
        return result;
    }

    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        PlayerRecord storage p = players[player];
        return (p.score, p.wins, p.losses, p.seasonId);
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

    // ================================================================
    // 缺失函数补充：与 config.js 的 arenaABI 对齐
    // ================================================================

    /**
     * @dev 充值挑战次数
     */
    function rechargeChallengeAttempts() external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRanking: ArenaPlayer not set");
        // 外部调用 arenaPlayer 的 rechargeChallengeAttempts
        (bool success, ) = arenaPlayerContract.call(
            abi.encodeWithSignature("rechargeChallengeAttempts()")
        );
        require(success, "ArenaRanking: rechargeChallengeAttempts failed");
    }

    /**
     * @dev 质押NFT到竞技场（通过 arenaPlayer 执行）
     */
    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRanking: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRanking: Invalid token count");
        // 通过 call 直接调用 arenaPlayer 处理 NFT 质押
        (bool success, ) = arenaPlayerContract.call(
            abi.encodeWithSignature("stakeNFTs(uint256[])", tokenIds)
        );
        require(success, "ArenaRanking: stakeNFTs failed");
    }

    /**
     * @dev 解除竞技场NFT质押（通过 arenaPlayer 执行）
     */
    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRanking: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRanking: Invalid token count");
        (bool success, ) = arenaPlayerContract.call(
            abi.encodeWithSignature("unstakeNFTs(uint256[])", tokenIds)
        );
        require(success, "ArenaRanking: unstakeNFTs failed");
    }

    /**
     * @dev 设置战斗队伍（动态数组版本，与前端 ABI 对齐）
     */
    function setBattleTeam(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(tokenIds.length == 6, "ArenaRanking: Team must have exactly 6 NFTs");
        uint256[6] memory fixedTeam;
        for (uint256 i = 0; i < 6; i++) {
            fixedTeam[i] = tokenIds[i];
        }
        _setBattleTeamInternal(fixedTeam);
    }

    /**
     * @dev 设置战斗队伍（委托 arenaPlayer 执行，作为统一入口）
     */
    function setBattleTeam(uint256[6] calldata tokenIds) external nonReentrant whenNotPaused {
        _setBattleTeamInternal(tokenIds);
    }

    /**
     * @dev 内部函数：设置战斗队伍
     */
    function _setBattleTeamInternal(uint256[6] memory tokenIds) internal {
        for (uint256 i = 0; i < 6; i++) {
            if (tokenIds[i] == 0) continue;
            require(INFTMint(nftContract).ownerOf(tokenIds[i]) == msg.sender, "ArenaRanking: Not owner");
            // 去重校验
            for (uint256 j = i + 1; j < 6; j++) {
                if (tokenIds[j] != 0) {
                    require(tokenIds[j] != tokenIds[i], "ArenaRanking: Duplicate token");
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
     * @dev 领取赛季奖励（由 arenaReward 实际处理）
     */
    /**
     * @dev 领取赛季奖励（无参版本，领取当前赛季）
     */
    function claimSeasonReward() external nonReentrant whenNotPaused {
        _claimSeasonReward(currentSeasonId);
    }

    /**
     * @dev 领取指定赛季奖励（带参数版本）
     */
    function claimSeasonReward(uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        return _claimSeasonReward(seasonId);
    }

    /**
     * @dev 内部函数：领取赛季奖励
     */
    function _claimSeasonReward(uint256 seasonId) internal returns (uint256) {
        require(seasonId > 0 && seasonId <= currentSeasonId, "ArenaRanking: Invalid season");
        require(!seasonRewardsClaimed[seasonId][msg.sender], "ArenaRanking: Already claimed");
        require(arenaRewardContract != address(0), "ArenaRanking: ArenaReward not set");
        uint256 amount = IArenaReward(arenaRewardContract).claimSeasonReward(msg.sender, seasonId);
        seasonRewardsClaimed[seasonId][msg.sender] = true;
        emit RewardClaimed(msg.sender, amount, seasonId);
        return amount;
    }

    /**
     * @dev 获取玩家当前赛季排名（此函数用于保持与原始实现一致）
     */

    /**
     * @dev 获取Mock玩家排名
     */
    function getMockPlayerRank(address player) external view returns (uint256) {
        if (!_isMockPlayer(player)) return 0;
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getMockPlayerRank(player);
        }
        return 0;
    }

    /**
     * @dev 获取排行榜（仅 limit 参数版本）
     */
    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory) {
        return this.getLeaderboard(currentSeasonId, limit);
    }

    /**
     * @dev 获取分页排行榜
     */
    function getLeaderboardByPage(uint256 seasonId, uint256 page, uint256 pageSize) external view returns (LeaderboardEntry[] memory entries, uint256 totalPages, uint256 totalPlayers) {
        if (arenaLeaderboardContract == address(0)) {
            return (new LeaderboardEntry[](0), 0, 0);
        }
        (bool success, bytes memory data) = arenaLeaderboardContract.staticcall(
            abi.encodeWithSignature("getLeaderboardByPage(uint256,uint256,uint256)", seasonId, page, pageSize)
        );
        require(success, "ArenaRanking: LeaderboardByPage call failed");
        
        uint256 count;
        assembly {
            count := mload(add(data, 32))
        }
        
        entries = new LeaderboardEntry[](count);
        
        uint256 offset = 64;
        for (uint256 i = 0; i < count; i++) {
            address playerAddress;
            uint256 points;
            uint256 wins;
            uint256 losses;
            bool isMock;
            
            assembly {
                playerAddress := mload(add(data, offset))
                points := mload(add(data, add(offset, 32)))
                wins := mload(add(data, add(offset, 64)))
                losses := mload(add(data, add(offset, 96)))
                isMock := mload(add(data, add(offset, 128)))
            }
            
            entries[i] = LeaderboardEntry({
                playerAddress: playerAddress,
                points: points,
                wins: wins,
                losses: losses,
                isMock: isMock
            });
            
            offset += 160;
        }
        
        assembly {
            totalPages := mload(add(data, offset))
            totalPlayers := mload(add(data, add(offset, 32)))
        }
    }

    /**
     * @dev 获取排行榜总页数
     */
    function getLeaderboardPageCount(uint256 seasonId, uint256 pageSize) external view returns (uint256) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getLeaderboardPageCount(seasonId, pageSize);
        }
        return 0;
    }

    /**
     * @dev 获取Top N玩家
     */
    function getTopPlayers(uint256 seasonId, uint256 count) external view returns (address[] memory playerAddrs, uint256[] memory scores) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getTopPlayers(seasonId, count);
        }
        return (new address[](0), new uint256[](0));
    }

    /**
     * @dev 获取玩家赛季奖励余额（当前赛季）
     */
    function getSeasonReward(address player) external view returns (uint256) {
        return playerSeasonRewards[currentSeasonId][player];
    }

    /**
     * @dev 获取玩家指定赛季的奖励余额（与 ABI 定义对齐）
     */
    function getSeasonReward(address player, uint256 seasonId) external view returns (uint256) {
        return playerSeasonRewards[seasonId][player];
    }

    /**
     * @dev 获取最近 N 个赛季信息
     */
    function getRecentSeasons(uint256 count) external view returns (SeasonInfo[] memory) {
        if (count == 0 || count > currentSeasonId) count = currentSeasonId;
        SeasonInfo[] memory result = new SeasonInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = seasons[currentSeasonId - count + i + 1];
        }
        return result;
    }

    /**
     * @dev 获取赛季总玩家数
     */
    function getTotalPlayersInSeason(uint256 seasonId) external view returns (uint256) {
        return seasons[seasonId].totalPlayers;
    }

    /**
     * @dev 获取玩家剩余挑战次数
     */
    function getRemainingAttempts(address player) external view returns (uint256) {
        PlayerRecord storage p = players[player];
        if (block.timestamp > p.lastResetTime + 24 hours) {
            return DAILY_ATTEMPTS;
        }
        return p.remainingAttempts;
    }

    /**
     * @dev 获取玩家战斗队伍（与 IArenaPlayer 格式一致，返回数组）
     */
    function getPlayerBattleTeam(address player) external view returns (uint256[] memory) {
        PlayerRecord storage p = players[player];
        uint256[] memory team = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            team[i] = p.battleTeam[i];
        }
        return team;
    }

    /**
     * @dev 获取每场基础获胜奖励（代币数量）
     */
    uint256 public baseRewardPerWin = 100;

    function setBaseRewardPerWin(uint256 _reward) external onlyOwner {
        baseRewardPerWin = _reward;
    }

    /**
     * @dev 获取战斗ID计数器（用于前端展示）
     */
    function getBattleIdCounter() external view returns (uint256) {
        return battleIdCounter;
    }

    /**
     * @dev 获取某玩家上次战斗时间
     */
    function getLastBattleTime(address player) external view returns (uint256) {
        return players[player].lastBattleTime;
    }

    /**
     * @dev 充值成本（与 arenaPlayer 对齐）
     */
    function rechargeCost() external pure returns (uint256) {
        return 888;
    }

    function setArenaRewardContract(address _arenaRewardContract) external onlyAuthorized {
        arenaRewardContract = _arenaRewardContract;
    }

    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).calculateSeasonRewards(seasonId);
        }
    }

    // ================================================================
    // 额外的查询函数 - 与 config.js 的 ABI 定义对齐
    // ================================================================

    /**
     * @dev 检查玩家在某个赛季的奖励是否已领取
     */
    function isSeasonRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        return seasonRewardsClaimed[seasonId][player];
    }

    /**
     * @dev 获取玩家在某个赛季的完整统计数据
     */
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

    /**
     * @dev 按排名范围获取玩家列表
     */
    function getPlayersByRankRange(uint256 seasonId, uint256 startRank, uint256 endRank) external view returns (
        address[] memory playerAddrs,
        uint256[] memory scores
    ) {
        if (arenaLeaderboardContract != address(0)) {
            return IArenaLeaderboard(arenaLeaderboardContract).getPlayersByRankRange(seasonId, startRank, endRank);
        }
        return (new address[](0), new uint256[](0));
    }

    /**
     * @dev 获取玩家挑战状态（剩余次数、上次战斗时间、是否有战队）
     */
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
}