// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

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
contract PriceOracle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 价格历史记录结构体
     */
    struct PriceRecord {
        uint256 tokenPriceUSD;
        uint256 ethPriceUSD;
        uint256 timestamp;
        address updater;
    }

    /**
     * @dev 价格历史记录数组
     */
    PriceRecord[] public priceHistory;
    uint256 public priceHistoryStartIndex;

    /**
     * @dev 价格历史记录最大长度
     */
    uint256 public constant MAX_HISTORY_LENGTH = 100;

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
    bool public paused;
    string public pauseReason;
    
    event Paused(address account, string reason);
    event Unpaused(address account);
    
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }
    
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }
    
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }
    
    modifier whenNotPaused() {
        require(!paused, "PriceOracle: Paused");
        _;
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
     * @dev 代币价格更新时间（秒）
     */
    uint256 public tokenPriceUpdatedAt;

    /**
     * @dev ETH的USD价格（精度18位）
     *
     * 例如：$2000 = 2000 * 10^18
     */
    uint256 public ethPriceUSD;

    /**
     * @dev ETH价格更新时间（秒）
     */
    uint256 public ethPriceUpdatedAt;

    /**
     * @dev 价格有效时间（秒，默认24小时）
     */
    uint256 public priceValidityPeriod = 86400;

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

    uint256 public maxPriceChangePercent = 5000;
    uint256 public priceUpdateCooldown = 5 minutes;
    uint256 public lastTokenPriceUpdateTime;
    uint256 public lastETHPriceUpdateTime;
    uint256 public pendingTokenPrice;
    uint256 public pendingETHPrice;
    uint256 public pendingPriceEffectiveTime;
    bool public hasPendingTokenPrice;
    bool public hasPendingETHPrice;

    event PriceChangeProposed(uint256 oldPrice, uint256 newPrice, uint256 executeTime, address proposer);
    event PendingPriceCancelled(uint256 price, bool isTokenPrice);

    modifier onlyAfterCooldown(uint256 lastUpdateTime) {
        require(block.timestamp >= lastUpdateTime + priceUpdateCooldown, "PriceOracle: Price update cooldown");
        _;
    }

    function setPriceChangeLimit(uint256 percent) external onlyOwner {
        require(percent >= 1000 && percent <= 10000, "PriceOracle: Invalid percent");
        maxPriceChangePercent = percent;
    }

    function setPriceUpdateCooldown(uint256 cooldown) external onlyOwner {
        require(cooldown >= 1 minutes && cooldown <= 1 hours, "PriceOracle: Invalid cooldown");
        priceUpdateCooldown = cooldown;
    }

    function proposeTokenPrice(uint256 _newPrice) external onlyOwner whenNotPaused {
        require(_newPrice > 0, "PriceOracle: Invalid price");
        require(_newPrice <= 10**27, "PriceOracle: Price too high");
        require(block.timestamp >= lastTokenPriceUpdateTime + priceUpdateCooldown, "PriceOracle: Cooldown not elapsed");

        if (tokenPriceUSD > 0) {
            uint256 maxNewPrice = tokenPriceUSD * maxPriceChangePercent / 10000;
            uint256 minNewPrice = tokenPriceUSD * (10000 - maxPriceChangePercent) / 10000;
            require(_newPrice >= minNewPrice && _newPrice <= maxNewPrice, "PriceOracle: Price change too large");
        }

        pendingTokenPrice = _newPrice;
        hasPendingTokenPrice = true;
        pendingPriceEffectiveTime = block.timestamp + priceUpdateCooldown;

        emit PriceChangeProposed(tokenPriceUSD, _newPrice, pendingPriceEffectiveTime, msg.sender);
    }

    function executePendingTokenPrice() external onlyOwner {
        require(hasPendingTokenPrice, "PriceOracle: No pending price");
        require(block.timestamp >= pendingPriceEffectiveTime, "PriceOracle: Not yet executable");
        require(block.timestamp <= pendingPriceEffectiveTime + priceUpdateCooldown / 2, "PriceOracle: Pending price expired");

        uint256 oldPrice = tokenPriceUSD;
        tokenPriceUSD = pendingTokenPrice;
        lastTokenPriceUpdateTime = block.timestamp;
        hasPendingTokenPrice = false;

        emit PriceUpdated(tokenPriceUSD, ethPriceUSD, msg.sender);
    }

    function cancelPendingTokenPrice() external onlyOwner {
        require(hasPendingTokenPrice, "PriceOracle: No pending price to cancel");
        uint256 cancelledPrice = pendingTokenPrice;
        hasPendingTokenPrice = false;
        emit PendingPriceCancelled(cancelledPrice, true);
    }

    function proposeETHPrice(uint256 _newPrice) external onlyOwner whenNotPaused {
        require(_newPrice > 0, "PriceOracle: Invalid price");
        require(_newPrice <= 10**24, "PriceOracle: Price too high");
        require(block.timestamp >= lastETHPriceUpdateTime + priceUpdateCooldown, "PriceOracle: Cooldown not elapsed");

        if (ethPriceUSD > 0) {
            uint256 maxNewPrice = ethPriceUSD * maxPriceChangePercent / 10000;
            uint256 minNewPrice = ethPriceUSD * (10000 - maxPriceChangePercent) / 10000;
            require(_newPrice >= minNewPrice && _newPrice <= maxNewPrice, "PriceOracle: Price change too large");
        }

        pendingETHPrice = _newPrice;
        hasPendingETHPrice = true;
        pendingPriceEffectiveTime = block.timestamp + priceUpdateCooldown;

        emit PriceChangeProposed(ethPriceUSD, _newPrice, pendingPriceEffectiveTime, msg.sender);
    }

    function executePendingETHPrice() external onlyOwner {
        require(hasPendingETHPrice, "PriceOracle: No pending price");
        require(block.timestamp >= pendingPriceEffectiveTime, "PriceOracle: Not yet executable");
        require(block.timestamp <= pendingPriceEffectiveTime + priceUpdateCooldown / 2, "PriceOracle: Pending price expired");

        uint256 oldPrice = ethPriceUSD;
        ethPriceUSD = pendingETHPrice;
        lastETHPriceUpdateTime = block.timestamp;
        hasPendingETHPrice = false;

        emit PriceUpdated(tokenPriceUSD, ethPriceUSD, msg.sender);
    }

    function cancelPendingETHPrice() external onlyOwner {
        require(hasPendingETHPrice, "PriceOracle: No pending price to cancel");
        uint256 cancelledPrice = pendingETHPrice;
        hasPendingETHPrice = false;
        emit PendingPriceCancelled(cancelledPrice, false);
    }

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
    function updateTokenPrice(uint256 _tokenPriceUSD) external onlyAuthorized whenNotPaused {
        require(_tokenPriceUSD > 0, "PriceOracle: Invalid token price");
        require(_tokenPriceUSD <= 10**27, "PriceOracle: Token price too high");
        tokenPriceUSD = _tokenPriceUSD;
        tokenPriceUpdatedAt = block.timestamp;
        emit PriceUpdated(_tokenPriceUSD, ethPriceUSD, msg.sender);
    }

    /**
     * @dev 更新ETH价格
     *
     * @param _ethPriceUSD 新的ETH价格（USD，精度18位）
     */
    function updateETHPrice(uint256 _ethPriceUSD) external onlyAuthorized whenNotPaused {
        require(_ethPriceUSD > 0, "PriceOracle: Invalid ETH price");
        require(_ethPriceUSD <= 10**24, "PriceOracle: ETH price too high");
        ethPriceUSD = _ethPriceUSD;
        ethPriceUpdatedAt = block.timestamp;
        emit PriceUpdated(tokenPriceUSD, _ethPriceUSD, msg.sender);
    }

    /**
     * @dev 批量更新价格
     *
     * @param _tokenPriceUSD 代币价格
     * @param _ethPriceUSD ETH价格
     */
    function updatePrices(uint256 _tokenPriceUSD, uint256 _ethPriceUSD) external onlyOwner whenNotPaused {
        require(_tokenPriceUSD > 0, "PriceOracle: Invalid token price");
        require(_ethPriceUSD > 0, "PriceOracle: Invalid ETH price");
        require(_tokenPriceUSD <= 10**27, "PriceOracle: Token price too high");
        require(_ethPriceUSD <= 10**24, "PriceOracle: ETH price too high");

        require(block.timestamp >= lastTokenPriceUpdateTime + PRICE_UPDATE_COOLDOWN, "PriceOracle: Token price update cooldown");
        require(block.timestamp >= lastETHPriceUpdateTime + PRICE_UPDATE_COOLDOWN, "PriceOracle: ETH price update cooldown");

        if (tokenPriceUSD > 0) {
            uint256 maxTokenNewPrice = tokenPriceUSD * MAX_PRICE_CHANGE_PERCENT / 10000;
            uint256 minTokenNewPrice = tokenPriceUSD * (10000 - MAX_PRICE_CHANGE_PERCENT) / 10000;
            require(_tokenPriceUSD >= minTokenNewPrice && _tokenPriceUSD <= maxTokenNewPrice, "PriceOracle: Token price change too large");
        }

        if (ethPriceUSD > 0) {
            uint256 maxETHNewPrice = ethPriceUSD * MAX_PRICE_CHANGE_PERCENT / 10000;
            uint256 minETHNewPrice = ethPriceUSD * (10000 - MAX_PRICE_CHANGE_PERCENT) / 10000;
            require(_ethPriceUSD >= minETHNewPrice && _ethPriceUSD <= maxETHNewPrice, "PriceOracle: ETH price change too large");
        }

        tokenPriceUSD = _tokenPriceUSD;
        ethPriceUSD = _ethPriceUSD;
        tokenPriceUpdatedAt = block.timestamp;
        ethPriceUpdatedAt = block.timestamp;
        lastTokenPriceUpdateTime = block.timestamp;
        lastETHPriceUpdateTime = block.timestamp;
        
        // 记录价格历史（使用环形缓冲区）
        if (priceHistory.length < MAX_HISTORY_LENGTH) {
            priceHistory.push(PriceRecord({
                tokenPriceUSD: _tokenPriceUSD,
                ethPriceUSD: _ethPriceUSD,
                timestamp: block.timestamp,
                updater: msg.sender
            }));
        } else {
            priceHistory[priceHistoryStartIndex] = PriceRecord({
                tokenPriceUSD: _tokenPriceUSD,
                ethPriceUSD: _ethPriceUSD,
                timestamp: block.timestamp,
                updater: msg.sender
            });
            priceHistoryStartIndex = (priceHistoryStartIndex + 1) % MAX_HISTORY_LENGTH;
        }
        
        emit PriceUpdated(_tokenPriceUSD, _ethPriceUSD, msg.sender);
    }

    /**
     * @dev 获取价格历史记录长度
     */
    function getPriceHistoryLength() external view returns (uint256) {
        return priceHistory.length;
    }

    /**
     * @dev 获取价格历史记录（分页，支持环形缓冲区）
     */
    function getPriceHistory(uint256 startIndex, uint256 count) external view returns (PriceRecord[] memory) {
        require(startIndex < priceHistory.length, "PriceOracle: Invalid start index");
        require(count > 0, "PriceOracle: Invalid count");
        
        uint256 endIndex = startIndex + count;
        if (endIndex > priceHistory.length) {
            endIndex = priceHistory.length;
        }
        
        PriceRecord[] memory records = new PriceRecord[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 actualIndex = (priceHistoryStartIndex + i) % priceHistory.length;
            records[i - startIndex] = priceHistory[actualIndex];
        }
        
        return records;
    }

    /**
     * @dev 获取最新价格记录
     */
    function getLatestPriceRecord() external view returns (PriceRecord memory) {
        require(priceHistory.length > 0, "PriceOracle: No history");
        uint256 latestIndex = (priceHistoryStartIndex + priceHistory.length - 1) % priceHistory.length;
        return priceHistory[latestIndex];
    }

    /**
     * @dev 获取最近N条价格记录（简化接口，无需理解环形缓冲区）
     * @param count 要获取的记录数量
     * @return PriceRecord[] 价格记录数组（最新的在前）
     */
    function getLastNPrices(uint256 count) external view returns (PriceRecord[] memory) {
        require(count > 0, "PriceOracle: Invalid count");
        
        uint256 actualCount = count;
        if (actualCount > priceHistory.length) {
            actualCount = priceHistory.length;
        }
        
        PriceRecord[] memory records = new PriceRecord[](actualCount);
        uint256 latestIndex = (priceHistoryStartIndex + priceHistory.length - 1) % priceHistory.length;
        
        for (uint256 i = 0; i < actualCount; i++) {
            uint256 historyIndex = (latestIndex + priceHistory.length - i) % priceHistory.length;
            records[i] = priceHistory[historyIndex];
        }
        
        return records;
    }

    /**
     * @dev 设置价格有效时间
     *
     * @param duration 有效时间（秒）
     */
    function setPriceValidityPeriod(uint256 duration) external onlyOwner {
        priceValidityPeriod = duration;
    }

    /**
     * @dev 检查代币价格是否过期
     *
     * @return bool 价格是否有效
     */
    function isTokenPriceValid() public view returns (bool) {
        return tokenPriceUSD > 0 && (block.timestamp - tokenPriceUpdatedAt) <= priceValidityPeriod;
    }

    /**
     * @dev 检查ETH价格是否过期
     *
     * @return bool 价格是否有效
     */
    function isETHPriceValid() public view returns (bool) {
        return ethPriceUSD > 0 && (block.timestamp - ethPriceUpdatedAt) <= priceValidityPeriod;
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
        // 使用先除后乘策略减少精度损失
        uint256 tokenAmountScaled = tokenAmount / 10**12;
        uint256 priceScaled = tokenPriceUSD / 10**6;
        return tokenAmountScaled * priceScaled;
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
        // 安全计算：先除后乘，避免溢出
        uint256 usdtInWei = usdtAmount * 10**12;
        return (usdtInWei * 10**18) / tokenPriceUSD;
    }

    /**
     * @dev 计算ETH的USDT等值
     *
     * @param ethAmount ETH数量（精度18位）
     * @return uint256 USDT数量（精度6位）
     */
    function calculateETHUSDTEquivalent(uint256 ethAmount) external view returns (uint256) {
        if (ethPriceUSD == 0 || ethAmount == 0) return 0;
        return (ethAmount * ethPriceUSD) / (10**30);
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
     * @dev 验证价格是否有效（未过期且非零）
     *
     * @return bool 价格是否有效
     */
    function isPriceValid() external view returns (bool) {
        return isTokenPriceValid() && isETHPriceValid();
    }
}
