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
 * 核心职责�?
 * 1. 战斗执行：处�?PvE（模拟玩家）�?PvP（真实玩家）战斗
 * 2. 赛季管理：跟踪赛季状态、玩家积分、排名等
 * 3. 奖励计算：根据战斗结果分配奖�?
 * 4. 排行榜更新：战斗结束后更�?ArenaLeaderboard
 * 
 * 战斗类型�?
 * - PvE（Mock Battle）：挑战模拟玩家，不涉及真实对手
 * - PvP（Real Battle）：挑战真实玩家，需要双方设置战斗队�?
 * 
 * 与其他合约的交互�?
 * - Battle：调用核心战斗逻辑
 * - ArenaLeaderboard：更新排行榜数据
 * - ArenaPlayer：管理玩�?NFT 质押
 * - RankingContract：发起战斗请�?
 * 
 * 安全机制�?
 * - ReentrancyGuard：防止重入攻�?
 * - Pausable：可暂停所有操�?
 * - 战斗冷却�?0秒冷却时间防止刷战斗
 * - NFT 锁定：战斗期间锁�?NFT 防止转移
 * 
 * 权限控制�?
 * - onlyOwner：设置合约地址、配置参�?
 * - onlyAuthorized：发起战斗调�?
 */
contract ArenaBattle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 竞技场排名管理合约地址
     */
    address public arenaRankingManagerContract;
    /**
     * @dev 战斗核心合约地址
     */
    address public battleContract;
    /**
     * @dev NFT 合约地址
     */
    address public nftContract;
    /**
     * @dev 竞技场玩家合约地址
     */
    address public arenaPlayerContract;
    /**
     * @dev 竞技场排行榜合约地址
     */
    address public arenaLeaderboardContract;
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    
    /**
     * @dev 每次胜利的基础奖励�?.1 BNB�?
     */
    uint256 public baseRewardPerWin = 100000000000000000; // 0.1 BNB
    
    /**
     * @dev 战斗冷却时间（秒�?
     */
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    /**
     * @dev 最大模拟玩家排�?
     */
    uint256 public constant MAX_MOCK_RANKING = 100;
    /**
     * @dev 队伍大小（NFT 数量�?
     */
    uint256 public constant TEAM_SIZE = 6;
    /**
     * @dev 模拟玩家 ID 偏移�?
     */
    uint256 public constant MOCK_ID_OFFSET = 10000;
    /**
     * @dev 模拟玩家 ID 乘数
     */
    uint256 public constant MOCK_ID_MULTIPLIER = 1000;
    /**
     * @dev 每日挑战次数
     */
    uint256 public constant DAILY_ATTEMPTS = 5;
    /**
     * @dev 最大模拟玩家数�?
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
     * @dev 玩家战斗 ID 计数�?
     */
    mapping(address => uint256) public battleIdCounter;
    /**
     * @dev 玩家上次战斗时间
     */
    mapping(address => uint256) public lastBattleTime;
    
    /**
     * @dev 玩家记录结构�?
     * @param score 玩家积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param draws 平局次数
     * @param seasonId 当前赛季 ID
     * @param lastBattleTime 上次战斗时间
     * @param lastResetTime 上次重置时间
     * @param remainingAttempts 剩余挑战次数
     * @param battleTeam 战斗队伍（NFT ID 数组�?
     * @param hasTeam 是否已设置战斗队�?
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
        uint256[6] battleTeam;
        bool hasTeam;
    }
    
    /**
     * @dev 赛季信息结构�?
     * @param startTime 赛季开始时�?
     * @param endTime 赛季结束时间
     * @param isActive 赛季是否进行�?
     * @param isSettled 赛季是否已结�?
     * @param totalPlayers 赛季总玩家数
     * @param rewardPool 奖励池金�?
     */
    struct SeasonInfo {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isSettled;
        uint256 totalPlayers;
        uint256 rewardPool;
    }
    
    /**
     * @dev 当前赛季 ID
     */
    uint256 public currentSeasonId;
    /**
     * @dev 赛季信息映射
     */
    mapping(uint256 => SeasonInfo) public seasons;
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
     * @param score 新分�?
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
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == arenaRankingManagerContract, "ArenaBattle: Not authorized");
        _;
    }

    /**
     * @dev 初始化函�?
     * @param _arenaRankingManagerContract 竞技场排名管理合约地址
     * @param _battleContract 战斗核心合约地址
     * @param _nftContract NFT 合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _arenaRankingManagerContract, address _battleContract, address _nftContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        arenaRankingManagerContract = _arenaRankingManagerContract;
        battleContract = _battleContract;
        nftContract = _nftContract;
        authorizer = _authorizer;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaBattle: Invalid authorizer address");
        authorizer = _authorizer;
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

    function setArenaRankingManagerContract(address _arenaRankingManagerContract) external onlyOwnerOrAuthorizer {
        arenaRankingManagerContract = _arenaRankingManagerContract;
    }

    function setBattleContract(address _battleContract) external onlyOwnerOrAuthorizer {
        battleContract = _battleContract;
    }

    function setNFTContract(address _nftContract) external onlyOwnerOrAuthorizer {
        nftContract = _nftContract;
    }

    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external onlyOwnerOrAuthorizer {
        arenaLeaderboardContract = _arenaLeaderboardContract;
    }

    function challengeMockPlayer(uint256 mockIndex) external nonReentrant whenNotPaused returns (bool, uint256) {
        SeasonInfo storage currentSeason = seasons[currentSeasonId];
        require(currentSeason.isActive, "ArenaBattle: Season not active");
        
        PlayerRecord storage record = players[msg.sender];
        _checkAndResetAttempts(msg.sender);
        require(record.remainingAttempts > 0, "ArenaBattle: No remaining attempts");
        
        record.remainingAttempts--;
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
        SeasonInfo storage currentSeason = seasons[currentSeasonId];
        require(currentSeason.isActive, "ArenaBattle: Season not active");
        require(challengedPlayer != address(0), "ArenaBattle: Invalid challenged player");
        require(challengedPlayer != msg.sender, "ArenaBattle: Cannot challenge self");
        
        PlayerRecord storage challengerRecord = players[msg.sender];
        PlayerRecord storage challengedRecord = players[challengedPlayer];
        
        _checkAndResetAttempts(msg.sender);
        require(challengerRecord.remainingAttempts > 0, "ArenaBattle: No remaining attempts");
        
        challengerRecord.remainingAttempts--;
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

    function _executeMockBattle(uint256 mockIndex) internal view returns (bool) {
        // 使用更安全的随机数生成，结合多个因素
        uint256 random = uint256(keccak256(abi.encodePacked(msg.sender, mockIndex, block.timestamp, block.number, tx.gasprice, block.prevrandao)));
        // 根据mockIndex调整胜率，mockIndex越低（排名越高），胜率越�?
        uint256 baseChance = 45; // 基础45%胜率
        if (mockIndex < 10) {
            baseChance = 30; // �?0名只�?0%胜率
        } else if (mockIndex < 30) {
            baseChance = 40;
        } else if (mockIndex < 50) {
            baseChance = 50;
        } else {
            baseChance = 60; // 排名靠后的模拟玩家更容易战胜
        }
        return random % 100 < baseChance;
    }

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

    function _updateScore(address player, bool isWinner) internal {
        SeasonInfo storage currentSeason = seasons[currentSeasonId];
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
            record.score += 25;
            record.wins++;
        } else {
            // 修复：使�?>= 确保当分数正好为25时也能正确扣�?
            if (record.score >= 25) record.score -= 25;
            else record.score = 0;
            record.losses++;
        }
        record.lastBattleTime = block.timestamp;

        if (arenaLeaderboardContract != address(0)) {
            IArenaLeaderboard(arenaLeaderboardContract).updateRanking(player, record.score, currentSeasonId);
        }
        emit ScoreUpdated(player, record.score, currentSeasonId);
    }

    function _checkAndResetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        if (block.timestamp > record.lastResetTime + 24 hours) {
            record.lastResetTime = block.timestamp;
            record.remainingAttempts = DAILY_ATTEMPTS;
        }
    }

    function _isMockPlayer(address player) internal pure returns (bool) {
        uint256 playerAddress = uint256(uint160(player));
        uint256 baseAddress = uint256(uint160(MOCK_PLAYER_BASE));
        uint256 maxAddress = baseAddress + MAX_MOCK_PLAYERS_COUNT;
        return playerAddress >= baseAddress && playerAddress < maxAddress;
    }

    function getRemainingAttempts(address player) external view returns (uint256) {
        PlayerRecord storage p = players[player];
        if (block.timestamp > p.lastResetTime + 24 hours) {
            return DAILY_ATTEMPTS;
        }
        return p.remainingAttempts;
    }

    function getPlayerRecord(address player) external view returns (uint256 score, uint256 wins, uint256 losses, uint256 seasonId) {
        PlayerRecord storage p = players[player];
        return (p.score, p.wins, p.losses, p.seasonId);
    }

    function executeMockBattle(
        uint256[6] calldata playerTeam,
        uint256 mockIndex
    ) external onlyOwnerOrAuthorizer nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
        require(battleContract != address(0), "ArenaBattle: Battle contract not set");
        require(nftContract != address(0), "ArenaBattle: NFT contract not set");
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

    function executeRealBattle(
        address challengedPlayer,
        uint256[6] calldata playerTeam,
        uint256[6] calldata challengedTeam
    ) external onlyOwnerOrAuthorizer nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
        require(battleContract != address(0), "ArenaBattle: Battle contract not set");
        require(nftContract != address(0), "ArenaBattle: NFT contract not set");
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

    function _validateTeam(uint256[6] memory team) internal view {
        require(nftContract != address(0), "ArenaBattle: NFT contract not set");
        // 轻量校验：仅检�?tokenId > 0（ArenaRanking会做更深层的所有者验�?
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
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                uint256 level = INFTMint(nftContract).tokenLevel(team[i]);
                // 基础战力 = level * 100 + level * level * 2（高等级加成�?
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

    function getLastBattleTime(address player) external view returns (uint256) {
        return lastBattleTime[player];
    }

    function simulateBattle(uint256[6] memory playerTeam, uint256 mockIndex) external view returns (bool) {
        uint256 playerPower = _calculateTeamPower(playerTeam);
        uint256 mockPower = (mockIndex % 1000) + 500;
        return playerPower > mockPower;
    }
}
