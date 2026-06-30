// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title ArenaBattle
 * @dev 竞技场战斗合约，执行 NFT 之间的战斗逻辑
 * 
 * 核心职责：
 * 1. 战斗执行：处理 PvE（模拟玩家）和 PvP（真实玩家）战斗
 * 2. 赛季管理：跟踪赛季状态、玩家积分、排名等
 * 3. 奖励计算：根据战斗结果分配奖励
 * 4. 排行榜更新：战斗结束后更新 ArenaLeaderboard
 * 
 * 战斗类型：
 * - PvE（Mock Battle）：挑战模拟玩家，不涉及真实对手
 * - PvP（Real Battle）：挑战真实玩家，需要双方设置战斗队伍
 * 
 * 与其他合约的交互：
 * - Battle：调用核心战斗逻辑
 * - ArenaLeaderboard：更新排行榜数据
 * - ArenaPlayer：管理玩家 NFT 质押
 * - RankingContract：发起战斗请求
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - 战斗冷却：30秒冷却时间防止刷战斗
 * - NFT 锁定：战斗期间锁定 NFT 防止转移
 * 
 * 权限控制：
 * - onlyOwner：设置合约地址、配置参数
 * - onlyAuthorized：发起战斗调用
 */
contract ArenaBattle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    
    /**
     * @dev 战斗冷却时间（秒）
     */
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    /**
     * @dev 最大模拟玩家排名
     */
    uint256 public constant MAX_MOCK_RANKING = 100;
    /**
     * @dev 队伍大小（NFT 数量）
     */
    uint256 public constant TEAM_SIZE = 6;
    /**
     * @dev 模拟玩家 ID 偏移量
     */
    uint256 public constant MOCK_ID_OFFSET = 10000;
    /**
     * @dev 模拟玩家 ID 乘数
     */
    uint256 public constant MOCK_ID_MULTIPLIER = 1000;
    /**
     * @dev 最大模拟玩家数量
     */
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;
    /**
     * @dev 模拟玩家基础地址
     */
    address public constant MOCK_PLAYER_BASE = address(0x1000000000000000000000000000000000000000);
    
    /**
     * @dev NFT 战斗锁定映射
     * tokenId => lockEndTime
     */
    mapping(uint256 => uint256) public nftBattleLocked;
    /**
     * @dev 玩家战斗 ID 计数器
     */
    mapping(address => uint256) public battleIdCounter;
    /**
     * @dev 玩家上次战斗时间
     */
    mapping(address => uint256) public lastBattleTime;
    
    /**
     * @dev 玩家记录结构体
     * @param score 玩家积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param draws 平局次数
     * @param seasonId 当前赛季 ID
     * @param lastBattleTime 上次战斗时间
     * @param lastResetTime 上次重置时间
     * @param remainingAttempts 剩余挑战次数
     */
    struct PlayerRecord {
        uint256 score;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 seasonId;
        uint256 lastBattleTime;
        uint256 lastResetTime;
        uint256 remainingAttempts;
    }
    
    /**
     * @dev 玩家记录映射
     */
    mapping(address => PlayerRecord) public players;
    
    /**
     * @dev 战斗执行事件
     * @param challenger 挑战者地址
     * @param challenged 被挑战者地址
     * @param isVictory 是否胜利
     * @param battleId 战斗 ID
     */
    event BattleExecuted(
        address indexed challenger,
        address indexed challenged,
        bool isVictory,
        uint256 battleId
    );
    
    /**
     * @dev 分数更新事件
     * @param player 玩家地址
     * @param score 新分数
     * @param seasonId 赛季 ID
     */
    event ScoreUpdated(address indexed player, uint256 score, uint256 seasonId);
    
    /**
     * @dev 战斗结束事件
     * @param winner 胜利者地址
     * @param loser 失败者地址
     * @param battleId 战斗 ID
     */
    event BattleEnded(address indexed winner, address indexed loser, uint256 battleId);
    
    /**
     * @dev 赛季结算事件
     * @param seasonId 赛季 ID
     * @param timestamp 结算时间
     */
    event SeasonSettled(uint256 seasonId, uint256 timestamp);

    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效，再进行系统合约验证
        require(authorizer != address(0), "ArenaBattle: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaBattle: Not authorized");
        _;
    }

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(
        address _authorizerAddress
    ) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaBattle: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev UUPS 升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 挑战模拟玩家（PvE战斗）
     * @param mockIndex 模拟玩家索引（0-99对应排名1-100）
     * @return isVictory 是否胜利, battleId 战斗ID
     * @notice 玩家挑战模拟玩家，胜利获得积分，失败扣除积分
     */
    function challengeMockPlayer(uint256 mockIndex) external nonReentrant whenNotPaused returns (bool, uint256) {
        _checkSeasonActive();
        
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayerContract != address(0), "ArenaBattle: Player contract not set");
        
        IArenaPlayer(arenaPlayerContract).decrementAttempts(msg.sender);
        
        require(_hasBattleTeam(msg.sender), "ArenaBattle: No battle team set");
        
        PlayerRecord storage record = players[msg.sender];
        record.lastBattleTime = block.timestamp;
        
        bool isVictory = _executeMockBattle(mockIndex);
        
        if (isVictory) {
            _updateScore(msg.sender, true);
        } else {
            _updateScore(msg.sender, false);
        }
        
        emit BattleExecuted(msg.sender, address(0), isVictory, battleIdCounter[msg.sender]);
        return (isVictory, 0);
    }

    function challengeRealPlayer(address challengedPlayer) external nonReentrant whenNotPaused returns (bool, uint256) {
        _checkSeasonActive();
        require(challengedPlayer != address(0), "ArenaBattle: Invalid challenged player");
        require(challengedPlayer != msg.sender, "ArenaBattle: Cannot challenge self");
        
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayerContract != address(0), "ArenaBattle: Player contract not set");
        
        IArenaPlayer(arenaPlayerContract).decrementAttempts(msg.sender);
        
        require(_hasBattleTeam(msg.sender), "ArenaBattle: Challenger has no battle team");
        require(_hasBattleTeam(challengedPlayer), "ArenaBattle: Challenged has no battle team");
        
        PlayerRecord storage challengerRecord = players[msg.sender];
        PlayerRecord storage challengedRecord = players[challengedPlayer];
        
        challengerRecord.lastBattleTime = block.timestamp;
        challengedRecord.lastBattleTime = block.timestamp;
        
        bool challengerVictory = _executeRealBattle(msg.sender, challengedPlayer);
        
        if (challengerVictory) {
            _updateScore(msg.sender, true);
            _updateScore(challengedPlayer, false);
        } else {
            _updateScore(msg.sender, false);
            _updateScore(challengedPlayer, true);
        }
        
        emit BattleExecuted(msg.sender, challengedPlayer, challengerVictory, battleIdCounter[msg.sender]);
        return (challengerVictory, 0);
    }

    function _checkSeasonActive() internal view {
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        require(arenaRankingManager != address(0), "ArenaBattle: Ranking manager not set");
        require(IArenaRanking(arenaRankingManager).currentSeasonId() > 0, "ArenaBattle: Season not active");
    }

    function _executeMockBattle(uint256 mockIndex) internal view returns (bool) {
        // 使用更安全的随机数生成，结合多个因素
        uint256 random = uint256(keccak256(abi.encodePacked(msg.sender, mockIndex, block.timestamp, block.number, tx.gasprice, block.prevrandao)));
        // 根据mockIndex调整胜率，mockIndex越低（排名越高），胜率越低
        uint256 baseChance = 45; // 基础45%胜率
        if (mockIndex < 10) {
            baseChance = 30; // 前10名只有30%胜率
        } else if (mockIndex < 30) {
            baseChance = 40;
        } else if (mockIndex < 50) {
            baseChance = 50;
        } else {
            baseChance = 60; // 排名靠后的模拟玩家更容易战胜
        }
        return random % 100 < baseChance;
    }

    /**
     * @dev 内部函数：执行真实战斗（PvP）
     * @param challenger 挑战者地址
     * @param challenged 被挑战者地址
     * @return 挑战者是否胜利
     * @notice 根据双方积分差距调整胜率，积分高者胜率更高
     */
    function _executeRealBattle(address challenger, address challenged) internal view returns (bool) {
        PlayerRecord storage challengerRecord = players[challenger];
        PlayerRecord storage challengedRecord = players[challenged];
        
        uint256 challengerScore = challengerRecord.score;
        uint256 challengedScore = challengedRecord.score;
        
        uint256 random = uint256(keccak256(abi.encodePacked(challenger, challenged, block.timestamp, block.number)));
        uint256 roll = random % 100;
        
        uint256 challengerChance = 50;
        if (challengerScore > challengedScore) {
            challengerChance += (challengerScore - challengedScore) / 100;
        } else if (challengedScore > challengerScore) {
            challengerChance -= (challengedScore - challengerScore) / 100;
        }
        
        if (challengerChance > 90) challengerChance = 90;
        if (challengerChance < 10) challengerChance = 10;
        
        return roll < challengerChance;
    }

    /**
     * @dev 内部函数：更新玩家分数
     * @param player 玩家地址
     * @param isWinner 是否获胜
     * @notice 胜利加25分，失败扣25分（最低0分），首次战斗初始化玩家数据
     */
    function _updateScore(address player, bool isWinner) internal {
        if (_isMockPlayer(player)) {
            return;
        }
        
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        
        PlayerRecord storage record = players[player];
        
        if (record.seasonId != currentSeasonId) {
            record.seasonId = currentSeasonId;
            record.score = 1000;
            record.wins = 0;
            record.losses = 0;
            record.draws = 0;
            record.lastBattleTime = block.timestamp;
            record.lastResetTime = block.timestamp;
            record.remainingAttempts = 3;
        }

        if (isWinner) {
            record.score += 25;
            record.wins++;
        } else {
            if (record.score >= 25) record.score -= 25;
            else record.score = 0;
            record.losses++;
        }
        record.lastBattleTime = block.timestamp;

        address arenaLeaderboard = IAuthorizer(authorizer).getArenaLeaderboard();
        if (arenaLeaderboard != address(0)) {
            IArenaLeaderboard(arenaLeaderboard).updateRanking(player, record.score, currentSeasonId);
        }
        emit ScoreUpdated(player, record.score, currentSeasonId);
    }

    function _isMockPlayer(address player) internal pure returns (bool) {
        uint256 playerAddress = uint256(uint160(player));
        uint256 baseAddress = uint256(uint160(MOCK_PLAYER_BASE));
        uint256 maxAddress = baseAddress + MAX_MOCK_PLAYERS_COUNT;
        return playerAddress >= baseAddress && playerAddress < maxAddress;
    }

    function getRemainingAttempts(address player) external view returns (uint256) {
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        require(arenaPlayerContract != address(0), "ArenaBattle: Player contract not set");
        return IArenaPlayer(arenaPlayerContract).getRemainingAttempts(player);
    }

    /**
     * @dev 获取玩家战斗记录
     * @param player 玩家地址
     * @return score 积分, wins 胜利次数, losses 失败次数, seasonId 赛季 ID
     */
    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        PlayerRecord memory p = players[player];
        return (p.score, p.wins, p.losses, p.seasonId);
    }

    /**
     * @dev 执行模拟战斗（完整版）
     * @param playerTeam 玩家队伍（6个NFT ID）
     * @param mockIndex 模拟玩家索引
     * @return success_ 是否成功, winner 胜利方(1=玩家,0=模拟), battleId 战斗ID
     * @notice 仅限owner或authorizer调用，执行完整的NFT战斗逻辑
     */
    function executeMockBattle(
        uint256[6] calldata playerTeam,
        uint256 mockIndex
    ) external onlyOwnerOrAuthorizer nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
        address battleContract = IAuthorizer(authorizer).getBattle();
        require(battleContract != address(0), "ArenaBattle: Battle contract not set");
        require(mockIndex < MAX_MOCK_RANKING, "ArenaBattle: Invalid mock player index");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaBattle: Battle cooldown");

        battleId = ++battleIdCounter[msg.sender];
        lastBattleTime[msg.sender] = block.timestamp;

        _validateTeam(playerTeam);

        uint256[6] memory mockTeam = _generateMockTeam(mockIndex);

        try IBattle(battleContract).challenge(
            playerTeam[0],
            (mockIndex + MOCK_ID_OFFSET) * MOCK_ID_MULTIPLIER,
            playerTeam,
            mockTeam,
            address(0)
        ) returns (bool success, uint256 result) {
            bool victory = result == 1;
            emit BattleExecuted(msg.sender, address(0), victory, battleId);
            return (success, result, battleId);
        } catch {
            revert("ArenaBattle: Battle failed");
        }
    }

    /**
     * @dev 执行真实战斗（PvP完整版）
     * @param challengedPlayer 被挑战的玩家地址
     * @param playerTeam 挑战者队伍（6个NFT ID）
     * @param challengedTeam 被挑战者队伍（6个NFT ID）
     * @return success_ 是否成功, winner 胜利方(1=挑战者,0=被挑战者), battleId 战斗ID
     * @notice 仅限owner或authorizer调用，执行完整的PvP战斗逻辑
     */
    function executeRealBattle(
        address challengedPlayer,
        uint256[6] calldata playerTeam,
        uint256[6] calldata challengedTeam
    ) external onlyOwnerOrAuthorizer nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
        address battleContract = IAuthorizer(authorizer).getBattle();
        require(battleContract != address(0), "ArenaBattle: Battle contract not set");
        require(challengedPlayer != address(0), "ArenaBattle: Invalid challenged player");
        require(challengedPlayer != msg.sender, "ArenaBattle: Cannot challenge self");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaBattle: Battle cooldown");
        require(block.timestamp >= lastBattleTime[challengedPlayer] + BATTLE_COOLDOWN, "ArenaBattle: Target in battle cooldown");

        battleId = ++battleIdCounter[msg.sender];
        lastBattleTime[msg.sender] = block.timestamp;
        lastBattleTime[challengedPlayer] = block.timestamp;

        _validateTeam(playerTeam);
        _validateTeam(challengedTeam);

        try IBattle(battleContract).challenge(
            playerTeam[0],
            challengedTeam[0],
            playerTeam,
            challengedTeam,
            challengedPlayer
        ) returns (bool success, uint256 result) {
            bool victory = result == 1;
            emit BattleExecuted(msg.sender, challengedPlayer, victory, battleId);
            return (success, result, battleId);
        } catch {
            revert("ArenaBattle: Battle failed");
        }
    }

    /**
     * @dev 内部函数：验证队伍有效性
     * @param team 队伍数组（6个NFT ID）
     * @notice 检查所有tokenId是否大于0
     */
    function _validateTeam(uint256[6] memory team) internal view {
        // 轻量校验：仅检查 tokenId > 0（ArenaRanking会做更深层的所有者验证）
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaBattle: Invalid token ID");
        }
    }

    function _generateMockTeam(uint256 mockIndex) internal view returns (uint256[TEAM_SIZE] memory) {
        uint256[TEAM_SIZE] memory team;
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            team[i] = (uint256(keccak256(abi.encodePacked(mockIndex, i, block.timestamp))) % 1000000) + 1;
        }
        return team;
    }

    function _calculateTeamPower(uint256[6] memory team) internal view returns (uint256) {
        uint256 totalPower = 0;
        address nftContract = IAuthorizer(authorizer).getNFTMintCore();
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                uint256 level = INFTMint(nftContract).tokenLevel(team[i]);
                // 基础战力 = level * 100 + level * level * 2（高等级加成）
                totalPower += level * 100 + level * level * 2;
            }
        }
        return totalPower;
    }

    function lockNFTsForBattle(uint256[6] calldata team, uint256 battleId) external onlyOwnerOrAuthorizer {
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                nftBattleLocked[team[i]] = battleId;
            }
        }
    }

    /**
     * @dev 从战斗解锁NFT
     * @param team 队伍数组（6个NFT ID）
     * @notice 仅限owner或authorizer调用，战斗结束后解除锁定
     */
    function unlockNFTsFromBattle(uint256[6] memory team) external onlyOwnerOrAuthorizer {
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                nftBattleLocked[team[i]] = 0;
            }
        }
    }

    function isNFTLocked(uint256 tokenId) external view returns (bool) {
        return nftBattleLocked[tokenId] > 0;
    }

    function getBattleIdCounter(address player) external view returns (uint256) {
        return battleIdCounter[player];
    }

    /**
     * @dev 获取玩家上次战斗时间
     * @param player 玩家地址
     * @return 时间戳
     */
    function getLastBattleTime(address player) external view returns (uint256) {
        return lastBattleTime[player];
    }

    /**
     * @dev 模拟战斗预测
     * @param playerTeam 玩家队伍
     * @param mockIndex 模拟玩家索引
     * @return 是否预测玩家胜利
     * @notice 基于队伍战力对比预测战斗结果
     */
    function simulateBattle(uint256[6] memory playerTeam, uint256 mockIndex) external view returns (bool) {
        uint256 playerPower = _calculateTeamPower(playerTeam);
        uint256 mockPower = (mockIndex % 1000) + 500;
        return playerPower > mockPower;
    }

    /**
     * @dev 内部函数：检查玩家是否设置了战斗队伍
     * 从 ArenaPlayer 合约获取玩家的战斗队伍信息
     * @param player 玩家地址
     * @return 是否有战斗队伍
     */
    function _hasBattleTeam(address player) internal view returns (bool) {
        address arenaPlayerContract = IAuthorizer(authorizer).getArenaPlayer();
        if (arenaPlayerContract == address(0)) {
            return false;
        }
        
        // 调用 ArenaPlayer 的 getPlayerBattleTeam 方法
        uint256[] memory team = IArenaPlayer(arenaPlayerContract).getPlayerBattleTeam(player);
        return team.length > 0 && team[0] > 0;
    }
}

// IArenaPlayer interface 已从 NFTInterface.sol 导入，无需重复定义