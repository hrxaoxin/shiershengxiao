// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

library DividendManagerLPLib {
    using SafeERC20 for IERC20;

    struct LPConfig {
        address token;
        address wbnb;
        address router;
        uint256 slippage;
        address lpToken;
    }

    error DML_MissingConfig();
    error DML_BNBTransferFailed();
    error DML_RedeemLPFailed();
    error DML_RedeemLPToTokenFailed();
    error DML_RedeemLPToWBNBFailed();
    error DML_RouterNotSet();
    error DML_LPTokenNotFound();

    function getConfig(IAuthorizer authorizer, uint8 dexType) private view returns (LPConfig memory) {
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
        return _convertBNBToLPWithFallback(authorizer, bnbAmount);
    }

    function _convertBNBToLPWithFallback(IAuthorizer authorizer, uint256 bnbAmount) private returns (uint256) {
        IWBNB(authorizer.getAddressByName("wbnb")).deposit{value: bnbAmount}();
        
        uint256 lpAmount;
        lpAmount = _tryConvertBNBToLP(authorizer, bnbAmount, 0);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertBNBToLP(authorizer, bnbAmount, 1);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertBNBToLP(authorizer, bnbAmount, 2);
        if (lpAmount > 0) return lpAmount;
        
        IWBNB(authorizer.getAddressByName("wbnb")).withdraw(bnbAmount);
        (bool success, ) = payable(msg.sender).call{value: bnbAmount}("");
        if (!success) revert DML_BNBTransferFailed();
        return 0;
    }

    function _tryConvertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount, uint8 dexType) private returns (uint256) {
        LPConfig memory config = getConfig(authorizer, dexType);
        if (config.router == address(0)) return 0;
        
        uint256 liquidity = _generateLPFromWBNB(config, bnbAmount);
        if (liquidity > 0) return liquidity;
        
        return 0;
    }

    function _generateLPFromWBNB(LPConfig memory config, uint256 wbnbAmount) private returns (uint256) {
        uint256 halfWBNB = wbnbAmount / 2;
        uint256 tokenAmount = _swapWBNBToToken(config, halfWBNB);

        if (tokenAmount == 0) {
            IWBNB(config.wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(msg.sender).call{value: wbnbAmount}("");
            if (!success) revert DML_BNBTransferFailed();
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
            (bool success, ) = payable(msg.sender).call{value: wbnbAmount - halfWBNB}("");
            if (!success) revert DML_BNBTransferFailed();
            IERC20(config.token).safeTransfer(msg.sender, tokenAmount);
            return 0;
        }
    }

    function _swapWBNBToToken(LPConfig memory config, uint256 wbnbAmount) private returns (uint256) {
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

    function swapBNBToToken(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, 0);
        if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) {
            revert DML_MissingConfig();
        }

        IWBNB(config.wbnb).deposit{value: bnbAmount}();
        
        return _swapWBNBToTokenWithFallback(authorizer, bnbAmount);
    }

    function swapWBNBToToken(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, 0);
        if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) {
            revert DML_MissingConfig();
        }
        
        return _swapWBNBToTokenWithFallback(authorizer, wbnbAmount);
    }

    function _swapWBNBToTokenWithFallback(IAuthorizer authorizer, uint256 wbnbAmount) private returns (uint256) {
        for (uint8 i = 0; i < 3; i++) {
            LPConfig memory config = getConfig(authorizer, i);
            if (config.router == address(0)) continue;
            
            uint256 amount = _swapWBNBToToken(config, wbnbAmount);
            if (amount > 0) return amount;
        }
        return 0;
    }

    function convertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        return _convertTokenToLPWithFallback(authorizer, tokenAmount);
    }

    function _convertTokenToLPWithFallback(IAuthorizer authorizer, uint256 tokenAmount) private returns (uint256) {
        uint256 lpAmount;
        lpAmount = _tryConvertTokenToLP(authorizer, tokenAmount, 0);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertTokenToLP(authorizer, tokenAmount, 1);
        if (lpAmount > 0) return lpAmount;
        
        lpAmount = _tryConvertTokenToLP(authorizer, tokenAmount, 2);
        if (lpAmount > 0) return lpAmount;
        
        IERC20(authorizer.getAddressByName("token")).safeTransfer(msg.sender, tokenAmount);
        return 0;
    }

    function _tryConvertTokenToLP(IAuthorizer authorizer, uint256 tokenAmount, uint8 dexType) private returns (uint256) {
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
        IERC20(config.token).safeTransfer(msg.sender, halfToken);
        return 0;
    }

    function _swapTokenToWBNBWithRetry(LPConfig memory config, uint256 tokenAmount) private returns (uint256) {
        uint256 amount = _swapTokenToWBNB(config, tokenAmount);
        if (amount > 0) return amount;
        return 0;
    }

    function _swapTokenToWBNB(LPConfig memory config, uint256 tokenAmount) private returns (uint256) {
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

    function swapTokenToBNB(IAuthorizer authorizer, uint256 tokenAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer, 0);
        if (config.token == address(0) || config.wbnb == address(0) || config.router == address(0)) {
            revert DML_MissingConfig();
        }

        uint256 wbnbAmount = _swapTokenToWBNBWithRetry(config, tokenAmount);
        
        if (wbnbAmount == 0) {
            IERC20(config.token).safeTransfer(msg.sender, tokenAmount);
            return 0;
        }

        IWBNB(config.wbnb).withdraw(wbnbAmount);
        return wbnbAmount;
    }

    function redeemLPToToken(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        return _redeemLPToTokenWithAutoDetect(authorizer, lpAmount);
    }

    function _redeemLPToTokenWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) private returns (uint256) {
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
        
        revert DML_RedeemLPToTokenFailed();
    }

    function redeemLPToWBNB(IAuthorizer authorizer, uint256 lpAmount) internal returns (uint256) {
        return _redeemLPToWBNBWithAutoDetect(authorizer, lpAmount);
    }

    function _redeemLPToWBNBWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) private returns (uint256) {
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
        
        revert DML_RedeemLPToWBNBFailed();
    }

    function redeemLP(IAuthorizer authorizer, uint256 lpAmount) private returns (uint256, uint256) {
        return _redeemLPWithAutoDetect(authorizer, lpAmount);
    }

    function _redeemLPWithAutoDetect(IAuthorizer authorizer, uint256 lpAmount) private returns (uint256, uint256) {
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
        
        revert DML_RedeemLPFailed();
    }

    function redeemLPToUser(IAuthorizer authorizer, uint256 lpAmount, address user) internal {
        (uint256 tokenAmount, uint256 wbnbAmount) = redeemLP(authorizer, lpAmount);
        _transferRewards(authorizer, user, tokenAmount, wbnbAmount);
    }

    function _transferRewards(IAuthorizer authorizer, address user, uint256 tokenAmount, uint256 wbnbAmount) private {
        address token = authorizer.getAddressByName("token");
        address wbnb = authorizer.getAddressByName("wbnb");

        if (tokenAmount > 0) {
            IERC20(token).safeTransfer(user, tokenAmount);
        }

        if (wbnbAmount > 0) {
            IWBNB(wbnb).withdraw(wbnbAmount);
            (bool success, ) = payable(user).call{value: wbnbAmount}("");
            if (!success) revert DML_BNBTransferFailed();
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
}
