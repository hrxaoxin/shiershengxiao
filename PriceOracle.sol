// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title PriceOracle
 * @dev 价格预言机合约，提供代币和ETH的USD价格查询
 *
 * 功能：
 * 1. 获取代币的USD价格
 * 2. 获取ETH的USD价格
 * 3. 计算代币与USDT的兑换比例
 *
 * 价格精度：
 * - 所有价格使用18位精度
 * - USDT使用6位精度
 * - 代币使用18位精度
 *
 * 用途：
 * - 升级费用计算（代币 → USDT）
 * - 铸造费用验证
 * - NFT定价参考
 */
contract PriceOracle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 代币地址
     */
    address public tokenAddress;

    /**
     * @dev USDT代币地址
     */
    address public usdtAddress;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "PriceOracle: Not authorized");
        _;
    }

    /**
     * @dev 代币的USD价格（精度18位）
     *
     * 例如：$0.1 = 0.1 * 10^18
     */
    uint256 public tokenPriceUSD;

    /**
     * @dev ETH的USD价格（精度18位）
     *
     * 例如：$2000 = 2000 * 10^18
     */
    uint256 public ethPriceUSD;

    /**
     * @dev 代币精度
     */
    uint256 public constant TOKEN_PRECISION = 10**18;

    /**
     * @dev USDT精度
     */
    uint256 public constant USDT_PRECISION = 10**6;

    /**
     * @dev 价格更新事件
     *
     * @param tokenPrice 新的代币价格
     * @param ethPrice 新的ETH价格
     * @param updater 更新者地址
     */
    event PriceUpdated(uint256 tokenPrice, uint256 ethPrice, address updater);

    /**
     * @dev 设置代币地址
     *
     * @param _tokenAddress 代币合约地址
     */
    function setTokenAddress(address _tokenAddress) external onlyAuthorized {
        require(_tokenAddress != address(0), "PriceOracle: Invalid token address");
        tokenAddress = _tokenAddress;
    }

    /**
     * @dev 设置USDT地址
     *
     * @param _usdtAddress USDT代币合约地址
     */
    function setUSDTAddress(address _usdtAddress) external onlyAuthorized {
        require(_usdtAddress != address(0), "PriceOracle: Invalid USDT address");
        usdtAddress = _usdtAddress;
    }

    /**
     * @dev 更新代币价格
     *
     * @param _tokenPriceUSD 新的代币价格（USD，精度18位）
     */
    function updateTokenPrice(uint256 _tokenPriceUSD) external onlyOwner {
        require(_tokenPriceUSD > 0, "PriceOracle: Invalid token price");
        tokenPriceUSD = _tokenPriceUSD;
        emit PriceUpdated(_tokenPriceUSD, ethPriceUSD, msg.sender);
    }

    /**
     * @dev 更新ETH价格
     *
     * @param _ethPriceUSD 新的ETH价格（USD，精度18位）
     */
    function updateETHPrice(uint256 _ethPriceUSD) external onlyOwner {
        require(_ethPriceUSD > 0, "PriceOracle: Invalid ETH price");
        ethPriceUSD = _ethPriceUSD;
        emit PriceUpdated(tokenPriceUSD, _ethPriceUSD, msg.sender);
    }

    /**
     * @dev 批量更新价格
     *
     * @param _tokenPriceUSD 代币价格
     * @param _ethPriceUSD ETH价格
     */
    function updatePrices(uint256 _tokenPriceUSD, uint256 _ethPriceUSD) external onlyOwner {
        require(_tokenPriceUSD > 0, "PriceOracle: Invalid token price");
        require(_ethPriceUSD > 0, "PriceOracle: Invalid ETH price");
        tokenPriceUSD = _tokenPriceUSD;
        ethPriceUSD = _ethPriceUSD;
        emit PriceUpdated(_tokenPriceUSD, _ethPriceUSD, msg.sender);
    }

    /**
     * @dev 获取代币价格
     *
     * @return uint256 代币价格（USD，精度18位）
     */
    function getTokenPrice() external view returns (uint256) {
        return tokenPriceUSD;
    }

    /**
     * @dev 获取ETH价格
     *
     * @return uint256 ETH价格（USD，精度18位）
     */
    function getETHPrice() external view returns (uint256) {
        return ethPriceUSD;
    }

    /**
     * @dev 计算代币的USDT等值
     *
     * 将代币数量转换为USDT数量
     *
     * @param tokenAmount 代币数量（精度18位）
     * @return uint256 USDT数量（精度6位）
     *
     * 计算公式：
     * usdtAmount = tokenAmount * tokenPriceUSD / (1 USD) / TOKEN_PRECISION * USDT_PRECISION
     *
     * 例如：
     * tokenAmount = 10000 * 10^18 (10000代币)
     * tokenPriceUSD = 0.1 * 10^18 ($0.1)
     * usdtAmount = 10000 * 0.1 = 1000 USDT
     */
    function calculateUSDTEquivalent(uint256 tokenAmount) external view returns (uint256) {
        if (tokenPriceUSD == 0 || tokenAmount == 0) return 0;
        return tokenAmount * tokenPriceUSD / TOKEN_PRECISION * USDT_PRECISION / (1 * TOKEN_PRECISION);
    }

    /**
     * @dev 计算USDT的代币等值
     *
     * 将USDT数量转换为代币数量
     *
     * @param usdtAmount USDT数量（精度6位）
     * @return uint256 代币数量（精度18位）
     *
     * 计算公式：
     * tokenAmount = usdtAmount * (1 USD) / tokenPriceUSD / USDT_PRECISION * TOKEN_PRECISION
     *
     * 例如：
     * usdtAmount = 1000 * 10^6 (1000 USDT)
     * tokenPriceUSD = 0.1 * 10^18 ($0.1)
     * tokenAmount = 1000 / 0.1 = 10000 代币
     */
    function calculateTokenEquivalent(uint256 usdtAmount) external view returns (uint256) {
        if (tokenPriceUSD == 0 || usdtAmount == 0) return 0;
        return usdtAmount * (1 * TOKEN_PRECISION) / tokenPriceUSD / USDT_PRECISION * TOKEN_PRECISION;
    }

    /**
     * @dev 计算ETH的USDT等值
     *
     * @param ethAmount ETH数量（精度18位）
     * @return uint256 USDT数量（精度6位）
     */
    function calculateETHUSDTEquivalent(uint256 ethAmount) external view returns (uint256) {
        if (ethPriceUSD == 0 || ethAmount == 0) return 0;
        return ethAmount * ethPriceUSD / TOKEN_PRECISION * USDT_PRECISION / (1 * TOKEN_PRECISION);
    }

    /**
     * @dev 获取精度信息
     *
     * @return uint256 代币精度
     * @return uint256 USDT精度
     */
    function getPrecisionInfo() external pure returns (uint256, uint256) {
        return (TOKEN_PRECISION, USDT_PRECISION);
    }

    /**
     * @dev 验证价格是否有效
     *
     * @return bool 价格是否有效（非零）
     */
    function isPriceValid() external view returns (bool) {
        return tokenPriceUSD > 0 && ethPriceUSD > 0;
    }
}
