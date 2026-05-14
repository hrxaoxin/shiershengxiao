// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./Battle.sol";

/**
 * @title ArenaRanking
 * @dev 十二生肖NFT竞技场排名合约
 * 管理赛季系统、玩家排名、挑战机制和奖励分发
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract ArenaRanking is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /** @dev 战斗合约地址 */
    Battle public battleContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 团队大小：每队6个NFT */
    uint256 public constant TEAM_SIZE = 6;
    /** @dev 胜利基础分数 */
    uint256 public constant BASE_WIN_POINTS = 100;
    /** @dev 失败基础分数（扣减） */
    uint256 public constant BASE_LOSS_POINTS = 50;
    /** @dev 最大排名加成分数 */
    uint256 public constant MAX_RANK_BONUS = 500;

    /**
     * @dev 玩家结构体
     * @param points 玩家积分
     * @param wins 胜利次数
     * @param losses 失败次数
     * @param lastBattleTime 上次战斗时间
     * @param offenseTeam 进攻队伍NFT列表
     * @param defenseTeam 防御队伍NFT列表
     */
    struct Player {
        uint256 points;
        uint256 wins;
        uint256 losses;
        uint256 lastBattleTime;
        uint256[] offenseTeam;
        uint256[] defenseTeam;
    }

    /**
     * @dev 赛季结构体
     * @param seasonNumber 赛季编号
     * @param startTime 赛季开始时间
     * @param endTime 赛季结束时间
     * @param isActive 是否活跃
     * @param totalReward 赛季总奖励
     */
    struct Season {
        uint256 seasonNumber;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        uint256 totalReward;
    }

    /**
     * @dev 赛季奖励结构体
     * @param seasonNumber 赛季编号
     * @param rank 玩家排名
     * @param reward 奖励金额
     * @param claimed 是否已领取
     */
    struct SeasonReward {
        uint256 seasonNumber;
        uint256 rank;
        uint256 reward;
        bool claimed;
    }

    /** @dev 玩家信息映射（地址 => 玩家） */
    mapping(address => Player) public players;
    /** @dev 赛季信息映射（赛季编号 => 赛季） */
    mapping(uint256 => Season) public seasons;
    /** @dev 玩家赛季奖励映射（地址 => 赛季编号 => 奖励） */
    mapping(address => mapping(uint256 => SeasonReward)) public playerRewards;
    /** @dev 前10名奖励映射（排名 => 奖励） */
    mapping(uint256 => uint256) public top10Rewards;
    /** @dev 分级奖励映射（等级 => 奖励） */
    mapping(uint256 => uint256) public tieredRewards;

    /** @dev NFT所属玩家映射（tokenId => 玩家地址） */
    mapping(uint256 => address) public nftToPlayer;
    /** @dev NFT是否在进攻队伍映射 */
    mapping(uint256 => bool) public isInOffenseTeam;
    /** @dev NFT是否在防御队伍映射 */
    mapping(uint256 => bool) public isInDefenseTeam;

    /** @dev 玩家地址列表 */
    address[] public playerAddresses;
    /** @dev 玩家是否已注册映射 */
    mapping(address => bool) public isPlayerRegistered;

    /** @dev 当前赛季 */
    uint256 public currentSeason;
    /** @dev 赛季持续时间（默认7天） */
    uint256 public seasonDuration;

    /**
     * @dev 挑战完成事件
     * @param attacker 攻击者地址
     * @param defender 防御者地址
     * @param attackerWon 攻击者是否获胜
     * @param attackerPointsChange 攻击者积分变化
     * @param defenderPointsChange 防御者积分变化
     * @param attackerRank 攻击者排名
     * @param defenderRank 防御者排名
     */
    event ChallengeCompleted(
        address indexed attacker,
        address indexed defender,
        bool attackerWon,
        int256 attackerPointsChange,
        int256 defenderPointsChange,
        uint256 attackerRank,
        uint256 defenderRank
    );

    /**
     * @dev 赛季开始事件
     * @param seasonNumber 赛季编号
     * @param startTime 开始时间
     * @param endTime 结束时间
     */
    event SeasonStarted(uint256 seasonNumber, uint256 startTime, uint256 endTime);

    /**
     * @dev 赛季结束事件
     * @param seasonNumber 赛季编号
     * @param totalReward 总奖励
     */
    event SeasonEnded(uint256 seasonNumber, uint256 totalReward);

    /**
     * @dev 奖励领取事件
     * @param player 玩家地址
     * @param seasonNumber 赛季编号
     * @param reward 奖励金额
     */
    event RewardClaimed(address indexed player, uint256 seasonNumber, uint256 reward);

    /**
     * @dev 进攻队伍设置事件
     * @param player 玩家地址
     * @param tokens NFT ID列表
     */
    event AttackTeamSet(address indexed player, uint256[] tokens);

    /**
     * @dev 防御队伍设置事件
     * @param player 玩家地址
     * @param tokens NFT ID列表
     */
    event DefenseTeamSet(address indexed player, uint256[] tokens);

    /**
     * @dev 队伍清空事件
     * @param player 玩家地址
     * @param isAttackTeam 是否进攻队伍
     */
    event TeamCleared(address indexed player, bool isAttackTeam);

    /**
     * @dev 赛季时长更新事件
     * @param oldDuration 旧时长
     * @param newDuration 新时长
     */
    event SeasonDurationUpdated(uint256 oldDuration, uint256 newDuration);

    /**
     * @dev 初始化合约
     * @param _battleContract 战斗合约地址
     */
    function initialize(address _battleContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        battleContract = Battle(_battleContract);
        currentSeason = 1;
        seasonDuration = 7 days;

        seasons[currentSeason] = Season({
            seasonNumber: currentSeason,
            startTime: block.timestamp,
            endTime: block.timestamp + seasonDuration,
            isActive: true,
            totalReward: 0
        });
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 设置战斗合约地址
     * @param _battleContract 战斗合约地址
     */
    function setBattleContract(address _battleContract) external onlyOwner {
        battleContract = Battle(_battleContract);
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 设置赛季持续时间
     * @param _duration 持续时间（秒）
     */
    function setSeasonDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Duration must be greater than 0");
        uint256 oldDuration = seasonDuration;
        seasonDuration = _duration;
        emit SeasonDurationUpdated(oldDuration, _duration);
    }

    /**
     * @dev 设置前10名奖励
     * @param rewards 奖励数组（索引0对应第1名，索引9对应第10名）
     */
    function setTop10Rewards(uint256[10] calldata rewards) external onlyOwner {
        for (uint256 i = 0; i < 10; i++) {
            top10Rewards[i + 1] = rewards[i];
        }
    }

    /**
     * @dev 设置分级奖励
     * @param tier 等级（从1开始）
     * @param reward 奖励金额
     */
    function setTieredReward(uint256 tier, uint256 reward) external onlyOwner {
        tieredRewards[tier] = reward;
    }

    /**
     * @dev 开启新赛季（仅限管理员）
     */
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

    /**
     * @dev 检查赛季是否结束（公开调用）
     */
    function checkSeasonEnd() external {
        Season storage current = seasons[currentSeason];
        if (current.isActive && block.timestamp >= current.endTime) {
            _endSeasonAndCalculateRewards();
        }
    }

    /**
     * @dev 结束赛季并计算奖励（内部函数）
     */
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

    /**
     * @dev 设置进攻队伍
     * @param tokenIds NFT ID数组（6个）
     */
    function setAttackTeam(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length == TEAM_SIZE, "E03: Attack team must have 6 NFTs");

        _validateUniqueTokens(tokenIds);

        _clearAttackTeam(msg.sender);

        Player storage player = players[msg.sender];
        player.offenseTeam = tokenIds;

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

    /**
     * @dev 设置防御队伍
     * @param tokenIds NFT ID数组（6个）
     */
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

    /**
     * @dev 清空进攻队伍
     */
    function clearAttackTeam() external nonReentrant {
        _clearAttackTeam(msg.sender);
        emit TeamCleared(msg.sender, true);
    }

    /**
     * @dev 清空防御队伍
     */
    function clearDefenseTeam() external nonReentrant {
        _clearDefenseTeam(msg.sender);
        emit TeamCleared(msg.sender, false);
    }

    /**
     * @dev 清空所有队伍
     */
    function clearAllTeams() external nonReentrant {
        _clearAttackTeam(msg.sender);
        _clearDefenseTeam(msg.sender);
        emit TeamCleared(msg.sender, true);
        emit TeamCleared(msg.sender, false);
    }

    /**
     * @dev 清空进攻队伍（内部函数）
     * @param player 玩家地址
     */
    function _clearAttackTeam(address player) internal {
        Player storage p = players[player];
        for (uint256 i = 0; i < p.offenseTeam.length; i++) {
            uint256 tokenId = p.offenseTeam[i];
            if (isInAttackTeam[tokenId] && !isInDefenseTeam[tokenId]) {
                delete nftToPlayer[tokenId];
            }
            isInAttackTeam[tokenId] = false;
        }
        delete p.offenseTeam;
    }

    /**
     * @dev 清空防御队伍（内部函数）
     * @param player 玩家地址
     */
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

    /**
     * @dev 发起挑战
     * @param defender 防御者地址
     * @return bool 攻击者是否获胜
     * @return uint256 攻击者获胜场次
     * @return uint256 防御者获胜场次
     */
    function challenge(address defender) external nonReentrant returns (bool, uint256, uint256) {
        require(seasons[currentSeason].isActive, "E02: Season not active");

        Player storage attacker = players[msg.sender];
        Player storage defenderPlayer = players[defender];

        require(attacker.offenseTeam.length == TEAM_SIZE, "E05: Attacker must set attack team");
        require(defenderPlayer.defenseTeam.length == TEAM_SIZE, "E06: Defender must set defense team");
        require(msg.sender != defender, "E16: Cannot challenge yourself");

        if (!isPlayerRegistered[msg.sender]) {
            _registerPlayer(msg.sender);
        }
        if (!isPlayerRegistered[defender]) {
            _registerPlayer(defender);
        }

        uint256 attackerRank = getPlayerRank(msg.sender);
        uint256 defenderRank = getPlayerRank(defender);

        (bool attackerWon, uint256 attackerWinCount, uint256 defenderWinCount) =
            battleContract.battle(attacker.offenseTeam, defenderPlayer.defenseTeam);

        int256 attackerPointsChange;
        int256 defenderPointsChange;

        if (attackerWon) {
            attackerPointsChange = _calculateWinPoints(attackerRank, defenderRank, attackerWinCount);
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
            defenderPointsChange = _calculateWinPoints(defenderRank, attackerRank, defenderWinCount);
            defenderPlayer.points += uint256(defenderPointsChange);
            defenderPlayer.wins++;

            attackerPointsChange = -_calculateLossPoints(attackerRank, defenderRank);
            if (attacker.points > uint256(-attackerPointsChange)) {
                attacker.points -= uint256(-attackerPointsChange);
            } else {
                attacker.points = 0;
            }
            attacker.losses++;
        }

        attacker.lastBattleTime = block.timestamp;

        emit ChallengeCompleted(msg.sender, defender, attackerWon, attackerPointsChange, defenderPointsChange, attackerRank, defenderRank);

        return (attackerWon, attackerWinCount, defenderWinCount);
    }

    /**
     * @dev 计算胜利积分（内部函数）
     * @param attackerRank 攻击者排名
     * @param defenderRank 防御者排名
     * @param winCount 获胜场次
     * @return int256 积分变化
     */
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

    /**
     * @dev 计算失败扣分（内部函数）
     * @param attackerRank 攻击者排名
     * @param defenderRank 防御者排名
     * @return uint256 扣分数值
     */
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

    /**
     * @dev 验证NFT唯一性（内部函数）
     * @param tokenIds NFT ID数组
     */
    function _validateUniqueTokens(uint256[] calldata tokenIds) internal pure {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenIds[i] != tokenIds[j], "E16: Duplicate NFT in team");
            }
        }
    }

    /**
     * @dev 注册玩家（内部函数）
     * @param player 玩家地址
     */
    function _registerPlayer(address player) internal {
        isPlayerRegistered[player] = true;
        playerAddresses.push(player);
    }

    /**
     * @dev 获取玩家排名
     * @param player 玩家地址
     * @return uint256 排名
     */
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

    /**
     * @dev 获取总玩家数
     * @return uint256 玩家数量
     */
    function getTotalPlayers() public view returns (uint256) {
        return playerAddresses.length;
    }

    /**
     * @dev 计算赛季奖励
     * @param player 玩家地址
     * @param seasonNumber 赛季编号
     * @return uint256 奖励金额
     */
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

    /**
     * @dev 领取赛季奖励
     * @param seasonNumber 赛季编号
     */
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

    /**
     * @dev 获取未领取奖励列表
     * @param player 玩家地址
     * @return uint256[] 赛季编号数组
     * @return uint256[] 奖励金额数组
     */
    function getUnclaimedRewards(address player) public view returns (uint256[] memory, uint256[] memory) {
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

    /**
     * @dev 获取已领取奖励列表
     * @param player 玩家地址
     * @return uint256[] 赛季编号数组
     * @return uint256[] 奖励金额数组
     */
    function getClaimedRewards(address player) public view returns (uint256[] memory, uint256[] memory) {
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

    /**
     * @dev 提取BNB（仅限管理员）
     * @param amount 提取金额
     */
    function withdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "E12: Insufficient balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "E13: Transfer failed");
    }

    /**
     * @dev 检查NFT是否在竞技场中
     * @param tokenId NFT ID
     * @return bool 是否在竞技场
     */
    function isNFTInArena(uint256 tokenId) external view returns (bool) {
        return isInAttackTeam[tokenId] || isInDefenseTeam[tokenId];
    }

    /**
     * @dev 获取玩家进攻队伍
     * @param player 玩家地址
     * @return uint256[] NFT ID数组
     */
    function getPlayerAttackTeam(address player) external view returns (uint256[] memory) {
        return players[player].offenseTeam;
    }

    /**
     * @dev 获取玩家防御队伍
     * @param player 玩家地址
     * @return uint256[] NFT ID数组
     */
    function getPlayerDefenseTeam(address player) external view returns (uint256[] memory) {
        return players[player].defenseTeam;
    }

    /**
     * @dev 获取赛季信息
     * @param seasonNumber 赛季编号
     * @return Season 赛季结构体
     */
    function getSeasonInfo(uint256 seasonNumber) external view returns (Season memory) {
        return seasons[seasonNumber];
    }

    /**
     * @dev 获取当前赛季信息
     * @return Season 赛季结构体
     */
    function getCurrentSeasonInfo() external view returns (Season memory) {
        return seasons[currentSeason];
    }

    /**
     * @dev 接收BNB
     */
    receive() external payable {}
}
