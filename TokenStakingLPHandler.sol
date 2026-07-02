// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "./TokenStakingLPLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenStakingLPHandler {
    using SafeERC20 for IERC20;
    
    uint256 private constant REWARD_PRECISION = 1e18;
    uint256 private constant DAILY_REWARD_PRECISION = 10000;

    address public authorizer;
    RewardType private rewardType;
    uint256 private lpRewardPoolBalance;
    uint256 private tokenRewardPoolBalance;
    uint256 private bnbRewardPoolBalance;
    uint256 private rewardRate;
    uint256 private maxRewardRate;
    uint256 private maxDailyRewardPercent;
    uint256 private rateStep;
    uint256 private todayStart;
    uint256 private todayRewardAmount;
    uint256 private todayIncomingTokens;
    uint256 private dailyRewardPerToken;
    uint256 public epoch;
    mapping(uint256 => mapping(address => uint256)) private _lastRewardAccumulatedRate;

    error TSLPH_NoStakedTokens();
    error TSLPH_InsufficientLP();
    error TSLPH_InsufficientToken();
    error TSLPH_BNBTransferFailed();

    event LPRewardsClaimed(address indexed user, uint256 amount);
    event TokenRewardsClaimed(address indexed user, uint256 amount);
    event BNBRewardsClaimed(address indexed user, uint256 amount);
    event DailyRewardCalculated(uint256 dailyReward, uint256 increment);
    event RewardRateUpdated(uint256 rewardRate);

    function claimLPRewardHandler() external {
        address tokenStaking = IAuthorizer(authorizer).getAddressByName("tokenStaking");
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(msg.sender);
        if (stake.amount == 0) revert TSLPH_NoStakedTokens();

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            uint256 reward = bnbRewardPoolBalance * stake.amount / (totalStaked + 1);
            if (reward > 0 && reward <= bnbRewardPoolBalance) {
                bnbRewardPoolBalance -= reward;
                (bool success, ) = payable(msg.sender).call{value: reward}("");
                if (!success) revert TSLPH_BNBTransferFailed();
                emit BNBRewardsClaimed(msg.sender, reward);
            }
            return;
        }

        uint256 currentEpoch = epoch;
        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = _lastRewardAccumulatedRate[currentEpoch][msg.sender];
        
        if (currentRate <= lastRate) {
            return;
        }

        uint256 reward = stake.amount * (currentRate - lastRate) / REWARD_PRECISION;
        
        if (currentType == RewardType.LP) {
            if (reward > lpRewardPoolBalance) revert TSLPH_InsufficientLP();
            lpRewardPoolBalance -= reward;
            TokenStakingLPLib.redeemLPToUser(IAuthorizer(authorizer), reward, msg.sender);
            emit LPRewardsClaimed(msg.sender, reward);
        } else if (currentType == RewardType.TOKEN) {
            if (reward > tokenRewardPoolBalance) revert TSLPH_InsufficientToken();
            tokenRewardPoolBalance -= reward;
            IERC20(IAuthorizer(authorizer).getAddressByName("token")).safeTransfer(msg.sender, reward);
            emit TokenRewardsClaimed(msg.sender, reward);
        }

        _lastRewardAccumulatedRate[currentEpoch][msg.sender] = currentRate;
    }

    function calculateDailyRewardHandler() external {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart <= todayStart) return;

        todayStart = currentDayStart;
        rewardRate = 100;

        address tokenStaking = IAuthorizer(authorizer).getAddressByName("tokenStaking");
        uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();

        RewardType currentType = rewardType;
        uint256 poolBalance;

        if (currentType == RewardType.LP) {
            poolBalance = lpRewardPoolBalance;
        } else if (currentType == RewardType.TOKEN) {
            poolBalance = tokenRewardPoolBalance;
        } else {
            poolBalance = bnbRewardPoolBalance;
        }

        if (poolBalance == 0 || totalStaked == 0) {
            todayRewardAmount = 0;
            todayIncomingTokens = 0;
            return;
        }

        uint256 expectedDailyReward = poolBalance * rewardRate / DAILY_REWARD_PRECISION;
        
        if (expectedDailyReward > 0 && todayIncomingTokens > expectedDailyReward) {
            uint256 multiple = todayIncomingTokens / expectedDailyReward;
            uint256 steps = multiple - 1;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);
            if (newRate != rewardRate) {
                rewardRate = newRate;
                emit RewardRateUpdated(rewardRate);
            }
        }

        uint256 dailyReward = poolBalance * rewardRate / DAILY_REWARD_PRECISION;
        uint256 maxDailyReward = poolBalance * maxDailyRewardPercent / 1000;
        
        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }

        if (dailyReward > 0) {
            uint256 increment = (dailyReward * REWARD_PRECISION) / totalStaked;
            dailyRewardPerToken += increment;
            todayRewardAmount = dailyReward;
            
            if (currentType == RewardType.LP) {
                lpRewardPoolBalance -= dailyReward;
            } else if (currentType == RewardType.TOKEN) {
                tokenRewardPoolBalance -= dailyReward;
            } else {
                bnbRewardPoolBalance -= dailyReward;
            }
            
            emit DailyRewardCalculated(dailyReward, increment);
        }

        todayIncomingTokens = 0;
    }
}