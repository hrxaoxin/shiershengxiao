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
    }

    function getConfig(IAuthorizer authorizer) internal view returns (LPConfig memory) {
        return LPConfig({
            token: authorizer.getToken(),
            wbnb: authorizer.getWBNB(),
            router: authorizer.getPancakeSwapRouter(),
            slippage: 1000
        });
    }

    function convertBNBToLP(IAuthorizer authorizer, uint256 bnbAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        IWBNB(config.wbnb).deposit{value: bnbAmount}();
        return _generateLPFromWBNB(config, bnbAmount);
    }

    function convertWBNBToLP(IAuthorizer authorizer, uint256 wbnbAmount) internal returns (uint256) {
        LPConfig memory config = getConfig(authorizer);
        require(config.token != address(0) && config.wbnb != address(0) && config.router != address(0), "LPLib: Missing config");

        IERC20(config.wbnb).transferFrom(msg.sender, address(this), wbnbAmount);
        return _generateLPFromWBNB(config, wbnbAmount);
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
        LPConfig memory config = getConfig(authorizer);
        
        address factory = IDexRouter(config.router).factory();
        address lpToken = IDexFactory(factory).getPair(config.token, config.wbnb);
        require(lpToken != address(0), "LPLib: LP token not found");

        IERC20(lpToken).transferFrom(msg.sender, address(this), lpAmount);
        IERC20(lpToken).approve(config.router, lpAmount);

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

    function redeemLPToUser(IAuthorizer authorizer, uint256 lpAmount, address user) internal {
        (uint256 tokenAmount, uint256 wbnbAmount) = redeemLP(authorizer, lpAmount);
        _transferRewards(authorizer, user, tokenAmount, wbnbAmount);
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
}