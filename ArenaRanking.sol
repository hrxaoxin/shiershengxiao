// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

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
 * - 赛季结束后根据排名领取奖励
 *
 * 升级支持：
 * - 支持UUPS代理升级模式
 */
contract ArenaRanking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

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
     * @dev 代币合约地址
     */
    address public tokenContract;

    /**
     * @dev 奖励池地址
     */
    address public rewardPool;

    /**
     * @dev 赛季奖励配置 [第一名, 第二名, 第三名]
     */
    uint256[3] public seasonRewards;

    /**
     * @dev 玩家赛季奖励领取记录
     * player => rewardAmount
     */
    mapping(address => uint256) public seasonRewardsClaimed;

    /**
     * @dev 玩家信息映射
     */
    mapping(address => PlayerRanking) public playerInfo;

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
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "ArenaRanking: Invalid token contract");
        tokenContract = _tokenContract;
        emit TokenContractSet(_tokenContract);
    }

    /**
     * @dev 设置奖励池地址
     * @param _rewardPool 奖励池地址
     */
    function setRewardPool(address _rewardPool) external onlyAuthorized {
        require(_rewardPool != address(0), "ArenaRanking: Invalid reward pool");
        rewardPool = _rewardPool;
        emit RewardPoolSet(_rewardPool);
    }

    /**
     * @dev 设置赛季奖励金额
     * @param firstReward 第一名奖励
     * @param secondReward 第二名奖励
     * @param thirdReward 第三名奖励
     */
    function setSeasonRewards(uint256 firstReward, uint256 secondReward, uint256 thirdReward) external onlyOwner {
        seasonRewards[0] = firstReward;
        seasonRewards[1] = secondReward;
        seasonRewards[2] = thirdReward;
        emit SeasonRewardsSet(firstReward, secondReward, thirdReward);
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "ArenaRanking: Not authorized");
        _;
    }

    /**
     * @dev 挑战事件
     */
    event ChallengeResult(
        address indexed player,
        bool isVictory,
        int256 scoreChange,
        uint256 newScore
    );

    /**
     * @dev 代币合约地址设置事件
     */
    event TokenContractSet(address indexed tokenContract);

    /**
     * @dev 奖励池地址设置事件
     */
    event RewardPoolSet(address indexed rewardPool);

    /**
     * @dev 赛季奖励配置设置事件
     */
    event SeasonRewardsSet(uint256 first, uint256 second, uint256 third);

    /**
     * @dev 赛季结束事件
     */
    event SeasonEnded(uint256 seasonId, uint256 totalWinners);

    /**
     * @dev 初始化赛季
     */
    function initializeSeason() external onlyOwner {
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
    ) external onlyOwner {
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
     * @dev 结束当前赛季
     */
    function endSeason() external onlyOwner {
        require(currentSeason.isActive, "ArenaRanking: Season not active");
        require(block.timestamp >= currentSeason.endTime, "ArenaRanking: Season not ended");

        currentSeason.isActive = false;

        emit SeasonEnded(currentSeason.seasonId, block.timestamp);
    }

    /**
     * @dev 领取赛季奖励
     */
    function claimSeasonReward() external returns (uint256) {
        require(!currentSeason.isActive, "ArenaRanking: Season still active");
        require(seasonRewardsClaimed[msg.sender] == 0, "ArenaRanking: Reward already claimed");

        uint256 playerScore = playerScores[msg.sender];
        require(playerScore > 0, "ArenaRanking: No score");

        uint256 reward = _calculateSeasonReward(playerScore);
        require(reward > 0, "ArenaRanking: No reward");

        require(tokenContract != address(0), "ArenaRanking: Token contract not set");
        require(rewardPool != address(0), "ArenaRanking: Reward pool not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(rewardPool) >= reward, "ArenaRanking: Insufficient reward pool balance");

        token.transferFrom(rewardPool, msg.sender, reward);

        seasonRewardsClaimed[msg.sender] = reward;

        emit SeasonRewardClaimed(msg.sender, reward);

        return reward;
    }

    /**
     * @dev 计算赛季奖励（内部函数）
     */
    function _calculateSeasonReward(uint256 score) internal view returns (uint256) {
        if (score >= 1000) {
            return seasonRewards[0];
        } else if (score >= 500) {
            return seasonRewards[1];
        } else if (score >= 100) {
            return seasonRewards[2];
        }
        return 0;
    }

    /**
     * @dev 获取赛季奖励金额
     */
    function getSeasonReward(address player) external view returns (uint256) {
        if (currentSeason.isActive || seasonRewardsClaimed[player] > 0) {
            return 0;
        }
        uint256 score = playerScores[player];
        return _calculateSeasonReward(score);
    }

    /**
     * @dev 赛季结束事件
     */
    event SeasonEnded(uint256 indexed seasonId, uint256 endTime);

    /**
     * @dev 赛季奖励领取事件
     */
    event SeasonRewardClaimed(address indexed player, uint256 amount);

    /**
     * @dev 获取玩家剩余挑战次数
     */
    function getRemainingChallenges(address player) external view returns (uint256) {
        return dailyChallenges[player];
    }
}
