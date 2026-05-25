// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ArenaRanking
 * @dev 竞技场排名合约，实现PVP竞技场系统
 *
 * 竞技场规则：
 * 1. 赛季制（默认7天）
 * 2. 每日5次挑战机会
 * 3. 可挑战虚拟玩家或真实玩家
 * 4. 排名基于积分
 *
 * 积分系统：
 * - 胜利: +25分
 * - 失败: -10分
 * - 最低积分: 0
 *
 * 奖励机制：
 * - 每日领取基础奖励
 * - 赛季结束领取排名奖励
 */
contract ArenaRanking {
    /**
     * @dev 赛季信息结构体
     */
    struct Season {
        uint256 seasonId;
        uint256 startTime;
        uint256 endTime;
        uint256 totalRewards;
        bool isActive;
    }

    /**
     * @dev 玩家排名信息
     */
    struct PlayerRanking {
        address player;
        uint256 score;
        uint256 tier;
        uint256 wins;
        uint256 losses;
        uint256 lastChallengeTime;
    }

    /**
     * @dev 虚拟玩家配置
     */
    struct MockPlayer {
        uint256 score;
        uint256 tier;
        uint256[6] team;
    }

    /**
     * @dev 虚拟玩家列表
     */
    MockPlayer[] public mockPlayers;

    /**
     * @dev 排名列表
     */
    PlayerRanking[] public rankings;

    /**
     * @dev 当前赛季
     */
    Season public currentSeason;

    /**
     * @dev 玩家每日挑战次数
     * player => challengesRemaining
     */
    mapping(address => uint256) public dailyChallenges;

    /**
     * @dev 玩家上次重置时间
     */
    mapping(address => uint256) public lastResetTime;

    /**
     * @dev 玩家积分映射
     */
    mapping(address => uint256) public playerScores;

    /**
     * @dev 玩家信息映射
     */
    mapping(address => PlayerRanking) public playerInfo;

    /**
     * @dev 每日基础奖励
     */
    uint256 public dailyBaseReward = 10 * 10**18;

    /**
     * @dev 挑战胜利得分
     */
    uint256 public constant WIN_SCORE = 25;

    /**
     * @dev 挑战失败扣分
     */
    uint256 public constant LOSS_SCORE = 10;

    /**
     * @dev 每日挑战次数
     */
    uint256 public constant DAILY_CHALLENGES = 5;

    /**
     * @dev 赛季时长（秒）
     */
    uint256 public constant SEASON_DURATION = 7 days;

    /**
     * @dev 挑战事件
     */
    event ChallengeResult(
        address indexed player,
        bool isVictory,
        uint256 scoreChange,
        uint256 newScore
    );

    /**
     * @dev 赛季结束事件
     */
    event SeasonEnded(uint256 seasonId, uint256 totalWinners);

    /**
     * @dev 初始化赛季
     */
    function initializeSeason() external {
        currentSeason = Season({
            seasonId: 1,
            startTime: block.timestamp,
            endTime: block.timestamp + SEASON_DURATION,
            totalRewards: 1000 * 10**18,
            isActive: true
        });
    }

    /**
     * @dev 挑战虚拟玩家
     */
    function challengeMockPlayer(
        uint256[6] calldata playerTeam,
        uint256 mockIndex
    ) external returns (bool) {
        require(playerTeam.length == 6, "ArenaRanking: Invalid team size");
        require(mockIndex < mockPlayers.length, "ArenaRanking: Invalid mock player");

        _resetDailyChallengesIfNeeded(msg.sender);

        require(dailyChallenges[msg.sender] > 0, "ArenaRanking: No challenges left");
        dailyChallenges[msg.sender]--;

        bool victory = _simulateBattleResult(playerTeam, mockPlayers[mockIndex].team);

        if (victory) {
            playerScores[msg.sender] += WIN_SCORE;
            emit ChallengeResult(msg.sender, true, WIN_SCORE, playerScores[msg.sender]);
        } else {
            if (playerScores[msg.sender] >= LOSS_SCORE) {
                playerScores[msg.sender] -= LOSS_SCORE;
            } else {
                playerScores[msg.sender] = 0;
            }
            emit ChallengeResult(msg.sender, false, int256(LOSS_SCORE), playerScores[msg.sender]);
        }

        return victory;
    }

    /**
     * @dev 挑战真实玩家
     */
    function challengeRealPlayer(
        address challengedPlayer,
        uint256[6] calldata playerTeam
    ) external returns (bool) {
        require(challengedPlayer != msg.sender, "ArenaRanking: Cannot challenge self");

        _resetDailyChallengesIfNeeded(msg.sender);
        require(dailyChallenges[msg.sender] > 0, "ArenaRanking: No challenges left");

        dailyChallenges[msg.sender]--;

        bool victory = true;

        if (victory) {
            playerScores[msg.sender] += WIN_SCORE;
            playerScores[challengedPlayer] = playerScores[challengedPlayer] >= LOSS_SCORE
                ? playerScores[challengedPlayer] - LOSS_SCORE
                : 0;
        }

        return victory;
    }

    /**
     * @dev 领取每日奖励
     */
    function claimDailyReward() external {
        require(playerScores[msg.sender] > 0, "ArenaRanking: No score");

        uint256 reward = dailyBaseReward * playerScores[msg.sender] / 1000;
        emit ChallengeResult(msg.sender, false, 0, 0);
    }

    /**
     * @dev 获取玩家排名
     */
    function getPlayerRank(address player) external view returns (uint256) {
        return playerScores[player];
    }

    /**
     * @dev 获取排名信息
     */
    function getRankings(
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (
        address[] memory players,
        uint256[] memory scores,
        uint256[] memory tiers
    ) {
        uint256 length = endIndex - startIndex + 1;
        players = new address[](length);
        scores = new uint256[](length);
        tiers = new uint256[](length);

        return (players, scores, tiers);
    }

    /**
     * @dev 获取赛季信息
     */
    function getSeasonInfo() external view returns (
        uint256 seasonId,
        uint256 startTime,
        uint256 endTime
    ) {
        return (currentSeason.seasonId, currentSeason.startTime, currentSeason.endTime);
    }

    /**
     * @dev 重置每日挑战次数
     */
    function _resetDailyChallengesIfNeeded(address player) internal {
        if (block.timestamp - lastResetTime[player] >= 24 hours) {
            dailyChallenges[player] = DAILY_CHALLENGES;
            lastResetTime[player] = block.timestamp;
        }
    }

    /**
     * @dev 模拟战斗结果
     */
    function _simulateBattleResult(
        uint256[6] memory team1,
        uint256[6] memory team2
    ) internal view returns (bool) {
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            msg.sender,
            team1[0],
            team2[0]
        )));
        return seed % 100 > 40;
    }

    /**
     * @dev 添加虚拟玩家
     */
    function addMockPlayer(
        uint256 score,
        uint256 tier,
        uint256[6] memory team
    ) external {
        mockPlayers.push(MockPlayer({
            score: score,
            tier: tier,
            team: team
        }));
    }

    /**
     * @dev 获取虚拟玩家数量
     */
    function getMockPlayerCount() external view returns (uint256) {
        return mockPlayers.length;
    }

    /**
     * @dev 获取玩家剩余挑战次数
     */
    function getRemainingChallenges(address player) external view returns (uint256) {
        return dailyChallenges[player];
    }
}
