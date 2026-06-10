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

contract ArenaRankingManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
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
        uint256[6] battleTeam;
        bool hasTeam;
        uint256 seasonId;
    }

    struct MockPlayerInfo {
        uint256[6] team;
        uint256 score;
        uint256 level;
        uint256 growth;
        uint256[] elementCounts;
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
        uint256 tokenRewardPool;
        uint256 pendingRewards;
    }

    mapping(address => PlayerRecord) public players;
    mapping(uint256 => SeasonInfo) public seasons;
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
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
    
    uint8 public arenaMode = 1;
    uint8 public modeControlType = 0;
    uint8 public lastSeasonMode = 1;
    address public mockRewardRecipient;
    
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
    address public constant MOCK_PLAYER_BASE = address(0x000000000000000000000000000000000000dEaD);
    uint256 public constant MAX_MOCK_PLAYERS_COUNT = 1000;
    
    uint256 public maxRechargeAttempts = type(uint256).max;
    uint256 public seasonRewardRate;
    mapping(address => uint256) public lastBattleTime;
    mapping(address => uint256) public rechargeCount;
    uint256 public battleIdCounter;

    event RechargeLimitUpdated(uint256 newLimit);
    event RewardTypeUpdated(uint8 oldType, uint8 newType);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event ArenaModeUpdated(uint8 oldMode, uint8 newMode);
    event ModeControlTypeUpdated(uint8 oldType, uint8 newType);
    event MockRewardRecipientUpdated(address oldAddress, address newAddress);
    event MockRewardDistributed(address indexed recipient, uint256 amount, uint256 seasonId);
    event ScoreUpdated(address indexed player, uint256 newScore, uint256 seasonId);
    event SeasonStarted(uint256 indexed seasonId, uint256 startTime);
    event SeasonSettled(uint256 indexed seasonId, uint256 endTime);
    event RewardClaimed(address indexed player, uint256 amount, uint256 seasonId);
    event ChallengeResult(address indexed challenger, address indexed challenged, bool isVictory, uint256 seasonId);
    event SeasonRewardsCalculated(uint256 indexed seasonNumber, uint256 totalReward, uint256 distributed);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
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

    function setArenaMode(uint8 mode) external onlyOwner {
        require(mode == 0 || mode == 1, "ArenaRankingManager: Invalid mode (0 or 1)");
        uint8 oldMode = arenaMode;
        arenaMode = mode;
        emit ArenaModeUpdated(oldMode, mode);
    }

    function setMockRewardRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "ArenaRankingManager: Invalid recipient");
        address oldRecipient = mockRewardRecipient;
        mockRewardRecipient = recipient;
        emit MockRewardRecipientUpdated(oldRecipient, recipient);
    }

    function setModeControlType(uint8 controlType) external onlyOwner {
        require(controlType <= 2, "ArenaRankingManager: Invalid control type (0-2)");
        uint8 oldType = modeControlType;
        modeControlType = controlType;
        emit ModeControlTypeUpdated(oldType, controlType);
    }

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

    function setMaxRechargeAttempts(uint256 _limit) external onlyOwner {
        require(_limit >= 1 && _limit <= MAX_RECHARGE_ATTEMPTS, "ArenaRankingManager: Invalid limit");
        maxRechargeAttempts = _limit;
        emit RechargeLimitUpdated(_limit);
    }

    function setRewardType(uint8 _rewardType) external onlyOwner {
        require(_rewardType == 0 || _rewardType == 1, "ArenaRankingManager: Invalid reward type");
        require(arenaRewardContract != address(0), "ArenaRankingManager: Reward contract not set");
        IArenaReward(arenaRewardContract).setRewardType(_rewardType);
        emit RewardTypeUpdated(0, _rewardType);
    }

    function _resetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        record.lastResetTime = block.timestamp;
        record.remainingAttempts = DAILY_ATTEMPTS;
    }

    function _checkAndResetAttempts(address player) internal {
        PlayerRecord storage record = players[player];
        if (record.lastResetTime == 0 || block.timestamp > record.lastResetTime + 24 hours) {
            _resetAttempts(player);
            rechargeCount[player] = 0;
        }
    }

    function _validateTeamOwnership(address owner, uint256[6] calldata team) internal view {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer contract not set");
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaRankingManager: Invalid token ID");
            require(IArenaPlayer(arenaPlayerContract).getNFTStakedOwner(tokenId) == owner, "ArenaRankingManager: NFT not staked or not owner");
        }
    }

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

    function _clearSeasonData(address player) internal {
        PlayerRecord storage record = players[player];
        record.score = 0;
        record.wins = 0;
        record.losses = 0;
        record.seasonId = currentSeasonId;
    }

    function startNewSeason() external onlyAuthorized {
        _tryStartNewSeason();
    }

    function _tryStartNewSeason() internal {
        require(block.timestamp >= seasons[currentSeasonId].endTime, "ArenaRankingManager: Current season not ended");
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
        require(seasonId <= currentSeasonId, "ArenaRankingManager: Invalid season");
        require(!seasons[seasonId].isSettled, "ArenaRankingManager: Already settled");
        
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

    function _calculateSeasonRewardsInternal(uint256 seasonId) internal {
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).calculateSeasonRewards(seasonId);
        }
    }

    function setSeasonDuration(uint256 duration) external onlyOwner {
        require(duration >= 1 days, "ArenaRankingManager: Duration too short");
        seasonDuration = duration;
    }

    function addRewardToPool() external payable onlyAuthorized {
        require(msg.value > 0, "ArenaRankingManager: No BNB sent");
        _checkNewDay();
        if (arenaRewardContract != address(0)) {
            IArenaReward(arenaRewardContract).updateTodayIncomingReward(msg.value);
        }
        seasons[currentSeasonId].rewardPool += msg.value;
    }

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

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRankingManager: Amount must be > 0");
        require(amount <= address(this).balance, "ArenaRankingManager: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaRankingManager: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "ArenaRankingManager: Amount must be > 0");
        require(tokenContract != address(0), "ArenaRankingManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "ArenaRankingManager: Insufficient token balance");
        token.transfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    function rechargeChallengeAttempts() external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer not set");
        IArenaPlayer(arenaPlayerContract).rechargeChallengeAttempts();
    }

    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRankingManager: Invalid token count");
        IArenaPlayer(arenaPlayerContract).stakeNFTs(tokenIds);
    }

    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(arenaPlayerContract != address(0), "ArenaRankingManager: ArenaPlayer not set");
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaRankingManager: Invalid token count");
        IArenaPlayer(arenaPlayerContract).unstakeNFTs(tokenIds);
    }

    function setBattleTeam(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(tokenIds.length == 6, "ArenaRankingManager: Team must have exactly 6 NFTs");
        uint256[6] memory fixedTeam;
        for (uint256 i = 0; i < 6; i++) {
            fixedTeam[i] = tokenIds[i];
        }
        _setBattleTeamInternal(fixedTeam);
    }

    function setBattleTeam(uint256[6] calldata tokenIds) external nonReentrant whenNotPaused {
        _setBattleTeamInternal(tokenIds);
    }

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

    function clearBattleTeam() external nonReentrant whenNotPaused {
        PlayerRecord storage record = players[msg.sender];
        for (uint256 i = 0; i < 6; i++) {
            record.battleTeam[i] = 0;
        }
        record.hasTeam = false;
    }

    uint256 public baseRewardPerWin = 100;

    function setBaseRewardPerWin(uint256 _reward) external onlyOwner {
        baseRewardPerWin = _reward;
    }
}