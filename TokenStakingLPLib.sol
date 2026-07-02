// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

library TokenStakingLPLib {
    using SafeERC20 for IERC20;
    struct LPConfig {
        address token;
        address wbnb;
        address router;
        uint256 slippage;
        address lpToken;
    }

    struct RewardPoolState {
        uint256 lpRewardPoolBalance;
        uint256 tokenRewardPoolBalance;
        uint256 bnbRewardPoolBalance;
        RewardType rewardType;
        uint256 stakingRewardPrecision;
    }

    error RP_LPOverflow();
    error RP_TokenOverflow();
    error RP_BNBOverflow();
    error TSL_BNBTransferFailed();
    error TSL_AmountZero();
    error TSL_InsufficientWBNB();

    event LPAddedToPool(uint256 lpAmount);
    event TokenAddedToPool(uint256 tokenAmount);
    event BNBAddedToPool(uint256 bnbAmount);

    function getConfig(IAuthorizer authorizer, uint8 dexType) internal view returns (LPConfig memory) {
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

    function convertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;

            IWBNB(config.wbnb).deposit{value: bnbAmount}();
            uint256 lpAmount = _generateLPFromWBNB(config, bnbAmount);
            if (lpAmount > 0) return lpAmount;
        }
        return 0;
    }

    function convertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;

            uint256 lpAmount = _convertTokenToLP(config, tokenAmount);
            if (lpAmount > 0) return lpAmount;
        }
        return 0;
    }

    function _convertTokenToLP(LPConfig memory config, uint256 tokenAmount) internal returns (uint256) {
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
            return 0;
        }
    }

    function _swapTokenToWBNB(LPConfig memory config, uint256 tokenAmount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = config.token;
        path[1] = config.wbnb;

        try IDexRouter(config.router).getAmountsOut(tokenAmount, path) returns (uint256[] memory amounts) {
            uint256 expectedOut = amounts[1];
            uint256 minOut = expectedOut * (10000 - config.slippage) / 10000;

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

    function _generateLPFromWBNB(LPConfig memory config, uint256 wbnbAmount) internal returns (uint256) {
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
            return 0;
        }
    }

    function _swapWBNBToToken(LPConfig memory config, uint256 wbnbAmount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = config.wbnb;
        path[1] = config.token;

        try IDexRouter(config.router).getAmountsOut(wbnbAmount, path) returns (uint256[] memory amounts) {
            uint256 expectedOut = amounts[1];
            uint256 minOut = expectedOut * (10000 - config.slippage) / 10000;

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

    function redeemLPToToken(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
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
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
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

    function swapTokenToBNB(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
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

    function swapBNBToToken(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
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
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
            if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) continue;

            IERC20(config.wbnb).approve(config.router, wbnbAmount);

            try IDexRouter(config.router).swapExactTokensForTokens(
                wbnbAmount,
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

    function _getPath(address from, address to) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        return path;
    }

    function addToRewardPool(
        RewardPoolState memory state,
        uint256 amount,
        RewardType type_
    ) internal returns (RewardPoolState memory) {
        if (type_ == RewardType.LP) {
            uint256 newBalance = state.lpRewardPoolBalance + amount;
            if (newBalance < state.lpRewardPoolBalance) revert RP_LPOverflow();
            state.lpRewardPoolBalance = newBalance;
            emit LPAddedToPool(amount);
        } else if (type_ == RewardType.TOKEN) {
            uint256 newBalance = state.tokenRewardPoolBalance + amount;
            if (newBalance < state.tokenRewardPoolBalance) revert RP_TokenOverflow();
            state.tokenRewardPoolBalance = newBalance;
            emit TokenAddedToPool(amount);
        } else if (type_ == RewardType.BNB) {
            uint256 newBalance = state.bnbRewardPoolBalance + amount;
            if (newBalance < state.bnbRewardPoolBalance) revert RP_BNBOverflow();
            state.bnbRewardPoolBalance = newBalance;
            emit BNBAddedToPool(amount);
        }
        return state;
    }

    function convertPoolAssets(
        RewardPoolState memory state,
        IAuthorizer authorizer,
        RewardType fromType,
        RewardType toType
    ) internal returns (RewardPoolState memory) {
        if (fromType == RewardType.LP && toType == RewardType.TOKEN) {
            if (state.lpRewardPoolBalance > 0) {
                uint256 tokenAmount = redeemLPToToken(authorizer, state.lpRewardPoolBalance);
                state.lpRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    state.tokenRewardPoolBalance += tokenAmount;
                }
            }
        } else if (fromType == RewardType.LP && toType == RewardType.BNB) {
            if (state.lpRewardPoolBalance > 0) {
                uint256 wbnbAmount = redeemLPToWBNB(authorizer, state.lpRewardPoolBalance);
                state.lpRewardPoolBalance = 0;
                if (wbnbAmount > 0) {
                    state.bnbRewardPoolBalance += wbnbAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.LP) {
            if (state.tokenRewardPoolBalance > 0) {
                uint256 lpAmount = convertTokenToLP(authorizer, state.tokenRewardPoolBalance);
                state.tokenRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    state.lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.BNB) {
            if (state.tokenRewardPoolBalance > 0) {
                uint256 bnbAmount = swapTokenToBNB(authorizer, state.tokenRewardPoolBalance);
                state.tokenRewardPoolBalance = 0;
                if (bnbAmount > 0) {
                    state.bnbRewardPoolBalance += bnbAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.LP) {
            if (state.bnbRewardPoolBalance > 0) {
                uint256 lpAmount = convertBNBToLP(authorizer, state.bnbRewardPoolBalance);
                state.bnbRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    state.lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.TOKEN) {
            if (state.bnbRewardPoolBalance > 0) {
                uint256 tokenAmount = swapBNBToToken(authorizer, state.bnbRewardPoolBalance);
                state.bnbRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    state.tokenRewardPoolBalance += tokenAmount;
                }
            }
        }
        return state;
    }

    function processIncomingBNB(
        RewardPoolState memory state,
        IAuthorizer authorizer,
        RewardType rewardType,
        uint256 amount
    ) internal returns (RewardPoolState memory) {
        if (rewardType == RewardType.LP) {
            uint256 lpAmount = convertBNBToLP(authorizer, amount);
            if (lpAmount > 0) {
                state = addToRewardPool(state, lpAmount, RewardType.LP);
            }
        } else if (rewardType == RewardType.TOKEN) {
            uint256 tokenAmount = swapBNBToToken(authorizer, amount);
            if (tokenAmount > 0) {
                state = addToRewardPool(state, tokenAmount, RewardType.TOKEN);
            }
        } else {
            state = addToRewardPool(state, amount, RewardType.BNB);
        }
        return state;
    }

    function processIncomingToken(
        RewardPoolState memory state,
        IAuthorizer authorizer,
        RewardType rewardType,
        address token,
        uint256 amount
    ) internal returns (RewardPoolState memory) {
        address wbnb = authorizer.getAddressByName("wbnb");
        address mainToken = authorizer.getAddressByName("token");

        if (token == wbnb) {
            if (rewardType == RewardType.LP) {
                IWBNB(wbnb).withdraw(amount);
                uint256 lpAmount = convertBNBToLP(authorizer, amount);
                if (lpAmount > 0) {
                    state = addToRewardPool(state, lpAmount, RewardType.LP);
                }
            } else if (rewardType == RewardType.TOKEN) {
                uint256 tokenAmount = swapWBNBToToken(authorizer, amount);
                if (tokenAmount > 0) {
                    state = addToRewardPool(state, tokenAmount, RewardType.TOKEN);
                }
            } else {
                IWBNB(wbnb).withdraw(amount);
                state = addToRewardPool(state, amount, RewardType.BNB);
            }
        } else if (token == mainToken) {
            if (rewardType == RewardType.LP) {
                uint256 lpAmount = convertTokenToLP(authorizer, amount);
                if (lpAmount > 0) {
                    state = addToRewardPool(state, lpAmount, RewardType.LP);
                }
            } else if (rewardType == RewardType.TOKEN) {
                state = addToRewardPool(state, amount, RewardType.TOKEN);
            } else {
                uint256 bnbAmount = swapTokenToBNB(authorizer, amount);
                if (bnbAmount > 0) {
                    state = addToRewardPool(state, bnbAmount, RewardType.BNB);
                }
            }
        } else {
            uint256 bnbAmount = swapTokenToBNB(authorizer, amount);
            if (bnbAmount > 0) {
                state = processIncomingBNB(state, authorizer, rewardType, bnbAmount);
            }
        }
        return state;
    }

    function compoundFees(IAuthorizer authorizer) internal {
        address wbnb = authorizer.getAddressByName("wbnb");
        uint256 balance = IWBNB(wbnb).balanceOf(address(this));

        if (balance >= 1000000000000000) {
            IWBNB(wbnb).withdraw(balance);
            convertBNBToLP(authorizer, balance);
        }
    }

    function redeemLPToUser(IAuthorizer authorizer, uint256 lpAmount, address user) internal {
        (uint256 tokenAmount, uint256 wbnbAmount) = _redeemLP(authorizer, lpAmount);
        _transferRewards(authorizer, user, tokenAmount, wbnbAmount);
    }

    function _redeemLP(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256, uint256) {
        for (uint8 dexType = 0; dexType <= 2; dexType++) {
            LPConfig memory config = getConfig(authorizer, dexType);
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
                return (tokenAmount, wbnbAmount);
            } catch {}
        }
        return (0, 0);
    }

    function _transferRewards(IAuthorizer authorizer, address user, uint256 tokenAmount, uint256 wbnbAmount) internal {
        address token = authorizer.getAddressByName("token");
        address wbnb = authorizer.getAddressByName("wbnb");

        if (tokenAmount > 0) {
            IERC20(token).safeTransfer(user, tokenAmount);
        }

        if (wbnbAmount > 0) {
            IWBNB(wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(user).call{value: wbnbAmount}("");
            if (!success) revert TSL_BNBTransferFailed();
        }
    }

    function emergencyWithdrawWBNB(IAuthorizer authorizer, uint256 amount) internal {
        address wbnb = authorizer.getAddressByName("wbnb");
        if (amount == 0) revert TSL_AmountZero();
        if (IWBNB(wbnb).balanceOf(address(this)) < amount) revert TSL_InsufficientWBNB();

        IWBNB(wbnb).withdraw(amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TSL_BNBTransferFailed();
    }

    function calculateRewardPerTokenIncrement(
        RewardPoolState memory state,
        uint256 lpBefore,
        uint256 tokenBefore,
        IAuthorizer authorizer,
        uint256 rewardPrecision
    ) internal view returns (uint256) {
        if (state.rewardType == RewardType.LP || state.rewardType == RewardType.TOKEN) {
            address tokenStaking = authorizer.getAddressByName("tokenStaking");
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            
            if (totalStaked > 0) {
                uint256 addedAmount = 0;
                if (state.rewardType == RewardType.LP) {
                    addedAmount = state.lpRewardPoolBalance - lpBefore;
                } else if (state.rewardType == RewardType.TOKEN) {
                    addedAmount = state.tokenRewardPoolBalance - tokenBefore;
                }
                
                if (addedAmount > 0) {
                    return (addedAmount * rewardPrecision) / totalStaked;
                }
            }
        }
        return 0;
    }
}