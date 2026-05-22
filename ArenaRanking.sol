// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./BattleLib.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

contract ArenaRanking is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IArenaRanking {
    using ArenaRankingLib for *;

    error InvalidDuration();
    error InvalidCost();
    error InvalidRate();
    error InvalidTierRange();
    error TierNotSequential();
    error InvalidTierPercentage();
    error TotalPercentageExceeds100();
    error InvalidMockRank();
    error NoActiveSeason();
    error BattleTeamSizeMismatch();
    error NFTNotOwned();
    error NFTAlreadyInTeam();
    error NoBattleTeamToClear();
    error DuplicateNFTInTeam();
    error MaxAttemptsReached();
    error TokenTransferFailed();
    error SeasonNotActive();
    error AttackerNoTeam();
    error CannotChallengeSelf();
    error NoAttemptsLeft();
    error DefenderNoTeam();
    error BattleCallFailed();
    error RewardAlreadyClaimed();
    error InsufficientRewardBalance();
    error TransferFailed();
    error InsufficientContractBalance();
    error InsufficientBNBBalance();
    error BNBTransferFailed();

    address public battleContract;
    INFTMint public nftContract;
    address public tokenContract;
    address public authorizer;

    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant DAILY_ATTEMPTS = 5;
    uint256 public constant RECHARGE_AMOUNT = 5;
    uint256 public constant DEFAULT_RECHARGE_COST = 888000000000000000000;
    uint256 public constant TIER1_NFT_COUNT = 120;
    uint256 public constant DEFAULT_SEASON_REWARD_RATE = 2;

    uint256 public rechargeCost = DEFAULT_RECHARGE_COST;
    uint256 public seasonRewardRate = DEFAULT_SEASON_REWARD_RATE;

    uint8 public currentMode;

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
        uint256 totalRewardPool;
    }

    struct SeasonReward {
        uint128 reward;
        uint64 rank;
        bool claimed;
    }

    struct BattleRecord {
        address attacker;
        address defender;
        bool attackerWon;
        uint256 attackerWinCount;
        uint256 defenderWinCount;
        uint256 timestamp;
        uint8 mode;
    }

    struct BattleResult {
        bool won;
        uint256 aw;
        uint256 dw;
        uint256 ar;
        uint256 dr;
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
        uint256 percentage;
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
        battleContract = _battleContract;
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
        rewardTiers.push(RewardTier({startRank: 1, endRank: 1, percentage: 1500}));
        rewardTiers.push(RewardTier({startRank: 2, endRank: 2, percentage: 1000}));
        rewardTiers.push(RewardTier({startRank: 3, endRank: 3, percentage: 800}));
        rewardTiers.push(RewardTier({startRank: 4, endRank: 5, percentage: 600}));
        rewardTiers.push(RewardTier({startRank: 6, endRank: 10, percentage: 400}));
        rewardTiers.push(RewardTier({startRank: 11, endRank: 20, percentage: 250}));
        rewardTiers.push(RewardTier({startRank: 21, endRank: 50, percentage: 150}));
        rewardTiers.push(RewardTier({startRank: 51, endRank: 100, percentage: 80}));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setBattleContract(address _battleContract) external onlyOwner {
        battleContract = _battleContract;
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
        if (_duration == 0) revert InvalidDuration();
        uint256 oldDuration = seasonDuration;
        seasonDuration = _duration;
        emit SeasonDurationUpdated(oldDuration, _duration);
    }

    function setRechargeCost(uint256 _cost) external onlyOwner {
        if (_cost == 0) revert InvalidCost();
        uint256 oldCost = rechargeCost;
        rechargeCost = _cost;
        emit RechargeCostUpdated(oldCost, _cost);
    }

    function setSeasonRewardRate(uint256 _rate) external onlyOwner {
        if (_rate == 0 || _rate > ArenaRankingLib.BPS) revert InvalidRate();
        uint256 oldRate = seasonRewardRate;
        seasonRewardRate = _rate;
        emit SeasonRewardRateUpdated(oldRate, _rate);
    }

    function setRewardTiers(RewardTier[] calldata _rewardTiers) external onlyOwner {
        delete rewardTiers;
        uint256 totalPercentage = 0;
        uint256 lastRank = 0;

        for (uint256 i = 0; i < _rewardTiers.length; i++) {
            if (_rewardTiers[i].startRank <= lastRank) revert TierNotSequential();
            if (_rewardTiers[i].endRank < _rewardTiers[i].startRank) revert InvalidTierRange();
            if (_rewardTiers[i].percentage == 0) revert InvalidTierPercentage();

            rewardTiers.push(_rewardTiers[i]);
            totalPercentage += _rewardTiers[i].percentage * (_rewardTiers[i].endRank - _rewardTiers[i].startRank + 1);
            lastRank = _rewardTiers[i].endRank;
        }

        if (totalPercentage > ArenaRankingLib.BPS) revert TotalPercentageExceeds100();
        emit RewardTiersUpdated();
    }

    event ChallengeModeUpdated(uint8 oldMode, uint8 newMode);

    function setChallengeMode(uint8 _mode) external onlyOwner {
        uint8 oldMode = currentMode;
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
                randomIndex = uint256(keccak256(abi.encodePacked(seed, i))) % TIER1_NFT_COUNT;
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
        if (rank == 0 || rank > mockPlayerCount) revert InvalidMockRank();
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, rank)));
        _generateMockTeam(seed);
        emit MockPlayerBattleTeamReplaced(rank);
    }

    function startNewSeason() external onlyOwner {
        if (!seasons[currentSeason].isActive) revert NoActiveSeason();
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
        uint256 seasonRewardPool = (contractBalance * seasonRewardRate) / ArenaRankingLib.BPS;
        current.totalRewardPool = seasonRewardPool;

        emit SeasonEnded(currentSeason, seasonRewardPool);
        _resetSeasonPoints();
    }

    function _startNewSeason() internal {
        uint256 contractBalance = address(this).balance;
        uint256 seasonRewardPool = (contractBalance * seasonRewardRate) / ArenaRankingLib.BPS;

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
        if (tokenIds.length != TEAM_SIZE) revert BattleTeamSizeMismatch();
        ArenaRankingLib.validateUniqueTokens(tokenIds);

        Player storage player = players[msg.sender];
        if (player.hasTeam) {
            _clearBattleTeam(msg.sender);
        }

        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (nftContract.ownerOf(tokenIds[i]) != msg.sender) revert NFTNotOwned();
            if (isInBattleTeam[tokenIds[i]]) revert NFTAlreadyInTeam();

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
        if (!player.hasTeam) revert NoBattleTeamToClear();

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
        if (player.remainingAttempts >= DAILY_ATTEMPTS) revert MaxAttemptsReached();

        (bool success, ) = tokenContract.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), rechargeCost)
        );
        if (!success) revert TokenTransferFailed();

        player.remainingAttempts += RECHARGE_AMOUNT;
        if (player.remainingAttempts > DAILY_ATTEMPTS) {
            player.remainingAttempts = DAILY_ATTEMPTS;
        }

        emit ChallengeRecharged(msg.sender, RECHARGE_AMOUNT);
    }

    function challenge(address defender) external nonReentrant returns (bool, uint256, uint256) {
        if (!seasons[currentSeason].isActive) revert SeasonNotActive();

        Player storage attacker = players[msg.sender];
        if (!attacker.hasTeam || attacker.battleTeam.length != TEAM_SIZE) revert AttackerNoTeam();
        if (msg.sender == defender) revert CannotChallengeSelf();

        _resetDailyAttempts(msg.sender);
        if (attacker.remainingAttempts == 0) revert NoAttemptsLeft();

        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }

        attacker.remainingAttempts--;

        uint256 attackerRank = getPlayerRank(msg.sender);
        uint256 defenderRank = defender == address(0) ? 1 : getPlayerRank(defender);

        bool isMockDefender = ArenaRankingLib.isMockPlayer(defender);
        uint256[6] memory defenderTeam;
        bool defenderHasTeam;

        if (isMockDefender) {
            uint256 mockRank = ArenaRankingLib.getMockPlayerRank(defender);
            defenderTeam = _getMockTeamByRank(mockRank);
            defenderHasTeam = true;
        } else {
            Player storage defenderPlayer = players[defender];
            if (!defenderPlayer.hasTeam || defenderPlayer.battleTeam.length != TEAM_SIZE) revert DefenderNoTeam();
            defenderTeam = _convertToFixedArray(defenderPlayer.battleTeam);
            defenderHasTeam = defenderPlayer.hasTeam;
        }

        if (!defenderHasTeam) revert DefenderNoTeam();

        if (!isPlayerRegistered[defender]) {
            _registerPlayer(defender);
        }

        if (currentMode == 1) {
            return _challengeRankSwapWithMock(msg.sender, defender, attackerRank, defenderRank, defenderTeam, isMockDefender);
        } else {
            return _challengePointsWithMock(msg.sender, defender, attackerRank, defenderRank, defenderTeam, isMockDefender);
        }
    }

    function _isMockPlayer(address player) internal view returns (bool) {
        if (player == address(0)) return true;
        uint256 mockRank = _getMockPlayerRank(player);
        return mockRank > 0 && mockRank <= mockPlayerCount && isMockPlayerActive[mockRank];
    }

    function _getMockPlayerRank(address player) internal pure returns (uint256) {
        if (player == address(0)) return 1;
        if (player >= address(1) && player <= address(20)) return uint256(uint160(player));
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
        if (!seasons[currentSeason].isActive) revert SeasonNotActive();
        if (defenderRank == 0 || defenderRank > mockPlayerCount) revert InvalidMockRank();

        Player storage attackerPlayer = players[attacker];
        if (!attackerPlayer.hasTeam || attackerPlayer.battleTeam.length != TEAM_SIZE) revert AttackerNoTeam();

        uint256[6] memory defenderTeam = _getMockTeamByRank(defenderRank);
        uint256 attackerRank = getPlayerRank(attacker);

        return _challengePointsWithMock(attacker, address(uint160(defenderRank)), attackerRank, defenderRank, defenderTeam, true);
    }

    function _executeBattle(uint256 attackerToken, uint256 defenderToken) internal view returns (bool) {
        (bool success, bytes memory data) = battleContract.staticcall(
            abi.encodeWithSignature("simulateBattle(uint256,uint256)", attackerToken, defenderToken)
        );
        if (!success) revert BattleCallFailed();
        BattleLib.SingleBattleResult memory result = abi.decode(data, (BattleLib.SingleBattleResult));
        return result.attackerWon;
    }

    function _executeTeamBattle(uint256[] memory attackerTeam, uint256[6] memory defenderTeam) internal view returns (uint256, uint256) {
        uint256 attackerWins = 0;
        uint256 defenderWins = 0;

        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (attackerWins >= 4 || defenderWins >= 4) break;
            
            bool attackerWon = _executeBattle(attackerTeam[i], defenderTeam[i]);
            if (attackerWon) {
                attackerWins++;
            } else {
                defenderWins++;
            }
        }

        return (attackerWins, defenderWins);
    }

    function _challengePointsWithMock(address attacker, address defender, uint256 attackerRank, uint256 defenderRank, uint256[6] memory defenderTeam, bool isMockDefender) internal returns (bool, uint256, uint256) {
        return _executePointsBattle(attacker, defender, attackerRank, defenderRank, defenderTeam, isMockDefender);
    }

    function _executePointsBattle(address a, address d, uint256 ar, uint256 dr, uint256[6] memory dt, bool md) private returns (bool, uint256, uint256) {
        Player storage ap = players[a];
        
        BattleResult memory br;
        br.ar = ar;
        br.dr = dr;

        uint256[] memory at = ap.battleTeam;
        (br.aw, br.dw) = _executeTeamBattle(at, dt);
        br.won = br.aw > br.dw;

        _updatePoints(a, d, ap, ar, dr, br.aw, br.dw, br.won, md);
        
        if (md && br.won) {
            replaceMockPlayerTeam(dr);
        }

        _finishBattle(a, d, ap, br, 0);

        return (br.won, br.aw, br.dw);
    }

    function _updatePoints(address attacker, address defender, Player storage ap, uint256 ar, uint256 dr, uint256 aw, uint256 dw, bool won, bool md) private {
        if (won) {
            uint256 wp = uint256(_calculateWinPoints(ar, dr, aw));
            ap.points += wp;
            ap.wins++;

            if (!md) {
                Player storage dp = players[defender];
                uint256 lp = wp / 2;
                dp.points = dp.points > lp ? dp.points - lp : 0;
                dp.losses++;
                _updatePlayerPosition(defender);
            }
        } else {
            uint256 lp = _calculateLossPoints(ar, dr);
            ap.points = ap.points > lp ? ap.points - lp : 0;
            ap.losses++;

            if (!md) {
                Player storage dp = players[defender];
                dp.points += uint256(_calculateWinPoints(dr, ar, dw));
                dp.wins++;
                _updatePlayerPosition(defender);
            }
        }

        _updatePlayerPosition(attacker);
    }

    

    function _challengeRankSwapWithMock(address attacker, address defender, uint256 attackerRank, uint256 defenderRank, uint256[6] memory defenderTeam, bool isMockDefender) internal returns (bool, uint256, uint256) {
        return _executeRankSwap(attacker, defender, attackerRank, defenderRank, defenderTeam, isMockDefender);
    }

    

    function _executeRankSwap(address a, address d, uint256 ar, uint256 dr, uint256[6] memory dt, bool md) private returns (bool, uint256, uint256) {
        Player storage ap = players[a];
        
        BattleResult memory br;
        br.ar = ar;
        br.dr = dr;

        uint256[] memory at = ap.battleTeam;
        for (uint256 i = 0; i < 3; i++) {
            if (br.aw >= 2 || br.dw >= 2) break;
            if (_executeBattle(at[i], dt[i])) {
                br.aw++;
            } else {
                br.dw++;
            }
        }

        br.won = br.aw >= 2;
        _updateRankSwap(a, d, ap, ar, br.won, md);
        _finishBattle(a, d, ap, br, 1);

        return (br.won, br.aw, br.dw);
    }

    function _finishBattle(address a, address d, Player storage ap, BattleResult memory br, uint8 m) private {
        ap.lastBattleTime = block.timestamp;
        battleHistory[nextBattleId++] = BattleRecord({
            attacker: a, defender: d, attackerWon: br.won, attackerWinCount: br.aw, defenderWinCount: br.dw, timestamp: block.timestamp, mode: m
        });

        int256 apc = br.won ? int256(ap.points) : int256(0);
        int256 dpc = br.won ? -apc : int256(0);
        emit ChallengeCompleted(a, d, br.won, apc, dpc, br.ar, br.dr);
    }

    

    function _updateRankSwap(address a, address d, Player storage ap, uint256 ar, bool won, bool md) private {
        if (won) {
            if (md) {
                uint256 mr = _getMockPlayerRank(d);
                replaceMockPlayerTeam(mr);
                ap.points = (mockPlayerCount - ar + 1) * 100;
            } else {
                Player storage dp = players[d];
                uint256 tp = ap.points;
                ap.points = dp.points;
                dp.points = tp;
                dp.losses++;
                _updatePlayerPosition(d);
            }
            ap.wins++;
            _updatePlayerPosition(a);
            emit RankSwapped(a, d, ar, _getMockPlayerRank(d));
        } else {
            ap.losses++;
            _updatePlayerPosition(a);
            if (!md) {
                players[d].wins++;
            }
        }
    }

    

    function _calculateWinPoints(uint256 attackerRank, uint256 defenderRank, uint256 winCount) internal pure returns (int256) {
        return ArenaRankingLib.calculateWinPoints(attackerRank, defenderRank, winCount);
    }

    function _calculateLossPoints(uint256 attackerRank, uint256 defenderRank) internal pure returns (uint256) {
        return ArenaRankingLib.calculateLossPoints(attackerRank, defenderRank);
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
        if (rank == 0 || rank > mockPlayerCount) revert InvalidMockRank();
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
            rewardPool = (address(this).balance * seasonRewardRate) / ArenaRankingLib.BPS;
        }

        for (uint256 i = 0; i < rewardTiers.length; i++) {
            if (rank >= rewardTiers[i].startRank && rank <= rewardTiers[i].endRank) {
                return (rewardPool * rewardTiers[i].percentage) / ArenaRankingLib.BPS;
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
        if (reward.claimed) revert RewardAlreadyClaimed();

        Season storage season = seasons[seasonNumber];
        if (season.isActive) revert NoActiveSeason();

        uint256 rewardAmount = calculateSeasonReward(msg.sender, seasonNumber);
        if (rewardAmount == 0) revert InsufficientRewardBalance();
        if (rewardAmount > season.totalRewardPool) revert InsufficientRewardBalance();

        reward.claimed = true;
        reward.reward = uint128(rewardAmount);
        reward.rank = uint64(getPlayerRank(msg.sender));

        (bool success, ) = msg.sender.call{value: rewardAmount}("");
        if (!success) revert TransferFailed();

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
        if (amount > address(this).balance) revert InsufficientContractBalance();
        (bool success, ) = owner().call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    function withdrawSpecificBNB(uint256 amount) external onlyOwner nonReentrant {
        if (amount > address(this).balance) revert InsufficientBNBBalance();
        (bool success, ) = owner().call{value: amount}("");
        if (!success) revert BNBTransferFailed();
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
