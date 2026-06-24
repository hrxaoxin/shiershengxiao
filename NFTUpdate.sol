// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";
import "./NFTInterface.sol";
import "./NFTLib.sol";
import "./PriceLibrary.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title NFTUpdate
 * @dev NFT升级合约
 * 支持使用NFT、代币或USD价值升级NFT等级
 * 基于OpenZeppelin UUPS可升级合约实现
 *
 * NOTE: 数据存储双轨机制：
 * - NFTMint (nftContract): 链上主存储 tokenType[] 和 tokenLevel[]（ERC721 合约自管理）
 * - NFTData (metadataContract): 分离数据层，存储详细的 ZodiacType、用户代币列表等
 * 本合约通过 metadataContract 读写 NFT 数据以保持与 NFTMint 的同步状态
 * 部署时需确保 metadataContract 正确初始化并与 NFTMint 数据对齐
 *
 * 升级方式（3种）：
 * 1. 消耗同类型 NFT（upgradeWithNFT）：
 *    - 消耗 N 张同等级 NFT 升级 1 级
 *    - 例如：1级→2级需要 1 张同级NFT；2级→3级需要 2 张；以此类推
 *    - 被消耗的 NFT 转入 BLACK_HOLE 永久锁定（实际销毁）
 *
 * 2. 消耗代币（upgradeWithToken）：
 *    - 按等级阶梯缴纳代币：1级=10000，2级=40000，3级=120000，4级=480000
 *    - 代币转入 TokenBurner 合约销毁，保持经济模型的紧缩性
 *
 * 3. 消耗等值 USD 价值的代币（upgradeWithUSDValue）：
 *    - 根据 PriceOracle 提供的当前代币/USD 价格动态计算消耗数量
 *    - 公式：tokenAmount = usdAmount / tokenPriceUSD
 *    - 防止代币价格波动导致升级费用实际价值严重失衡
 *
 * 等级成长曲线：
 * - 等级 1：初始铸造等级（基础属性 100%）
 * - 等级 2：属性 +20%（约）
 * - 等级 3：属性 +50%（约）
 * - 等级 4：属性 +100%（约）
 * - 等级 5：属性 +200%（约），可参与繁殖
 *
 * 权重联动：
 * - 每次升级后调用 DividendManager.updateUserWeight() 更新用户在分红池中的权重
 * - 同时更新 WeightManager 中的用户权重快照
 * - 权重越高，分红越多；稀有属性（闪光）基础权重更高
 *
 * 价格验证：
 * - priceExpirySeconds（默认1小时）：防止使用已失效的旧价格
 * - priceDeviationThreshold（默认 5000 = 50%）：价格相对 PancakeSwap 现货偏离过大时拒绝升级
 * - 防止在预言机被操纵时产生异常便宜/昂贵的升级
 *
 * 冷却期：
 * - upgradeCooldown 防止同一 NFT 被反复刷级（配合重入保护）
 *
 * 安全限制：
 * - 必须拥有 NFT 才能升级（ownerOf 验证）
 * - 每次只能升 1 级（不可越级）
 * - 5 级为上限，达到后不可再升
 * - ReentrancyGuard 防止跨合约重入
 * - paused 可暂停所有升级操作
 *
 * 典型用户流程：
 * 1. 集齐 N 张同等级 NFT 或准备好足够代币
 * 2. 前端根据价格预言机计算费用并展示
 * 3. 用户批准 NFT/代币转移
 * 4. 调用 upgradeWithNFT / upgradeWithToken / upgradeWithUSDValue
 * 5. 等级 +1，用户权重更新，升级事件广播
 */
contract NFTUpdate is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using NFTLib for uint256;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "NFTUpdate: Paused");
        _;
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

    /** @dev 黑洞地址，用于销毁NFT和代币 */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 合约地址 */
    address public nftContract;
    address public tokenContract;
    address public metadataContract;
    address public dividendManager;
    address public priceOracle;
    address public pancakeSwapPair;
    
    /** @dev 手动设置的Pair地址（绕过Router直接从Pair获取价格）
     * flapSwapPair_WBNB: FlapSwap的代币-WBNB Pair地址
     * pancakeSwapPair_WBNB: PancakeSwap的代币-WBNB Pair地址
     * uniswapPair_WBNB: Uniswap的代币-WBNB Pair地址
     * wbnbUsdtPair: WBNB-USDT Pair地址（用于计算代币-USDT价格）
     */
    address public flapSwapPair_WBNB;
    address public pancakeSwapPair_WBNB;
    address public uniswapPair_WBNB;
    address public wbnbUsdtPair;

    /** @dev 最小PancakeSwap流动性（防止价格操纵） */
    uint256 public minPancakeSwapLiquidity;

    /** @dev 价格过期时间（秒），默认1小时 */
    uint256 public priceExpirySeconds = 3600;
    /** @dev 价格波动保护阈值（千分比，默认5000 = 50%） */
    uint256 public priceDeviationThreshold = 5000;
    /** @dev 上次价格 */
    uint256 public lastPrice;
    /** @dev 上次价格更新时间 */
    uint256 public lastPriceUpdateTime;
    /** @dev 上次价格更新时的区块号（防止同一区块内价格操纵） */
    uint256 public lastPriceUpdateBlock;
    /** @dev 价格更新最小区块间隔（默认1个区块） */
    uint256 public minPriceUpdateBlocks = 1;
    /** @dev 价格更新最小时间间隔（秒）- 防止快速出块链上的时间窗口攻击 */
    uint256 public minPriceUpdateSeconds = 60;

    /** @dev 各级别升级费用（代币数量，含精度18位） */
    uint256 public level1UpgradeCost = 10000 * 10**18;
    uint256 public level2UpgradeCost = 40000 * 10**18;
    uint256 public level3UpgradeCost = 120000 * 10**18;
    uint256 public level4UpgradeCost = 480000 * 10**18;
    
    /** @dev USD价值升级方式是否隐藏（默认隐藏） */
    bool public usdUpgradeHidden = true;
    
    /** @dev USD价值升级各级别费用（USDT数量，精度18位）
     *  level1USDUpgradeCost: 1级→2级所需USDT价值
     *  level2USDUpgradeCost: 2级→3级所需USDT价值
     *  level3USDUpgradeCost: 3级→4级所需USDT价值
     *  level4USDUpgradeCost: 4级→5级所需USDT价值
     */
    uint256 public level1USDUpgradeCost = 1e18;      // 1 USDT
    uint256 public level2USDUpgradeCost = 4e18;      // 4 USDT
    uint256 public level3USDUpgradeCost = 12e18;     // 12 USDT
    uint256 public level4USDUpgradeCost = 48e18;     // 48 USDT

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[45] private __gap;

    /** @dev 初始化函数
     * @param initialOwner 初始所有者地址
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address initialOwner, address _authorizerAddress) external initializer {
        require(initialOwner != address(0), "NFTUpdate: Invalid initial owner address");
        require(_authorizerAddress != address(0), "NFTUpdate: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        transferOwnership(initialOwner);
        authorizer = _authorizerAddress;
        
        // 从 Authorizer 初始化合约地址
        _syncContractAddresses();
        
        // 初始化带默认值的参数
        priceExpirySeconds = 3600;
        priceDeviationThreshold = 5000;
        minPriceUpdateBlocks = 1;
        minPriceUpdateSeconds = 60;
        level1UpgradeCost = 10000 * 10**18;
        level2UpgradeCost = 40000 * 10**18;
        level3UpgradeCost = 120000 * 10**18;
        level4UpgradeCost = 480000 * 10**18;
        usdUpgradeHidden = true;
        minPancakeSwapLiquidity = 10**15;
        
        // 初始化 USD 升级费用
        level1USDUpgradeCost = 1e18;      // 1 USDT
        level2USDUpgradeCost = 4e18;      // 4 USDT
        level3USDUpgradeCost = 12e18;     // 12 USDT
        level4USDUpgradeCost = 48e18;     // 48 USDT
    }

    /**
     * @dev 同步合约地址（从Authorizer获取并更新）
     */
    function _syncContractAddresses() internal {
        IAuthorizer auth = IAuthorizer(authorizer);
        nftContract = auth.getNFTMintCore();
        tokenContract = auth.getToken();
        metadataContract = auth.getNFTData();
        dividendManager = auth.getDividendManager();
        priceOracle = auth.getPriceOracle();
    }

    /**
     * @dev 设置PancakeSwap交易对地址
     * @param pair PancakeSwap交易对地址
     */
    function setPancakeSwapPair(address pair) external onlyOwner {
        pancakeSwapPair = pair;
    }
    
    /**
     * @dev 设置FlapSwap的代币-WBNB Pair地址
     * @param pair Pair地址
     */
    function setFlapSwapPair(address pair) external onlyOwner {
        flapSwapPair_WBNB = pair;
    }
    
    /**
     * @dev 设置PancakeSwap的代币-WBNB Pair地址
     * @param pair Pair地址
     */
    function setPancakeSwapPairWBNB(address pair) external onlyOwner {
        pancakeSwapPair_WBNB = pair;
    }
    
    /**
     * @dev 设置Uniswap的代币-WBNB Pair地址
     * @param pair Pair地址
     */
    function setUniswapPair(address pair) external onlyOwner {
        uniswapPair_WBNB = pair;
    }
    
    /**
     * @dev 设置WBNB-USDT Pair地址
     * @param pair Pair地址
     */
    function setWbnbUsdtPair(address pair) external onlyOwner {
        wbnbUsdtPair = pair;
    }
    
    /**
     * @dev 批量设置所有Pair地址
     * @param _flapSwapPair FlapSwap的代币-WBNB Pair地址
     * @param _pancakeSwapPair PancakeSwap的代币-WBNB Pair地址
     * @param _uniswapPair Uniswap的代币-WBNB Pair地址
     * @param _wbnbUsdtPair WBNB-USDT Pair地址
     */
    function setAllPairs(address _flapSwapPair, address _pancakeSwapPair, address _uniswapPair, address _wbnbUsdtPair) external onlyOwner {
        flapSwapPair_WBNB = _flapSwapPair;
        pancakeSwapPair_WBNB = _pancakeSwapPair;
        uniswapPair_WBNB = _uniswapPair;
        wbnbUsdtPair = _wbnbUsdtPair;
    }
    
    /**
     * @dev 升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 检查是否为授权地址
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "NFTUpdate: Not authorized");
        _;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "NFTUpdate: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置价格过期时间
     * @param seconds_ 过期时间（秒）
     */
    function setPriceExpirySeconds(uint256 seconds_) external onlyOwner {
        require(seconds_ > 0, "NFTUpdate: expiry must be > 0");
        priceExpirySeconds = seconds_;
    }

    /**
     * @dev 设置价格波动保护阈值（千分比）
     * @param threshold 阈值（0-10000）
     */
    function setPriceDeviationThreshold(uint256 threshold) external onlyOwner {
        require(threshold <= 10000, "NFTUpdate: threshold <= 10000");
        priceDeviationThreshold = threshold;
    }

    /**
     * @dev 重置价格缓存
     */
    function resetPriceCache() external onlyOwner {
        lastPrice = 0;
        lastPriceUpdateTime = 0;
        lastPriceUpdateBlock = 0;
    }

    /**
     * @dev 设置1级升级费用
     * @param cost 升级费用（代币数量）
     */
    function setLevel1UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level1UpgradeCost = cost;
    }

    /**
     * @dev 设置2级升级费用
     * @param cost 升级费用（代币数量）
     */
    function setLevel2UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level2UpgradeCost = cost;
    }

    /**
     * @dev 设置3级升级费用
     * @param cost 升级费用（代币数量）
     */
    function setLevel3UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level3UpgradeCost = cost;
    }

    /**
     * @dev 设置4级升级费用
     * @param cost 升级费用（代币数量）
     */
    function setLevel4UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level4UpgradeCost = cost;
    }

    /**
     * @dev 批量设置所有等级的升级费用
     * @param costs 所有等级的升级费用数组（长度4，索引0对应等级1）
     */
    function setAllLevelUpgradeCosts(uint256[4] calldata costs) external onlyOwner {
        uint256 maxCost = 1e30;
        require(costs[0] > 0 && costs[0] <= maxCost, "NFTUpdate: Invalid level 1 cost");
        require(costs[1] > 0 && costs[1] <= maxCost, "NFTUpdate: Invalid level 2 cost");
        require(costs[2] > 0 && costs[2] <= maxCost, "NFTUpdate: Invalid level 3 cost");
        require(costs[3] > 0 && costs[3] <= maxCost, "NFTUpdate: Invalid level 4 cost");
        
        level1UpgradeCost = costs[0];
        level2UpgradeCost = costs[1];
        level3UpgradeCost = costs[2];
        level4UpgradeCost = costs[3];
    }

    /**
     * @dev 设置USD价值升级方式的显示/隐藏状态
     * @param hidden 是否隐藏（true=隐藏，false=显示）
     */
    function setUSDUpgradeHidden(bool hidden) external onlyOwner {
        usdUpgradeHidden = hidden;
        emit USDUpgradeHiddenChanged(hidden);
    }

    /**
     * @dev 获取所有等级的升级费用
     * @return 所有等级的升级费用数组
     */
    function getAllLevelUpgradeCosts() external view returns (uint256[4] memory) {
        return [
            level1UpgradeCost,
            level2UpgradeCost,
            level3UpgradeCost,
            level4UpgradeCost
        ];
    }

    /**
     * @dev 设置USD价值升级的1级升级费用（USDT数量）
     * @param cost USDT数量（精度18位）
     */
    function setLevel1USDUpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: USD cost must be > 0");
        level1USDUpgradeCost = cost;
        emit USDUpgradeCostChanged(1, cost);
    }

    /**
     * @dev 设置USD价值升级的2级升级费用（USDT数量）
     * @param cost USDT数量（精度18位）
     */
    function setLevel2USDUpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: USD cost must be > 0");
        level2USDUpgradeCost = cost;
        emit USDUpgradeCostChanged(2, cost);
    }

    /**
     * @dev 设置USD价值升级的3级升级费用（USDT数量）
     * @param cost USDT数量（精度18位）
     */
    function setLevel3USDUpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: USD cost must be > 0");
        level3USDUpgradeCost = cost;
        emit USDUpgradeCostChanged(3, cost);
    }

    /**
     * @dev 设置USD价值升级的4级升级费用（USDT数量）
     * @param cost USDT数量（精度18位）
     */
    function setLevel4USDUpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: USD cost must be > 0");
        level4USDUpgradeCost = cost;
        emit USDUpgradeCostChanged(4, cost);
    }

    /**
     * @dev 批量设置所有等级的USD价值升级费用
     * @param costs 所有等级的USD升级费用数组（长度4，索引0对应等级1）
     */
    function setAllLevelUSDUpgradeCosts(uint256[4] calldata costs) external onlyOwner {
        uint256 maxCost = 1e30;
        require(costs[0] > 0 && costs[0] <= maxCost, "NFTUpdate: Invalid level 1 USD cost");
        require(costs[1] > 0 && costs[1] <= maxCost, "NFTUpdate: Invalid level 2 USD cost");
        require(costs[2] > 0 && costs[2] <= maxCost, "NFTUpdate: Invalid level 3 USD cost");
        require(costs[3] > 0 && costs[3] <= maxCost, "NFTUpdate: Invalid level 4 USD cost");
        
        level1USDUpgradeCost = costs[0];
        level2USDUpgradeCost = costs[1];
        level3USDUpgradeCost = costs[2];
        level4USDUpgradeCost = costs[3];
        
        emit USDUpgradeCostChanged(1, costs[0]);
        emit USDUpgradeCostChanged(2, costs[1]);
        emit USDUpgradeCostChanged(3, costs[2]);
        emit USDUpgradeCostChanged(4, costs[3]);
    }

    /**
     * @dev 获取所有等级的USD价值升级费用
     * @return 所有等级的USD升级费用数组
     */
    function getAllLevelUSDUpgradeCosts() external view returns (uint256[4] memory) {
        return [
            level1USDUpgradeCost,
            level2USDUpgradeCost,
            level3USDUpgradeCost,
            level4USDUpgradeCost
        ];
    }

    /**
     * @dev 设置最小PancakeSwap流动性要求
     * @param minLiq 最小流动性数量
     */
    function setMinPancakeSwapLiquidity(uint256 minLiq) external onlyOwner {
        minPancakeSwapLiquidity = minLiq;
    }

    /**
     * @dev 从PancakeSwap获取代币价格（USD）
     * @return uint256 代币价格（精度18位）
     */
    function getTokenPriceFromPancakeSwap() public view returns (uint256) {
        require(pancakeSwapPair != address(0), "E24: PancakeSwap pair not set");
        
        IPancakeSwapPair pair = IPancakeSwapPair(pancakeSwapPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        // 修复：添加最小流动性检查，防止低流动性 pair 被操纵价格
        require(reserve0 > 0 && reserve1 > 0, "E25: Insufficient liquidity");
        
        address token0 = pair.token0();
        address token1 = pair.token1();

        // 修复：校验 pair 确实包含 tokenContract，防止设置假 pair 导致价格异常
        require(token0 == tokenContract || token1 == tokenContract, "E26: Token not in pair");
        
        uint8 decimals0 = 18;
        uint8 decimals1 = 18;
        
        if (token0 == tokenContract) {
            // 修复：对代币侧（本项目代币）的流动性进行下限校验
            require(uint256(reserve0) >= minPancakeSwapLiquidity, "E25: Token side liquidity too low");
            try IBEP20(token1).decimals() returns (uint8 d) {
                decimals1 = d;
            } catch {}
            
            uint256 price = (uint256(reserve1) * 10**18) / uint256(reserve0);
            return _adjustPriceDecimals(price, decimals1);
        } else {
            // token1 == tokenContract
            // 修复：对代币侧（本项目代币）的流动性进行下限校验
            require(uint256(reserve1) >= minPancakeSwapLiquidity, "E25: Token side liquidity too low");
            try IBEP20(token0).decimals() returns (uint8 d) {
                decimals0 = d;
            } catch {}
            
            uint256 price = (uint256(reserve0) * 10**18) / uint256(reserve1);
            return _adjustPriceDecimals(price, decimals0);
        }
    }
    
    /**
     * @dev 调整价格的小数位数（内部函数）
     * @param price 原始价格
     * @param tokenDecimals 代币小数位数
     * @return uint256 调整后的价格（精度18位）
     */
    function _adjustPriceDecimals(uint256 price, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == 18) {
            return price;
        } else if (tokenDecimals < 18) {
            return price * 10**(18 - tokenDecimals);
        } else {
            return price / 10**(tokenDecimals - 18);
        }
    }

    /**
     * @dev 调整小数位数（内部函数）
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

    /**
     * @dev 使用NFT升级（消耗同类型同等级的其他NFT）
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithNFT(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8) {
        require(nftContract != address(0), "NFTUpdate: NFT contract not set");
        require(metadataContract != address(0), "NFTUpdate: Metadata contract not set");
        require(dividendManager != address(0), "NFTUpdate: Dividend manager not set");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint256 tokenTypeValue = m.tokenType(tokenId);
        NFTDataTypes.ZodiacType t = NFTDataTypes.ZodiacType(tokenTypeValue);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        
        uint256[] memory burnCandidates = _findBurnCandidates(tokenId, lv, tokenTypeValue, nft);
        // 修复：先完成升级逻辑（状态变更、跨合约权重更新）再销毁 NFT，避免升级失败导致 NFT 永久损失
        _completeUpgrade(tokenId, lv, t, m, nft);
        _burnNFTs(burnCandidates, t, nft);
        
        return lv + 1;
    }

    /**
     * @dev 查找可销毁的NFT候选
     * @param tokenId 要升级的NFT ID
     * @param lv 当前等级
     * @param tokenTypeValue NFT类型值
     * @param nft NFT合约实例
     * @return 可销毁的NFT ID数组
     */
    function _findBurnCandidates(uint256 tokenId, uint8 lv, uint256 tokenTypeValue, INFTMint nft) internal view returns (uint256[] memory) {
        uint256[] memory allUserTokens = nft.getTokenIdsByOwner(msg.sender);
        uint256 maxIterations = 100;
        uint256 actualIterations = allUserTokens.length;
        if (actualIterations > maxIterations) {
            actualIterations = maxIterations;
        }
        require(allUserTokens.length <= maxIterations, "E33: Too many NFTs, please reduce holdings");
        
        uint256[] memory arr = new uint256[](actualIterations);
        uint256 arrLength = 0;
        uint256 count = 0;
        
        for (uint i = 0; i < actualIterations; i++) {
            uint256 tid = allUserTokens[i];
            if (nft.tokenType(tid) == tokenTypeValue) {
                arr[arrLength] = tid;
                arrLength++;
                if (nft.tokenLevel(tid) == lv) {
                    count++;
                }
            }
        }
        // 修复：升级到 lv+1 需要销毁 lv 张同类型同级 NFT，count 要包含 tokenId 本身
        // 逻辑：count 是所有同级 NFT 数（包括 tokenId 自己），需要 >= lv+1（销毁 lv 张 + 留 1 张升级）
        require(count >= lv + 1, "E17");
        
        uint256[] memory burnCandidates = new uint256[](lv);
        uint256 candidateIdx = 0;
        
        for (uint i = 0; i < arrLength && candidateIdx < lv; i++) {
            uint256 currentId = arr[i];
            if (currentId != tokenId && nft.tokenLevel(currentId) == lv) {
                burnCandidates[candidateIdx++] = currentId;
            }
        }
        
        require(candidateIdx == lv, "E28: Insufficient burn candidates");
        return burnCandidates;
    }

    /**
     * @dev 销毁NFT
     * @param burnCandidates 要销毁的NFT ID数组
     * @param t NFT类型
     * @param nft NFT合约实例
     */
    function _burnNFTs(uint256[] memory burnCandidates, NFTDataTypes.ZodiacType t, INFTMint nft) internal {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(t);
        uint8 burnLevel = m.tokenLevel(burnCandidates[0]); // 同类型同级NFT
        
        for (uint i = 0; i < burnCandidates.length; i++) {
            uint burnId = burnCandidates[i];
            // 同步权重：移除被销毁NFT的权重
            _updateUserWeight(msg.sender, burnLevel, false, element);
            // 从NFTData用户NFT列表中移除
            _removeUserNFT(msg.sender, burnId);
            nft.safeTransferFrom(msg.sender, BLACK_HOLE, burnId);
            emit CardBurned(burnId, t, msg.sender);
        }
    }

    /**
     * @dev 从NFTData用户NFT列表中移除
     * @param user 用户地址
     * @param tokenId NFT ID
     */
    function _removeUserNFT(address user, uint256 tokenId) internal {
        try INFTDataInterface(metadataContract).removeUserNFT(user, tokenId) {
            // 成功
        } catch {
            // 忽略错误，继续执行
        }
    }

    /**
     * @dev 完成升级操作
     * @param tokenId 要升级的NFT ID
     * @param lv 当前等级
     * @param t NFT类型
     * @param m 元数据合约实例
     * @param nft NFT合约实例
     * @return 新等级
     */
    function _completeUpgrade(uint256 tokenId, uint8 lv, NFTDataTypes.ZodiacType t, INFTDataInterface m, INFTMint nft) internal returns (uint8) {
        uint8 newLv = lv + 1;
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(t);
        
        require(dividendManager != address(0), "NFTUpdate: Dividend manager not set");
        
        _updateUserWeight(msg.sender, lv, false, element);
        _updateUserWeight(msg.sender, newLv, true, element);
        
        m.setTokenLevel(tokenId, newLv);
        nft.adminSetNFTLevel(tokenId, newLv);
        
        emit CardUpgraded(tokenId, t, lv, newLv, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    /**
     * @dev 更新用户权重
     * @param user 用户地址
     * @param level 等级
     * @param isAdd 是否增加
     * @param element 属性类型
     */
    function _updateUserWeight(address user, uint8 level, bool isAdd, NFTDataTypes.ElementType element) internal {
        try IDividendManager(dividendManager).updateUserWeight(user, uint256(level), isAdd, uint8(element)) {
            // 成功
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("NFTUpdate: Update weight failed - ", reason)));
        } catch {
            revert("NFTUpdate: Update weight failed with unknown error");
        }
        
        // 修复：添加 WeightManager 同步，确保权重数据一致性
        address weightManager = IAuthorizer(authorizer).getWeightManager();
        if (weightManager != address(0)) {
            try IWeightManager(weightManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略 WeightManager 同步失败，不影响主流程
            }
        }
    }

    /**
     * @dev 使用代币升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithToken(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8) {
        require(nftContract != address(0), "NFTUpdate: NFT contract not set");
        require(metadataContract != address(0), "NFTUpdate: Metadata contract not set");
        require(tokenContract != address(0), "E7: Token contract not set");
        require(dividendManager != address(0), "NFTUpdate: Dividend manager not set");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        uint256 cost;
        if (lv == 1) cost = level1UpgradeCost;
        else if (lv == 2) cost = level2UpgradeCost;
        else if (lv == 3) cost = level3UpgradeCost;
        else if (lv == 4) cost = level4UpgradeCost;
        else revert("E18: Invalid level");
        
        IERC20 t = IERC20(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8: Insufficient balance");
        require(t.allowance(msg.sender, address(this)) >= cost, "E8: Insufficient allowance");
        t.safeTransferFrom(msg.sender, BLACK_HOLE, cost);
        
        NFTDataTypes.ZodiacType zodiacType = NFTDataTypes.ZodiacType(m.tokenType(tokenId));
        uint8 newLv = _completeUpgrade(tokenId, lv, zodiacType, m, nft);
        emit TokenUpgraded(tokenId, zodiacType, lv, newLv, cost, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    /**
     * @dev 使用USD价值升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithUSDValue(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8) {
        require(nftContract != address(0), "NFTUpdate: NFT contract not set");
        require(metadataContract != address(0), "NFTUpdate: Metadata contract not set");
        require(tokenContract != address(0), "NFTUpdate: Token contract not set");
        require(dividendManager != address(0), "NFTUpdate: Dividend manager not set");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        // 修复：减少局部变量，使用内部函数处理升级逻辑
        return _upgradeWithUSDValueInternal(tokenId, lv, m, nft);
    }
    
    /**
     * @dev 使用USD价值升级（内部函数，减少栈深度）
     */
    function _upgradeWithUSDValueInternal(uint256 tokenId, uint8 lv, INFTDataInterface m, INFTMint nft) internal returns (uint8) {
        // 使用可配置的USD升级费用
        uint256 usdValue;
        if (lv == 1) usdValue = level1USDUpgradeCost;
        else if (lv == 2) usdValue = level2USDUpgradeCost;
        else if (lv == 3) usdValue = level3USDUpgradeCost;
        else if (lv == 4) usdValue = level4USDUpgradeCost;
        else revert("E18: Invalid level");
        
        // 修复：检查USD费用是否有效（不能为0）
        require(usdValue > 0, "E22: USD upgrade cost not set");
        
        uint256 price = _getTokenPrice();
        require(price > 0, "E20: Price oracle returned zero");
        require(price >= 10**10, "E20: Price too low");
        
        uint256 cost = (usdValue * 1e18) / price;
        require(cost > 0, "E21: Invalid cost");
        require(cost <= 10**30, "E21: Cost exceeds maximum");
        
        // 添加余额和授权检查
        IERC20 t = IERC20(tokenContract);
        uint256 balance = t.balanceOf(msg.sender);
        require(balance >= cost, "E8: Insufficient balance");
        
        uint256 allowance = t.allowance(msg.sender, address(this));
        require(allowance >= cost, "E8: Insufficient allowance");
        
        t.safeTransferFrom(msg.sender, BLACK_HOLE, cost);
        
        NFTDataTypes.ZodiacType zodiacType = NFTDataTypes.ZodiacType(m.tokenType(tokenId));
        uint8 newLv = _completeUpgrade(tokenId, lv, zodiacType, m, nft);
        emit USDValueUpgraded(tokenId, zodiacType, lv, newLv, usdValue, cost, price, msg.sender, uint64(block.timestamp));
        return newLv;
    }
    
    /**
     * @dev 获取代币价格（自动检查所有DEX，选择最低价格）
     * 价格获取优先级：
     * 1. PriceOracle（如果有效且非零）
     * 2. 自动扫描所有DEX（FlapSwap、PancakeSwap、Uniswap），选择最低价格
     * @return uint256 代币价格（精度18位）
     */
    function _getTokenPrice() internal view returns (uint256) {
        uint256 lowestPrice = 0;
        
        // 优先从PriceOracle获取价格（支持多DEX，包括FlapSwap内盘）
        if (priceOracle != address(0)) {
            try IPriceOracle(priceOracle).getTokenPrice() returns (uint256 price) {
                if (price > 0) {
                    // 检查价格是否有效（未过期）
                    try IPriceOracle(priceOracle).isTokenPriceValid() returns (bool isValid) {
                        if (isValid) {
                            lowestPrice = price;
                        }
                    } catch {
                        // 如果isTokenPriceValid调用失败，直接使用价格（兼容旧版本）
                        lowestPrice = price;
                    }
                }
            } catch {}
        }
        
        // 自动扫描所有DEX，获取最低价格
        uint256[] memory dexPrices = _getAllDEXPrices();
        for (uint256 i = 0; i < dexPrices.length; i++) {
            uint256 dexPrice = dexPrices[i];
            if (dexPrice > 0) {
                if (lowestPrice == 0 || dexPrice < lowestPrice) {
                    lowestPrice = dexPrice;
                }
            }
        }
        
        return lowestPrice;
    }
    
    /**
     * @dev 从所有DEX获取价格数组
     * @return prices 价格数组（索引0=FlapSwap, 1=PancakeSwap, 2=Uniswap）
     */
    function _getAllDEXPrices() internal view returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](3);
        
        IAuthorizer auth = IAuthorizer(authorizer);
        
        // FlapSwap (dexType = 0) - 优先使用手动设置的Pair
        if (flapSwapPair_WBNB != address(0)) {
            prices[0] = _getPriceFromManualPair(flapSwapPair_WBNB);
        }
        if (prices[0] == 0) {
            address flapSwapRouter = auth.getFlapSwapRouter();
            if (flapSwapRouter != address(0)) {
                prices[0] = _getPriceFromRouter(flapSwapRouter);
            }
        }
        
        // PancakeSwap (dexType = 1) - 优先使用手动设置的Pair
        if (pancakeSwapPair_WBNB != address(0)) {
            prices[1] = _getPriceFromManualPair(pancakeSwapPair_WBNB);
        }
        if (prices[1] == 0) {
            address pancakeSwapRouter = auth.getPancakeSwapRouter();
            if (pancakeSwapRouter != address(0)) {
                prices[1] = _getPriceFromRouter(pancakeSwapRouter);
            }
        }
        
        // Uniswap (dexType = 2) - 优先使用手动设置的Pair
        if (uniswapPair_WBNB != address(0)) {
            prices[2] = _getPriceFromManualPair(uniswapPair_WBNB);
        }
        if (prices[2] == 0) {
            address uniswapRouter = auth.getUniswapRouter();
            if (uniswapRouter != address(0)) {
                prices[2] = _getPriceFromRouter(uniswapRouter);
            }
        }
        
        return prices;
    }
    
    /**
     * @dev 从手动设置的Pair地址获取代币价格
     * @param pair Pair地址
     * @return 代币价格（USD，精度18位），获取失败返回0
     */
    function _getPriceFromManualPair(address pair) internal view returns (uint256) {
        IAuthorizer auth = IAuthorizer(authorizer);
        return PriceLibrary.getPriceFromPairs(
            pair,
            wbnbUsdtPair,
            tokenContract,
            auth.getWBNB(),
            auth.getUSDT()
        );
    }
    
    /**
     * @dev 获取WBNB-USDT价格
     * 优先使用手动设置的Pair
     * @return WBNB价格（USD，精度18位）
     */
    function _getWbnbUsdtPrice() internal view returns (uint256) {
        IAuthorizer auth = IAuthorizer(authorizer);
        
        // 优先使用手动设置的WBNB-USDT Pair
        uint256 price = PriceLibrary.getWbnbUsdtPriceFromPair(wbnbUsdtPair, auth.getWBNB(), auth.getUSDT());
        if (price > 0) {
            return price;
        }
        
        // 备用：通过Router获取
        address flapSwapRouter = auth.getFlapSwapRouter();
        if (flapSwapRouter != address(0)) {
            return PriceLibrary.getETHPriceFromRouter(flapSwapRouter, auth.getWBNB(), auth.getUSDT());
        }
        
        return 0;
    }
    
    /**
     * @dev 从特定DEX Router获取代币价格
     * @param router DEX路由地址
     * @return 代币价格（USD，精度18位），获取失败返回0
     */
    function _getPriceFromRouter(address router) internal view returns (uint256) {
        if (router == address(0) || tokenContract == address(0)) {
            return 0;
        }
        
        IAuthorizer auth = IAuthorizer(authorizer);
        return PriceLibrary.getPriceFromRouter(router, tokenContract, auth.getWBNB(), auth.getUSDT());
    }
    
    /**
     * @dev 公开函数：获取所有DEX的价格（供前端展示）
     * @return prices 价格数组（索引0=FlapSwap, 1=PancakeSwap, 2=Uniswap）
     * @return lowestPrice 最低价格
     * @return bestDEX 最佳DEX索引
     */
    function getAllDEXPrices() external view returns (uint256[] memory prices, uint256 lowestPrice, uint8 bestDEX) {
        prices = _getAllDEXPrices();
        lowestPrice = 0;
        bestDEX = 0;
        
        for (uint8 i = 0; i < 3; i++) {
            if (prices[i] > 0) {
                if (lowestPrice == 0 || prices[i] < lowestPrice) {
                    lowestPrice = prices[i];
                    bestDEX = i;
                }
            }
        }
        
        // 也检查PriceOracle
        if (priceOracle != address(0)) {
            try IPriceOracle(priceOracle).getTokenPrice() returns (uint256 oraclePrice) {
                if (oraclePrice > 0 && oraclePrice < lowestPrice) {
                    lowestPrice = oraclePrice;
                    bestDEX = 255; // 特殊值表示来自PriceOracle
                }
            } catch {}
        }
    }

    /**
     * @dev NFT销毁事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param owner 持有者地址
     */
    event CardBurned(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner);
    
    /**
     * @dev NFT升级事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     * @param owner 持有者地址
     * @param timestamp 时间戳
     */
    event CardUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);
    
    /**
     * @dev 权重更新失败事件（用于追踪和手动修复）
     * @param user 用户地址
     * @param tokenId NFT ID
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     * @param failureType 失败类型（old_weight/new_weight）
     */
    event WeightUpdateFailed(address indexed user, uint256 indexed tokenId, uint8 oldLevel, uint8 newLevel, string failureType);
    
    /**
     * @dev 使用代币升级事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     * @param tokensBurned 销毁代币数量
     * @param owner 持有者地址
     * @param timestamp 时间戳
     */
    event TokenUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, uint256 tokensBurned, address indexed owner, uint64 timestamp);
    
    /**
     * @dev 使用USD价值升级事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     * @param usdValue USD价值
     * @param tokensBurned 销毁代币数量
     * @param tokenPrice 代币价格
     * @param owner 持有者地址
     * @param timestamp 时间戳
     */
    event USDValueUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, uint256 usdValue, uint256 tokensBurned, uint256 tokenPrice, address indexed owner, uint64 timestamp);
    
    /**
     * @dev 价格更新事件
     * @param price 价格
     * @param timestamp 时间戳
     */
    event PriceUpdated(uint256 price, uint256 timestamp);
    
    /**
     * @dev USD价值升级方式显示/隐藏状态变更事件
     * @param hidden 是否隐藏
     */
    event USDUpgradeHiddenChanged(bool hidden);
    
    /**
     * @dev USD价值升级费用变更事件
     * @param level 等级（1-4）
     * @param cost 新的USDT费用（精度18位）
     */
    event USDUpgradeCostChanged(uint8 level, uint256 cost);
    
    /**
     * @dev 紧急提取BNB（仅限合约所有者）
     * @param amount 提取金额
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTUpdate: Amount must be > 0");
        require(amount <= address(this).balance, "NFTUpdate: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "NFTUpdate: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币（仅限合约所有者）
     * @param amount 提取金额
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTUpdate: Amount must be > 0");
        require(tokenContract != address(0), "NFTUpdate: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "NFTUpdate: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}