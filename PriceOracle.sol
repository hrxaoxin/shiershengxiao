// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PriceOracle
 * @dev 价格预言机合约，从PancakeSwap获取代币的USD价格
 * 提供价格缓存、波动保护等安全机制
 */
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/access/Ownable.sol";

contract PriceOracle is Ownable {
    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev PancakeSwap流动性池地址（代币/稳定币对） */
    address public pancakeSwapPair;
    /** @dev WBNB合约地址 */
    address public wbnbAddress;
    /** @dev 稳定币合约地址（如USDT/USDC/BUSD） */
    address public stablecoinAddress;
    /** @dev 价格过期时间（秒）- 默认1小时 */
    uint256 public priceExpirySeconds = 3600;
    /** @dev 价格波动保护阈值（千分比，精度4位）- 默认50% */
    uint256 public priceDeviationThreshold = 5000;
    /** @dev 上次查询价格 */
    uint256 public lastPrice;
    /** @dev 上次价格更新时间戳 */
    uint256 public lastPriceUpdateTime;

    /** @dev 授权调用者映射（如UpgradeModule） */
    mapping(address => bool) public authorizedCaller;

    // ====================== Events ======================

    event PriceUpdated(uint256 price, uint256 timestamp);
    event TokenContractSet(address indexed tokenContract);
    event PancakeSwapPairSet(address indexed pair);
    event PriceParamsUpdated(uint256 expirySeconds, uint256 deviationThreshold);

    // ====================== Constructor ======================

    constructor() Ownable() {}

    // ====================== Price Query ======================

    /**
     * @dev 从PancakeSwap获取代币价格（USD）
     * @return uint256 代币价格（精度18位，如1.5 USD = 1500000000000000000）
     */
    function getTokenPriceFromPancakeSwap() public view returns (uint256) {
        require(pancakeSwapPair != address(0), "E24: PancakeSwap pair not set");

        IPancakeSwapPair pair = IPancakeSwapPair(pancakeSwapPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "E25: Insufficient liquidity");

        address token0 = pair.token0();
        address token1 = pair.token1();

        uint8 decimals0 = 18;
        uint8 decimals1 = 18;

        if (token0 == tokenContract) {
            try IBEP20(token1).decimals() returns (uint8 d) {
                decimals1 = d;
            } catch {}

            uint256 price = (uint256(reserve1) * 10**18) / uint256(reserve0);
            return adjustDecimals(price, 18, decimals1);
        } else if (token1 == tokenContract) {
            try IBEP20(token0).decimals() returns (uint8 d) {
                decimals0 = d;
            } catch {}

            uint256 price = (uint256(reserve0) * 10**18) / uint256(reserve1);
            return adjustDecimals(price, decimals0, 18);
        } else {
            revert("E26: Token not found in pair");
        }
    }

    /**
     * @dev 获取代币价格并更新缓存（包含波动保护检查）
     * 仅供授权合约调用（如UpgradeModule）
     * @return uint256 代币价格（精度18位）
     */
    function getAndUpdatePrice() external returns (uint256) {
        require(authorizedCaller[msg.sender] || msg.sender == owner(), "PriceOracle: Unauthorized");

        uint256 price = getTokenPriceFromPancakeSwap();
        require(price > 0, "E20: Price oracle returned zero");

        // 价格波动保护
        if (lastPrice > 0) {
            uint256 deviation;
            if (price > lastPrice) {
                deviation = ((price - lastPrice) * 10000) / lastPrice;
            } else {
                deviation = ((lastPrice - price) * 10000) / lastPrice;
            }
            require(deviation <= priceDeviationThreshold, "E23: Price deviation too high");
        }

        lastPrice = price;
        lastPriceUpdateTime = block.timestamp;
        emit PriceUpdated(price, block.timestamp);
        return price;
    }

    /**
     * @dev 调整小数位数
     * @param value 原始值
     * @param fromDecimals 原始小数位数
     * @param toDecimals 目标小数位数
     * @return uint256 调整后的值
     */
    function adjustDecimals(uint256 value, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return value;
        } else if (fromDecimals < toDecimals) {
            return value * 10**(toDecimals - fromDecimals);
        } else {
            return value / 10**(fromDecimals - toDecimals);
        }
    }

    // ====================== Config Setters ======================

    /**
     * @dev 设置代币合约地址
     */
    function setTokenContract(address a) external onlyOwner {
        require(a != address(0), "PriceOracle: Zero address");
        tokenContract = a;
        emit TokenContractSet(a);
    }

    /**
     * @dev 设置PancakeSwap流动性池地址
     */
    function setPancakeSwapPair(address pair) external onlyOwner {
        require(pair != address(0), "E27: Zero address");
        pancakeSwapPair = pair;
        emit PancakeSwapPairSet(pair);
    }

    /**
     * @dev 设置WBNB合约地址
     */
    function setWBNBAddress(address wbnb) external onlyOwner {
        wbnbAddress = wbnb;
    }

    /**
     * @dev 设置稳定币合约地址
     */
    function setStablecoinAddress(address stablecoin) external onlyOwner {
        stablecoinAddress = stablecoin;
    }

    /**
     * @dev 设置价格过期时间（秒）
     */
    function setPriceExpirySeconds(uint256 seconds_) external onlyOwner {
        require(seconds_ > 0, "PriceOracle: expiry must be > 0");
        priceExpirySeconds = seconds_;
        emit PriceParamsUpdated(seconds_, priceDeviationThreshold);
    }

    /**
     * @dev 设置价格波动保护阈值（千分比，如5000表示50%）
     */
    function setPriceDeviationThreshold(uint256 threshold) external onlyOwner {
        require(threshold <= 10000, "PriceOracle: threshold <= 10000");
        priceDeviationThreshold = threshold;
        emit PriceParamsUpdated(priceExpirySeconds, threshold);
    }

    /**
     * @dev 重置价格缓存
     */
    function resetPriceCache() external onlyOwner {
        lastPrice = 0;
        lastPriceUpdateTime = 0;
    }

    /**
     * @dev 授权调用者（如UpgradeModule合约）
     */
    function setAuthorizedCaller(address caller, bool ok) external onlyOwner {
        authorizedCaller[caller] = ok;
    }
}
