// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

/**
 * @title TokenStaking
 * @dev 代币质押合约，允许用户质押游戏代币以获取奖励
 *
 * 质押规则：
 * 1. 无最低质押金额限制
 * 2. 质押后进入30分钟锁定期
 * 3. 锁定期后可随时解除质押
 * 4. 质押期间可领取奖励
 *
 * 奖励机制：
 * - 质押奖励来自游戏池
 * - 奖励按质押代币数量和时长分配
 */
contract TokenStaking is Ownable {
    /**
     * @dev 最低质押时长（秒）
     * 30分钟 = 30 * 60
     */
    uint256 public constant MIN_STAKING_DURATION = 30 minutes;

    /**
     * @dev 质押信息结构体
     */
    struct TokenStakingInfo {
        uint256 stakedAmount;     // 质押数量
        uint256 stakeTime;       // 质押时间
        uint256 lastClaimTime;   // 最后领取时间
        uint256 accumulatedReward; // 累积奖励
    }

    /**
     * @dev 用户质押映射
     * user => TokenStakingInfo
     */
    mapping(address => TokenStakingInfo) public stakingInfo;

    /**
     * @dev 总质押金额
     */
    uint256 public totalStaked;

    /**
     * @dev 年化收益率（APY，精度4位小数）
     * 例如：1500 = 15.00%
     */
    uint256 public annualRewardRate;

    /**
     * @dev 质押事件
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @dev 解除质押事件
     */
    event Unstaked(address indexed user, uint256 amount);

    /**
     * @dev 领取奖励事件
     */
    event RewardClaimed(address indexed user, uint256 amount);

    /**
     * @dev 质押代币
     *
     * @param amount 质押数量
     */
    function stake(uint256 amount) external {
        require(amount > 0, "TokenStaking: Invalid amount");

        TokenStakingInfo storage info = stakingInfo[msg.sender];

        if (info.stakedAmount > 0) {
            uint256 pending = _calculateReward(msg.sender);
            info.accumulatedReward += pending;
        } else {
            info.stakeTime = block.timestamp;
        }

        info.stakedAmount += amount;
        info.lastClaimTime = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev 解除质押
     *
     * @param amount 解除数量
     */
    function unstake(uint256 amount) external {
        TokenStakingInfo storage info = stakingInfo[msg.sender];
        require(info.stakedAmount >= amount, "TokenStaking: Insufficient balance");
        require(block.timestamp >= info.stakeTime + MIN_STAKING_DURATION, "TokenStaking: Lock period");

        uint256 pending = _calculateReward(msg.sender);
        info.accumulatedReward += pending;
        info.stakedAmount -= amount;
        info.lastClaimTime = block.timestamp;

        if (info.stakedAmount == 0) {
            info.stakeTime = 0;
        }

        totalStaked -= amount;

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @dev 领取奖励
     */
    function claimReward() external returns (uint256) {
        TokenStakingInfo storage info = stakingInfo[msg.sender];
        uint256 pending = _calculateReward(msg.sender);
        uint256 total = info.accumulatedReward + pending;

        require(total > 0, "TokenStaking: No reward");

        info.accumulatedReward = 0;
        info.lastClaimTime = block.timestamp;

        emit RewardClaimed(msg.sender, total);
        return total;
    }

    /**
     * @dev 获取质押信息
     */
    function getStakingInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 lastClaimTime,
        uint256 accumulatedReward
    ) {
        TokenStakingInfo memory info = stakingInfo[user];
        return (info.stakedAmount, info.lastClaimTime, info.accumulatedReward);
    }

    /**
     * @dev 获取待领取奖励
     */
    function getPendingReward(address user) external view returns (uint256) {
        return _calculateReward(user) + stakingInfo[user].accumulatedReward;
    }

    /**
     * @dev 计算奖励
     */
    function _calculateReward(address user) internal view returns (uint256) {
        TokenStakingInfo memory info = stakingInfo[user];
        if (info.stakedAmount == 0) return 0;

        uint256 timeDiff = block.timestamp - info.lastClaimTime;
        if (timeDiff == 0 || annualRewardRate == 0) return 0;

        uint256 yearlyReward = info.stakedAmount * annualRewardRate / 10000;
        uint256 dailyReward = yearlyReward / 365;
        uint256 reward = dailyReward * timeDiff / 86400;

        return reward;
    }

    /**
     * @dev 设置年化收益率
     */
    function setAnnualRewardRate(uint256 rate) external onlyOwner {
        require(rate <= 10000, "TokenStaking: Rate too high");
        annualRewardRate = rate;
        emit AnnualRewardRateSet(rate);
    }

    /**
     * @dev 事件：年化收益率设置
     */
    event AnnualRewardRateSet(uint256 rate);

    /**
     * @dev 获取质押常量
     */
    function getStakingConstants() external pure returns (uint256) {
        return MIN_STAKING_DURATION;
    }
}
