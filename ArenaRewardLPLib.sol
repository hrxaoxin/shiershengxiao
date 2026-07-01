// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./LPLib.sol";

library ArenaRewardLPLib {
    using SafeERC20 for IERC20;
    using LPLib for IAuthorizer;

    struct RewardPool {
        uint256 lpRewardPoolBalance;
        uint256 tokenRewardPoolBalance;
        uint256 bnbRewardPoolBalance;
        RewardType rewardType;
        uint256 rewardRate;
        uint256 maxRewardRate;
        uint256 maxDailyRewardPercent;
        uint256 rateStep;
        uint256 todayStart;
        uint256 todayRewardAmount;
        uint256 todayIncomingTokens;
        uint256 rewardPrecision;
    }

    error ARL_InvalidAmount();
    error ARL_LPOverflow();
    error ARL_TokenOverflow();
    error ARL_BNBOverflow();
    error ARL_InsufficientLP();
    error ARL_InsufficientToken();
    error ARL_InsufficientBNB();
    error ARL_NoReward();
    error ARL_AlreadyClaimed();

    event LPAddedToPool(uint256 amount);
    event TokenAddedToPool(uint256 amount);
    event BNBAddedToPool(uint256 amount);
    event DailyRewardCalculated(uint256 dailyReward);
    event RewardRateUpdated(uint256 newRate);
    event LPRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event TokenRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event BNBRewardClaimed(address user, uint256 seasonId, uint256 amount);

    function addToRewardPool(
        RewardPool storage pool,
        uint256 amount,
        RewardType type_
    ) internal {
        if (type_ == RewardType.LP) {
            uint256 newBalance = pool.lpRewardPoolBalance + amount;
            if (newBalance < pool.lpRewardPoolBalance) revert ARL_LPOverflow();
            pool.lpRewardPoolBalance = newBalance;
            emit LPAddedToPool(amount);
        } else if (type_ == RewardType.TOKEN) {
            uint256 newBalance = pool.tokenRewardPoolBalance + amount;
            if (newBalance < pool.tokenRewardPoolBalance) revert ARL_TokenOverflow();
            pool.tokenRewardPoolBalance = newBalance;
            emit TokenAddedToPool(amount);
        } else if (type_ == RewardType.BNB) {
            uint256 newBalance = pool.bnbRewardPoolBalance + amount;
            if (newBalance < pool.bnbRewardPoolBalance) revert ARL_BNBOverflow();
            pool.bnbRewardPoolBalance = newBalance;
            emit BNBAddedToPool(amount);
        }
    }

    function processIncomingBNB(
        RewardPool storage pool,
        IAuthorizer authorizer,
        uint256 amount
    ) internal {
        RewardType currentType = pool.rewardType;
        if (currentType == RewardType.LP) {
            uint256 lpAmount = authorizer.convertBNBToLP(amount);
            if (lpAmount > 0) {
                addToRewardPool(pool, lpAmount, RewardType.LP);
            }
        } else if (currentType == RewardType.TOKEN) {
            uint256 tokenAmount = authorizer.swapBNBToToken(amount);
            if (tokenAmount > 0) {
                addToRewardPool(pool, tokenAmount, RewardType.TOKEN);
            }
        } else if (currentType == RewardType.BNB) {
            addToRewardPool(pool, amount, RewardType.BNB);
        }
    }

    function processIncomingToken(
        RewardPool storage pool,
        IAuthorizer authorizer,
        address token,
        uint256 amount
    ) internal {
        RewardType currentType = pool.rewardType;
        address wbnb = authorizer.getAddressByName(\"wbnb\");
        address mainToken = authorizer.getAddressByName(\"token\");

        if (token == wbnb) {
            if (currentType == RewardType.LP) {
                IWBNB(wbnb).withdraw(amount);
                uint256 lpAmount = authorizer.convertBNBToLP(amount);
                if (lpAmount > 0) {
                    addToRewardPool(pool, lpAmount, RewardType.LP);
                }
            } else if (currentType == RewardType.TOKEN) {
                uint256 tokenAmount = authorizer.swapWBNBToToken(amount);
                if (tokenAmount > 0) {
                    addToRewardPool(pool, tokenAmount, RewardType.TOKEN);
                }
            } else if (currentType == RewardType.BNB) {
                IWBNB(wbnb).withdraw(amount);
                addToRewardPool(pool, amount, RewardType.BNB);
            }
        } else if (token == mainToken) {
            if (currentType == RewardType.LP) {
                uint256 lpAmount = authorizer.convertTokenToLP(amount);
                if (lpAmount > 0) {
                    addToRewardPool(pool, lpAmount, RewardType.LP);
                }
            } else if (currentType == RewardType.TOKEN) {
                addToRewardPool(pool, amount, RewardType.TOKEN);
            } else if (currentType == RewardType.BNB) {
                uint256 bnbAmount = authorizer.swapTokenToBNB(amount);
                if (bnbAmount > 0) {
                    addToRewardPool(pool, bnbAmount, RewardType.BNB);
                }
            }
        } else {
            uint256 bnbAmount = authorizer.swapTokenToBNB(amount);
            if (bnbAmount > 0) {
                processIncomingBNB(pool, authorizer, bnbAmount);
            }
        }
    }

    function convertPoolAssets(
        RewardPool storage pool,
        IAuthorizer authorizer,
        RewardType fromType,
        RewardType toType
    ) internal {
        if (fromType == RewardType.LP && toType == RewardType.TOKEN) {
            if (pool.lpRewardPoolBalance > 0) {
                uint256 tokenAmount = authorizer.redeemLPToToken(pool.lpRewardPoolBalance);
                pool.lpRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    pool.tokenRewardPoolBalance += tokenAmount;
                }
            }
        } else if (fromType == RewardType.LP && toType == RewardType.BNB) {
            if (pool.lpRewardPoolBalance > 0) {
                uint256 wbnbAmount = authorizer.redeemLPToWBNB(pool.lpRewardPoolBalance);
                pool.lpRewardPoolBalance = 0;
                if (wbnbAmount > 0) {
                    pool.bnbRewardPoolBalance += wbnbAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.LP) {
            if (pool.tokenRewardPoolBalance > 0) {
                uint256 lpAmount = authorizer.convertTokenToLP(pool.tokenRewardPoolBalance);
                pool.tokenRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    pool.lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.BNB) {
            if (pool.tokenRewardPoolBalance > 0) {
                uint256 bnbAmount = authorizer.swapTokenToBNB(pool.tokenRewardPoolBalance);
                pool.tokenRewardPoolBalance = 0;
                if (bnbAmount > 0) {
                    pool.bnbRewardPoolBalance += bnbAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.LP) {
            if (pool.bnbRewardPoolBalance > 0) {
                uint256 lpAmount = authorizer.convertBNBToLP(pool.bnbRewardPoolBalance);
                pool.bnbRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    pool.lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.TOKEN) {
            if (pool.bnbRewardPoolBalance > 0) {
                uint256 tokenAmount = authorizer.swapBNBToToken(pool.bnbRewardPoolBalance);
                pool.bnbRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    pool.tokenRewardPoolBalance += tokenAmount;
                }
            }
        }
    }

    function getPoolBalance(RewardPool storage pool, RewardType type_) internal view returns (uint256) {
        if (type_ == RewardType.LP) {
            return pool.lpRewardPoolBalance;
        } else if (type_ == RewardType.TOKEN) {
            return pool.tokenRewardPoolBalance;
        } else {
            return pool.bnbRewardPoolBalance;
        }
    }

    function deductFromPool(RewardPool storage pool, RewardType type_, uint256 amount) internal {
        if (type_ == RewardType.LP) {
            if (pool.lpRewardPoolBalance < amount) revert ARL_InsufficientLP();
            pool.lpRewardPoolBalance -= amount;
        } else if (type_ == RewardType.TOKEN) {
            if (pool.tokenRewardPoolBalance < amount) revert ARL_InsufficientToken();
            pool.tokenRewardPoolBalance -= amount;
        } else if (type_ == RewardType.BNB) {
            if (pool.bnbRewardPoolBalance < amount) revert ARL_InsufficientBNB();
            pool.bnbRewardPoolBalance -= amount;
        }
    }

    function calculateDailyReward(RewardPool storage pool) internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart <= pool.todayStart) return;

        pool.todayStart = currentDayStart;
        pool.rewardRate = 100;

        RewardType currentType = pool.rewardType;
        uint256 poolBalance = getPoolBalance(pool, currentType);

        if (poolBalance == 0) {
            pool.todayRewardAmount = 0;
            pool.todayIncomingTokens = 0;
            return;
        }

        uint256 expectedDailyReward = poolBalance * pool.rewardRate / pool.rewardPrecision;
        _adjustRewardRate(pool, expectedDailyReward);

        uint256 dailyReward = poolBalance * pool.rewardRate / pool.rewardPrecision;
        uint256 maxDailyReward = poolBalance * pool.maxDailyRewardPercent / 1000;

        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }

        if (dailyReward > 0) {
            pool.todayRewardAmount = dailyReward;
            deductFromPool(pool, currentType, dailyReward);
            emit DailyRewardCalculated(dailyReward);
        }

        pool.todayIncomingTokens = 0;
    }

    function _adjustRewardRate(RewardPool storage pool, uint256 expectedDailyReward) internal {
        if (expectedDailyReward == 0) return;

        if (pool.todayIncomingTokens > expectedDailyReward) {
            uint256 multiple = pool.todayIncomingTokens / expectedDailyReward;
            uint256 steps = multiple - 1;
            uint256 maxSteps = (pool.maxRewardRate - pool.rewardRate) / pool.rateStep;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = pool.rewardRate + (steps * pool.rateStep);

            if (newRate != pool.rewardRate) {
                pool.rewardRate = newRate;
                emit RewardRateUpdated(pool.rewardRate);
            }
        }
    }

    function recordIncomingTokens(RewardPool storage pool, uint256 amount) internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart != pool.todayStart) {
            pool.todayStart = currentDayStart;
            pool.todayIncomingTokens = 0;
        }
        pool.todayIncomingTokens += amount;
    }

    function claimReward(
        RewardPool storage pool,
        IAuthorizer authorizer,
        address user,
        uint256 seasonId,
        uint256 reward,
        address arenaReward
    ) internal returns (uint256) {
        if (reward == 0) revert ARL_NoReward();
        if (IArenaReward(arenaReward).isRewardClaimed(user, seasonId)) revert ARL_AlreadyClaimed();

        RewardType currentType = pool.rewardType;
        deductFromPool(pool, currentType, reward);

        if (currentType == RewardType.LP) {
            authorizer.redeemLPToUser(reward, user);
            emit LPRewardClaimed(user, seasonId, reward);
        } else if (currentType == RewardType.TOKEN) {
            IERC20(authorizer.getAddressByName(\"token\")).safeTransfer(user, reward);
            emit TokenRewardClaimed(user, seasonId, reward);
        } else if (currentType == RewardType.BNB) {
            (bool success, ) = payable(user).call{value: reward}("");
            require(success, "ArenaRewardLPLib: BNB transfer failed");
            emit BNBRewardClaimed(user, seasonId, reward);
        }

        IArenaReward(arenaReward).markRewardClaimed(user, seasonId);
        return reward;
    }

    function getPendingReward(
        RewardPool storage pool,
        address user,
        uint256 seasonId,
        address arenaReward
    ) internal view returns (uint256) {
        IArenaReward arenaRewardContract = IArenaReward(arenaReward);

        if (arenaRewardContract.isRewardClaimed(user, seasonId)) {
            return 0;
        }

        uint256 reward = arenaRewardContract.getPendingRewardsByPlayer(user, seasonId);
        uint256 poolBalance = getPoolBalance(pool, pool.rewardType);

        return reward > poolBalance ? poolBalance : reward;
    }

    function shouldCalculateDailyReward(RewardPool storage pool) internal view returns (bool) {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        return currentDayStart > pool.todayStart;
    }
}
