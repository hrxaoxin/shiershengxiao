// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title TokenStaking
 * @dev 代币质押合约
 * 允许用户质押代币获取BNB奖励，支持弹性奖励释放机制
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract TokenStaking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /** @dev 基础奖励比例（万分比，默认10 = 0.1%） */
    uint256 public rewardRate = 10;
    /** @dev 最大奖励比例（万分比，默认20 = 0.2%） */
    uint256 public maxRewardRate = 20;
    /** @dev 每次上调比例（万分比，1 = 0.01%） */
    uint256 public rateStep = 1;
    /** @dev 最小质押锁定时间（30分钟） */
    uint256 public constant MIN_STAKING_DURATION = 30 minutes;
    /** @dev 今日已进入合约的BNB数量 */
    uint256 public todayIncomingBNB;
    /** @dev 今日奖励总量 */
    uint256 public todayRewardAmount;
    /** @dev 今日开始时间 */
    uint256 public todayStart;
    /** @dev 所有用户待领取奖励总和（简化处理） */
    uint256 public totalPendingRewards;

    /** @dev 奖励精度缩放因子（1e18，用于避免 dailyRewardPerToken 整数截断） */
    uint256 private constant REWARD_PRECISION = 1e18;

    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 总质押代币数量 */
    uint256 public totalStakedTokens;
    /** @dev 上次奖励更新时间 */
    uint256 public lastRewardUpdate;
    /** @dev 当日已分配奖励 */
    uint256 public dailyRewardDistributed;

    /**
     * @dev 质押信息结构体
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
     * @param user 用户地址
     * @param amount 质押数量
     */
    event TokensStaked(address indexed user, uint256 amount);
    
    /**
     * @dev 代币解除质押事件
     * @param user 用户地址
     * @param amount 解除质押数量
     */
    event TokensUnstaked(address indexed user, uint256 amount);
    
    /**
     * @dev 奖励领取事件
     * @param user 用户地址
     * @param amount 领取奖励数量
     */
    event RewardsClaimed(address indexed user, uint256 amount);
    
    /**
     * @dev BNB接收事件
     * @param amount 接收BNB数量
     */
    event BNBReceived(uint256 amount);

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    /** @dev 奖励比例更新事件 */
    event RewardRateUpdated(uint256 newRate);
    /** @dev 最大奖励比例更新事件 */
    event MaxRewardRateUpdated(uint256 newMaxRate);
    /** @dev 上调步长更新事件 */
    event RateStepUpdated(uint256 newStep);
    /** @dev 每日奖励计算事件 */
    event DailyRewardCalculated(uint256 totalReward, uint256 totalStaked);
    /** @dev 流入BNB记录事件 */
    event IncomingBNBRecorded(uint256 amount, uint256 totalToday);

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev 构造函数：禁用初始化器
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _tokenContract 代币合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        tokenContract = _tokenContract;
        authorizer = _authorizer;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 接收BNB
     */
    receive() external payable {
        require(msg.value > 0, "TokenStaking: Cannot receive zero BNB");
        recordIncomingBNB(msg.value);
        emit BNBReceived(msg.value);
    }

    /**
     * @dev 质押代币
     * @param amount 质押数量
     */
    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "TokenStaking: Amount must be > 0");

        _checkNewDay();
        
        _accumulateRewards(msg.sender);
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.balanceOf(msg.sender) >= amount, "TokenStaking: Insufficient balance");
        require(token.allowance(msg.sender, address(this)) >= amount, "TokenStaking: Insufficient allowance");
        
        require(token.transferFrom(msg.sender, address(this), amount), "TokenStaking: Token transfer failed");
        
        StakeInfo storage stake = userStakes[msg.sender];
        
        if (stake.amount == 0) {
            stake.stakedAt = block.timestamp;
        }
        
        stake.amount += amount;
        totalStakedTokens += amount;
        
        emit TokensStaked(msg.sender, amount);
    }

    /**
     * @dev 解除质押代币
     * @param amount 解除质押数量
     */
    function unstakeTokens(uint256 amount) external nonReentrant {
        StakeInfo storage stake = userStakes[msg.sender];
        require(stake.amount >= amount, "TokenStaking: Insufficient staked amount");
        require(stake.stakedAt > 0, "TokenStaking: No stake found");
        require(block.timestamp >= stake.stakedAt + MIN_STAKING_DURATION, 
                "TokenStaking: Must stake for at least 30 minutes");
        
        _accumulateRewards(msg.sender);
        
        stake.amount -= amount;
        totalStakedTokens -= amount;
        
        if (stake.amount == 0) {
            stake.stakedAt = 0;
        }
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transfer(msg.sender, amount), "TokenStaking: Failed to transfer staked tokens");
        
        emit TokensUnstaked(msg.sender, amount);
    }

    /**
     * @dev 设置奖励比例（仅owner）
     * @param _rewardRate 新的奖励比例（万分比）
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0 && _rewardRate <= maxRewardRate, "TokenStaking: Invalid reward rate");
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @dev 设置最大奖励比例（仅owner）
     * @param _maxRewardRate 最大奖励比例（万分比）
     */
    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        require(_maxRewardRate >= rewardRate, "TokenStaking: Max rate must be >= current rate");
        maxRewardRate = _maxRewardRate;
        emit MaxRewardRateUpdated(_maxRewardRate);
    }

    /**
     * @dev 设置上调步长（仅owner）
     * @param _rateStep 上调步长（万分比）
     */
    function setRateStep(uint256 _rateStep) external onlyOwner {
        require(_rateStep > 0, "TokenStaking: Step must be > 0");
        rateStep = _rateStep;
        emit RateStepUpdated(_rateStep);
    }

    /**
     * @dev 记录进入合约的BNB数量
     */
    function recordIncomingBNB(uint256 amount) internal {
        _checkNewDay();
        todayIncomingBNB += amount;
        emit IncomingBNBRecorded(amount, todayIncomingBNB);
    }

    /**
     * @dev 检查是否进入新的一天
     * 仅重置每日统计，dailyRewardPerToken 保持累计不重置
     */
    function _checkNewDay() internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;

        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingBNB = 0;
            todayRewardAmount = 0;
            // dailyRewardPerToken 为累积值，跨日不重置
            _adjustRewardRate();
        }
    }

    /**
     * @dev 动态调整奖励比例
     * 规则：流入BNB量是每日奖励总量的倍数，每增加1倍，比例上调0.01%，最多上调0.1%
     */
    function _adjustRewardRate() internal {
        if (todayRewardAmount > 0 && todayIncomingBNB > todayRewardAmount) {
            uint256 multiple = todayIncomingBNB / todayRewardAmount;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;
            uint256 steps = multiple - 1;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);

            if (newRate != rewardRate) {
                rewardRate = newRate;
                emit RewardRateUpdated(rewardRate);
            }
        }
    }

    /**
     * @dev 每日奖励比率（基于质押量）
     */
    uint256 public dailyRewardPerToken;
    /**
     * @dev 上次计算奖励的时间
     */
    uint256 public lastRewardCalculationTime;

    /**
     * @dev 用户上次累积时使用的奖励率，防止重复累加
     * user => lastAccumulatedRate
     */
    mapping(address => uint256) private lastAccumulatedRate;

    /**
     * @dev 计算并分发每日奖励
     * dailyRewardPerToken 为累积值（持续递增），避免跨日覆盖导致奖励丢失
     */
    function calculateDailyReward() external onlyAuthorized {
        _checkNewDay();

        uint256 contractBalance = address(this).balance;
        uint256 availableBalance = contractBalance - totalPendingRewards;
        
        if (availableBalance > 0 && totalStakedTokens > 0) {
            todayRewardAmount = availableBalance * rewardRate / 10000;
            // 使用高精度累积 dailyRewardPerToken，持续递增而非覆盖
            dailyRewardPerToken += todayRewardAmount * REWARD_PRECISION / totalStakedTokens;
            lastRewardCalculationTime = block.timestamp;
            emit DailyRewardCalculated(todayRewardAmount, totalStakedTokens);
        }
    }

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
        require(address(this).balance >= userReward, "TokenStaking: Insufficient BNB in contract");

        stake.accumulatedRewards = 0;

        if (totalPendingRewards >= userReward) {
            totalPendingRewards -= userReward;
        } else {
            totalPendingRewards = 0;
        }

        (bool success, ) = payable(msg.sender).call{value: userReward}("");
        require(success, "TokenStaking: Failed to transfer BNB rewards");

        emit RewardsClaimed(msg.sender, userReward);
    }

    /**
     * @dev 累积用户奖励（在质押/解除质押时调用）
     * dailyRewardPerToken 为累积值，持续递增；通过差值计算用户未领取奖励
     */
    function _accumulateRewards(address user) internal {
        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = lastAccumulatedRate[user];
        uint256 stakedAmount = userStakes[user].amount;

        if (currentRate > lastRate && stakedAmount > 0) {
            uint256 newReward = stakedAmount * (currentRate - lastRate) / REWARD_PRECISION;
            userStakes[user].accumulatedRewards += newReward;
            totalPendingRewards += newReward;
        }

        // 更新用户上次累积的奖励率，防止重复累加
        lastAccumulatedRate[user] = currentRate;
    }

    /**
     * @dev 获取用户质押信息
     * @param user 用户地址
     * @return StakeInfo 质押信息
     */
    function getUserStake(address user) external view returns (StakeInfo memory) {
        return userStakes[user];
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenStaking: Not authorized");
        _;
    }

    /**
     * @dev 设置代币合约地址（内部方法）
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyOwner {
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置代币合约地址（Authorizer 调用接口，与 ISetTokenAddress 匹配）
     * @param _tokenContract 代币合约地址
     */
    function setTokenAddress(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "TokenStaking: Invalid token address");
        tokenContract = _tokenContract;
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 获取总质押数量
     * @return uint256 总质押数量
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStakedTokens;
    }

    /**
     * @dev 获取合约BNB余额
     * @return uint256 BNB余额
     */
    function getContractBNBBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 获取合约代币余额
     * @return uint256 代币余额
     */
    function getContractTokenBalance() external view returns (uint256) {
        return IERC20Upgradeable(tokenContract).balanceOf(address(this));
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

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "TokenStaking: Amount must be > 0");
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(tokenContract != address(0), "TokenStaking: Token contract not set");
        require(amount <= token.balanceOf(address(this)), "TokenStaking: insufficient token balance");
        require(token.transfer(owner(), amount), "TokenStaking: transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }
}
