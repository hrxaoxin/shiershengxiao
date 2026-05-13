// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract TokenStaking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public constant REWARD_INTERVAL = 1 minutes;
    uint256 public dailyReleaseRatio = 15;
    uint256 public constant RELEASE_RATIO_DENOMINATOR = 10000;
    uint256 public constant MAX_ELASTIC_INCREMENT = 5;
    uint256 public dailyDeposited;
    uint256 public multipleThreshold = 2;
    uint256 public lastDateReset;
    
    uint256 public constant MIN_STAKING_DURATION = 30 minutes;

    address public tokenContract;

    uint256 public totalStakedTokens;
    uint256 public lastRewardUpdate;
    uint256 public dailyRewardDistributed;

    struct StakeInfo {
        uint256 amount;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
        uint256 stakedAt;
    }

    mapping(address => StakeInfo) public userStakes;

    event TokensStaked(address indexed user, uint256 amount);
    event TokensUnstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event BNBReceived(uint256 amount);

    uint256[50] private __gap;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        tokenContract = _tokenContract;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {
        require(msg.value > 0, "TokenStaking: Cannot receive zero BNB");
        _updateDailyDeposited(msg.value);
        emit BNBReceived(msg.value);
    }

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

    function withdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "TokenStaking: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "TokenStaking: Failed to withdraw BNB");
    }

    function getContractBNBBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getContractTokenBalance() external view returns (uint256) {
        return IERC20Upgradeable(tokenContract).balanceOf(address(this));
    }

    function _updateDailyDeposited(uint256 amount) internal {
        if (block.timestamp >= lastDateReset + 1 days) {
            dailyDeposited = amount;
            lastDateReset = block.timestamp;
        } else {
            dailyDeposited += amount;
        }
    }

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

    function calculateRewards(address user) external view returns (uint256) {
        StakeInfo memory stake = userStakes[user];
        return stake.accumulatedRewards;
    }

    function getUserStake(address user) external view returns (StakeInfo memory) {
        return userStakes[user];
    }

    function setTokenContract(address _tokenContract) external onlyOwner {
        tokenContract = _tokenContract;
    }

    function setDailyReleaseRatio(uint256 _ratio) external onlyOwner {
        require(_ratio > 0 && _ratio <= 1000, "TokenStaking: Ratio must be between 1 and 1000");
        dailyReleaseRatio = _ratio;
    }

    function setMultipleThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 1, "TokenStaking: Multiple threshold must be >= 1");
        multipleThreshold = _threshold;
    }

    function getCurrentReleaseRatio() external view returns (uint256) {
        return _calculateCurrentReleaseRatio();
    }

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

    function _getAvailableDailyReward() internal view returns (uint256) {
        uint256 contractBalance = address(this).balance;
        
        uint256 currentRatio = _calculateCurrentReleaseRatio();
        
        return (contractBalance * currentRatio) / RELEASE_RATIO_DENOMINATOR;
    }

    function _calculateRewardPerMinute(uint256 dailyReward, uint256 userStake) internal view returns (uint256) {
        if (totalStakedTokens == 0 || dailyReward == 0) {
            return 0;
        }
        
        uint256 rewardPerMinuteTotal = dailyReward / 1440;
        return (rewardPerMinuteTotal * userStake) / totalStakedTokens;
    }

    function _updateDailyRewardDistributed(uint256 amount) internal {
        if (block.timestamp >= lastDateReset + 1 days) {
            dailyRewardDistributed = amount;
            lastDateReset = block.timestamp;
        } else {
            dailyRewardDistributed += amount;
        }
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStakedTokens;
    }
}