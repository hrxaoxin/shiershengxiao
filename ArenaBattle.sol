// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";

contract ArenaBattle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    address public rankingContract;
    address public battleContract;
    address public nftContract;
    address public arenaPlayerContract;
    address public arenaLeaderboardContract;
    address public authorizer;
    
    uint256 public baseRewardPerWin = 100000000000000000; // 0.1 BNB
    
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    uint256 public constant MAX_MOCK_RANKING = 100;
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant MOCK_ID_OFFSET = 10000;
    uint256 public constant MOCK_ID_MULTIPLIER = 1000;
    uint256 public constant DAILY_ATTEMPTS = 5;
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;
    address public constant MOCK_PLAYER_BASE = address(0x1000000000000000000000000000000000000000);
    
    mapping(uint256 => uint256) public nftBattleLocked;
    mapping(address => uint256) public battleIdCounter;
    mapping(address => uint256) public lastBattleTime;
    
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
    
    struct SeasonInfo {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isSettled;
        uint256 totalPlayers;
        uint256 rewardPool;
    }
    
    uint256 public currentSeasonId;
    mapping(uint256 => SeasonInfo) public seasons;
    mapping(address => PlayerRecord) public players;
    
    event BattleExecuted(
        address indexed challenger,
        address indexed challenged,
        bool isVictory,
        uint256 battleId
    );
    
    event ScoreUpdated(address indexed player, uint256 score, uint256 seasonId);
    
    event BattleEnded(address indexed winner, address indexed loser, uint256 battleId);
    
    event SeasonSettled(uint256 seasonId, uint256 timestamp);

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == rankingContract, "ArenaBattle: Not authorized");
        _;
    }

    function initialize(address _rankingContract, address _battleContract, address _nftContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        rankingContract = _rankingContract;
        battleContract = _battleContract;
        nftContract = _nftContract;
        authorizer = _authorizer;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaBattle: Invalid authorizer address");
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRankingContract(address _rankingContract) external onlyAuthorized {
        rankingContract = _rankingContract;
    }

    function setBattleContract(address _battleContract) external onlyAuthorized {
        battleContract = _battleContract;
    }

    function setNFTContract(address _nftContract) external onlyAuthorized {
        nftContract = _nftContract;
    }

    function setArenaLeaderboardContract(address _arenaLeaderboardContract) external onlyAuthorized {
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
        uint256 random = uint256(keccak256(abi.encodePacked(msg.sender, mockIndex, block.timestamp, block.number, tx.gasprice)));
        return random % 100 < 55;
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
            if (record.score > 25) record.score -= 25;
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
    ) external nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
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
    ) external nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
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
        // 轻量校验：仅检查 tokenId > 0（ArenaRanking会做更深层的所有者验证
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
                // 基础战力 = level * 100 + level * level * 2（高等级加成）
                totalPower += level * 100 + level * level * 2;
            }
        }
        return totalPower;
    }

    function lockNFTsForBattle(uint256[6] calldata team, uint256 battleId) external onlyAuthorized {
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                nftBattleLocked[team[i]] = battleId;
            }
        }
    }

    function unlockNFTsFromBattle(uint256[6] memory team) external onlyAuthorized {
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
