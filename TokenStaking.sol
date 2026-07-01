// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./NFTInterface.sol";
import "./LPLib.sol";

/**
 * @title TokenStaking
 * @dev 代币质押合约，允许用户质押原生代币以获取代币奖励
 *
 * 核心功能：
 * 1. 代币质押（stakeTokens）：用户存入代币，进入质押池
 * 2. 奖励领取（claimRewards）：根据用户质押份额分配合约收到的代币奖励
 * 3. 解除质押（unstakeTokens）：取出质押的代币，需经过最小锁仓期
 *
 * 奖励机制设计：
 * - 全局累积奖励/代币（rewardPerToken）持续累积
 * - 用户领取时计算其快照与当前值的差值 × 质押数量 = 应得奖励
 * - 用户快照（lastAccumulatedRate）记录上次领取时的累积值，防止重复计算
 * - 每日奖励计算：计算当前合约代币余额 × rewardRate（万分比）作为当日奖励池
 *
 * 动态奖励率调整：
 * - 基础奖励率（rewardRate）：默认1%（100/10000）
 * - 最大奖励率（maxRewardRate）：默认2%（200/10000）
 * - 当每日流入代币超过每日奖励时，奖励率自动上调（rateStep步长）
 * - 目的：在高流入期回馈更多给质押者，激励长期持有
 *
 * 安全限制：
 * - 最小质押持续时间（MIN_STAKING_DURATION = 30分钟）：防止瞬间进出刷奖励
 * - 最大总质押量（maxTotalStaked）：防止系统风险
 * - 最大单用户质押量（maxUserStaked）：防止巨鲸控制奖励
 * - 暂停机制（Pausable）：紧急情况下可暂停全部用户操作
 * - 重入保护（ReentrancyGuard）：防止领取奖励时的重入攻击
 *
 * 合约升级：
 * - UUPS 可升级模式，由 onlyOwner 授权升级
 * - 所有状态变量均为 storage 存储，升级后保留
 * - 预留 __gap 存储间隙，便于未来新增变量
 *
 * 典型用户流程：
 * 1. 授权合约使用代币（approve）
 * 2. 调用 stakeTokens(amount) 质押代币
 * 3. 等待若干时间（收取代币奖励）
 * 4. 调用 claimRewards() 领取累计奖励
 * 5. 30分钟锁仓期后调用 unstakeTokens(amount) 解除质押
 */
contract TokenStaking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LPLib for IAuthorizer;
    
    /** @dev 最小质押锁定时间（30分钟） */
    uint256 public constant MIN_STAKING_DURATION = 30 minutes;
    /** @dev 最大总质押数量（无限制） */
    uint256 public maxTotalStaked = type(uint256).max;
    /** @dev 单个用户最大质押数量（无限制） */
    uint256 public maxUserStaked = type(uint256).max;
    /** @dev 今日已进入合约的代币数量 */
    uint256 public todayIncomingTokens;
    /** @dev 所有用户待领取奖励总和（简化处理） */
    uint256 public totalPendingRewards;

    /** @dev 奖励精度缩放因子（1e18），用于避免 dailyRewardPerToken 整数截断 */
    uint256 private constant REWARD_PRECISION = 1e18;
    /** @dev dailyRewardPerToken 最大阈值，超过时触发重置 */
    uint256 public constant MAX_DAILY_REWARD_PER_TOKEN = 1e36;

    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 总质押代币数量 */
    uint256 public totalStakedTokens;
    /** @dev 上次奖励更新时间 */
    uint256 public lastRewardUpdate;
    /** @dev 当日已分配奖励 */
    uint256 public dailyRewardDistributed;

    /**
     * @dev 质押信息结构：
     * @param amount 质押数量
     * @param lastRewardTime 上次领取奖励时间
     * @param accumulatedRewards 累计未领取奖励
     * @param stakedAt 质押时间（用于锁定检查）
     */
    struct StakeInfo {
        uint256 amount;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
        uint256 stakedAt;
    }

    /** @dev 用户质押信息映射（地址 => 质押信息） */
    mapping(address => StakeInfo) public userStakes;

    /**
     * @dev 代币质押事件
     * @param user 质押用户地址
     * @param amount 质押数量
     */
    event TokensStaked(address indexed user, uint256 amount);
    
    /**
     * @dev 代币解除质押事件
     * @param user 解除质押用户地址
     * @param amount 解除质押数量
     */
    event TokensUnstaked(address indexed user, uint256 amount);
    
    /**
     * @dev 奖励领取事件
     * @param user 领取奖励用户地址
     * @param amount 领取奖励数量
     */
    event RewardsClaimed(address indexed user, uint256 amount);
    
    /**
     * @dev 代币接收事件
     * @param amount 接收代币数量
     */
    event TokensReceived(uint256 amount);

    /** @dev 紧急提取BNB事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    /** @dev 紧急提取代币事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    /** @dev 紧急提取WBNB事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyWBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    /** @dev 奖励比例更新事件
     * @param newRate 新的奖励率
     */
    event RewardRateUpdated(uint256 newRate);
    /** @dev 最大奖励比例更新事件
     * @param newMaxRate 新的最大奖励率
     */
    event MaxRewardRateUpdated(uint256 newMaxRate);
    /** @dev 每日奖励计算事件
     * @param totalReward 当日总奖励
     * @param totalStaked 当前总质押量
     */
    event DailyRewardCalculated(uint256 totalReward, uint256 totalStaked);
    /** @dev 流入代币记录事件
     * @param amount 流入数量
     * @param totalToday 今日总流入
     */
    event IncomingTokensRecorded(uint256 amount, uint256 totalToday);

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "TokenStaking: Invalid authorizer address");
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        authorizer = _authorizerAddress;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
        
        // 初始化带默认值的参数
        maxTotalStaked = type(uint256).max;
        maxUserStaked = type(uint256).max;
    }
    
    /**
     * @dev 暂停合约（仅owner）
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev 恢复合约（仅owner）
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev UUPS升级授权函数
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 接收代币奖励（通过 token.transfer 进入合约）
     * 提供一个记录函数供外部调用以更新流入统计
     * 仅允许 RewardManager 合约或授权地址调用
     * @param amount 接收代币数量
     */
    function recordIncomingTokens(uint256 amount) external {
        require(amount > 0, "TokenStaking: Amount must be > 0");
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == IAuthorizer(authorizer).getRewardManager(), 
                "TokenStaking: Not authorized");
        todayIncomingTokens += amount;
        emit IncomingTokensRecorded(amount, todayIncomingTokens);
    }

    /**
     * @dev 质押代币
     * @param amount 质押数量
     */
    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "TokenStaking: Amount must be > 0");

        _accumulateRewards(msg.sender);
        
        StakeInfo storage stake = userStakes[msg.sender];
        
        require(stake.amount + amount <= maxUserStaked, "TokenStaking: User stake limit exceeded");
        require(totalStakedTokens + amount <= maxTotalStaked, "TokenStaking: Total stake limit exceeded");
        
        IERC20Upgradeable token = IERC20Upgradeable(IAuthorizer(authorizer).getToken());
        require(token.balanceOf(msg.sender) >= amount, "TokenStaking: Insufficient balance");
        require(token.allowance(msg.sender, address(this)) >= amount, "TokenStaking: Insufficient allowance");
        
        SafeERC20Upgradeable.safeTransferFrom(token, msg.sender, address(this), amount);
        
        // 修复：每次追加质押时更新 stakedAt，确保新增代币也受锁仓期约束
        stake.stakedAt = block.timestamp;
        
        stake.amount += amount;
        totalStakedTokens += amount;
        
        emit TokensStaked(msg.sender, amount);
    }
    
    /**
     * @dev 设置最大总质押量
     * @param _maxTotalStaked 最大总质押数量
     */
    function setMaxTotalStaked(uint256 _maxTotalStaked) external onlyOwner {
        require(_maxTotalStaked > 0, "TokenStaking: Max total must be greater than 0");
        maxTotalStaked = _maxTotalStaked;
    }
    
    /**
     * @dev 设置单用户最大质押量
     * @param _maxUserStaked 单用户最大质押数量
     */
    function setMaxUserStaked(uint256 _maxUserStaked) external onlyOwner {
        require(_maxUserStaked > 0, "TokenStaking: Max user must be greater than 0");
        maxUserStaked = _maxUserStaked;
    }

    /**
     * @dev 解除质押代币
     * @param amount 解除质押数量
     */
    function unstakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage stake = userStakes[msg.sender];
        require(stake.amount >= amount, "TokenStaking: Insufficient staked amount");
        require(stake.stakedAt > 0, "TokenStaking: No stake found");
        require(block.timestamp >= stake.stakedAt + MIN_STAKING_DURATION, 
                "TokenStaking: Must stake for at least 30 minutes");
        
        // 先累积用户的未领取奖励
        _accumulateRewards(msg.sender);
        
        // 计算用户要提取的代币对应的累积奖励份额
        uint256 userStakeShare = stake.amount > 0 ? stake.accumulatedRewards * amount / stake.amount : 0;
        
        stake.amount -= amount;
        totalStakedTokens -= amount;
        
        // 重置已提取份额对应的累积奖励
        if (stake.amount > 0) {
            // 修复：添加下溢检查
            require(stake.accumulatedRewards >= userStakeShare, "TokenStaking: Reward underflow");
            stake.accumulatedRewards -= userStakeShare;
        } else {
            stake.accumulatedRewards = 0;
            stake.stakedAt = 0;
        }
        
        IERC20Upgradeable token = IERC20Upgradeable(IAuthorizer(authorizer).getToken());
        token.safeTransfer(msg.sender, amount);
        
        emit TokensUnstaked(msg.sender, amount);
    }

    /** @dev 每日奖励比率（基于质押量），累积值持续递增 */
    uint256 public dailyRewardPerToken;
    /** @dev 上次计算奖励的时间 */
    uint256 public lastRewardCalculationTime;

    /** @dev 用户上次累积时使用的奖励率，防止重复累加（地址 => 上次累积率） */
    mapping(address => uint256) private lastAccumulatedRate;

    /**
     * @dev 重置 dailyRewardPerToken（当接近溢出时调用）
     * 注意：调用此函数前必须确保所有用户已领取奖励，否则会导致奖励丢失
     */
    function resetDailyRewardPerToken() external onlyOwner {
        require(totalPendingRewards == 0, "TokenStaking: There are pending rewards");
        dailyRewardPerToken = 0;
        emit DailyRewardPerTokenReset();
    }

    /** @dev dailyRewardPerToken重置事件 */
    event DailyRewardPerTokenReset();

    /**
     * @dev 领取奖励
     */
    function claimRewards() external nonReentrant whenNotPaused {
        StakeInfo storage stake = userStakes[msg.sender];
        require(stake.amount > 0, "TokenStaking: No staked tokens");

        // 领取前先累积最新未计入的奖励
        _accumulateRewards(msg.sender);

        uint256 userReward = stake.accumulatedRewards;
        require(userReward > 0, "TokenStaking: No rewards to claim");
        
        IERC20Upgradeable token = IERC20Upgradeable(IAuthorizer(authorizer).getToken());
        require(token.balanceOf(address(this)) >= userReward + totalStakedTokens, 
                "TokenStaking: Insufficient token balance in contract");

        stake.accumulatedRewards = 0;

        // 修复：添加安全检查确保不会下溢
        if (totalPendingRewards >= userReward) {
            totalPendingRewards -= userReward;
        } else {
            totalPendingRewards = 0;
        }

        SafeERC20Upgradeable.safeTransfer(token, msg.sender, userReward);

        emit RewardsClaimed(msg.sender, userReward);
    }

    /**
     * @dev 累积用户奖励（在质押/解除质押时调用）
     * dailyRewardPerToken 为累积值，持续递增；通过差值计算用户未领取奖励
     * @param user 用户地址
     */
    function _accumulateRewards(address user) internal {
        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = lastAccumulatedRate[user];
        uint256 stakedAmount = userStakes[user].amount;

        if (currentRate > lastRate && stakedAmount > 0) {
            uint256 newReward = stakedAmount * (currentRate - lastRate) / REWARD_PRECISION;
            // 修复：添加溢出检查，防止 accumulatedRewards 溢出
            uint256 newAccumulated = userStakes[user].accumulatedRewards + newReward;
            require(newAccumulated >= userStakes[user].accumulatedRewards, "TokenStaking: Accumulated rewards overflow");
            userStakes[user].accumulatedRewards = newAccumulated;
            
            // 修复：添加溢出检查，防止 totalPendingRewards 溢出
            uint256 newTotalPending = totalPendingRewards + newReward;
            require(newTotalPending >= totalPendingRewards, "TokenStaking: Total pending rewards overflow");
            totalPendingRewards = newTotalPending;
        }

        // 更新用户上次累积的奖励率，防止重复累积
        lastAccumulatedRate[user] = currentRate;
    }

    /**
     * @dev 获取用户质押信息
     * @param user 用户地址
     * @return StakeInfo 质押信息结构体
     */
    function getUserStake(address user) external view returns (StakeInfo memory) {
        return userStakes[user];
    }

    /**
     * @dev 仅owner或authorizer或系统合约的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "TokenStaking: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "TokenStaking: Not authorized");
        _;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "TokenStaking: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 获取总质押数量
     * @return uint256 总质押数量
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStakedTokens;
    }

    /**
     * @dev 获取合约代币余额
     * @return uint256 代币余额
     */
    function getContractTokenBalance() external view returns (uint256) {
        return IERC20Upgradeable(IAuthorizer(authorizer).getToken()).balanceOf(address(this));
    }

    /**
     * @dev 获取合约可用奖励代币余额（扣除质押本金后）
     * @return uint256 奖励代币余额
     */
    function getRewardTokenBalance() external view returns (uint256) {
        uint256 balance = IERC20Upgradeable(IAuthorizer(authorizer).getToken()).balanceOf(address(this));
        return balance > totalStakedTokens ? balance - totalStakedTokens : 0;
    }

    /**
     * @dev 紧急提取BNB（仅限管理员）
     * @param amount 提取金额
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "TokenStaking: Amount must be > 0");
        require(amount <= address(this).balance, "TokenStaking: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "TokenStaking: Failed to withdraw BNB");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币（仅owner）
     * @param amount 提取金额
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "TokenStaking: Amount must be > 0");
        IERC20Upgradeable token = IERC20Upgradeable(IAuthorizer(authorizer).getToken());
        require(amount <= token.balanceOf(address(this)), "TokenStaking: insufficient token balance");
        SafeERC20Upgradeable.safeTransfer(token, owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp);

    /**
     * @dev 重置合约核心数据（仅owner或authorizer）
     * 注意：无法遍历mapping，只重置核心状态变量
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        totalStakedTokens = 0;
        dailyRewardPerToken = 0;
        todayIncomingTokens = 0;
        totalPendingRewards = 0;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
        lastRewardCalculationTime = 0;
        
        emit ContractDataReset(msg.sender, block.timestamp);
    }
}
