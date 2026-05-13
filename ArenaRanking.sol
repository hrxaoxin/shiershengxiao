// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./Battle.sol";

contract ArenaRanking is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    Battle public battleContract;
    
    uint256 public constant TEAM_SIZE = 6;
    
    struct Player {
        uint256 points;
        uint256 wins;
        uint256 losses;
        uint256 lastBattleTime;
        uint256[] attackTeam;
        uint256[] defenseTeam;
    }
    
    struct Season {
        uint256 seasonNumber;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        uint256 totalReward;
    }
    
    struct SeasonReward {
        uint256 seasonNumber;
        uint256 rank;
        uint256 reward;
        bool claimed;
    }
    
    mapping(address => Player) public players;
    mapping(uint256 => Season) public seasons;
    mapping(address => mapping(uint256 => SeasonReward)) public playerRewards;
    mapping(uint256 => uint256) public top10Rewards;
    mapping(uint256 => uint256) public tieredRewards;
    
    mapping(uint256 => address) public nftToPlayer;
    mapping(uint256 => bool) public isInAttackTeam;
    mapping(uint256 => bool) public isInDefenseTeam;
    
    address[] public playerAddresses;
    mapping(address => bool) public isPlayerRegistered;
    
    uint256 public currentSeason;
    uint256 public seasonDuration;
    uint256 public dailyBattleLimit;
    
    event ChallengeCompleted(
        address indexed attacker,
        address indexed defender,
        bool attackerWon,
        int256 attackerPointsChange,
        int256 defenderPointsChange
    );
    
    event SeasonStarted(uint256 seasonNumber, uint256 startTime, uint256 endTime);
    
    event SeasonEnded(uint256 seasonNumber, uint256 totalReward);
    
    event RewardClaimed(address indexed player, uint256 seasonNumber, uint256 reward);
    
    event AttackTeamSet(address indexed player, uint256[] tokens);
    
    event DefenseTeamSet(address indexed player, uint256[] tokens);
    
    event TeamCleared(address indexed player, bool isAttackTeam);
    
    function initialize(address _battleContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        battleContract = Battle(_battleContract);
        currentSeason = 1;
        seasonDuration = 30 days;
        dailyBattleLimit = 10;
        
        seasons[currentSeason] = Season({
            seasonNumber: currentSeason,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            totalReward: 0
        });
    }
    
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    function setBattleContract(address _battleContract) external onlyOwner {
        battleContract = Battle(_battleContract);
    }
    
    function setSeasonDuration(uint256 _duration) external onlyOwner {
        seasonDuration = _duration;
    }
    
    function setDailyBattleLimit(uint256 _limit) external onlyOwner {
        dailyBattleLimit = _limit;
    }
    
    function setTop10Rewards(uint256[10] calldata rewards) external onlyOwner {
        for (uint256 i = 0; i < 10; i++) {
            top10Rewards[i + 1] = rewards[i];
        }
    }
    
    function setTieredReward(uint256 tier, uint256 reward) external onlyOwner {
        tieredRewards[tier] = reward;
    }
    
    function startNewSeason() external onlyOwner {
        require(seasons[currentSeason].isActive, "E01: No active season");
        
        seasons[currentSeason].isActive = false;
        seasons[currentSeason].totalReward = address(this).balance;
        
        emit SeasonEnded(currentSeason, seasons[currentSeason].totalReward);
        
        currentSeason++;
        seasons[currentSeason] = Season({
            seasonNumber: currentSeason,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            totalReward: 0
        });
        
        emit SeasonStarted(currentSeason, block.timestamp, block.timestamp + seasonDuration);
    }
    
    function checkSeasonEnd() external {
        Season storage current = seasons[currentSeason];
        if (current.isActive && block.timestamp >= current.endTime) {
            _endSeasonAndCalculateRewards();
        }
    }
    
    function _endSeasonAndCalculateRewards() internal {
        Season storage current = seasons[currentSeason];
        current.isActive = false;
        current.totalReward = address(this).balance;
        
        emit SeasonEnded(currentSeason, current.totalReward);
        
        currentSeason++;
        seasons[currentSeason] = Season({
            seasonNumber: currentSeason,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            totalReward: 0
        });
        
        emit SeasonStarted(currentSeason, block.timestamp, block.timestamp + seasonDuration);
    }
    
    function setAttackTeam(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length == TEAM_SIZE, "E03: Attack team must have 6 NFTs");
        
        _validateUniqueTokens(tokenIds);
        
        _clearAttackTeam(msg.sender);
        
        Player storage player = players[msg.sender];
        player.attackTeam = tokenIds;
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            require(!isInDefenseTeam[tokenIds[i]], "E14: NFT already in defense team");
            nftToPlayer[tokenIds[i]] = msg.sender;
            isInAttackTeam[tokenIds[i]] = true;
        }
        
        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }
        
        emit AttackTeamSet(msg.sender, tokenIds);
    }
    
    function setDefenseTeam(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length == TEAM_SIZE, "E04: Defense team must have 6 NFTs");
        
        _validateUniqueTokens(tokenIds);
        
        _clearDefenseTeam(msg.sender);
        
        Player storage player = players[msg.sender];
        player.defenseTeam = tokenIds;
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            require(!isInAttackTeam[tokenIds[i]], "E15: NFT already in attack team");
            nftToPlayer[tokenIds[i]] = msg.sender;
            isInDefenseTeam[tokenIds[i]] = true;
        }
        
        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }
        
        emit DefenseTeamSet(msg.sender, tokenIds);
    }
    
    function clearAttackTeam() external nonReentrant {
        _clearAttackTeam(msg.sender);
        emit TeamCleared(msg.sender, true);
    }
    
    function clearDefenseTeam() external nonReentrant {
        _clearDefenseTeam(msg.sender);
        emit TeamCleared(msg.sender, false);
    }
    
    function clearAllTeams() external nonReentrant {
        _clearAttackTeam(msg.sender);
        _clearDefenseTeam(msg.sender);
        emit TeamCleared(msg.sender, true);
        emit TeamCleared(msg.sender, false);
    }
    
    function _clearAttackTeam(address player) internal {
        Player storage p = players[player];
        for (uint256 i = 0; i < p.attackTeam.length; i++) {
            uint256 tokenId = p.attackTeam[i];
            if (isInAttackTeam[tokenId] && !isInDefenseTeam[tokenId]) {
                delete nftToPlayer[tokenId];
            }
            isInAttackTeam[tokenId] = false;
        }
        delete p.attackTeam;
    }
    
    function _clearDefenseTeam(address player) internal {
        Player storage p = players[player];
        for (uint256 i = 0; i < p.defenseTeam.length; i++) {
            uint256 tokenId = p.defenseTeam[i];
            if (isInDefenseTeam[tokenId] && !isInAttackTeam[tokenId]) {
                delete nftToPlayer[tokenId];
            }
            isInDefenseTeam[tokenId] = false;
        }
        delete p.defenseTeam;
    }
    
    function challenge(address defender) external nonReentrant returns (bool, uint256, uint256) {
        require(seasons[currentSeason].isActive, "E02: Season not active");
        
        Player storage attacker = players[msg.sender];
        Player storage defenderPlayer = players[defender];
        
        require(attacker.attackTeam.length == TEAM_SIZE, "E05: Attacker must set attack team");
        require(defenderPlayer.defenseTeam.length == TEAM_SIZE, "E06: Defender must set defense team");
        
        uint256 today = block.timestamp / 1 days;
        uint256 attackerLastBattleDay = attacker.lastBattleTime / 1 days;
        if (attackerLastBattleDay == today) {
            require(attacker.wins + attacker.losses < dailyBattleLimit, "E07: Daily battle limit exceeded");
        }
        
        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }
        if (!isPlayerRegistered[defender]) {
            _registerPlayer(defender);
        }
        
        (bool attackerWon, uint256 attackerWinCount, uint256 defenderWinCount) = 
            battleContract.battle(attacker.attackTeam, defenderPlayer.defenseTeam);
        
        int256 attackerPointsChange;
        int256 defenderPointsChange;
        
        uint256 battlePoints = attackerWinCount * 100;
        
        if (attackerWon) {
            attackerPointsChange = int256(battlePoints);
            attacker.points += uint256(attackerPointsChange);
            attacker.wins++;
            
            defenderPointsChange = -attackerPointsChange / 2;
            if (defenderPlayer.points > uint256(-defenderPointsChange)) {
                defenderPlayer.points -= uint256(-defenderPointsChange);
            } else {
                defenderPlayer.points = 0;
            }
            defenderPlayer.losses++;
        } else {
            attackerPointsChange = -50;
            if (attacker.points > 50) {
                attacker.points -= 50;
            } else {
                attacker.points = 0;
            }
            attacker.losses++;
            
            defenderPointsChange = int256(battlePoints);
            defenderPlayer.points += uint256(battlePoints);
            defenderPlayer.wins++;
        }
        
        attacker.lastBattleTime = block.timestamp;
        
        emit ChallengeCompleted(msg.sender, defender, attackerWon, attackerPointsChange, defenderPointsChange);
        
        return (attackerWon, attackerWinCount, defenderWinCount);
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
    }
    
    function getPlayerRank(address player) public view returns (uint256) {
        uint256 playerPoints = players[player].points;
        uint256 rank = 1;
        
        for (uint256 i = 0; i < playerAddresses.length; i++) {
            if (playerAddresses[i] != player && players[playerAddresses[i]].points > playerPoints) {
                rank++;
            }
        }
        
        return rank;
    }
    
    function getTotalPlayers() public view returns (uint256) {
        return playerAddresses.length;
    }
    
    function calculateSeasonReward(address player, uint256 seasonNumber) public view returns (uint256) {
        SeasonReward storage reward = playerRewards[player][seasonNumber];
        if (reward.claimed) return 0;
        
        uint256 rank = getPlayerRank(player);
        
        if (rank <= 10) {
            return top10Rewards[rank];
        } else {
            uint256 tier = (rank - 11) / 100 + 1;
            return tieredRewards[tier];
        }
    }
    
    function claimReward(uint256 seasonNumber) external nonReentrant {
        SeasonReward storage reward = playerRewards[msg.sender][seasonNumber];
        require(!reward.claimed, "E08: Reward already claimed");
        
        Season storage season = seasons[seasonNumber];
        require(!season.isActive, "E09: Season still active");
        
        uint256 rewardAmount = calculateSeasonReward(msg.sender, seasonNumber);
        require(rewardAmount > 0, "E10: No reward available");
        
        reward.claimed = true;
        reward.reward = rewardAmount;
        
        (bool success, ) = msg.sender.call{value: rewardAmount}("");
        require(success, "E11: Transfer failed");
        
        emit RewardClaimed(msg.sender, seasonNumber, rewardAmount);
    }
    
    function getUnclaimedRewards(address player) public view returns (uint256[] memory, uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (!playerRewards[player][i].claimed && calculateSeasonReward(player, i) > 0) {
                count++;
            }
        }
        
        uint256[] memory seasons = new uint256[](count);
        uint256[] memory rewards = new uint256[](count);
        
        count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (!playerRewards[player][i].claimed && calculateSeasonReward(player, i) > 0) {
                seasons[count] = i;
                rewards[count] = calculateSeasonReward(player, i);
                count++;
            }
        }
        
        return (seasons, rewards);
    }
    
    function getClaimedRewards(address player) public view returns (uint256[] memory, uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (playerRewards[player][i].claimed) {
                count++;
            }
        }
        
        uint256[] memory seasons = new uint256[](count);
        uint256[] memory rewards = new uint256[](count);
        
        count = 0;
        for (uint256 i = 1; i < currentSeason; i++) {
            if (playerRewards[player][i].claimed) {
                seasons[count] = i;
                rewards[count] = playerRewards[player][i].reward;
                count++;
            }
        }
        
        return (seasons, rewards);
    }
    
    function withdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "E12: Insufficient balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "E13: Transfer failed");
    }
    
    function isNFTInArena(uint256 tokenId) external view returns (bool) {
        return isInAttackTeam[tokenId] || isInDefenseTeam[tokenId];
    }
    
    function getPlayerAttackTeam(address player) external view returns (uint256[] memory) {
        return players[player].attackTeam;
    }
    
    function getPlayerDefenseTeam(address player) external view returns (uint256[] memory) {
        return players[player].defenseTeam;
    }
    
    receive() external payable {}
}