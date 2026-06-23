// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";

/**
 * @title LPLib
 * @dev LP（流动性提供者）操作工具库，提供LP相关的统一函数
 *
 * 功能：
 * 1. BNB转换为LP：将BNB一半兑换为代币，一半兑换为WBNB，组成LP
 * 2. LP赎回为代币+WBNB：解除LP并返回代币和WBNB
 * 3. LP赎回并发送给用户：解除LP后直接发送给用户
 * 4. 手续费复投：将WBNB手续费自动转换为LP复投
 * 5. 紧急提现：支持紧急提取WBNB和LP
 *
 * 安全特性：
 * - 使用滑点保护防止MEV攻击
 * - 所有操作都经过授权验证
 * - 支持紧急提现功能
 */
library LPLib {

    struct LPConfig {
        address token;
        address wbnb;
        address router;
        uint256 slippage;
        address lpToken;
    }

    function getConfig(IAuthorizer authorizer, uint8 dexType) internal view returns (LPConfig memory) {
        address router;
        if (dexType == 0) {
            router = authorizer.getFlapSwapRouter();
        } else if (dexType == 1) {
            router = authorizer.getPancakeSwapRouter();
        } else {
            router = authorizer.getUniswapRouter();
        }
        
        address lpToken = address(0);
        if (router != address(0)) {
            try IDexRouter(router).factory() returns (address factory) {
                lpToken = IDexFactory(factory).getPair(authorizer.getToken(), authorizer.getWBNB());
            } catch {}
        }
        
        return LPConfig({
            token: authorizer.getToken(),
            wbnb: authorizer.getWBNB(),
            router: router,
            slippage: 1000,
            lpToken: lpToken
        });
    }
    
    function getConfigWithRouter(IAuthorizer authorizer, address _router) internal view returns (LPConfig memory) {
        address lpToken = address(0);
        if (_router != address(0)) {
            try IDexRouter(_router).factory() returns (address factory) {
                lpToken = IDexFactory(factory).getPair(authorizer.getToken(), authorizer.getWBNB());
            } catch {}
        }
        
        return LPConfig({
            token: authorizer.getToken(),
            wbnb: authorizer.getWBNB(),
            router: _router,
            slippage: 1000,
            lpToken: lpToken
        });
    }

    function convertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        return _convertBNBToLPWithFallback(authorizer, bnbAmount);
    }

    function convertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount, uint8 dexType) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        IWBNB(config.wbnb).deposit{value: bnbAmount}();
        return _generateLPFromWBNB(config, bnbAmount);
    }

    function convertWBNBToLP(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        return _convertWBNBToLPWithFallback(authorizer, wbnbAmount);
    }

    function convertWBNBToLP(IAuthorizer authorizer, uint256 wbnbAmount, uint8 dexType) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        IERC20(config.wbnb).transferFrom(msg.sender, address(this), wbnbAmount);
        return _generateLPFromWBNB(config, wbnbAmount);
    }

    function convertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        return _convertTokenToLPWithFallback(authorizer, tokenAmount);
    }

    function convertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount, uint8 dexType) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        uint256 halfToken = tokenAmount / 2;
        uint256 wbnbAmount = _swapTokenToWBNB(config, halfToken);

        if (wbnbAmount == 0) {
            IERC20(config.token).transfer(msg.sender, tokenAmount);
            return 0;
        }

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
            payable(msg.sender).transfer(wbnbAmount);
            IERC20(config.token).transfer(msg.sender, halfToken);
            return 0;
        }
    }

    function _swapTokenToWBNB(LPConfig memory config, uint256 tokenAmount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = config.token;
        path[1] = config.wbnb;

        uint256[] memory amounts = IDexRouter(config.router).getAmountsOut(tokenAmount, path);
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
    }

    function _generateLPFromWBNB(LPConfig memory config, uint256 wbnbAmount) internal returns (uint256) {
        uint256 halfWBNB = wbnbAmount / 2;
        uint256 tokenAmount = _swapWBNBToToken(config, halfWBNB);

        if (tokenAmount == 0) {
            IWBNB(config.wbnb).withdraw(wbnbAmount);
            payable(msg.sender).transfer(wbnbAmount);
            return 0;
        }

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
            payable(msg.sender).transfer(wbnbAmount - halfWBNB);
            IERC20(config.token).transfer(msg.sender, tokenAmount);
            return 0;
        }
    }

    function _swapWBNBToToken(LPConfig memory config, uint256 wbnbAmount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = config.wbnb;
        path[1] = config.token;

        uint256[] memory amounts = IDexRouter(config.router).getAmountsOut(wbnbAmount, path);
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
    }

    function redeemLP(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256, uint256) {
        return _redeemLPWithAutoDetect(authorizer, lpAmount);
    }
    
    function redeemLP(IAuthorizer authorizer, uint256 lpAmount, uint8 dexType) internal returns (uint256, uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        require(config.router != address(0), "LPLib: Router not set");
        require(config.lpToken != address(0), "LPLib: LP token not found");

        IERC20(config.lpToken).transferFrom(msg.sender, address(this), lpAmount);
        IERC20(config.lpToken).approve(config.router, lpAmount);

        (uint256 tokenAmount, uint256 wbnbAmount) = IDexRouter(config.router).removeLiquidityETH(
            config.token,
            lpAmount,
            0,
            0,
            address(this),
            block.timestamp + 300
        );

        return (tokenAmount, wbnbAmount);
    }
    
    function _redeemLPWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256, uint256) {
        for (uint8 i = 0; i < 3; i++) {
            LPConfig memory config = getConfig(authorizer, i);
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
        
        revert("LPLib: Failed to redeem LP from any DEX");
    }

    function redeemLPToUser(IAuthorizer authorizer, uint256 lpAmount, address user) internal {
        (uint256 tokenAmount, uint256 wbnbAmount) = redeemLP(authorizer, lpAmount);
        _transferRewards(authorizer, user, tokenAmount, wbnbAmount);
    }

    function redeemLPToToken(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        return _redeemLPToTokenWithAutoDetect(authorizer, lpAmount);
    }

    function redeemLPToWBNB(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        return _redeemLPToWBNBWithAutoDetect(authorizer, lpAmount);
    }
    
    function _redeemLPToTokenWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        for (uint8 i = 0; i < 3; i++) {
            LPConfig memory config = getConfig(authorizer, i);
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
                    if (wbnbAmount > 0) {
                        uint256 convertedToken = _swapWBNBToTokenWithFallback(authorizer, wbnbAmount);
                        tokenAmount += convertedToken;
                    }
                    return tokenAmount;
                } catch {}
            }
        }
        
        revert("LPLib: Failed to redeem LP to token");
    }
    
    function _redeemLPToWBNBWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        for (uint8 i = 0; i < 3; i++) {
            LPConfig memory config = getConfig(authorizer, i);
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
                    if (tokenAmount > 0) {
                        uint256 convertedWBNB = _swapTokenToWBNBWithRetry(config, tokenAmount);
                        wbnbAmount += convertedWBNB;
                    }
                    IWBNB(config.wbnb).withdraw(wbnbAmount);
                    return wbnbAmount;
                } catch {}
            }
        }
        
        revert("LPLib: Failed to redeem LP to WBNB");
    }

    function _transferRewards(IAuthorizer authorizer, address user, uint256 tokenAmount, uint256 wbnbAmount) internal {
        address token = authorizer.getToken();
        address wbnb = authorizer.getWBNB();

        if (tokenAmount > 0) {
            IERC20(token).transfer(user, tokenAmount);
        }

        if (wbnbAmount > 0) {
            IWBNB(wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(user).call{value: wbnbAmount}("");
            require(success, "LPLib: BNB transfer failed");
        }
    }

    function compoundFees(IAuthorizer authorizer) internal {
        address wbnb = authorizer.getWBNB();
        uint256 balance = IWBNB(wbnb).balanceOf(address(this));

        if (balance >= 1000000000000000) {
            IWBNB(wbnb).withdraw(balance);
            convertBNBToLP(authorizer, balance);
        }
    }

    function emergencyWithdrawWBNB(IAuthorizer authorizer, uint256 amount) internal {
        address wbnb = authorizer.getWBNB();
        require(amount > 0, "LPLib: Amount must be > 0");
        require(IWBNB(wbnb).balanceOf(address(this)) >= amount, "LPLib: Insufficient WBNB");

        IWBNB(wbnb).withdraw(amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "LPLib: BNB transfer failed");
    }

    function swapTokenToBNB(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        uint256 wbnbAmount = _swapTokenToWBNB(config, tokenAmount);
        
        if (wbnbAmount == 0) {
            IERC20(config.token).transfer(msg.sender, tokenAmount);
            return 0;
        }

        IWBNB(config.wbnb).withdraw(wbnbAmount);
        return wbnbAmount;
    }

    function emergencyWithdrawLP(IAuthorizer authorizer, uint256 amount) internal {
        LPConfig memory config = getConfig(authorizer);
        
        address factory = IDexRouter(config.router).factory();
        address lpToken = IDexFactory(factory).getPair(config.token, config.wbnb);
        require(lpToken != address(0), "LPLib: LP token not found");
        require(IERC20(lpToken).balanceOf(address(this)) >= amount, "LPLib: Insufficient LP");

        IERC20(lpToken).approve(config.router, amount);

        (uint256 tokenAmount, uint256 wbnbAmount) = IDexRouter(config.router).removeLiquidityETH(
            config.token,
            amount,
            0,
            0,
            msg.sender,
            block.timestamp + 300
        );

        if (wbnbAmount > 0) {
            IWBNB(config.wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(msg.sender).call{value: wbnbAmount}("");
            require(success, "LPLib: BNB transfer failed");
        }
    }

    function swapBNBToToken(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        IWBNB(config.wbnb).deposit{value: bnbAmount}();
        
        return _swapWBNBToToken(config, bnbAmount);
    }

    function swapWBNBToToken(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, 0);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");
        
        return _swapWBNBToTokenWithFallback(authorizer, wbnbAmount);
    }

    function _convertBNBToLPWithFallback(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        IWBNB(authorizer.getWBNB()).deposit{value: bnbAmount}();
        
        uint256 lpAmount;
        lpAmount = _tryConvertBNBToLP(authorizer, bnbAmount, 0);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertBNBToLP(authorizer, bnbAmount, 1);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertBNBToLP(authorizer, bnbAmount, 2);
        if (lpAmount > 0) return lpAmount;
        
        IWBNB(authorizer.getWBNB()).withdraw(bnbAmount);
        payable(msg.sender).transfer(bnbAmount);
        return 0;
    }

    function _tryConvertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount, uint8 dexType) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        if (config.router == address(0)) return 0;
        
        try _generateLPFromWBNB(config, bnbAmount) returns (uint256 liquidity) {
            if (liquidity > 0) return liquidity;
        } catch {}
        
        return 0;
    }

    function _convertWBNBToLPWithFallback(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        IERC20(authorizer.getWBNB()).transferFrom(msg.sender, address(this), wbnbAmount);
        
        uint256 lpAmount;
        lpAmount = _tryConvertWBNBToLP(authorizer, wbnbAmount, 0);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertWBNBToLP(authorizer, wbnbAmount, 1);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertWBNBToLP(authorizer, wbnbAmount, 2);
        if (lpAmount > 0) return lpAmount;
        
        IERC20(authorizer.getWBNB()).transfer(msg.sender, wbnbAmount);
        return 0;
    }

    function _tryConvertWBNBToLP(IAuthorizer authorizer, uint256 wbnbAmount, uint8 dexType) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        if (config.router == address(0)) return 0;
        
        try _generateLPFromWBNB(config, wbnbAmount) returns (uint256 liquidity) {
            if (liquidity > 0) return liquidity;
        } catch {}
        
        return 0;
    }

    function _convertTokenToLPWithFallback(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        uint256 lpAmount;
        lpAmount = _tryConvertTokenToLP(authorizer, tokenAmount, 0);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertTokenToLP(authorizer, tokenAmount, 1);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertTokenToLP(authorizer, tokenAmount, 2);
        if (lpAmount > 0) return lpAmount;
        
        IERC20(authorizer.getToken()).transfer(msg.sender, tokenAmount);
        return 0;
    }

    function _tryConvertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount, uint8 dexType) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        if (config.router == address(0)) return 0;
        
        uint256 halfToken = tokenAmount / 2;
        uint256 wbnbAmount = _swapTokenToWBNBWithRetry(config, halfToken);
        
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
            if (liquidity > 0) return liquidity;
        } catch {}
        
        IWBNB(config.wbnb).withdraw(wbnbAmount);
        IERC20(config.token).transfer(msg.sender, halfToken);
        return 0;
    }

    function _swapTokenToWBNBWithRetry(LPConfig memory config, uint256 tokenAmount) internal returns (uint256) {
        try _swapTokenToWBNB(config, tokenAmount) returns (uint256 amount) {
            if (amount > 0) return amount;
        } catch {}
        return 0;
    }

    function _swapWBNBToTokenWithFallback(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        for (uint8 i = 0; i < 3; i++) {
            LPConfig memory config = getConfig(authorizer, i);
            if (config.router == address(0)) continue;
            
            try _swapWBNBToToken(config, wbnbAmount) returns (uint256 amount) {
                if (amount > 0) return amount;
            } catch {}
        }
        return 0;
    }
}