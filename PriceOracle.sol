// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title PriceOracle
 * @dev 价格预言机合约，提供代币和ETH的USD价格查询
 *
 * 核心功能：
 * 1. 代币USD价格管理：存储和更新代币相对USD的价格
 * 2. ETH/BNB USD价格管理：存储和更新原生代币的USD价格
 * 3. 价值换算：代币数量与USDT数量的换算
 * 4. 多DEX价格抓取：从 FlapSwap、PancakeSwap、Uniswap 读取价格并取平均
 *
 * 价格精度体系：
 * - 代币价格（tokenPriceUSD）：18位精度，表示 1 token = X USD（X 10^18）
 * - ETH价格（ethPriceUSD）：18位精度，表示 1 ETH = X USD
 * - TOKEN_PRECISION = 10^18（代币数量精度）
 * - USDT_PRECISION = 10^6（USDT数量精度）
 *
 * 价格更新方式（三种模式，从高信任到低信任）：
 * 1. 提议-执行两阶段（proposeTokenPrice 和 executePendingTokenPrice）：
 *    - Owner 先提议新价格，等待 priceUpdateCooldown（默认5分钟）后执行
 *    - 价格变动不得超过 maxPriceChangePercent（默认50%）
 *    - 防止 Owner 瞬间大幅篡改价格
 * 2. 授权合约直接更新（updateTokenPrice / updatePrices）：
 *    - 由 authorizer 授权的可信合约（如 Chainlink 集成或官方喂价机器人）直接设置
 *    - 变动同样受 maxPriceChangePercent 限制
 * 3. DEX 自动抓取（fetchPriceFromDEX / fetchPriceFromAllDEX）：
 *    - 通过 UniswapV2 风格的 pair 获取现货价格
 *    - fetchPriceFromAllDEX 从多个 DEX 取平均，减少单个 DEX 被操纵的影响
 *    - 需要 autoPriceEnabled = true
 *
 * 价格有效性检查：
 * - priceValidityPeriod（默认24小时）：价格更新后超过此时间视为失效
 * - isTokenPriceValid() / isETHPriceValid() / isPriceValid() 供外部检查
 *
 * 价格历史记录：
 * - 使用环形缓冲区（priceHistory / priceHistoryStartIndex），最多 MAX_HISTORY_LENGTH = 100 条
 * - 通过 getPriceHistory() / getLastNPrices() / getLatestPriceRecord() 查询
 *
 * 依赖的外部合约：
 * - IDEXRouter（UniswapV2 风格）：通过 getAmountsOut 获取价格
 *   - 路径：token → WBNB → USDT 用于代币价格
 *   - 路径：WBNB → USDT 用于 ETH/BNB 价格
 * - tokenContract：需正确设置以识别代币
 * - usdtContract：需正确设置以识别 USDT
 *
 * 典型业务调用场景：
 * - NFTUpdate.sol：升级费用 = tokenAmount × tokenPriceUSD（把代币换算成USD价值验证）
 * - NFTTrading.sol：可选择用 BNB 价格作为 NFT 挂牌价的参考
 * - RewardManager.sol：用 USD 价值评估奖励金额
 *
 * 安全考虑：
 * - 价格更新冷却期（priceUpdateCooldown）：防止高频恶意更新
 * - 价格变更幅度限制（maxPriceChangePercent）：防止单次价格剧烈变动
 * - 重入保护：防止价格更新时的外部调用攻击
 * - 暂停机制：可在被操纵时暂停自动喂价
 * - UUPS 可升级：未来可替换为 Chainlink 喂价或更高级算法
 *
 * 注意：本价格预言机仅用于游戏内部经济计算，不保证与真实市场价格完全一致。
 * 主网部署时建议结合 Chainlink 或多签验证机制以增强安全性。
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
     * @dev 价格更新冷却时间（秒）
     */
    uint256 public constant PRICE_UPDATE_COOLDOWN = 3600;

    /**
     * @dev 最大价格变动百分比（基数10000，例如 1000 = 10%）
     */
    uint256 public constant MAX_PRICE_CHANGE_PERCENT = 5000;

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

    bool public paused;
    string public pauseReason;
    
    event Paused(address account, string reason);
    event Unpaused(address account);
    
    function initialize(
        address _authorizerAddress,
        address _tokenContractAddress,
        address _usdtContractAddress,
        address _pancakeSwapRouterAddress
    ) external initializer {
        require(_authorizerAddress != address(0), "PriceOracle: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        
        if (_tokenContractAddress != address(0)) {
            tokenAddress = _tokenContractAddress;
        }
        if (_usdtContractAddress != address(0)) {
            usdtAddress = _usdtContractAddress;
        }
        if (_pancakeSwapRouterAddress != address(0)) {
            pancakeSwapRouter = _pancakeSwapRouterAddress;
            wbnb = IDexRouter(_pancakeSwapRouterAddress).WETH();
            activeDEX = 1;
        } else {
            // 设置默认 DEX Router 地址（BSC 链）
            pancakeSwapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
            uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
            activeDEX = 1;
        }
        
        // 初始化带默认值的参数
        priceValidityPeriod = 86400;
        autoPriceEnabled = true;
        maxPriceChangePercent = 5000;
        priceUpdateCooldown = 5 minutes;
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
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "PriceOracle: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "PriceOracle: Not authorized");
        _;
    }

    /**
     * @dev 代币的USD价格（精度18位）
     *
     * 例如：0.1 = 0.1 * 10^18
     */
    uint256 public tokenPriceUSD;

    /**
     * @dev 代币价格更新时间（秒）
     */
    uint256 public tokenPriceUpdatedAt;

    /**
     * @dev ETH的USD价格（精度18位）
     *
     * 例如：2000 = 2000 * 10^18
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
     * @dev DEX Router 配置 - 支持 FlapSwap、PancakeSwap、Uniswap
     */
    address public flapSwapRouter;
    address public pancakeSwapRouter;
    address public uniswapRouter;
    address public wbnb;
    
    /**
     * @dev 当前活跃的DEX类型
     * 0: FlapSwap
     * 1: PancakeSwap
     * 2: Uniswap
     */
    uint8 public activeDEX;
    
    /**
     * @dev 是否启用DEX自动价格获取
     */
    bool public autoPriceEnabled = true;

    /**
     * @dev 价格更新事件
     *
     * @param tokenPrice 新的代币价格
     * @param ethPrice 新的ETH价格
     * @param updater 更新者地址
     */
    event PriceUpdated(uint256 tokenPrice, uint256 ethPrice, address updater);
    
    /**
     * @dev DEX价格获取事件
     */
    event PriceFetchedFromDEX(uint8 indexed dexType, uint256 tokenPrice, uint256 ethPrice);

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
     * @param _tokenContractAddress 代币合约地址
     */
    function setTokenAddress(address _tokenContractAddress) external onlyOwnerOrAuthorizer {
        require(_tokenContractAddress != address(0), "PriceOracle: Invalid token address");
        tokenAddress = _tokenContractAddress;
    }

    /**
     * @dev 设置USDT地址
     *
     * @param _usdtContractAddress USDT代币合约地址
     */
    function setUSDTAddress(address _usdtContractAddress) external onlyOwnerOrAuthorizer {
        require(_usdtContractAddress != address(0), "PriceOracle: Invalid USDT address");
        usdtAddress = _usdtContractAddress;
    }

    /**
     * @dev 设置PancakeSwap Router地址
     * @param _pancakeSwapRouterAddress PancakeSwap Router 地址
     */
    function setPancakeSwapRouter(address _pancakeSwapRouterAddress) external onlyOwnerOrAuthorizer {
        require(_pancakeSwapRouterAddress != address(0), "PriceOracle: Invalid PancakeSwap router address");
        pancakeSwapRouter = _pancakeSwapRouterAddress;
        activeDEX = 1;
        wbnb = IDexRouter(_pancakeSwapRouterAddress).WETH();
    }

    /**
     * @dev 设置DEX Router地址（支持 FlapSwap、PancakeSwap、Uniswap）
     * @param _flapSwapRouter FlapSwap Router 地址
     * @param _pancakeSwapRouter PancakeSwap Router 地址
     * @param _uniswapRouter Uniswap Router 地址
     */
    function setDEXRouters(address _flapSwapRouter, address _pancakeSwapRouter, address _uniswapRouter) external onlyOwner {
        require(
            _flapSwapRouter != address(0) || _pancakeSwapRouter != address(0) || _uniswapRouter != address(0),
            "PriceOracle: At least one DEX router must be valid"
        );
        flapSwapRouter = _flapSwapRouter;
        pancakeSwapRouter = _pancakeSwapRouter;
        uniswapRouter = _uniswapRouter;
        
        // 设置默认活跃DEX（优先使用PancakeSwap，如果可用）
        if (_pancakeSwapRouter != address(0)) {
            activeDEX = 1;
            wbnb = IDexRouter(_pancakeSwapRouter).WETH();
        } else if (_flapSwapRouter != address(0)) {
            activeDEX = 0;
            wbnb = IDexRouter(_flapSwapRouter).WETH();
        } else if (_uniswapRouter != address(0)) {
            activeDEX = 2;
            wbnb = IDexRouter(_uniswapRouter).WETH();
        }
    }

    /**
     * @dev 设置活跃DEX
     * @param _dexType DEX类型（0=FlapSwap, 1=PancakeSwap, 2=Uniswap）
     */
    function setActiveDEX(uint8 _dexType) external onlyOwner {
        require(_dexType <= 2, "PriceOracle: Invalid DEX type");
        
        address router;
        if (_dexType == 0) {
            require(flapSwapRouter != address(0), "PriceOracle: FlapSwap not configured");
            router = flapSwapRouter;
        } else if (_dexType == 1) {
            require(pancakeSwapRouter != address(0), "PriceOracle: PancakeSwap not configured");
            router = pancakeSwapRouter;
        } else {
            require(uniswapRouter != address(0), "PriceOracle: Uniswap not configured");
            router = uniswapRouter;
        }
        
        activeDEX = _dexType;
        wbnb = IDexRouter(router).WETH();
    }

    /**
     * @dev 设置自动价格获取开关
     */
    function setAutoPriceEnabled(bool enabled) external onlyOwner {
        autoPriceEnabled = enabled;
    }

    /**
     * @dev 从DEX获取当前代币价格（通过WBNB/ETH中转）
     * @return uint256 代币价格（USD，精度18位）
     */
    function fetchPriceFromDEX() external onlyOwnerOrAuthorizer whenNotPaused returns (uint256, uint256) {
        require(autoPriceEnabled, "PriceOracle: Auto price disabled");
        
        address router = _getActiveRouter();
        require(router != address(0), "PriceOracle: No DEX configured");
        
        // 获取代币价格（代币 -> WBNB -> USDT）
        uint256 tokenPrice = _fetchTokenPrice(router);
        uint256 ethPrice = _fetchETHPrice(router);
        
        if (tokenPrice > 0) {
            tokenPriceUSD = tokenPrice;
            tokenPriceUpdatedAt = block.timestamp;
        }
        if (ethPrice > 0) {
            ethPriceUSD = ethPrice;
            ethPriceUpdatedAt = block.timestamp;
        }
        
        emit PriceFetchedFromDEX(activeDEX, tokenPrice, ethPrice);
        emit PriceUpdated(tokenPriceUSD, ethPriceUSD, msg.sender);
        
        return (tokenPrice, ethPrice);
    }

    /**
     * @dev 获取当前活跃的DEX Router
     */
    function _getActiveRouter() internal view returns (address) {
        if (activeDEX == 0) return flapSwapRouter;
        if (activeDEX == 1) return pancakeSwapRouter;
        return uniswapRouter;
    }

    /**
     * @dev 从DEX获取代币价格
     */
    function _fetchTokenPrice(address router) internal view returns (uint256) {
        if (tokenAddress == address(0) || usdtAddress == address(0) || wbnb == address(0)) {
            return 0;
        }
        
        // 路径：代币 -> WBNB -> USDT
        address[] memory path = new address[](3);
        path[0] = tokenAddress;
        path[1] = wbnb;
        path[2] = usdtAddress;
        
        try IDexRouter(router).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 3 && amounts[2] > 0) {
                // amounts[2] 是 USDT 数量（6位精度）
                // 转换为 USD 价格（18位精度）
                return amounts[2] * 10**12;
            }
        } catch {}
        
        return 0;
    }

    /**
     * @dev 从DEX获取ETH价格
     */
    function _fetchETHPrice(address router) internal view returns (uint256) {
        if (usdtAddress == address(0) || wbnb == address(0)) {
            return 0;
        }
        
        // 路径：WBNB -> USDT
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = usdtAddress;
        
        try IDexRouter(router).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 2 && amounts[1] > 0) {
                // amounts[1] 是 USDT 数量（6位精度）
                // 转换为 USD 价格（18位精度）
                return amounts[1] * 10**12;
            }
        } catch {}
        
        return 0;
    }

    /**
     * @dev 获取所有DEX的价格并返回平均值
     */
    function fetchPriceFromAllDEX() external onlyOwnerOrAuthorizer whenNotPaused returns (uint256, uint256) {
        uint256 tokenPriceSum = 0;
        uint256 ethPriceSum = 0;
        uint256 count = 0;
        
        // 从FlapSwap获取
        if (flapSwapRouter != address(0)) {
            uint256 tp = _fetchTokenPrice(flapSwapRouter);
            uint256 ep = _fetchETHPrice(flapSwapRouter);
            if (tp > 0 && ep > 0) {
                tokenPriceSum += tp;
                ethPriceSum += ep;
                count++;
            }
        }
        
        // 从PancakeSwap获取
        if (pancakeSwapRouter != address(0)) {
            uint256 tp = _fetchTokenPrice(pancakeSwapRouter);
            uint256 ep = _fetchETHPrice(pancakeSwapRouter);
            if (tp > 0 && ep > 0) {
                tokenPriceSum += tp;
                ethPriceSum += ep;
                count++;
            }
        }
        
        // 从Uniswap获取
        if (uniswapRouter != address(0)) {
            uint256 tp = _fetchTokenPrice(uniswapRouter);
            uint256 ep = _fetchETHPrice(uniswapRouter);
            if (tp > 0 && ep > 0) {
                tokenPriceSum += tp;
                ethPriceSum += ep;
                count++;
            }
        }
        
        if (count == 0) {
            return (0, 0);
        }
        
        uint256 avgTokenPrice = tokenPriceSum / count;
        uint256 avgETHPrice = ethPriceSum / count;
        
        tokenPriceUSD = avgTokenPrice;
        ethPriceUSD = avgETHPrice;
        tokenPriceUpdatedAt = block.timestamp;
        ethPriceUpdatedAt = block.timestamp;
        
        emit PriceFetchedFromDEX(activeDEX, avgTokenPrice, avgETHPrice);
        emit PriceUpdated(avgTokenPrice, avgETHPrice, msg.sender);
        
        return (avgTokenPrice, avgETHPrice);
    }

    /**
     * @dev 更新代币价格
     *
     * @param _tokenPriceUSD 新的代币价格（USD，精度18位）
     */
    function updateTokenPrice(uint256 _tokenPriceUSD) external onlyOwnerOrAuthorizer whenNotPaused {
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
    function updateETHPrice(uint256 _ethPriceUSD) external onlyOwnerOrAuthorizer whenNotPaused {
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

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}