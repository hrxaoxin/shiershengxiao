// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

/**
 * @title ArenaReward
 * @dev 竞技场奖励合约，负责赛季奖励的计算和发放
 * 
 * 核心功能：
 * 1. 赛季奖励计算：根据玩家排名计算奖励分配
 * 2. 奖励发放：处理玩家领取竞技奖励（LP形式）
 * 3. 奖励池管理：管理 LP 奖励池
 * 4. 模拟玩家奖励：处理虚拟玩家获得的奖励
 * 
 * 奖励机制：
 * - 赛季结束后计算奖励
 * - 根据玩家排名分配奖励
 * - 奖励以LP形式发放，领取时自动兑换为代币+WBNB
 * - 奖励率可配置，影响奖励分配比例
 * 
 * 与其他合约的交互：
 * - ArenaRanking / ArenaRankingManager：获取竞技数据和玩家排名
 * - ArenaLeaderboard：获取排行榜数据
 * - Token 合约：处理代币转账
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * 
 * 权限控制：
 * - onlyOwner：管理合约、设置参数
 * - onlyOwnerOrAuthorizer：计算奖励、设置合约地址
 */
contract ArenaReward is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using LPLib for IAuthorizer;

    /**
     * @dev 赛季奖励信息结构体
     * @param rewardPool BNB 奖励池
     * @param tokenRewardPool 代币奖励池
     * @param pendingRewards 待发放奖励
     * @param rewardCalculated 奖励是否已计算
     * @param totalDistributed 已发放奖励总额
     */
    struct SeasonRewardInfo {
        uint256 rewardPool;
        uint256 tokenRewardPool;
        uint256 pendingRewards;
        bool rewardCalculated;
        uint256 totalDistributed;
    }

    /**
     * @dev 模拟玩家奖励接收地址
     */
    address public mockRewardRecipient;
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    /**
     * @dev 奖励类型：0 = BNB, 1 = 代币
     */
    uint8 public rewardType;
    
    /**
     * @dev 今日奖励金额
     */
    uint256 public todayRewardAmount;
    /**
     * @dev 奖励率（百分比）
     */
    uint256 public rewardRate = 100;
    /**
     * @dev 最大奖励率
     */
    uint256 public maxRewardRate = 200;
    /**
     * @dev 奖励率步长
     */
    uint256 public rateStep = 10;
    
    /**
     * @dev 今日开始时间
     */
    uint256 public todayStart;
    /**
     * @dev 今日流入奖励
     */
    uint256 public todayIncomingReward;
    
    /**
     * @dev 赛季奖励信息映射
     */
    mapping(uint256 => SeasonRewardInfo) public seasonRewards;
    /**
     * @dev 玩家赛季奖励映射
     */
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    /**
     * @dev 玩家奖励领取状态映射
     */
    mapping(uint256 => mapping(address => bool)) public claimedRewards;

    /**
     * @dev 赛季奖励计算事件
     */
    event SeasonRewardsCalculated(uint256 seasonId, uint256 totalReward, uint256 distributed);
    /**
     * @dev 奖励领取事件
     */
    event RewardClaimed(address player, uint256 seasonId, uint256 amount);
    /**
     * @dev 模拟玩家奖励发放事件
     */
    event MockRewardDistributed(address recipient, uint256 amount, uint256 seasonId);
    /**
     * @dev 模拟玩家奖励分配失败事件
     */
    event MockRewardDistributionFailed(uint256 amount, uint256 seasonId);
    /**
     * @dev 奖励添加事件
     */
    event RewardAdded(uint256 amount);
    /**
     * @dev 紧急提取事件
     */
    event EmergencyWithdraw(address recipient, uint256 amount);

    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaReward: Not authorized");
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
        rewardType = 1;
    }
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaReward: Invalid authorizer address");
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
     * @dev 设置模拟玩家奖励接收地址
     * @param recipient 接收地址
     */
    function setMockRewardRecipient(address recipient) external onlyOwner {
        mockRewardRecipient = recipient;
    }

    /**
     * @dev 计算赛季奖励
     * @param seasonId 赛季 ID
     */
    function calculateSeasonRewards(uint256 seasonId) external onlyOwnerOrAuthorizer whenNotPaused nonReentrant {
        require(!seasonRewards[seasonId].rewardCalculated, "ArenaReward: Already calculated");
        
        (uint256 rewardPool, uint256 tokenRewardPool, uint256 totalPlayers) = _getSeasonData(seasonId);
        require(rewardPool + tokenRewardPool > 0, "ArenaReward: No reward in pool");
        
        SeasonRewardInfo storage seasonReward = seasonRewards[seasonId];
        seasonReward.rewardPool = rewardPool;
        seasonReward.tokenRewardPool = tokenRewardPool;
        
        uint256 totalReward = rewardPool;
        if (rewardType == 1) {
            totalReward = tokenRewardPool;
        }
        
        uint256 mockRewardTotal = _calculateMockRewards(seasonId, totalReward);
        uint256 distributed = _calculateRealPlayerRewards(seasonId, totalReward, mockRewardTotal);
        
        seasonReward.pendingRewards += distributed;
        seasonReward.rewardCalculated = true;
        seasonReward.totalDistributed = distributed;
        
        if (mockRewardTotal > 0 && mockRewardRecipient != address(0)) {
            if (rewardType == 0) {
                (bool success, ) = payable(mockRewardRecipient).call{value: mockRewardTotal}("");
                if (success) {
                    emit MockRewardDistributed(mockRewardRecipient, mockRewardTotal, seasonId);
                } else {
                    emit MockRewardDistributionFailed(mockRewardTotal, seasonId);
                }
            } else {
                address tokenContract = IAuthorizer(authorizer).getToken();
                require(tokenContract != address(0), "ArenaReward: Token contract not set");
                SafeERC20.safeTransfer(IERC20(tokenContract), mockRewardRecipient, mockRewardTotal);
                emit MockRewardDistributed(mockRewardRecipient, mockRewardTotal, seasonId);
            }
        }
        
        emit SeasonRewardsCalculated(seasonId, totalReward, distributed);
    }

    /**
     * @dev 内部函数：获取竞技数据
     * @param seasonId 赛季 ID
     * @return rewardPool BNB 奖励池, tokenRewardPool 代币奖励池, totalPlayers 总玩家数
     */
    function _getSeasonData(uint256 seasonId) internal view returns (uint256, uint256, uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        return IArenaRanking(arenaRankingManager).getSeasonRewardData(seasonId);
    }

    /**
     * @dev 内部函数：计算模拟玩家奖励
     * @param seasonId 赛季 ID
     * @param totalReward 总奖励金额
     * @return 模拟玩家奖励总额
     */
    function _calculateMockRewards(uint256 seasonId, uint256 totalReward) internal view returns (uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        address[] memory rankings = IArenaRanking(arenaRankingManager).getSeasonRankings(seasonId);
        uint256 totalPlayers = rankings.length;
        uint256 mockRewardTotal = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = rankings[i];
            if (IArenaRanking(arenaRankingManager).isMockPlayer(player)) {
                uint256 rank = i + 1;
                uint256 reward = ArenaRankingLib.calculateRankReward(rank, totalReward, totalPlayers);
                mockRewardTotal += reward;
            }
        }
        
        return mockRewardTotal;
    }

    /**
     * @dev 内部函数：计算真实玩家奖励
     * @param seasonId 赛季 ID
     * @param totalReward 总奖励金额
     * @param mockRewardTotal 模拟玩家奖励总额
     * @return 已分配奖励总额
     */
    function _calculateRealPlayerRewards(uint256 seasonId, uint256 totalReward, uint256 mockRewardTotal) internal returns (uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        address[] memory rankings = IArenaRanking(arenaRankingManager).getSeasonRankings(seasonId);
        uint256 totalRealPlayers = IArenaRanking(arenaRankingManager).countRealPlayers(seasonId);
        
        uint256 realPlayerRewardPool = mockRewardTotal <= totalReward ? totalReward - mockRewardTotal : 0;
        
        return _distributeRealPlayerRewards(seasonId, rankings, arenaRankingManager, realPlayerRewardPool, totalRealPlayers);
    }

    /**
     * @dev 内部函数：分配真实玩家奖励
     * @param seasonId 赛季 ID
     * @param rankings 排名数组
     * @param arenaRankingManager 排名管理合约地址
     * @param realPlayerRewardPool 真实玩家奖励池
     * @param totalRealPlayers 真实玩家总数
     * @return distributed 已分配的奖励总额
     */
    function _distributeRealPlayerRewards(
        uint256 seasonId,
        address[] memory rankings,
        address arenaRankingManager,
        uint256 realPlayerRewardPool,
        uint256 totalRealPlayers
    ) internal returns (uint256) {
        uint256 distributed = 0;
        for (uint256 i = 0; i < rankings.length; i++) {
            address player = rankings[i];
            if (IArenaRanking(arenaRankingManager).isMockPlayer(player)) {
                continue;
            }
            uint256 rank = IArenaRanking(arenaRankingManager).getRealPlayerRank(seasonId, i);
            uint256 rankReward = ArenaRankingLib.calculateRankReward(rank, realPlayerRewardPool, totalRealPlayers);
            playerSeasonRewards[seasonId][player] = rankReward;
            distributed += rankReward;
        }
        return distributed;
    }

    /**
     * @dev 内部函数：发放模拟玩家奖励
     * @param amount 奖励金额
     */
    function _distributeMockReward(uint256 amount) internal {
        if (rewardType == 0) {
            (bool success, ) = payable(mockRewardRecipient).call{value: amount}("");
            require(success, "ArenaReward: Mock reward transfer failed");
        } else {
            address tokenContract = IAuthorizer(authorizer).getToken();
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            SafeERC20.safeTransfer(IERC20(tokenContract), mockRewardRecipient, amount);
        }
    }

    /**
     * @dev 领取赛季奖励
     * @param seasonId 赛季 ID
     */
    function claimReward(uint256 seasonId) external nonReentrant whenNotPaused {
        require(seasonRewards[seasonId].rewardCalculated, "ArenaReward: Rewards not calculated");
        require(!claimedRewards[seasonId][msg.sender], "ArenaReward: Already claimed");
        
        uint256 reward = playerSeasonRewards[seasonId][msg.sender];
        require(reward > 0, "ArenaReward: No reward to claim");
        
        claimedRewards[seasonId][msg.sender] = true;
        
        if (rewardType == 0) {
            require(address(this).balance >= reward, "ArenaReward: Insufficient balance");
            (bool success, ) = payable(msg.sender).call{value: reward}("");
            require(success, "ArenaReward: Transfer failed");
        } else {
            address tokenContract = IAuthorizer(authorizer).getToken();
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            IERC20 token = IERC20(tokenContract);
            require(token.balanceOf(address(this)) >= reward, "ArenaReward: Insufficient token balance");
            token.safeTransfer(msg.sender, reward);
        }
        
        emit RewardClaimed(msg.sender, seasonId, reward);
    }

    /**
     * @dev 领取当前赛季奖励（重载）
     */
    function claimSeasonReward() external nonReentrant whenNotPaused {
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        _claimRewardFor(msg.sender, currentSeasonId);
    }

    /**
     * @dev 领取指定赛季奖励（可代领）
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return 领取的奖励金额
     */
    function claimSeasonReward(address player, uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        require(player != address(0), "ArenaReward: Invalid player address");
        require(seasonId > 0, "ArenaReward: Invalid season ID");
        require(msg.sender == player || msg.sender == authorizer || msg.sender == owner(),
            "ArenaReward: Not authorized to claim for this player");
        return _claimRewardFor(player, seasonId);
    }

    /**
     * @dev 内部函数：为指定玩家领取指定赛季奖励
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return 领取的奖励金额
     */
    function _claimRewardFor(address player, uint256 seasonId) internal returns (uint256) {
        require(seasonRewards[seasonId].rewardCalculated, "ArenaReward: Rewards not calculated");
        require(!claimedRewards[seasonId][player], "ArenaReward: Reward already claimed");

        uint256 reward = playerSeasonRewards[seasonId][player];
        require(reward > 0, "ArenaReward: No reward to claim");

        claimedRewards[seasonId][player] = true;

        if (rewardType == 0) {
            require(address(this).balance >= reward, "ArenaReward: Insufficient balance");
            (bool success, ) = payable(player).call{value: reward}("");
            require(success, "ArenaReward: BNB transfer failed");
        } else {
            address tokenContract = IAuthorizer(authorizer).getToken();
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            IERC20 token = IERC20(tokenContract);
            require(token.balanceOf(address(this)) >= reward, "ArenaReward: Insufficient token balance");
            token.safeTransfer(player, reward);
        }

        emit RewardClaimed(player, seasonId, reward);
        return reward;
    }

    /**
     * @dev 获取指定赛季的待领取奖励（调用者自己）
     * @param seasonId 赛季 ID
     * @return 待领取奖励金额
     */
    function getPendingRewardsBySeason(uint256 seasonId) external view returns (uint256) {
        if (!seasonRewards[seasonId].rewardCalculated) return 0;
        if (claimedRewards[seasonId][msg.sender]) return 0;
        return playerSeasonRewards[seasonId][msg.sender];
    }

    /**
     * @dev 获取指定玩家在指定赛季的待领取奖励
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return 待领取奖励金额
     */
    function getPendingRewardsByPlayer(address player, uint256 seasonId) external view returns (uint256) {
        if (!seasonRewards[seasonId].rewardCalculated) return 0;
        if (claimedRewards[seasonId][player]) return 0;
        return playerSeasonRewards[seasonId][player];
    }

    /**
     * @dev 获取玩家所有赛季的待领取奖励总额
     * @param player 玩家地址
     * @return 待领取奖励总额
     */
    function getTotalPendingRewards(address player) external view returns (uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        uint256 total = 0;
        
        for (uint256 i = 1; i <= currentSeasonId; i++) {
            if (seasonRewards[i].rewardCalculated && !claimedRewards[i][player]) {
                total += playerSeasonRewards[i][player];
            }
        }
        
        return total;
    }

    /**
     * @dev 添加奖励到池中（用于接收BNB）
     * @notice 当合约收到BNB时，自动添加到LP奖励池
     */
    function addRewardToPool() external payable onlyOwnerOrAuthorizer {
        emit RewardAdded(msg.value);
    }

    function emergencyWithdrawBNB() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ArenaReward: Withdraw failed");
        emit EmergencyWithdraw(owner(), balance);
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "ArenaReward: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaReward: Withdraw failed");
        emit EmergencyWithdraw(owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "ArenaReward: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "ArenaReward: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emit EmergencyWithdraw(owner(), amount);
    }

    function isRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        return claimedRewards[seasonId][player];
    }

    /**
     * @dev 计算指定排名的奖励
     * @param rank 排名
     * @return 奖励金额
     */
    function calculateRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaReward: Rank must be > 0");
        address arenaRankingManager = IAuthorizer(authorizer).getArenaRankingManager();
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        (uint256 rewardPool, , uint256 totalPlayers) = IArenaRanking(arenaRankingManager).getSeasonRewardData(currentSeasonId);
        uint256 totalRealPlayers = IArenaRanking(arenaRankingManager).countRealPlayers(currentSeasonId);
        return ArenaRankingLib.calculateRankReward(rank, rewardPool, totalRealPlayers);
    }

    function getRewardForRank(uint256 rank) external view returns (uint256) {
        return this.calculateRewardForRank(rank);
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        require(rate <= maxRewardRate, "ArenaReward: Rate exceeds max");
        rewardRate = rate;
    }

    /**
     * @dev 设置最大奖励率
     * @param maxRate 最大奖励率
     * @notice 仅限owner调用
     */
    function setMaxRewardRate(uint256 maxRate) external onlyOwner {
        maxRewardRate = maxRate;
    }

    function setRateStep(uint256 step) external onlyOwner {
        rateStep = step;
    }

    /**
     * @dev 设置奖励类型
     * @param _rewardType 奖励类型（0=BNB, 1=代币）
     * @notice 仅限owner或authorizer调用
     */
    function setRewardType(uint8 _rewardType) external onlyOwnerOrAuthorizer {
        require(_rewardType == 0 || _rewardType == 1, "ArenaReward: Invalid reward type");
        rewardType = _rewardType;
    }

    function checkNewDay() external onlyOwnerOrAuthorizer {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;

        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingReward = 0;
            todayRewardAmount = 0;
            _adjustRewardRate();
        }
    }

    /**
     * @dev 更新今日奖励金额
     * @param amount 今日奖励金额
     * @notice 仅限owner或authorizer调用
     */
    function updateTodayRewardAmount(uint256 amount) external onlyOwnerOrAuthorizer {
        todayRewardAmount = amount;
    }

    /**
     * @dev 更新今日流入奖励
     * @param amount 流入奖励金额
     * @notice 仅限owner或authorizer调用，累加到todayIncomingReward
     */
    function updateTodayIncomingReward(uint256 amount) external onlyOwnerOrAuthorizer {
        todayIncomingReward += amount;
    }

    /**
     * @dev 内部函数：根据每日流入奖励调整奖励率
     */
    function _adjustRewardRate() internal {
        if (todayRewardAmount > 0 && todayIncomingReward > todayRewardAmount) {
            uint256 multiple = todayIncomingReward / todayRewardAmount;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;
            uint256 steps = multiple - 1;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);

            if (newRate != rewardRate) {
                rewardRate = newRate;
            }
        }
    }

    /**
     * @dev 紧急提取WBNB
     * @param amount WBNB数量
     * @notice 仅限owner调用，用于紧急情况
     */
    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        IAuthorizer(authorizer).emergencyWithdrawWBNB(amount);
    }
}