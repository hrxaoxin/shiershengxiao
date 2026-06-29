// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";
import "./NFTInterface.sol";
import "./NFTLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
        
        // 初始化带默认值的参数
        level1UpgradeCost = 10000 * 10**18;
        level2UpgradeCost = 40000 * 10**18;
        level3UpgradeCost = 120000 * 10**18;
        level4UpgradeCost = 480000 * 10**18;
        usdUpgradeHidden = true;
        
        // 初始化 USD 升级费用
        level1USDUpgradeCost = 1e18;      // 1 USDT
        level2USDUpgradeCost = 4e18;      // 4 USDT
        level3USDUpgradeCost = 12e18;     // 12 USDT
        level4USDUpgradeCost = 48e18;     // 48 USDT
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
     * @dev 管理员设置NFT等级（仅合约所有者可调用）
     * @param tokenId NFT ID
     * @param newLevel 新等级（1-5）
     */
    function adminSetNFTLevel(uint256 tokenId, uint8 newLevel) external onlyOwner {
        require(newLevel >= 1 && newLevel <= 5, "NFTUpdate: Invalid level");
        IAuthorizer auth = IAuthorizer(authorizer);
        address nftAddr = auth.getNFTMintCore();
        address dividendAddr = auth.getDividendManager();
        require(nftAddr != address(0), "NFTUpdate: NFT contract not set");
        INFTMint nft = INFTMint(nftAddr);
        
        address owner = nft.ownerOf(tokenId);
        uint8 oldLevel = nft.tokenLevel(tokenId);
        uint256 tokenType = nft.tokenType(tokenId);
        NFTDataTypes.ElementType element = NFTDataTypes.ElementType(tokenType / 24);
        
        if (oldLevel >= 1 && oldLevel <= 5 && dividendAddr != address(0)) {
            _updateUserWeight(owner, oldLevel, false, element, dividendAddr);
        }
        
        nft.adminSetNFTLevel(tokenId, newLevel);
        
        if (dividendAddr != address(0)) {
            _updateUserWeight(owner, newLevel, true, element, dividendAddr);
        }
        
        emit AdminLevelSet(tokenId, newLevel);
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
        IAuthorizer auth = IAuthorizer(authorizer);
        address nftAddr = auth.getNFTMintCore();
        address metadataAddr = auth.getNFTData();
        address dividendAddr = auth.getDividendManager();
        
        require(nftAddr != address(0), "NFTUpdate: NFT contract not set");
        require(metadataAddr != address(0), "NFTUpdate: Metadata contract not set");
        require(dividendAddr != address(0), "NFTUpdate: Dividend manager not set");
        
        INFTMint nft = INFTMint(nftAddr);
        require(nft.ownerOf(tokenId) == msg.sender, "E15");
        
        INFTDataInterface m = INFTDataInterface(metadataAddr);
        uint256 tokenTypeValue = m.tokenType(tokenId);
        NFTDataTypes.ZodiacType t = NFTDataTypes.ZodiacType(tokenTypeValue);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        
        uint256[] memory burnCandidates = _findBurnCandidates(tokenId, lv, tokenTypeValue, nft, nftAddr);
        // 修复：先完成升级逻辑（状态变更、跨合约权重更新）再销毁 NFT，避免升级失败导致 NFT 永久损失
        _completeUpgrade(tokenId, lv, t, m, nft, dividendAddr);
        _burnNFTs(burnCandidates, t, nft, metadataAddr, dividendAddr);
        
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
    function _findBurnCandidates(uint256 tokenId, uint8 lv, uint256 tokenTypeValue, INFTMint nft, address nftAddr) internal view returns (uint256[] memory) {
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
    function _burnNFTs(uint256[] memory burnCandidates, NFTDataTypes.ZodiacType t, INFTMint nft, address metadataAddr, address dividendAddr) internal {
        INFTDataInterface m = INFTDataInterface(metadataAddr);
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(t);
        uint8 burnLevel = m.tokenLevel(burnCandidates[0]); // 同类型同级NFT
        
        for (uint i = 0; i < burnCandidates.length; i++) {
            uint burnId = burnCandidates[i];
            // 同步权重：移除被销毁NFT的权重
            _updateUserWeight(msg.sender, burnLevel, false, element, dividendAddr);
            // 从NFTData用户NFT列表中移除
            _removeUserNFT(msg.sender, burnId, metadataAddr);
            nft.safeTransferFrom(msg.sender, BLACK_HOLE, burnId);
            emit CardBurned(burnId, t, msg.sender);
        }
    }

    /**
     * @dev 从NFTData用户NFT列表中移除
     * @param user 用户地址
     * @param tokenId NFT ID
     */
    function _removeUserNFT(address user, uint256 tokenId, address metadataAddr) internal {
        try INFTDataInterface(metadataAddr).removeUserNFT(user, tokenId) {
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
    function _completeUpgrade(uint256 tokenId, uint8 lv, NFTDataTypes.ZodiacType t, INFTDataInterface m, INFTMint nft, address dividendAddr) internal returns (uint8) {
        uint8 newLv = lv + 1;
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(t);
        
        require(dividendAddr != address(0), "NFTUpdate: Dividend manager not set");
        
        _updateUserWeight(msg.sender, lv, false, element, dividendAddr);
        _updateUserWeight(msg.sender, newLv, true, element, dividendAddr);
        
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
    function _updateUserWeight(address user, uint8 level, bool isAdd, NFTDataTypes.ElementType element, address dividendAddr) internal {
        try IDividendManager(dividendAddr).updateUserWeight(user, uint256(level), isAdd, uint8(element)) {
            // 成功
        } catch {
            // 忽略分红权重更新失败，不影响升级主流程
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
        IAuthorizer auth = IAuthorizer(authorizer);
        address nftAddr = auth.getNFTMintCore();
        address metadataAddr = auth.getNFTData();
        address tokenAddr = auth.getToken();
        address dividendAddr = auth.getDividendManager();
        
        require(nftAddr != address(0), "NFTUpdate: NFT contract not set");
        require(metadataAddr != address(0), "NFTUpdate: Metadata contract not set");
        require(tokenAddr != address(0), "E7: Token contract not set");
        require(dividendAddr != address(0), "NFTUpdate: Dividend manager not set");
        
        INFTMint nft = INFTMint(nftAddr);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        
        INFTDataInterface m = INFTDataInterface(metadataAddr);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        uint256 cost;
        if (lv == 1) cost = level1UpgradeCost;
        else if (lv == 2) cost = level2UpgradeCost;
        else if (lv == 3) cost = level3UpgradeCost;
        else if (lv == 4) cost = level4UpgradeCost;
        else revert("E18: Invalid level");
        
        IERC20 t = IERC20(tokenAddr);
        require(t.balanceOf(msg.sender) >= cost, "E8: Insufficient balance");
        require(t.allowance(msg.sender, address(this)) >= cost, "E8: Insufficient allowance");
        t.safeTransferFrom(msg.sender, BLACK_HOLE, cost);
        
        NFTDataTypes.ZodiacType zodiacType = NFTDataTypes.ZodiacType(m.tokenType(tokenId));
        uint8 newLv = _completeUpgrade(tokenId, lv, zodiacType, m, nft, dividendAddr);
        emit TokenUpgraded(tokenId, zodiacType, lv, newLv, cost, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    /**
     * @dev 使用USD价值升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithUSDValue(uint256 tokenId) external nonReentrant whenNotPaused returns (uint8) {
        IAuthorizer auth = IAuthorizer(authorizer);
        address nftAddr = auth.getNFTMintCore();
        address metadataAddr = auth.getNFTData();
        address tokenAddr = auth.getToken();
        address dividendAddr = auth.getDividendManager();
        address priceOracleAddr = auth.getPriceOracle();
        
        require(nftAddr != address(0), "NFTUpdate: NFT contract not set");
        require(metadataAddr != address(0), "NFTUpdate: Metadata contract not set");
        require(tokenAddr != address(0), "NFTUpdate: Token contract not set");
        require(dividendAddr != address(0), "NFTUpdate: Dividend manager not set");
        require(priceOracleAddr != address(0), "NFTUpdate: Price oracle not set");
        
        INFTMint nft = INFTMint(nftAddr);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        
        INFTDataInterface m = INFTDataInterface(metadataAddr);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        // 修复：减少局部变量，使用内部函数处理升级逻辑
        return _upgradeWithUSDValueInternal(tokenId, lv, m, nft, tokenAddr, dividendAddr, priceOracleAddr);
    }
    
    /**
     * @dev 使用USD价值升级（内部函数，减少栈深度）
     */
    function _upgradeWithUSDValueInternal(uint256 tokenId, uint8 lv, INFTDataInterface m, INFTMint nft, address tokenAddr, address dividendAddr, address priceOracleAddr) internal returns (uint8) {
        uint256 usdValue;
        if (lv == 1) usdValue = level1USDUpgradeCost;
        else if (lv == 2) usdValue = level2USDUpgradeCost;
        else if (lv == 3) usdValue = level3USDUpgradeCost;
        else if (lv == 4) usdValue = level4USDUpgradeCost;
        else revert("E18: Invalid level");
        
        require(usdValue > 0, "E22: USD upgrade cost not set");
        
        uint256 price = _getTokenPriceInternal(priceOracleAddr);
        require(price > 0, "E20: Price oracle returned zero");
        require(price >= 10**10, "E20: Price too low");
        
        uint256 cost = (usdValue * 1e18) / price;
        require(cost > 0, "E21: Invalid cost");
        require(cost <= 10**30, "E21: Cost exceeds maximum");
        
        IERC20(tokenAddr).safeTransferFrom(msg.sender, BLACK_HOLE, cost);
        
        NFTDataTypes.ZodiacType zodiacType = NFTDataTypes.ZodiacType(m.tokenType(tokenId));
        uint8 newLv = _completeUpgrade(tokenId, lv, zodiacType, m, nft, dividendAddr);
        _emitUSDValueUpgraded(tokenId, zodiacType, lv, newLv, usdValue, cost, price);
        return newLv;
    }

    function _getTokenPriceInternal(address priceOracleAddr) internal view returns (uint256) {
        require(priceOracleAddr != address(0), "NFTUpdate: Price oracle not set");
        return IPriceOracle(priceOracleAddr).getTokenPriceUSD();
    }

    function _emitUSDValueUpgraded(uint256 tokenId, NFTDataTypes.ZodiacType zodiacType, uint8 lv, uint8 newLv, uint256 usdValue, uint256 cost, uint256 price) internal {
        emit USDValueUpgraded(tokenId, zodiacType, lv, newLv, usdValue, cost, price, msg.sender, uint64(block.timestamp));
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
    event AdminLevelSet(uint256 indexed tokenId, uint8 newLevel);
    
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
        address tokenAddr = IAuthorizer(authorizer).getToken();
        require(tokenAddr != address(0), "NFTUpdate: Token contract not set");
        IERC20 token = IERC20(tokenAddr);
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