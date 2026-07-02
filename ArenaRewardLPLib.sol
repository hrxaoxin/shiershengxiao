// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

library ArenaRewardLPLib {
    using SafeERC20 for IERC20;

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

    struct LPConfig {
        address token;
        address wbnb;
        address router;
        uint256 slippage;
        address lpToken;
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
    error ARL_InvalidToken();
    error ARL_InvalidRecipient();
    error ARL_InvalidRate();
    error ARL_BNBTransferFailed();
    error ARL_ZeroAmount();

    event LPAddedToPool(uint256 amount);
    event TokenAddedToPool(uint256 amount);
    event BNBAddedToPool(uint256 amount);
    event DailyRewardCalculated(uint256 dailyReward);
    event RewardRateUpdated(uint256 newRate);
    event LPRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event TokenRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event BNBRewardClaimed(address user, uint256 seasonId, uint256 amount);

    function _getLPConfig(IAuthorizer authorizer, uint8 dexType) private view returns (LPConfig memory) {
        address router;
        if (dexType == 0) {
            router = authorizer.getAddressByName("flapSwapRouter");
        } else if (dexType == 1) {
            router = authorizer.getAddressByName("pancakeSwapRouter");
        } else {
            router = authorizer.getAddressByName("uniswapRouter");
        }

        address lpToken = address(0);
        if (router != address(0)) {
            try IDexRouter(router).factory() returns (address factory) {
                lpToken = IDexFactory(factory).getPair(authorizer.getAddressByName("token"), authorizer.getAddressByName("wbnb"));
            } catch {}
        }

        return LPConfig({
            token: authorizer.getAddressByName("token"),
            wbnb: authorizer.getAddressByName("wbnb"),
            router: router,
            slippage: 1000,
            lpToken: lpToken
        });
    }

    function _getPath(address from, address to) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        return path;
    }

    function _swapTokenToWBNB(LPConfig memory config, uint256 tokenAmount) private returns (uint256) {
        address[] memory path = _getPath(config.token, config.wbnb);

        try IDexRouter(config.router).getAmountsOut(tokenAmount, path) returns (uint256[] memory amounts) {
            uint256 minOut = amounts[1] * (10000 - config.slippage) / 10000;
            IERC20(config.token).approve(config.router, tokenAmount);

            try IDexRouter(config.router).swapExactTokensForTokens(
                tokenAmount,
                minOut,
                path,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory outputAmounts) {
                return outputAmounts[1];
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }

    function _swapWBNBToToken(LPConfig memory config, uint256 wbnbAmount) private returns (uint256) {
        address[] memory path = _getPath(config.wbnb, config.token);

        try IDexRouter(config.router).getAmountsOut(wbnbAmount, path) returns (uint256[] memory amounts) {
            uint256 minOut = amounts[1] * (10000 - config.slippage) / 10000;
            IERC20(config.wbnb).approve(config.router, wbnbAmount);

            try IDexRouter(config.router).swapExactTokensForTokens(
                wbnbAmount,
                minOut,
                path,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory outputAmounts) {
                return outputAmounts[1];
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }

    function _generateLPFromWBNB(LPConfig memory config, uint256 wbnbAmount) private returns (uint256) {
        uint256 halfWBNB = wbnbAmount / 2;
        uint256 tokenAmount = _swapWBNBToToken(config, halfWBNB);

        if (tokenAmount == 0) return 0;

        IERC20(config.wbnb).approve(config.router, halfWBNB);
        IERC20(config.token).approve(config.router, tokenAmount);

        try IDexRouter(config.router).addLiquidityETH{value: halfWBNB}(
            config.token,
            tokenAmount,
            tokenAmount * (10000 - config.slippage) / 10000,
            halfWBNB * (10000 - config.slippage) / 10000,
            address(this),
            block.timestamp + 300
        ) returns (uint256, uint256, uint256 liquidity) {
            return liquidity;
        } catch {
            IWBNB(config.wbnb).withdraw(wbnbAmount - halfWBNB);
            (bool success, ) = payable(msg.sender).call{value: wbnbAmount - halfWBNB}("");
            if (!success) revert ARL_BNBTransferFailed();
            IERC20(config.token).safeTransfer(msg.sender, tokenAmount);
            return 0;
        }
    }

    function _convertTokenToLP(LPConfig memory config, uint256 tokenAmount) private returns (uint256) {
        uint256 halfToken = tokenAmount / 2;
        uint256 wbnbAmount = _swapTokenToWBNB(config, halfToken);

        if (wbnbAmount == 0) return 0;

        IERC20(config.token).approve(config.router, halfToken);
        IERC20(config.wbnb).approve(config.router, wbnbAmount);

        try IDexRouter(config.router).addLiquidityETH{value: wbnbAmount}(
            config.token,
            halfToken,
            halfToken * (10000 - config.slippage) / 10000,
            wbnbAmount * (10000 - config.slippage) / 10000,
            address(this),
            block.timestamp + 300
        ) returns (uint256, uint256, uint256 liquidity) {
            return liquidity;
        } catch {
            IWBNB(config.wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(msg.sender).call{value: wbnbAmount}("");
            if (!success) revert ARL_BNBTransferFailed();
            IERC20(config.token).safeTransfer(msg.sender, halfToken);
            return 0;
        }
    }

    function _redeemLPWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) private returns (uint256, uint256) {
        for (uint8 i = 0; i < 3; i++) {
            LPConfig memory config = _getLPConfig(authorizer, i);
            if (config.lpToken == address(0) || config.router == address(0)) continue;

            uint256 balance = IERC20(config.lpToken).balanceOf(address(this));
            if (balance >= lpAmount) {
                IERC20(config.lpToken).approve(config.router, lpAmount);

                try IDexRouter(config.router).removeLiquidityETH(
                    config.token,
                    lpAmount,
                    0,
                    0,
                    address(this),
                    block.timestamp + 300
                ) returns (uint256 tokenAmount, uint256 wbnbAmount) {
                    return (tokenAmount, wbnbAmount);
                } catch {}
            }
        }
        return (0, 0);
    }

    function convertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        address wbnb = authorizer.getAddressByName("wbnb");
        IWBNB(wbnb).deposit{value: bnbAmount}();

        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.router == address(0)) continue;
            uint256 lpAmount = _generateLPFromWBNB(config, bnbAmount);
            if (lpAmount > 0) return lpAmount;
        }

        IWBNB(wbnb).withdraw(bnbAmount);
        (bool success, ) = payable(msg.sender).call{value: bnbAmount}("");
        if (!success) revert ARL_BNBTransferFailed();
        return 0;
    }

    function convertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;
            uint256 lpAmount = _convertTokenToLP(config, tokenAmount);
            if (lpAmount > 0) return lpAmount;
        }
        return 0;
    }

    function swapBNBToToken(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;

            try IDexRouter(config.router).swapExactETHForTokens{value: bnbAmount}(
                0,
                _getPath(config.wbnb, config.token),
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts) {
                return amounts[amounts.length - 1];
            } catch {}
        }
        return 0;
    }

    function swapWBNBToToken(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;
            uint256 amount = _swapWBNBToToken(config, wbnbAmount);
            if (amount > 0) return amount;
        }
        return 0;
    }

    function swapTokenToBNB(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;

            IERC20(config.token).approve(config.router, tokenAmount);
            try IDexRouter(config.router).swapExactTokensForETH(
                tokenAmount,
                0,
                _getPath(config.token, config.wbnb),
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts) {
                return amounts[amounts.length - 1];
            } catch {}
        }
        return 0;
    }

    function redeemLPToToken(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.lpToken == address(0) || config.router == address(0)) continue;

            uint256 balance = IERC20(config.lpToken).balanceOf(address(this));
            if (balance < lpAmount) continue;

            IERC20(config.lpToken).approve(config.router, lpAmount);

            try IDexRouter(config.router).removeLiquidityETH(
                config.token,
                lpAmount,
                0,
                0,
                address(this),
                block.timestamp + 300
            ) returns (uint256 tokenAmount, uint256 wbnbAmount) {
                if (wbnbAmount > 0) {
                    uint256 convertedToken = swapWBNBToToken(authorizer, wbnbAmount);
                    tokenAmount += convertedToken;
                }
                return tokenAmount;
            } catch {}
        }
        return 0;
    }

    function redeemLPToWBNB(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType < 3; dexType++) {
            LPConfig memory config = _getLPConfig(authorizer, dexType);
            if (config.lpToken == address(0) || config.router == address(0)) continue;

            uint256 balance = IERC20(config.lpToken).balanceOf(address(this));
            if (balance < lpAmount) continue;

            IERC20(config.lpToken).approve(config.router, lpAmount);

            try IDexRouter(config.router).removeLiquidityETH(
                config.token,
                lpAmount,
                0,
                0,
                address(this),
                block.timestamp + 300
            ) returns (uint256 tokenAmount, uint256 wbnbAmount) {
                if (tokenAmount > 0) {
                    uint256 convertedBNB = swapTokenToBNB(authorizer, tokenAmount);
                    if (convertedBNB > 0) {
                        wbnbAmount += convertedBNB;
                    }
                }
                return wbnbAmount;
            } catch {}
        }
        return 0;
    }

    function redeemLPToUser(IAuthorizer authorizer, uint256 lpAmount, address user) internal {
        (uint256 tokenAmount, uint256 wbnbAmount) = _redeemLPWithAutoDetect(authorizer, lpAmount);
        address token = authorizer.getAddressByName("token");
        address wbnb = authorizer.getAddressByName("wbnb");

        if (tokenAmount > 0) {
            IERC20(token).safeTransfer(user, tokenAmount);
        }

        if (wbnbAmount > 0) {
            IWBNB(wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(user).call{value: wbnbAmount}("");
            if (!success) revert ARL_BNBTransferFailed();
        }
    }

    function compoundFees(IAuthorizer authorizer) internal {
        address wbnb = authorizer.getAddressByName("wbnb");
        uint256 balance = IWBNB(wbnb).balanceOf(address(this));

        if (balance >= 1000000000000000) {
            IWBNB(wbnb).withdraw(balance);
            convertBNBToLP(authorizer, balance);
        }
    }

    function emergencyWithdrawWBNB(IAuthorizer authorizer, uint256 amount) internal {
        address wbnb = authorizer.getAddressByName("wbnb");
        if (amount == 0) revert ARL_ZeroAmount();
        if (IWBNB(wbnb).balanceOf(address(this)) < amount) revert ARL_InsufficientBNB();

        IWBNB(wbnb).withdraw(amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert ARL_BNBTransferFailed();
    }

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
            uint256 lpAmount = convertBNBToLP(authorizer, amount);
            if (lpAmount > 0) {
                addToRewardPool(pool, lpAmount, RewardType.LP);
            }
        } else if (currentType == RewardType.TOKEN) {
            uint256 tokenAmount = swapBNBToToken(authorizer, amount);
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
        address wbnb = authorizer.getAddressByName("wbnb");
        address mainToken = authorizer.getAddressByName("token");

        if (token == wbnb) {
            if (currentType == RewardType.LP) {
                IWBNB(wbnb).withdraw(amount);
                uint256 lpAmount = convertBNBToLP(authorizer, amount);
                if (lpAmount > 0) {
                    addToRewardPool(pool, lpAmount, RewardType.LP);
                }
            } else if (currentType == RewardType.TOKEN) {
                uint256 tokenAmount = swapWBNBToToken(authorizer, amount);
                if (tokenAmount > 0) {
                    addToRewardPool(pool, tokenAmount, RewardType.TOKEN);
                }
            } else if (currentType == RewardType.BNB) {
                IWBNB(wbnb).withdraw(amount);
                addToRewardPool(pool, amount, RewardType.BNB);
            }
        } else if (token == mainToken) {
            if (currentType == RewardType.LP) {
                uint256 lpAmount = convertTokenToLP(authorizer, amount);
                if (lpAmount > 0) {
                    addToRewardPool(pool, lpAmount, RewardType.LP);
                }
            } else if (currentType == RewardType.TOKEN) {
                addToRewardPool(pool, amount, RewardType.TOKEN);
            } else if (currentType == RewardType.BNB) {
                uint256 bnbAmount = swapTokenToBNB(authorizer, amount);
                if (bnbAmount > 0) {
                    addToRewardPool(pool, bnbAmount, RewardType.BNB);
                }
            }
        } else {
            uint256 bnbAmount = swapTokenToBNB(authorizer, amount);
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
                uint256 tokenAmount = redeemLPToToken(authorizer, pool.lpRewardPoolBalance);
                pool.lpRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    pool.tokenRewardPoolBalance += tokenAmount;
                }
            }
        } else if (fromType == RewardType.LP && toType == RewardType.BNB) {
            if (pool.lpRewardPoolBalance > 0) {
                uint256 wbnbAmount = redeemLPToWBNB(authorizer, pool.lpRewardPoolBalance);
                pool.lpRewardPoolBalance = 0;
                if (wbnbAmount > 0) {
                    pool.bnbRewardPoolBalance += wbnbAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.LP) {
            if (pool.tokenRewardPoolBalance > 0) {
                uint256 lpAmount = convertTokenToLP(authorizer, pool.tokenRewardPoolBalance);
                pool.tokenRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    pool.lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.BNB) {
            if (pool.tokenRewardPoolBalance > 0) {
                uint256 bnbAmount = swapTokenToBNB(authorizer, pool.tokenRewardPoolBalance);
                pool.tokenRewardPoolBalance = 0;
                if (bnbAmount > 0) {
                    pool.bnbRewardPoolBalance += bnbAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.LP) {
            if (pool.bnbRewardPoolBalance > 0) {
                uint256 lpAmount = convertBNBToLP(authorizer, pool.bnbRewardPoolBalance);
                pool.bnbRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    pool.lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.TOKEN) {
            if (pool.bnbRewardPoolBalance > 0) {
                uint256 tokenAmount = swapBNBToToken(authorizer, pool.bnbRewardPoolBalance);
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

    function _adjustRewardRate(RewardPool storage pool, uint256 expectedDailyReward) private {
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
            redeemLPToUser(authorizer, reward, user);
            emit LPRewardClaimed(user, seasonId, reward);
        } else if (currentType == RewardType.TOKEN) {
            IERC20(authorizer.getAddressByName("token")).safeTransfer(user, reward);
            emit TokenRewardClaimed(user, seasonId, reward);
        } else if (currentType == RewardType.BNB) {
            (bool success, ) = payable(user).call{value: reward}("");
            if (!success) revert ARL_BNBTransferFailed();
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
