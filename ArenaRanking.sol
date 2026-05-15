// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./Battle.sol";
import "./NFTInterface.sol";

contract ArenaRanking is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IArenaRanking {
    Battle public battleContract;
    INFTMint public nftContract;
    address public tokenContract;
    address public authorizer;

    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant BASE_WIN_POINTS = 100;
    uint256 public constant BASE_LOSS_POINTS = 50;
    uint256 public constant MAX_RANK_BONUS = 500;
    uint256 public constant DAILY_ATTEMPTS = 5;
    uint256 public constant RECHARGE_AMOUNT = 5;
    uint256 public constant DEFAULT_RECHARGE_COST = 888000000000000000000;
    uint256 public constant TIER1_NFT_COUNT = 120;
    uint256 public constant DEFAULT_SEASON_REWARD_RATE = 2; // 0.2% (2 basis points)
    uint256 public constant BPS = 10000; // Basis points denominator

    uint256 public rechargeCost = DEFAULT_RECHARGE_COST;
    uint256 public seasonRewardRate = DEFAULT_SEASON_REWARD_RATE; // Reward rate in basis points

    enum ChallengeMode {
        Points,
        RankSwap
    }

    struct Player {
        uint256 points;
        uint256 wins;
        uint256 losses;
        uint256 lastBattleTime;
        uint256 lastResetTime;
        uint256 remainingAttempts;
        uint256[] battleTeam;
        bool hasTeam;
    }

    struct Season {
        uint256 seasonNumber;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        uint256 totalReward;
        uint256 totalRewardPool; // Total BNB pool for the season
    }

    struct SeasonReward {
        uint256 seasonNumber;
        uint256 rank;
        uint256 reward;
        bool claimed;
    }

    struct BattleRecord {
        address attacker;
        address defender;
        bool attackerWon;
        uint256 attackerWinCount;
        uint256 defenderWinCount;
        uint256 timestamp;
        ChallengeMode mode;
    }

    struct LeaderboardEntry {
        address playerAddress;
        uint256 points;
        uint256 wins;
        uint256 losses;
        bool isMock;
    }

    struct RewardTier {
        uint256 startRank;
        uint256 endRank;
        uint256 percentage; // in basis points
    }

    mapping(address => Player) public players;
    mapping(uint256 => Season) public seasons;
    mapping(address => mapping(uint256 => SeasonReward)) public playerRewards;

    mapping(uint256 => address) public nftToPlayer;
    mapping(uint256 => bool) public isInBattleTeam;

    address[] public playerAddresses;
    mapping(address => bool) public isPlayerRegistered;

    uint256 public currentSeason;
    uint256 public seasonDuration;

    uint256 public nextBattleId;
    mapping(uint256 => BattleRecord) public battleHistory;

    uint256 public mockPlayerCount;
    mapping(uint256 => bool) public isMockPlayerActive;

    RewardTier[] public rewardTiers;

    ChallengeMode public currentMode;

    address[] public sortedPlayerAddresses;
    mapping(address => uint256) public playerSortedIndex;

    event ChallengeCompleted(
        address indexed attacker,
        address indexed defender,
        bool attackerWon,
        int256 attackerPointsChange,
        int256 defenderPointsChange,
        uint256 attackerRank,
        uint256 defenderRank
    );

    event SeasonStarted(uint256 seasonNumber, uint256 startTime, uint256 endTime, uint256 totalRewardPool);
    event SeasonEnded(uint256 seasonNumber, uint256 totalReward);
    event RewardClaimed(address indexed player, uint256 seasonNumber, uint256 reward);
    event BattleTeamSet(address indexed player, uint256[] tokens);
    event BattleTeamCleared(address indexed player);
    event SeasonDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event ChallengeRecharged(address indexed player, uint256 amount);
    event RankSwapped(address indexed winner, address indexed loser, uint256 oldWinnerRank, uint256 oldLoserRank);
    event RechargeCostUpdated(uint256 oldCost, uint256 newCost);
    event MockPlayerBattleTeamReplaced(uint256 mockRank);
    event SeasonRewardRateUpdated(uint256 oldRate, uint256 newRate);
    event RewardTiersUpdated();

    function initialize(address _battleContract, address _nftContract, address _tokenContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        battleContract = Battle(_battleContract);
        nftContract = INFTMint(_nftContract);
        tokenContract = _tokenContract;
        currentSeason = 1;
        seasonDuration = 7 days;

        _initializeDefaultRewardTiers();

        seasons[currentSeason] = Season({
            seasonNumber: currentSeason,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            totalReward: 0,
            totalRewardPool: 0
        });

        _initializeMockPlayers();
    }

    function _initializeDefaultRewardTiers() internal {
        delete rewardTiers;
        rewardTiers.push(RewardTier({startRank: 1, endRank: 1, percentage: 1500})); // 15%
        rewardTiers.push(RewardTier({startRank: 2, endRank: 2, percentage: 1000})); // 10%
        rewardTiers.push(RewardTier({startRank: 3, endRank: 3, percentage: 800}));  // 8%
        rewardTiers.push(RewardTier({startRank: 4, endRank: 5, percentage: 600}));  // 6% each
        rewardTiers.push(RewardTier({startRank: 6, endRank: 10, percentage: 400})); // 4% each
        rewardTiers.push(RewardTier({startRank: 11, endRank: 20, percentage: 250})); // 2.5% each
        rewardTiers.push(RewardTier({startRank: 21, endRank: 50, percentage: 150})); // 1.5% each
        rewardTiers.push(RewardTier({startRank: 51, endRank: 100, percentage: 80})); // 0.8% each
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setBattleContract(address _battleContract) external onlyOwner {
        battleContract = Battle(_battleContract);
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        nftContract = INFTMint(_nftContract);
    }

    function setTokenContract(address _tokenContract) external onlyOwner {
        tokenContract = _tokenContract;
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    function setSeasonDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Duration must be greater than 0");
        uint256 oldDuration = seasonDuration;
        seasonDuration = _duration;
        emit SeasonDurationUpdated(oldDuration, _duration);
    }

    function setRechargeCost(uint256 _cost) external onlyOwner {
        require(_cost > 0, "Cost must be greater than 0");
        uint256 oldCost = rechargeCost;
        rechargeCost = _cost;
        emit RechargeCostUpdated(oldCost, _cost);
    }

    function setSeasonRewardRate(uint256 _rate) external onlyOwner {
        require(_rate > 0 && _rate <= BPS, "Rate must be between 1 and 10000 basis points");
        uint256 oldRate = seasonRewardRate;
        seasonRewardRate = _rate;
        emit SeasonRewardRateUpdated(oldRate, _rate);
    }

    function setRewardTiers(RewardTier[] calldata _rewardTiers) external onlyOwner {
        delete rewardTiers;
        uint256 totalPercentage = 0;
        uint256 lastRank = 0;

        for (uint256 i = 0; i < _rewardTiers.length; i++) {
            require(_rewardTiers[i].startRank > lastRank, "Tiers must be sequential");
            require(_rewardTiers[i].endRank >= _rewardTiers[i].startRank, "Invalid tier range");
            require(_rewardTiers[i].percentage > 0, "Percentage must be positive");

            rewardTiers.push(_rewardTiers[i]);
            totalPercentage += _rewardTiers[i].percentage * (_rewardTiers[i].endRank - _rewardTiers[i].startRank + 1);
            lastRank = _rewardTiers[i].endRank;
        }

        require(totalPercentage <= BPS, "Total percentage cannot exceed 100%");
        emit RewardTiersUpdated();
    }

    event ChallengeModeUpdated(ChallengeMode oldMode, ChallengeMode newMode);

    function setChallengeMode(ChallengeMode _mode) external onlyOwner {
        ChallengeMode oldMode = currentMode;
        currentMode = _mode;
        emit ChallengeModeUpdated(oldMode, _mode);
    }

    function _initializeMockPlayers() internal {
        mockPlayerCount = 20;
        for (uint256 i = 0; i < mockPlayerCount; i++) {
            isMockPlayerActive[i + 1] = true;
        }
    }

    function _generateMockTeam(uint256 seed) internal pure returns (uint256[6] memory) {
        uint256[6] memory team;

        for (uint256 i = 0; i < 6; i++) {
            uint256 randomIndex;
            bool isUnique;

            do {
                randomIndex = uint256(keccak256(abi.encodePacked(seed, i, block.timestamp, block.number))) % TIER1_NFT_COUNT;
                isUnique = true;
                for (uint256 j = 0; j < i; j++) {
                    if (team[j] == randomIndex) {
                        isUnique = false;
                        break;
                    }
                }
            } while (!isUnique);

            team[i] = randomIndex;
        }

        return team;
    }

    function replaceMockPlayerTeam(uint256 rank) internal {
        require(rank <= mockPlayerCount && rank > 0, "Invalid mock player rank");
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, rank, msg.sender)));
        uint256[6] memory newTeam = _generateMockTeam(seed);
        emit MockPlayerBattleTeamReplaced(rank);
    }

    function startNewSeason() external onlyOwner {
        require(seasons[currentSeason].isActive, "E01: No active season");

        _finalizeCurrentSeason();

        currentSeason++;
        _startNewSeason();
    }

    function checkSeasonEnd() external {
        Season storage current = seasons[currentSeason];
        if (current.isActive && block.timestamp >= current.endTime) {
            _finalizeCurrentSeason();
            currentSeason++;
            _startNewSeason();
        }
    }

    function _finalizeCurrentSeason() internal {
        Season storage current = seasons[currentSeason];
        current.isActive = false;

        uint256 contractBalance = address(this).balance;
        uint256 seasonRewardPool = (contractBalance * seasonRewardRate) / BPS;
        current.totalRewardPool = seasonRewardPool;

        emit SeasonEnded(currentSeason, seasonRewardPool);
        _resetSeasonPoints();
    }

    function _startNewSeason() internal {
        uint256 contractBalance = address(this).balance;
        uint256 seasonRewardPool = (contractBalance * seasonRewardRate) / BPS;

        seasons[currentSeason] = Season({
            seasonNumber: currentSeason,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            totalReward: 0,
            totalRewardPool: seasonRewardPool
        });

        _initializeMockPlayers();
        emit SeasonStarted(currentSeason, block.timestamp, block.timestamp + seasonDuration, seasonRewardPool);
    }

    function _resetSeasonPoints() internal {
        for (uint256 i = 0; i < playerAddresses.length; i++) {
            address player = playerAddresses[i];
            players[player].points = 0;
            players[player].wins = 0;
            players[player].losses = 0;
            delete playerSortedIndex[player];
        }
        delete sortedPlayerAddresses;
    }

    function setBattleTeam(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length == TEAM_SIZE, "E03: Battle team must have 6 NFTs");

        _validateUniqueTokens(tokenIds);

        Player storage player = players[msg.sender];

        if (player.hasTeam) {
            _clearBattleTeam(msg.sender);
        }

        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            require(nftContract.ownerOf(tokenIds[i]) == msg.sender, "E17: NFT not owned by sender");
            require(!isInBattleTeam[tokenIds[i]], "E18: NFT already in another battle team");

            nftContract.transferFrom(msg.sender, address(this), tokenIds[i]);
            nftToPlayer[tokenIds[i]] = msg.sender;
            isInBattleTeam[tokenIds[i]] = true;
        }

        player.battleTeam = tokenIds;
        player.hasTeam = true;

        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }

        emit BattleTeamSet(msg.sender, tokenIds);
    }

    function clearBattleTeam() external nonReentrant {
        Player storage player = players[msg.sender];
        require(player.hasTeam, "E19: No battle team to clear");

        for (uint256 i = 0; i < player.battleTeam.length; i++) {
            uint256 tokenId = player.battleTeam[i];
            if (isInBattleTeam[tokenId]) {
                nftContract.transferFrom(address(this), msg.sender, tokenId);
                delete nftToPlayer[tokenId];
                isInBattleTeam[tokenId] = false;
            }
        }

        delete player.battleTeam;
        player.hasTeam = false;

        emit BattleTeamCleared(msg.sender);
    }

    function _validateUniqueTokens(uint256[] calldata tokenIds) internal pure {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenIds[i] != tokenIds[j], "E16: Duplicate NFT in team");
            }
        }
    }

    function _registerPlayer(address player) internal {
        isPlayerRegistered[player] = true;
        playerAddresses.push(player);
        _insertIntoSortedArray(player);
    }

    function _clearBattleTeam(address playerAddr) internal {
        Player storage p = players[playerAddr];
        for (uint256 i = 0; i < p.battleTeam.length; i++) {
            uint256 tokenId = p.battleTeam[i];
            if (isInBattleTeam[tokenId]) {
                nftContract.transferFrom(address(this), playerAddr, tokenId);
                delete nftToPlayer[tokenId];
                isInBattleTeam[tokenId] = false;
            }
        }
        delete p.battleTeam;
        p.hasTeam = false;
    }

    function _resetDailyAttempts(address player) internal {
        Player storage p = players[player];
        if (block.timestamp >= p.lastResetTime + 1 days) {
            p.remainingAttempts = DAILY_ATTEMPTS;
            p.lastResetTime = block.timestamp;
        }
    }

    function getRemainingAttempts(address player) public view returns (uint256) {
        Player storage p = players[player];
        if (block.timestamp >= p.lastResetTime + 1 days) {
            return DAILY_ATTEMPTS;
        }
        return p.remainingAttempts;
    }

    function rechargeChallengeAttempts() external nonReentrant {
        _resetDailyAttempts(msg.sender);

        Player storage player = players[msg.sender];
        require(player.remainingAttempts < DAILY_ATTEMPTS, "E20: Already have max attempts");

        (bool success, ) = tokenContract.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), rechargeCost)
        );
        require(success, "E21: Token transfer failed");

        player.remainingAttempts += RECHARGE_AMOUNT;
        if (player.remainingAttempts > DAILY_ATTEMPTS) {
            player.remainingAttempts = DAILY_ATTEMPTS;
        }

        emit ChallengeRecharged(msg.sender, RECHARGE_AMOUNT);
    }

    function challenge(address defender) external nonReentrant returns (bool, uint256, uint256) {
        require(seasons[currentSeason].isActive, "E02: Season not active");

        Player storage attacker = players[msg.sender];

        require(attacker.hasTeam && attacker.battleTeam.length == TEAM_SIZE, "E05: Attacker must set battle team");
        require(msg.sender != defender, "E22: Cannot challenge yourself");

        _resetDailyAttempts(msg.sender);
        require(attacker.remainingAttempts > 0, "E23: No remaining challenge attempts");

        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }

        attacker.remainingAttempts--;

        uint256 attackerRank = getPlayerRank(msg.sender);
        uint256 defenderRank;

        if (defender == address(0)) {
            defenderRank = 1;
        } else {
            defenderRank = getPlayerRank(defender);
        }

        bool isMockDefender = _isMockPlayer(defender);
        uint256[6] memory defenderTeam;
        bool defenderHasTeam;

        if (isMockDefender) {
            uint256 mockRank = _getMockPlayerRank(defender);
            defenderTeam = _getMockTeamByRank(mockRank);
            defenderHasTeam = true;
        } else {
            Player storage defenderPlayer = players[defender];
            require(defenderPlayer.hasTeam && defenderPlayer.battleTeam.length == TEAM_SIZE, "E06: Defender must set battle team");
            defenderTeam = _convertToFixedArray(defenderPlayer.battleTeam);
            defenderHasTeam = defenderPlayer.hasTeam;
        }

        require(defenderHasTeam, "E06: Defender must set battle team");

        ChallengeMode mode = currentMode;

        if (mode == ChallengeMode.RankSwap) {
            if (isMockDefender) {
                require(attackerRank < _getMockPlayerRank(defender), "E24: Can only challenge higher ranked players");
            }
        }

        if (!isPlayerRegistered[defender]) {
            _registerPlayer(defender);
        }

        if (mode == ChallengeMode.RankSwap) {
            return _challengeRankSwapWithMock(msg.sender, defender, attackerRank, defenderRank, defenderTeam, isMockDefender);
        } else {
            return _challengePointsWithMock(msg.sender, defender, attackerRank, defenderRank, defenderTeam, isMockDefender);
        }
    }

    function _isMockPlayer(address player) internal view returns (bool) {
        uint256 mockRank = _getMockPlayerRank(player);
        return mockRank > 0 && mockRank <= mockPlayerCount && isMockPlayerActive[mockRank];
    }

    function _getMockPlayerRank(address player) internal pure returns (uint256) {
        if (player >= address(1) && player <= address(20)) {
            return uint256(uint160(player));
        }
        return 0;
    }

    function _getMockTeamByRank(uint256 rank) internal view returns (uint256[6] memory) {
        return _generateMockTeam(rank * 1000 + currentSeason);
    }

    function _convertToFixedArray(uint256[] memory dynamicArray) internal pure returns (uint256[6] memory) {
        uint256[6] memory fixedArray;
        for (uint256 i = 0; i < 6 && i < dynamicArray.length; i++) {
            fixedArray[i] = dynamicArray[i];
        }
        return fixedArray;
    }

    function challengeWithMock(address attacker, uint256 defenderRank) external onlyOwner returns (bool, uint256, uint256) {
        require(seasons[currentSeason].isActive, "E02: Season not active");
        require(defenderRank > 0 && defenderRank <= mockPlayerCount, "Invalid mock rank");

        Player storage attackerPlayer = players[attacker];
        require(attackerPlayer.hasTeam && attackerPlayer.battleTeam.length == TEAM_SIZE, "E05: Attacker must set battle team");

        uint256[6] memory defenderTeam = _getMockTeamByRank(defenderRank);

        uint256 attackerRank = getPlayerRank(attacker);

        return _challengePointsWithMock(attacker, address(uint160(defenderRank)), attackerRank, defenderRank, defenderTeam, true);
    }

    function _challengePointsWithMock(address attacker, address defender, uint256 attackerRank, uint256 defenderRank, uint256[6] memory defenderTeam, bool isMockDefender) internal returns (bool, uint256, uint256) {
        Player storage attackerPlayer = players[attacker];

        uint256[] memory attackerTeamDynamic = attackerPlayer.battleTeam;
        uint256[6] memory attackerTeamFixed = _convertToFixedArray(attackerTeamDynamic);

        (bool attackerWon, uint256 attackerWinCount, uint256 defenderWinCount) =
            battleContract.battle(attackerTeamFixed, defenderTeam);

        int256 attackerPointsChange;
        int256 defenderPointsChange;

        if (attackerWon) {
            attackerPointsChange = _calculateWinPoints(attackerRank, defenderRank, attackerWinCount);
            attackerPlayer.points += uint256(attackerPointsChange);
            attackerPlayer.wins++;

            if (!isMockDefender) {
                Player storage defenderPlayer = players[defender];
                defenderPointsChange = -attackerPointsChange / 2;
                if (defenderPlayer.points > uint256(-defenderPointsChange)) {
                    defenderPlayer.points -= uint256(-defenderPointsChange);
                } else {
                    defenderPlayer.points = 0;
                }
                defenderPlayer.losses++;
                _updatePlayerPosition(defender);
            }
        } else {
            attackerPointsChange = -_calculateLossPoints(attackerRank, defenderRank);
            if (attackerPlayer.points > uint256(-attackerPointsChange)) {
                attackerPlayer.points -= uint256(-attackerPointsChange);
            } else {
                attackerPlayer.points = 0;
            }
            attackerPlayer.losses++;

            if (!isMockDefender) {
                Player storage defenderPlayer = players[defender];
                defenderPointsChange = _calculateWinPoints(defenderRank, attackerRank, defenderWinCount);
                defenderPlayer.points += uint256(defenderPointsChange);
                defenderPlayer.wins++;
                _updatePlayerPosition(defender);
            }
        }

        _updatePlayerPosition(attacker);
        attackerPlayer.lastBattleTime = block.timestamp;

        battleHistory[nextBattleId] = BattleRecord({
            attacker: attacker,
            defender: defender,
            attackerWon: attackerWon,
            attackerWinCount: attackerWinCount,
            defenderWinCount: defenderWinCount,
            timestamp: block.timestamp,
            mode: ChallengeMode.Points
        });
        nextBattleId++;

        if (isMockDefender && attackerWon) {
            replaceMockPlayerTeam(defenderRank);
        }

        emit ChallengeCompleted(attacker, defender, attackerWon, attackerPointsChange, defenderPointsChange, attackerRank, defenderRank);

        return (attackerWon, attackerWinCount, defenderWinCount);
    }

    function _challengeRankSwapWithMock(address attacker, address defender, uint256 attackerRank, uint256 defenderRank, uint256[6] memory defenderTeam, bool isMockDefender) internal returns (bool, uint256, uint256) {
        Player storage attackerPlayer = players[attacker];

        uint256[] memory attackerTeamDynamic = attackerPlayer.battleTeam;
        uint256[6] memory attackerTeamFixed = _convertToFixedArray(attackerTeamDynamic);

        uint256 attackerWins = 0;
        uint256 defenderWins = 0;

        for (uint256 i = 0; i < 3; i++) {
            (bool roundWon, uint256 atkCount, uint256 defCount) =
                battleContract.battle(attackerTeamFixed, defenderTeam);

            if (roundWon) {
                attackerWins++;
            } else {
                defenderWins++;
            }

            if (attackerWins >= 2 || defenderWins >= 2) {
                break;
            }
        }

        bool attackerWon = attackerWins >= 2;

        if (attackerWon) {
            if (isMockDefender) {
                uint256 mockRank = _getMockPlayerRank(defender);
                replaceMockPlayerTeam(mockRank);
                attackerPlayer.points = (mockPlayerCount - attackerRank + 1) * 100;
            } else {
                Player storage defenderPlayer = players[defender];
                uint256 tempPoints = attackerPlayer.points;
                attackerPlayer.points = defenderPlayer.points;
                defenderPlayer.points = tempPoints;
                defenderPlayer.losses++;
                _updatePlayerPosition(defender);
            }
            attackerPlayer.wins++;
            _updatePlayerPosition(attacker);

            emit RankSwapped(attacker, defender, attackerRank, defenderRank);
        } else {
            attackerPlayer.losses++;
            _updatePlayerPosition(attacker);
            if (!isMockDefender) {
                Player storage defenderPlayer = players[defender];
                defenderPlayer.wins++;
            }
        }

        attackerPlayer.lastBattleTime = block.timestamp;

        battleHistory[nextBattleId] = BattleRecord({
            attacker: attacker,
            defender: defender,
            attackerWon: attackerWon,
            attackerWinCount: attackerWins,
            defenderWinCount: defenderWins,
            timestamp: block.timestamp,
            mode: ChallengeMode.RankSwap
        });
        nextBattleId++;

        int256 attackerPointsChange = attackerWon ? int256(attackerPlayer.points) : 0;
        int256 defenderPointsChange = attackerWon ? -attackerPointsChange : 0;

        emit ChallengeCompleted(attacker, defender, attackerWon, attackerPointsChange, defenderPointsChange, attackerRank, defenderRank);

        return (attackerWon, attackerWins, defenderWins);
    }

    function _calculateWinPoints(uint256 attackerRank, uint256 defenderRank, uint256 winCount) internal pure returns (int256) {
        uint256 rankDiff;
        if (attackerRank > defenderRank) {
            rankDiff = attackerRank - defenderRank;
        } else {
            rankDiff = defenderRank - attackerRank;
        }

        uint256 bonus = (rankDiff * MAX_RANK_BONUS) / 100;

        uint256 battlePoints = winCount * BASE_WIN_POINTS;

        if (attackerRank > defenderRank) {
            return int256(battlePoints + bonus);
        } else if (attackerRank < defenderRank) {
            uint256 penalty = (battlePoints * bonus) / 1000;
            if (battlePoints > penalty) {
                return int256(battlePoints - penalty);
            }
            return int256(battlePoints / 2);
        } else {
            return int256(battlePoints);
        }
    }

    function _calculateLossPoints(uint256 attackerRank, uint256 defenderRank) internal pure returns (uint256) {
        uint256 rankDiff;
        if (attackerRank > defenderRank) {
            rankDiff = attackerRank - defenderRank;
        } else {
            rankDiff = defenderRank - attackerRank;
        }

        uint256 bonus = (rankDiff * MAX_RANK_BONUS) / 100;

        if (attackerRank > defenderRank) {
            uint256 penalty = (BASE_LOSS_POINTS * bonus) / 1000;
            if (penalty < BASE_LOSS_POINTS) {
                return BASE_LOSS_POINTS - penalty;
            }
            return BASE_LOSS_POINTS / 2;
        } else if (attackerRank < defenderRank) {
            return BASE_LOSS_POINTS + bonus;
        } else {
            return BASE_LOSS_POINTS;
        }
    }

    function _insertIntoSortedArray(address player) internal {
        uint256 playerPoints = players[player].points;
        uint256 left = 0;
        uint256 right = sortedPlayerAddresses.length;

        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (players[sortedPlayerAddresses[mid]].points > playerPoints) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        playerSortedIndex[player] = left;
        
        if (left == sortedPlayerAddresses.length) {
            sortedPlayerAddresses.push(player);
        } else {
            sortedPlayerAddresses.push();
            for (uint256 i = sortedPlayerAddresses.length - 1; i > left; i--) {
                sortedPlayerAddresses[i] = sortedPlayerAddresses[i - 1];
                playerSortedIndex[sortedPlayerAddresses[i]] = i;
            }
            sortedPlayerAddresses[left] = player;
        }
    }

    function _updatePlayerPosition(address player) internal {
        uint256 oldIndex = playerSortedIndex[player];
        uint256 playerPoints = players[player].points;
        uint256 arrayLength = sortedPlayerAddresses.length;

        if (oldIndex > 0 && players[sortedPlayerAddresses[oldIndex - 1]].points < playerPoints) {
            uint256 newIndex = oldIndex;
            while (newIndex > 0 && players[sortedPlayerAddresses[newIndex - 1]].points < playerPoints) {
                newIndex--;
            }
            
            if (newIndex != oldIndex) {
                for (uint256 i = oldIndex; i > newIndex; i--) {
                    sortedPlayerAddresses[i] = sortedPlayerAddresses[i - 1];
                    playerSortedIndex[sortedPlayerAddresses[i]] = i;
                }
                sortedPlayerAddresses[newIndex] = player;
                playerSortedIndex[player] = newIndex;
            }
        } else if (oldIndex < arrayLength - 1 && players[sortedPlayerAddresses[oldIndex + 1]].points > playerPoints) {
            uint256 newIndex = oldIndex;
            while (newIndex < arrayLength - 1 && players[sortedPlayerAddresses[newIndex + 1]].points > playerPoints) {
                newIndex++;
            }
            
            if (newIndex != oldIndex) {
                for (uint256 i = oldIndex; i < newIndex; i++) {
                    sortedPlayerAddresses[i] = sortedPlayerAddresses[i + 1];
                    playerSortedIndex[sortedPlayerAddresses[i]] = i;
                }
                sortedPlayerAddresses[newIndex] = player;
                playerSortedIndex[player] = newIndex;
            }
        }
    }

    function getPlayerRank(address player) public view returns (uint256) {
        if (!isPlayerRegistered[player]) {
            return playerAddresses.length + mockPlayerCount + 1;
        }
        
        uint256 sortedIndex = playerSortedIndex[player];
        uint256 playerPoints = players[player].points;
        uint256 rank = sortedIndex + 1;

        for (uint256 i = sortedIndex; i > 0; i--) {
            if (players[sortedPlayerAddresses[i - 1]].points != playerPoints) {
                break;
            }
            rank = i;
        }

        return rank + mockPlayerCount;
    }

    function getTotalPlayers() public view returns (uint256) {
        return playerAddresses.length;
    }

    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory) {
        uint256 totalRealPlayers = sortedPlayerAddresses.length;
        uint256 totalSlots = totalRealPlayers + mockPlayerCount;

        if (limit < totalSlots) {
            totalSlots = limit;
        }

        LeaderboardEntry[] memory entries = new LeaderboardEntry[](totalSlots);

        uint256 entryIndex = 0;

        for (uint256 i = 0; i < totalRealPlayers && entryIndex < totalSlots; i++) {
            address player = sortedPlayerAddresses[i];
            entries[entryIndex] = LeaderboardEntry({
                playerAddress: player,
                points: players[player].points,
                wins: players[player].wins,
                losses: players[player].losses,
                isMock: false
            });
            entryIndex++;
        }

        for (uint256 i = 1; i <= mockPlayerCount && entryIndex < totalSlots; i++) {
            if (isMockPlayerActive[i]) {
                uint256 mockPoints = (mockPlayerCount - i + 1) * 100;
                entries[entryIndex] = LeaderboardEntry({
                    playerAddress: address(uint160(i)),
                    points: mockPoints,
                    wins: 0,
                    losses: 0,
                    isMock: true
                });
                entryIndex++;
            }
        }

        return entries;
    }

    function getMockPlayerTeam(uint256 rank) external view returns (uint256[6] memory) {
        require(rank > 0 && rank <= mockPlayerCount, "Invalid mock rank");
        return _getMockTeamByRank(rank);
    }

    function isMockPlayer(address player) external view returns (bool) {
        return _isMockPlayer(player);
    }

    function getMockPlayerRank(address player) external pure returns (uint256) {
        return _getMockPlayerRank(player);
    }

    function getCurrentRewardPool() public view returns (uint256) {
        return seasons[currentSeason].totalRewardPool;
    }

    function getRewardForRank(uint256 rank) public view returns (uint256) {
        uint256 rewardPool = seasons[currentSeason].totalRewardPool;
        if (rewardPool == 0) {
            rewardPool = (address(this).balance * seasonRewardRate) / BPS;
        }

        for (uint256 i = 0; i < rewardTiers.length; i++) {
            if (rank >= rewardTiers[i].startRank && rank <= rewardTiers[i].endRank) {
                return (rewardPool * rewardTiers[i].percentage) / BPS;
            }
        }

        return 0;
    }

    function getRewardTiersCount() public view returns (uint256) {
        return rewardTiers.length;
    }

    function calculateSeasonReward(address player, uint256 seasonNumber) public view returns (uint256) {
        SeasonReward storage reward = playerRewards[player][seasonNumber];
        if (reward.claimed) return 0;

        uint256 rank = getPlayerRank(player);
        return getRewardForRank(rank);
    }

    function claimReward(uint256 seasonNumber) external nonReentrant {
        SeasonReward storage reward = playerRewards[msg.sender][seasonNumber];
        require(!reward.claimed, "E08: Reward already claimed");

        Season storage season = seasons[seasonNumber];
        require(!season.isActive, "E09: Season still active");

        uint256 rewardAmount = calculateSeasonReward(msg.sender, seasonNumber);
        require(rewardAmount > 0, "E10: No reward available");
        require(rewardAmount <= season.totalRewardPool, "Reward exceeds pool");

        reward.claimed = true;
        reward.reward = rewardAmount;
        reward.rank = getPlayerRank(msg.sender);

        (bool success, ) = msg.sender.call{value: rewardAmount}("");
        require(success, "E11: Transfer failed");

        emit RewardClaimed(msg.sender, seasonNumber, rewardAmount);
    }

    function getUnclaimedRewards(address player) external view returns (uint256[] memory, uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (!playerRewards[player][i].claimed && calculateSeasonReward(player, i) > 0) {
                count++;
            }
        }

        uint256[] memory seasonsList = new uint256[](count);
        uint256[] memory rewards = new uint256[](count);

        count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (!playerRewards[player][i].claimed && calculateSeasonReward(player, i) > 0) {
                seasonsList[count] = i;
                rewards[count] = calculateSeasonReward(player, i);
                count++;
            }
        }

        return (seasonsList, rewards);
    }

    function getClaimedRewards(address player) external view returns (uint256[] memory, uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (playerRewards[player][i].claimed) {
                count++;
            }
        }

        uint256[] memory seasonsList = new uint256[](count);
        uint256[] memory rewards = new uint256[](count);

        count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (playerRewards[player][i].claimed) {
                seasonsList[count] = i;
                rewards[count] = playerRewards[player][i].reward;
                count++;
            }
        }

        return (seasonsList, rewards);
    }

    function withdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "E12: Insufficient balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "E13: Transfer failed");
    }

    function withdrawSpecificBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient BNB balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "BNB transfer failed");
    }

    function withdrawNFTs(uint256[] calldata tokenIds) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            nftContract.transferFrom(address(this), owner(), tokenIds[i]);
        }
    }

    function isNFTInArena(uint256 tokenId) external view returns (bool) {
        return isInBattleTeam[tokenId];
    }

    function getPlayerBattleTeam(address player) external view returns (uint256[] memory) {
        if (_isMockPlayer(player)) {
            uint256 rank = _getMockPlayerRank(player);
            uint256[6] memory mockTeam = _getMockTeamByRank(rank);
            uint256[] memory result = new uint256[](6);
            for (uint256 i = 0; i < 6; i++) {
                result[i] = mockTeam[i];
            }
            return result;
        }
        return players[player].battleTeam;
    }

    function getSeasonInfo(uint256 seasonNumber) external view returns (Season memory) {
        return seasons[seasonNumber];
    }

    function getCurrentSeasonInfo() external view returns (Season memory) {
        return seasons[currentSeason];
    }

    function getBattleRecord(uint256 battleId) external view returns (BattleRecord memory) {
        return battleHistory[battleId];
    }

    function getPlayerInfo(address player) external view returns (Player memory) {
        return players[player];
    }

    receive() external payable {}
}
