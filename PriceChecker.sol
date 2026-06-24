// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

contract PriceChecker {
    address public constant PANCAKE_SWAP_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    /**
     * @dev 使用PancakeSwap Router获取代币价格
     * @param token 代币地址
     * @return tokenPriceUSD 代币价格（USD，精度18位）
     */
    function getTokenPrice(address token) external view returns (uint256 tokenPriceUSD) {
        if (token == address(0) || token == WBNB) {
            return 0;
        }

        // 尝试路径：代币 -> WBNB -> USDT
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = WBNB;
        path[2] = USDT;

        try IDexRouter(PANCAKE_SWAP_ROUTER).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 3 && amounts[2] > 0) {
                return amounts[2] * 10**12;
            }
        } catch {}

        // 备用：尝试直接路径 代币 -> USDT
        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = USDT;

        try IDexRouter(PANCAKE_SWAP_ROUTER).getAmountsOut(10**18, directPath) returns (uint256[] memory amounts) {
            if (amounts.length == 2 && amounts[1] > 0) {
                return amounts[1] * 10**12;
            }
        } catch {}

        return 0;
    }

    /**
     * @dev 获取WBNB价格
     * @return wbnbPriceUSD WBNB价格（USD，精度18位）
     */
    function getWbnbPrice() external view returns (uint256 wbnbPriceUSD) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = USDT;

        try IDexRouter(PANCAKE_SWAP_ROUTER).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 2 && amounts[1] > 0) {
                return amounts[1] * 10**12;
            }
        } catch {}

        return 0;
    }

    /**
     * @dev 检查Pair储备
     * @param pair Pair地址
     * @return reserve0 储备0
     * @return reserve1 储备1
     */
    function checkPairReserves(address pair) external view returns (uint112 reserve0, uint112 reserve1) {
        try IPancakeSwapPair(pair).getReserves() returns (uint112 r0, uint112 r1, uint32) {
            return (r0, r1);
        } catch {
            return (0, 0);
        }
    }
}