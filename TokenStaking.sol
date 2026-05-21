// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title TokenStaking
 * @dev 代币质押合约
 * 允许用户质押代币获取BNB奖励，支持弹性奖励释放机制
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract TokenStaking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /** @dev 奖励计算间隔（每分钟） */
    uint256 public constant REWARD_INTERVAL = 1 minutes;
    /** @dev 每日奖励释放比例（千分之15 = 1.5%） */
    uint256 public dailyReleaseRatio = 15;
    /** @dev 释放比例分母 */
    uint256 public constant RELEASE_RATIO_DENOMINATOR = 10000;
    /** @dev 最大弹性增量（千分之5 = 0.5%） */
    uint256 public constant MAX_ELASTIC_INCREMENT = 5;
    /** @dev 当日转入代币量（用于弹性调控） */
    uint256 public dailyDeposited;
    /** @dev 倍数阈值（超过此倍数触发弹性调控） */
    uint256 public multipleThreshold = 2;
    /** @dev 上次日期重置时间戳 */
    uint256 public lastDateReset;
    
    /** @dev 最小质押锁定时间（30分钟） */
    uint256 public constant MIN_STAKING_DURATION = 30 minutes;

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
     */
    function initialize(address _tokenContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        tokenContract = _tokenContract;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 接收BNB
     */
    receive() external payable {
        require(msg.value > 0, "TokenStaking: Cannot receive zero BNB");
        _updateDailyDeposited(msg.value);
        emit BNBReceived(msg.value);
    }

    /**
     * @dev 质押代币
     * @param amount 质押数量
     */
    function stakeTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenStaking: Amount must be > 0");
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.balanceOf(msg.sender) >= amount, "TokenStaking: Insufficient balance");
        require(token.allowance(msg.sender, address(this)) >= amount, "TokenStaking: Insufficient allowance");
        
        require(token.transferFrom(msg.sender, address(this), amount), "TokenStaking: Token transfer failed");
        
        StakeInfo storage stake = userStakes[msg.sender];
        
        if (stake.amount == 0) {
            stake.lastRewardTime = block.timestamp;
            stake.stakedAt = block.timestamp;
        } else {
            _updateRewards(msg.sender);
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
        
        _updateRewards(msg.sender);
        
        uint256 userReward = stake.accumulatedRewards;
        
        stake.amount -= amount;
        totalStakedTokens -= amount;
        
        if (stake.amount == 0) {
            stake.accumulatedRewards = 0;
            stake.lastRewardTime = 0;
            stake.stakedAt = 0;
        } else {
            stake.accumulatedRewards = 0;
            stake.lastRewardTime = block.timestamp;
        }
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transfer(msg.sender, amount), "TokenStaking: Failed to transfer staked tokens");
        
        if (userReward > 0) {
            require(address(this).balance >= userReward, "TokenStaking: Insufficient BNB balance");
            _updateDailyRewardDistributed(userReward);
            (bool success, ) = payable(msg.sender).call{value: userReward}("");
            require(success, "TokenStaking: Failed to transfer BNB rewards");
            emit RewardsClaimed(msg.sender, userReward);
        }
        
        emit TokensUnstaked(msg.sender, amount);
    }

    /**
     * @dev 提取BNB（仅限管理员）
     * @param amount 提取金额
     */
    function withdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "TokenStaking: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "TokenStaking: Failed to withdraw BNB");
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
     * @dev 更新当日存入金额（内部函数）
     * @param amount 存入金额
     */
    function _updateDailyDeposited(uint256 amount) internal {
        if (block.timestamp >= lastDateReset + 1 days) {
            dailyDeposited = amount;
            lastDateReset = block.timestamp;
        } else {
            dailyDeposited += amount;
        }
    }

    /**
     * @dev 领取奖励
     */
    function claimRewards() external nonReentrant {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "TokenStaking: No BNB available for rewards");
        
        _updateRewards(msg.sender);
        
        StakeInfo storage stake = userStakes[msg.sender];
        uint256 totalRewards = stake.accumulatedRewards;
        
        require(totalRewards > 0, "TokenStaking: No rewards to claim");
        require(totalRewards <= contractBalance, "TokenStaking: Insufficient BNB in contract");
        
        stake.accumulatedRewards = 0;
        stake.lastRewardTime = block.timestamp;
        
        _updateDailyRewardDistributed(totalRewards);
        
        (bool success, ) = payable(msg.sender).call{value: totalRewards}("");
        require(success, "TokenStaking: Failed to transfer BNB rewards");
        
        emit RewardsClaimed(msg.sender, totalRewards);
    }

    /**
     * @dev 计算用户奖励
     * @param user 用户地址
     * @return uint256 奖励金额
     */
    function calculateRewards(address user) external view returns (uint256) {
        StakeInfo memory stake = userStakes[user];
        return stake.accumulatedRewards;
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
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyOwner {
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置每日释放比例（千分比）
     * @param _ratio 释放比例（1-1000 = 0.01%-10%）
     */
    function setDailyReleaseRatio(uint256 _ratio) external onlyOwner {
        require(_ratio > 0 && _ratio <= 1000, "TokenStaking: Ratio must be between 1 and 1000");
        dailyReleaseRatio = _ratio;
    }

    /**
     * @dev 设置倍数阈值
     * @param _threshold 阈值（>=1）
     */
    function setMultipleThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 1, "TokenStaking: Multiple threshold must be >= 1");
        multipleThreshold = _threshold;
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 获取当前释放比例
     * @return uint256 当前释放比例
     */
    function getCurrentReleaseRatio() external view returns (uint256) {
        return _calculateCurrentReleaseRatio();
    }

    /**
     * @dev 获取最小质押时间
     * @return uint256 最小质押时间（秒）
     */
    function minimumStakeDuration() external view returns (uint256) {
        return REWARD_INTERVAL;
    }

    /**
     * @dev 计算当前释放比例（内部函数）
     * 根据当日存入量动态调整释放比例
     * @return uint256 当前释放比例
     */
    function _calculateCurrentReleaseRatio() internal view returns (uint256) {
        if (dailyDeposited <= dailyReleaseRatio * multipleThreshold) {
            return dailyReleaseRatio;
        }
        
        uint256 baseThreshold = dailyReleaseRatio * multipleThreshold;
        if (dailyDeposited <= baseThreshold) {
            return dailyReleaseRatio;
        }
        
        uint256 excess = dailyDeposited - baseThreshold;
        uint256 excessMultiple = excess / dailyReleaseRatio;
        uint256 additionalRatio = excessMultiple > MAX_ELASTIC_INCREMENT ? MAX_ELASTIC_INCREMENT : excessMultiple;
        
        return dailyReleaseRatio + additionalRatio;
    }

    /**
     * @dev 更新用户奖励（内部函数）
     * @param user 用户地址
     */
    function _updateRewards(address user) internal {
        StakeInfo storage stake = userStakes[user];
        if (stake.amount == 0) return;
        
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - stake.lastRewardTime;
        
        if (timeElapsed > 0 && totalStakedTokens > 0) {
            uint256 dailyReward = _getAvailableDailyReward();
            uint256 rewardPerMinute = _calculateRewardPerMinute(dailyReward, stake.amount);
            
            uint256 intervals = timeElapsed / REWARD_INTERVAL;
            if (intervals > 0 && rewardPerMinute > 0) {
                require(intervals <= type(uint256).max / rewardPerMinute, "TokenStaking: intervals overflow");
                uint256 rewards = intervals * rewardPerMinute;
                require(stake.accumulatedRewards <= type(uint256).max - rewards, "TokenStaking: rewards overflow");
                stake.accumulatedRewards += rewards;
                stake.lastRewardTime = currentTime;
            }
        }
    }

    /**
     * @dev 获取当日可用奖励（内部函数）
     * @return uint256 当日可用奖励
     */
    function _getAvailableDailyReward() internal view returns (uint256) {
        uint256 contractBalance = address(this).balance;
        
        uint256 currentRatio = _calculateCurrentReleaseRatio();
        
        return (contractBalance * currentRatio) / RELEASE_RATIO_DENOMINATOR;
    }

    /**
     * @dev 计算每分钟奖励（内部函数）
     * @param dailyReward 当日奖励
     * @param userStake 用户质押数量
     * @return uint256 每分钟奖励
     */
    function _calculateRewardPerMinute(uint256 dailyReward, uint256 userStake) internal view returns (uint256) {
        if (totalStakedTokens == 0 || dailyReward == 0) {
            return 0;
        }
        
        uint256 rewardPerMinuteTotal = dailyReward / 1440;
        return (rewardPerMinuteTotal * userStake) / totalStakedTokens;
    }

    /**
     * @dev 更新当日奖励分配（内部函数）
     * @param amount 分配金额
     */
    function _updateDailyRewardDistributed(uint256 amount) internal {
        if (block.timestamp >= lastDateReset + 1 days) {
            dailyRewardDistributed = amount;
            lastDateReset = block.timestamp;
        } else {
            dailyRewardDistributed += amount;
        }
    }

    /**
     * @dev 获取总质押数量
     * @return uint256 总质押数量
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStakedTokens;
    }

    function withdrawSpecificBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "TokenStaking: insufficient BNB balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "TokenStaking: BNB transfer failed");
    }

    function withdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(amount <= token.balanceOf(address(this)), "TokenStaking: insufficient token balance");
        token.transfer(owner(), amount);
    }
}
