// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PriceLibrary
 * @dev 价格获取相关的工具库，用于从DEX获取代币价格
 * @notice 支持FlapSwap、PancakeSwap、Uniswap
 */
library PriceLibrary {
    
    /// @dev DEX类型枚举
    enum DEXType { FlapSwap, PancakeSwap, Uniswap }
    
    /// @dev Pair信息结构
    struct PairInfo {
        address tokenWbnbPair;    // 代币-WBNB Pair地址
        address wbnbUsdtPair;     // WBNB-USDT Pair地址
        address token;            // 代币地址
        address wbnb;             // WBNB地址
        address usdt;             // USDT地址
    }
    
    /**
     * @dev 从Pair储备计算代币价格
     * @param pair 代币-WBNB Pair地址
     * @param wbnbUsdtPair WBNB-USDT Pair地址
     * @param token 代币地址
     * @param wbnb WBNB地址
     * @param usdt USDT地址
     * @return 代币价格（USD，精度18位），获取失败返回0
     */
    function getPriceFromPairs(
        address pair,
        address wbnbUsdtPair,
        address token,
        address wbnb,
        address usdt
    ) internal view returns (uint256) {
        if (pair == address(0) || token == address(0) || wbnb == address(0) || usdt == address(0)) {
            return 0;
        }
        
        // 获取代币-WBNB储备
        (uint112 tokenReserve0, uint112 wbnbReserve0, ) = getReserves(pair);
        if (tokenReserve0 == 0 || wbnbReserve0 == 0) {
            return 0;
        }
        
        address token0 = IPancakeSwapPair(pair).token0();
        uint256 tokenReserve = token0 == token ? uint256(tokenReserve0) : uint256(wbnbReserve0);
        uint256 wbnbReserve = token0 == token ? uint256(wbnbReserve0) : uint256(tokenReserve0);
        
        // 获取WBNB-USDT价格
        uint256 usdtPrice = getWbnbUsdtPriceFromPair(wbnbUsdtPair, wbnb, usdt);
        if (usdtPrice == 0) {
            return 0;
        }
        
        // 计算：1 token = (wbnbReserve / tokenReserve) * usdtPrice USD
        uint256 wbnbPerToken = (wbnbReserve * 1e18) / tokenReserve;
        uint256 tokenPrice = (wbnbPerToken * usdtPrice) / 1e18;
        return tokenPrice * 10**12;
    }
    
    /**
     * @dev 从Pair储备获取WBNB-USDT价格
     * @param pair WBNB-USDT Pair地址
     * @param wbnb WBNB地址
     * @param usdt USDT地址
     * @return WBNB价格（USD，精度18位）
     */
    function getWbnbUsdtPriceFromPair(address pair, address wbnb, address usdt) internal view returns (uint256) {
        if (pair == address(0) || wbnb == address(0) || usdt == address(0)) {
            return 0;
        }
        
        (uint112 reserve0, uint112 reserve1, ) = getReserves(pair);
        if (reserve0 == 0 || reserve1 == 0) {
            return 0;
        }
        
        address token0 = IPancakeSwapPair(pair).token0();
        uint256 wbnbReserve = token0 == wbnb ? uint256(reserve0) : uint256(reserve1);
        uint256 usdtReserve = token0 == wbnb ? uint256(reserve1) : uint256(reserve0);
        
        // usdtReserve 是6位精度
        return (usdtReserve * 1e18) / wbnbReserve;
    }
    
    /**
     * @dev 安全获取Pair储备（处理异常）
     * @param pair Pair地址
     * @return reserve0 储备0
     * @return reserve1 储备1
     */
    function getReserves(address pair) internal view returns (uint112, uint112, ) {
        try IPancakeSwapPair(pair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
            return (reserve0, reserve1, blockTimestampLast);
        } catch {
            return (0, 0, 0);
        }
    }
    
    /**
     * @dev 通过Router获取代币价格
     * @param router Router地址
     * @param token 代币地址
     * @param wbnb WBNB地址
     * @param usdt USDT地址
     * @return 代币价格（USD，精度18位）
     */
    function getPriceFromRouter(address router, address token, address wbnb, address usdt) internal view returns (uint256) {
        if (router == address(0) || token == address(0) || wbnb == address(0) || usdt == address(0)) {
            return 0;
        }
        
        // 路径：代币 -> WBNB -> USDT
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = wbnb;
        path[2] = usdt;
        
        try IDexRouter(router).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 3 && amounts[2] > 0) {
                // amounts[2] 是 USDT 数量（6位精度）
                // 转换为 USD 价格（18位精度）
                return amounts[2] * 10**12;
            }
        } catch {}
        
        // 备用：尝试直接路径 代币 -> USDT
        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = usdt;
        
        try IDexRouter(router).getAmountsOut(10**18, directPath) returns (uint256[] memory amounts) {
            if (amounts.length == 2 && amounts[1] > 0) {
                return amounts[1] * 10**12;
            }
        } catch {}
        
        return 0;
    }
    
    /**
     * @dev 通过Router获取ETH价格
     * @param router Router地址
     * @param wbnb WBNB地址
     * @param usdt USDT地址
     * @return ETH价格（USD，精度18位）
     */
    function getETHPriceFromRouter(address router, address wbnb, address usdt) internal view returns (uint256) {
        if (router == address(0) || wbnb == address(0) || usdt == address(0)) {
            return 0;
        }
        
        // 路径：WBNB -> USDT
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = usdt;
        
        try IDexRouter(router).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 2 && amounts[1] > 0) {
                // amounts[1] 是 USDT 数量（6位精度）
                // 转换为 USD 价格（18位精度）
                return amounts[1] * 10**12;
            }
        } catch {}
        
        return 0;
    }
}

/**
 * @dev PancakeSwap Pair接口
 */
interface IPancakeSwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

/**
 * @dev DEX Router接口
 */
interface IDexRouter {
    function factory() external view returns (address);
    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts);
}
