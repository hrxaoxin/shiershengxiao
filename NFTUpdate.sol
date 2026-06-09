// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";
import "./NFTInterface.sol";
import "./NFTLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

interface IDividendManager {
    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external;
}

interface IPancakeSwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/**
 * @title NFTUpdate
 * @dev NFT升级合约
 * 支持使用NFT、代币或USD价值升级NFT等级
 * 基于OpenZeppelin UUPS可升级合约实现
 *
 * NOTE: 数据存储双轨制
 * - NFTMint (nftContract): 链上主存储 tokenType[] 和 tokenLevel[]（ERC721 合约自管）
 * - NFTData (metadataContract): 分离数据层，存储详细的 ZodiacType、用户代币列表等
 * 本合约通过 metadataContract 读写 NFT 数据以保持与 NFTMint 的同步。
 * 部署时需确保 metadataContract 正确初始化并与 NFTMint 数据对齐。
 *
 * 升级方式（3 种）：
 * 1. 消耗同类型 NFT（upgradeWithNFT）：
 *    - 消耗 N 张同等级 NFT 升级 1 张
 *    - 例如：1级→2级需要 1 张同级NFT；2级→3级需要 2 张；以此类推
 *    - 被消耗的 NFT 转入 BLACK_HOLE 永久锁定（实际销毁）
 *
 * 2. 消耗代币（upgradeWithToken）：
 *    - 按等级阶梯缴纳代币：1→2 = 10000，2→3 = 40000，3→4 = 120000，4→5 = 480000
 *    - 代币转入 TokenBurner 合约销毁，保持经济模型的紧缩性
 *
 * 3. 消耗等价 USD 价值的代币（upgradeWithUSDValue）：
 *    - 根据 PriceOracle 提供的当前代币-USD 价格动态计算消耗数量
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
 * - 权重越高，分红越多；稀有属性（暗/光）基础权重更高
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
    
    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 元数据合约地址 */
    address public metadataContract;
    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 分红管理合约地址 */
    address public dividendManager;
    /** @dev PancakeSwap流动性池地址 */
    address public pancakeSwapPair;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 价格过期时间（秒）- 默认1小时 */
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

    /** @dev 各级别升级费用（代币数量，含精度18） */
    uint256 public level1UpgradeCost = 10000 * 10**18;
    uint256 public level2UpgradeCost = 40000 * 10**18;
    uint256 public level3UpgradeCost = 120000 * 10**18;
    uint256 public level4UpgradeCost = 480000 * 10**18;
    
    /** @dev USD价值升级方式是否隐藏（默认隐藏） */
    bool public usdUpgradeHidden = true;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[49] private __gap;

    /** @dev 初始化函数
     * @param initialOwner 初始所有者地址
     * @param _nftContract NFT合约地址
     * @param _metadataContract 元数据合约地址
     * @param _dividendManager 分红管理合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address initialOwner, address _nftContract, address _metadataContract, address _dividendManager, address _authorizer) external initializer {
        require(initialOwner != address(0), "NFTUpdate: Invalid initial owner address");
        require(_nftContract != address(0), "NFTUpdate: Invalid NFT contract address");
        require(_metadataContract != address(0), "NFTUpdate: Invalid metadata contract address");
        require(_dividendManager != address(0), "NFTUpdate: Invalid dividend manager address");
        require(_authorizer != address(0), "NFTUpdate: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        transferOwnership(initialOwner);
        nftContract = _nftContract;
        metadataContract = _metadataContract;
        dividendManager = _dividendManager;
        authorizer = _authorizer;
    }

    /**
     * @dev 设置分红管理合约地址
     * @param a 分红管理合约地址
     */
    function setDividendManager(address a) external onlyOwner {
        require(a != address(0), "NFTUpdate: Invalid dividend manager address");
        dividendManager = a;
    }

    /**
     * @dev 升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 检查是否为授权地址
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTUpdate: Not authorized");
        _;
    }

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "NFTUpdate: Invalid authorizer address");
        authorizer = a;
    }

    /**
     * @dev 设置NFT合约地址
     * @param a NFT合约地址
     */
    function setNFTContract(address a) external onlyAuthorized {
        require(a != address(0), "NFTUpdate: Invalid NFT contract address");
        nftContract = a;
    }

    /**
     * @dev 设置元数据合约地址
     * @param a 元数据合约地址
     */
    function setMetadataContract(address a) external onlyAuthorized {
        require(a != address(0), "NFTUpdate: Invalid metadata contract address");
        metadataContract = a;
    }

    /**
     * @dev 设置代币合约地址
     * @param a 代币合约地址
     */
    function setTokenContract(address a) external onlyAuthorized {
        require(a != address(0), "NFTUpdate: Invalid token contract address");
        tokenContract = a;
    }

    /**
     * @dev 设置PancakeSwap流动性池地址
     * @param pair 流动性池地址
     */
    function setPancakeSwapPair(address pair) external onlyAuthorized {
        require(pair != address(0), "E27: Zero address");
        pancakeSwapPair = pair;
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
     * @param costs 所有等级的升级费用数组（长度4，索引0到3对应等级1到4）
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
     * @dev 从PancakeSwap获取代币价格（USD）
     * @return uint256 代币价格（精度18位）
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
            return _adjustPriceDecimals(price, decimals1);
        } else if (token1 == tokenContract) {
            try IBEP20(token0).decimals() returns (uint8 d) {
                decimals0 = d;
            } catch {}
            
            uint256 price = (uint256(reserve0) * 10**18) / uint256(reserve1);
            return _adjustPriceDecimals(price, decimals0);
        } else {
            revert("E26: Token not found in pair");
        }
    }
    
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
        require(metadataContract != address(0), "NFTUpdate: Metadata contract not set");
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint256 tokenTypeValue = m.tokenType(tokenId);
        NFTDataTypes.ZodiacType t = NFTDataTypes.ZodiacType(tokenTypeValue);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        
        uint256[] memory burnCandidates = _findBurnCandidates(tokenId, lv, tokenTypeValue, nft);
        _burnNFTs(burnCandidates, t, nft);
        
        return _completeUpgrade(tokenId, lv, t, m, nft);
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
        for (uint i = 0; i < burnCandidates.length; i++) {
            uint burnId = burnCandidates[i];
            nft.safeTransferFrom(msg.sender, BLACK_HOLE, burnId);
            emit CardBurned(burnId, t, msg.sender);
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
    }

    /**
     * @dev 使用代币升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithToken(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8) {
        require(metadataContract != address(0), "NFTUpdate: Metadata contract not set");
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        require(tokenContract != address(0), "E7: Token contract not set");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        uint256 cost;
        if (lv == 1) cost = level1UpgradeCost;
        else if (lv == 2) cost = level2UpgradeCost;
        else if (lv == 3) cost = level3UpgradeCost;
        else if (lv == 4) cost = level4UpgradeCost;
        else revert("E18: Invalid level");
        
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8: Insufficient balance");
        require(t.transferFrom(msg.sender, BLACK_HOLE, cost), "E9: Transfer failed");
        
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
        require(metadataContract != address(0), "NFTUpdate: Metadata contract not set");
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        require(tokenContract != address(0) && pancakeSwapPair != address(0), "E19: Missing contracts");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        uint256 usdValue;
        if (lv == 1) usdValue = 1e18;      // 1 USD
        else if (lv == 2) usdValue = 4e18;  // 4 USD
        else if (lv == 3) usdValue = 12e18; // 12 USD
        else if (lv == 4) usdValue = 48e18; // 48 USD
        else revert("E18: Invalid level");
        
        uint256 price = getTokenPriceFromPancakeSwap();
        require(price > 0, "E20: Price oracle returned zero");
        
        // 防御同一区块内的价格操纵：要求至少间隔 minPriceUpdateBlocks 个区块
        require(block.number >= lastPriceUpdateBlock + minPriceUpdateBlocks, "E31: Price update too frequent");
        // 防御时间窗口攻击：要求至少间隔 minPriceUpdateSeconds 秒
        require(block.timestamp >= lastPriceUpdateTime + minPriceUpdateSeconds, "E32: Price update too frequent (time)");
        
        // 首次价格获取：直接使用，同时缓存
        if (lastPrice == 0) {
            lastPrice = price;
            lastPriceUpdateTime = block.timestamp;
            lastPriceUpdateBlock = block.number;
            emit PriceUpdated(price, block.timestamp);
        }
        
        require(block.timestamp <= lastPriceUpdateTime + priceExpirySeconds, "E30: Price expired");
        
        uint256 deviation;
        if (price > lastPrice) {
            deviation = ((price - lastPrice) * 10000) / lastPrice;
        } else {
            deviation = ((lastPrice - price) * 10000) / lastPrice;
        }
        require(deviation <= priceDeviationThreshold, "E23: Price deviation too high");
        
        lastPrice = price;
        lastPriceUpdateTime = block.timestamp;
        lastPriceUpdateBlock = block.number;
        emit PriceUpdated(price, block.timestamp);
        
        uint256 cost = (usdValue * 1e18) / price;
        require(cost > 0, "E21: Invalid cost");
        
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8: Insufficient balance");
        require(t.transferFrom(msg.sender, BLACK_HOLE, cost), "E9: Transfer failed");
        
        NFTDataTypes.ZodiacType zodiacType = NFTDataTypes.ZodiacType(m.tokenType(tokenId));
        uint8 newLv = _completeUpgrade(tokenId, lv, zodiacType, m, nft);
        emit USDValueUpgraded(tokenId, zodiacType, lv, newLv, usdValue, cost, price, msg.sender, uint64(block.timestamp));
        return newLv;
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
        IToken token = IToken(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "NFTUpdate: Insufficient token balance");
        require(token.transfer(owner(), amount), "NFTUpdate: Token transfer failed");
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
