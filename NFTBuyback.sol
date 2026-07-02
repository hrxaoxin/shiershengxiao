// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入NFT接口
import "./NFTInterface.sol";
// 导入ERC20接口和安全转账工具
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
// 导入可升级合约相关依赖
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title NFTBuyback - NFT回购销毁合约
 * @dev 实现三种回购方式：
 *      1. 成长价回购：根据NFT等级和持有时间动态计算回购价格（需开启growthBuybackOpen）
 *      2. 固定价回购：管理员设置固定回购价格，用户按固定价格出售（需开启fixedBuybackOpen）
 *      3. 余额比例回购：根据合约代币余额与NFT总供应量计算单张NFT回购价格（需开启balanceRatioBuybackOpen）
 * 
 * 回购价格规则：
 * - 1阶普通NFT：基础回购价为normalMintCost的10%，每日持有加成1%，持有90天回本，最高到成本的110%
 * - 1阶稀有NFT：基础回购价为rareMintCost的10%，每日持有加成1%，持有90天回本，最高到成本的110%
 * - 2阶NFT：基础回购价为(铸造成本+level1UpgradeCost)的15%，每日持有加成1%，持有85天回本，最高到成本的110%
 * - 3阶NFT：基础回购价为(铸造成本+level1UpgradeCost+level2UpgradeCost)的20%，每日持有加成1%，持有80天回本，最高到成本的110%
 * - 4阶NFT：基础回购价为(铸造成本+level1UpgradeCost+level2UpgradeCost+level3UpgradeCost)的25%，每日持有加成1%，持有75天回本，最高到成本的110%
 * - 5阶NFT：基础回购价为(铸造成本+level1UpgradeCost+level2UpgradeCost+level3UpgradeCost+level4UpgradeCost)的30%，每日持有加成1%，持有70天回本，最高到成本的110%
 */
contract NFTBuyback is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 构造函数，禁用初始化器以确保合约只能通过代理部署
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 黑洞地址，用于销毁NFT
     */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /**
     * @dev 合约暂停状态
     */
    bool public paused;
    
    /**
     * @dev 暂停原因
     */
    string public pauseReason;

    /**
     * @dev 暂停事件
     * @param account 执行暂停操作的账户
     * @param reason 暂停原因
     */
    event Paused(address account, string reason);
    
    /**
     * @dev 取消暂停事件
     * @param account 执行取消暂停操作的账户
     */
    event Unpaused(address account);

    /**
     * @dev 修饰器：合约未暂停时才能执行
     */
    modifier whenNotPaused() {
        require(!paused, "NFTBuyback: Paused");
        _;
    }

    /**
     * @dev 暂停合约
     * @param reason 暂停原因
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消暂停合约
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 授权者地址（可与所有者共同管理合约）- 通过此地址获取所有关联合约地址
     */
    address public authorizer;
    
    /**
     * @dev 纪元版本号，用于快速重置合约数据
     */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;

    /**
     * @dev 最高回购倍率（默认110，表示最高回购价为成本的110%）
     */
    uint256 public maxBuybackMultiplier = 110;
    
    /**
     * @dev 固定回购价格
     */
    uint256 public fixedBuybackPrice;
    
    /**
     * @dev 固定回购是否开启
     */
    bool public fixedBuybackOpen = false;
    
    /**
     * @dev 成长价回购是否开启
     */
    bool public growthBuybackOpen = false;
    
    /**
     * @dev 余额比例回购是否开启
     */
    bool public balanceRatioBuybackOpen = false;
    
    /**
     * @dev 锁定的余额，用于防止竞态条件（多个用户同时回购时的资金锁定）
     */
    uint256 public lockedBalance;

    /**
     * @dev 获取最高加成百分比
     * @return 最高加成百分比（maxBuybackMultiplier - 100）
     */
    function maxBonusPercent() public view returns (uint256) {
        return maxBuybackMultiplier - 100;
    }

    /**
     * @dev 获取自动回购（固定价回购）是否开启
     * @return fixedBuybackOpen 固定回购开启状态
     */
    function autoBuybackOpen() public view returns (bool fixedBuybackOpen) {
        return fixedBuybackOpen;
    }

    /**
     * @dev 记录收到的代币（用于RewardManager等合约调用，通知回购池收到资金）
     * @param amount 收到的代币数量
     *
     * 说明：该函数不做任何状态变化，仅作为通知钩子。不设访问控制是因为
     * RewardManager 合约在 `_distributeReward` 中会主动调用它来传递资金，
     * 但那个时候 msg.sender 是 RewardManager 本身（而非 Authorizer）。
     */
    function recordIncomingTokens(uint256 amount) external {
        // 回购池收到代币后可直接用于回购销毁，无需额外记录
        // 合约余额会自动增加。保留参数以保持接口签名一致性。
        amount;
    }

    /**
     * @dev 修饰器：仅所有者或授权者可执行
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "NFTBuyback: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "NFTBuyback: Not authorized");
        _;
    }

    /**
     * @dev 初始化合约
     * @param _authorizerAddress 授权者地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "NFTBuyback: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        epoch = 1;
        
        maxBuybackMultiplier = 110;
        fixedBuybackOpen = false;
        growthBuybackOpen = false;
        balanceRatioBuybackOpen = false;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }

    /**
     * @dev UUPS升级授权（仅所有者可升级）
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "NFTBuyback: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置最高回购倍率
     * @param _multiplier 新的最高回购倍率（100-200）
     */
    function setMaxBuybackMultiplier(uint256 _multiplier) external onlyOwner {
        require(_multiplier >= 100, "NFTBuyback: Multiplier must be at least 100");
        require(_multiplier <= 200, "NFTBuyback: Multiplier cannot exceed 200");
        maxBuybackMultiplier = _multiplier;
        emit MaxBuybackMultiplierUpdated(_multiplier);
    }

    /**
     * @dev 设置固定回购价格
     * @param _price 固定回购价格（代币数量）
     */
    function setFixedBuybackPrice(uint256 _price) external onlyOwner {
        fixedBuybackPrice = _price;
        emit FixedBuybackPriceUpdated(_price);
    }

    /**
     * @dev 设置固定回购开关
     * @param _open 是否开启固定回购
     */
    function setFixedBuybackOpen(bool _open) external onlyOwner {
        fixedBuybackOpen = _open;
        emit FixedBuybackOpenUpdated(_open);
    }
    
    /**
     * @dev 设置成长价回购开关
     * @param _open 是否开启成长价回购
     */
    function setGrowthBuybackOpen(bool _open) external onlyOwner {
        growthBuybackOpen = _open;
        emit GrowthBuybackOpenUpdated(_open);
    }
    
    /**
     * @dev 设置余额比例回购开关
     * @param _open 是否开启余额比例回购
     */
    function setBalanceRatioBuybackOpen(bool _open) external onlyOwner {
        balanceRatioBuybackOpen = _open;
        emit BalanceRatioBuybackOpenUpdated(_open);
    }

    /**
     * @dev 获取NFT的总铸造成本（包括升级成本）
     * @param level NFT等级
     * @param isRare 是否稀有NFT
     * @return 总铸造成本
     */
    function getNFTMintCost(uint8 level, bool isRare) public view returns (uint256) {
        address tokenBurnerContract = IAuthorizer(authorizer).getAddressByName("tokenBurner");
        require(tokenBurnerContract != address(0), "NFTBuyback: Token burner not set");
        
        (uint256 normalCost, uint256 rareCost) = ITokenBurner(tokenBurnerContract).getAllCosts();
        uint256 baseCost = isRare ? rareCost : normalCost;

        if (level == 1) {
            return baseCost;
        }

        address nftUpdateContract = IAuthorizer(authorizer).getAddressByName("nftUpdate");
        uint256[4] memory upgradeCosts = INFTUpdate(nftUpdateContract).getAllLevelUpgradeCosts();
        uint256 level1Cost = upgradeCosts[0];
        uint256 level2Cost = upgradeCosts[1];
        uint256 level3Cost = upgradeCosts[2];
        uint256 level4Cost = upgradeCosts[3];

        // 累加对应等级的升级成本
        uint256 totalCost = baseCost;
        if (level >= 2) totalCost += level1Cost;
        if (level >= 3) totalCost += level2Cost;
        if (level >= 4) totalCost += level3Cost;
        if (level >= 5) totalCost += level4Cost;

        return totalCost;
    }

    /**
     * @dev 获取各等级的回购折扣率
     * @param level NFT等级
     * @return 回购折扣率（百分比）
     */
    function getBuybackDiscount(uint8 level) public pure returns (uint256) {
        if (level == 1) return 10;   // 1阶：10%
        if (level == 2) return 15;   // 2阶：15%
        if (level == 3) return 20;   // 3阶：20%
        if (level == 4) return 25;   // 4阶：25%
        if (level == 5) return 30;   // 5阶：30%
        revert("NFTBuyback: Invalid level");
    }

    /**
     * @dev 获取各等级回本所需天数
     * @param level NFT等级
     * @return 回本所需天数
     */
    function getDaysToBreakEven(uint8 level) public pure returns (uint256) {
        if (level == 1) return 90;   // 1阶：90天回本
        if (level == 2) return 85;   // 2阶：85天回本
        if (level == 3) return 80;   // 3阶：80天回本
        if (level == 4) return 75;   // 4阶：75天回本
        if (level == 5) return 70;   // 5阶：70天回本
        revert("NFTBuyback: Invalid level");
    }

    /**
     * @dev 计算成长回购价格（仅返回最终价格）
     * @param tokenId NFT ID
     * @return 最终回购价格
     */
    function calculateGrowthPrice(uint256 tokenId) public view returns (uint256) {
        address nftContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        uint8 level = nft.tokenLevel(tokenId);
        bool isRare = nft.isRare(tokenId);

        uint256 totalCost = getNFTMintCost(level, isRare);
        uint256 discount = getBuybackDiscount(level);
        uint256 basePrice = (totalCost * discount) / 100;

        uint256 mintTime = _getMintTime(tokenId);
        if (mintTime == 0) {
            return basePrice;
        }

        return _calculateGrowthWithBonus(mintTime, level, totalCost, discount, basePrice);
    }

    function _calculateGrowthWithBonus(
        uint256 mintTime,
        uint8 level,
        uint256 totalCost,
        uint256 discount,
        uint256 basePrice
    ) private view returns (uint256) {
        if (mintTime >= block.timestamp) {
            return basePrice;
        }
        uint256 holdingDays = (block.timestamp - mintTime) / 1 days;
        
        if (maxBuybackMultiplier <= 100 || discount >= 100) {
            return basePrice;
        }
        
        uint256 maxBonusDays = maxBuybackMultiplier - discount;
        uint256 bonusDays = holdingDays > maxBonusDays ? maxBonusDays : holdingDays;
        
        uint256 dailyBonus = (totalCost * 1) / 100;
        uint256 bonus = dailyBonus * bonusDays;

        uint256 finalPrice = basePrice + bonus;
        uint256 maxPrice = (totalCost * maxBuybackMultiplier) / 100;
        return finalPrice > maxPrice ? maxPrice : finalPrice;
    }

    /**
     * @dev 计算回购价格（返回详细信息）
     * @param tokenId NFT ID
     * @return basePrice 基础回购价
     * @return bonusPercent 持有加成百分比
     * @return finalPrice 最终回购价
     * @return daysToMax 达到最高回购价所需天数
     */
    function calculateBuybackPrice(uint256 tokenId) public view returns (uint256, uint256, uint256, uint256) {
        address nftContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        uint8 level = nft.tokenLevel(tokenId);
        bool isRare = nft.isRare(tokenId);

        uint256 totalCost = getNFTMintCost(level, isRare);
        uint256 discount = getBuybackDiscount(level);
        uint256 basePrice = (totalCost * discount) / 100;
        uint256 daysToBreakEven = getDaysToBreakEven(level);
        uint256 daysToMax = 0;
        if (maxBuybackMultiplier > 100 && discount < 100) {
            daysToMax = maxBuybackMultiplier - discount;
        }

        uint256 mintTime = _getMintTime(tokenId);

        if (mintTime == 0) {
            return (basePrice, 0, basePrice, daysToMax);
        }

        return _calculateWithBonus(mintTime, totalCost, discount, basePrice, daysToMax);
    }

    function _getMintTime(uint256 tokenId) private view returns (uint256) {
        address nftDataContract = IAuthorizer(authorizer).getAddressByName("nftData");
        if (nftDataContract == address(0)) {
            return 0;
        }
        try INFTData(nftDataContract).getNFTMintTime(tokenId) returns (uint256 m) {
            return m;
        } catch {
            return 0;
        }
    }

    /**
     * @dev 销毁NFT后同步权重
     * 在NFT被销毁前调用，更新用户的权重信息
     * @param user 用户地址
     * @param tokenId NFT ID
     */
    function _syncWeightAfterBurn(address user, uint256 tokenId) internal {
        address nftDataContract = IAuthorizer(authorizer).getAddressByName("nftData");
        address dividendManager = IAuthorizer(authorizer).getAddressByName("dividendManager");
        address weightManager = IAuthorizer(authorizer).getAddressByName("weightManager");
        
        // 移除用户NFT记录
        if (nftDataContract != address(0)) {
            try INFTDataInterface(nftDataContract).removeUserNFT(user, tokenId) {
                // 成功
            } catch {
                // 忽略错误
            }
        }
        
        // 同步用户权重 - DividendManager
        if (dividendManager != address(0)) {
            try IDividendManager(dividendManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略错误
            }
        }
        
        // 修复：同步用户权重 - WeightManager，确保权重数据一致性
        if (weightManager != address(0)) {
            try IWeightManager(weightManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略错误，不影响主流程
            }
        }
    }

    function _calculateWithBonus(
        uint256 mintTime,
        uint256 totalCost,
        uint256 discount,
        uint256 basePrice,
        uint256 daysToMax
    ) internal view returns (uint256, uint256, uint256, uint256) {
        if (mintTime >= block.timestamp || maxBuybackMultiplier <= 100 || discount >= 100) {
            return (basePrice, 0, basePrice, daysToMax);
        }
        
        uint256 maxBonusDays = maxBuybackMultiplier - discount;
        uint256 bonusDays = ((block.timestamp - mintTime) / 1 days);
        if (bonusDays > maxBonusDays) {
            bonusDays = maxBonusDays;
        }

        uint256 finalPrice = basePrice;
        if (bonusDays > 0) {
            finalPrice = basePrice + (totalCost * bonusDays) / 100;
        }
        
        uint256 maxPrice = (totalCost * maxBuybackMultiplier) / 100;
        if (finalPrice > maxPrice) {
            finalPrice = maxPrice;
        }

        return (basePrice, bonusDays, finalPrice, maxBonusDays);
    }

    /**
     * @dev 按成长价出售NFT
     * @param tokenId 要出售的NFT ID
     */
    function sellWithGrowthPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(growthBuybackOpen, "NFTBuyback: Growth buyback not open");
        address nftContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");

        uint256 buybackPrice = calculateGrowthPrice(tokenId);
        
        IERC20 token = IERC20(tokenContract);
        uint256 availableBalance = token.balanceOf(address(this)) - lockedBalance;
        require(availableBalance >= buybackPrice, "NFTBuyback: Insufficient contract balance");
        
        lockedBalance += buybackPrice;
        
        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        token.safeTransfer(msg.sender, buybackPrice);
        
        lockedBalance -= buybackPrice;
        
        _syncWeightAfterBurn(msg.sender, tokenId);

        emit NFTBurnedForBuyback(tokenId, msg.sender, buybackPrice, "growth");
    }

    /**
     * @dev 按固定价出售NFT
     * @param tokenId 要出售的NFT ID
     */
    function sellWithFixedPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(fixedBuybackOpen, "NFTBuyback: Fixed buyback not open");
        address nftContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");
        require(fixedBuybackPrice > 0, "NFTBuyback: Fixed price not set");

        IERC20 token = IERC20(tokenContract);
        uint256 availableBalance = token.balanceOf(address(this)) - lockedBalance;
        require(availableBalance >= fixedBuybackPrice, "NFTBuyback: Insufficient contract balance");
        
        lockedBalance += fixedBuybackPrice;
        
        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        token.safeTransfer(msg.sender, fixedBuybackPrice);
        
        lockedBalance -= fixedBuybackPrice;
        
        _syncWeightAfterBurn(msg.sender, tokenId);

        emit NFTBurnedForBuyback(tokenId, msg.sender, fixedBuybackPrice, "fixed");
    }
    
    /**
     * @dev 计算余额比例回购价格
     * @return 单张NFT的回购价格（合约余额/NFT总量）
     * @return 合约代币余额
     * @return NFT总供应量
     */
    function calculateBalanceRatioPrice(uint256 tokenId) public view returns (uint256, uint256, uint256) {
        address nftContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        address nftDataContract = IAuthorizer(authorizer).getAddressByName("nftData");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");
        
        IERC20 token = IERC20(tokenContract);
        uint256 balance = token.balanceOf(address(this));
        
        INFTMint nft = INFTMint(nftContract);
        uint256 totalSupply = nft.totalSupply();
        
        require(totalSupply > 0, "NFTBuyback: No NFT exists");
        
        uint256 pricePerNFT = balance / totalSupply;
        
        uint256 nftWeight = 1;
        if (nftDataContract != address(0)) {
            try INFTData(nftDataContract).calcNFTWeight(tokenId) returns (uint256 w) {
                nftWeight = w > 0 ? w : 1;
            } catch {
            }
        }
        
        uint256 weightedPrice = pricePerNFT * nftWeight;
        
        return (weightedPrice, balance, totalSupply);
    }
    
    /**
     * @dev 按余额比例出售NFT
     * @param tokenId 要出售的NFT ID
     */
    function sellWithBalanceRatioPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(balanceRatioBuybackOpen, "NFTBuyback: Balance ratio buyback not open");
        address nftContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");
        
        (uint256 buybackPrice, , ) = calculateBalanceRatioPrice(tokenId);
        require(buybackPrice > 0, "NFTBuyback: Buyback price is zero");
        
        IERC20 token = IERC20(tokenContract);
        uint256 availableBalance = token.balanceOf(address(this)) - lockedBalance;
        require(availableBalance >= buybackPrice, "NFTBuyback: Insufficient contract balance");
        
        lockedBalance += buybackPrice;
        
        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        token.safeTransfer(msg.sender, buybackPrice);
        
        lockedBalance -= buybackPrice;
        
        _syncWeightAfterBurn(msg.sender, tokenId);
        
        emit NFTBurnedForBuyback(tokenId, msg.sender, buybackPrice, "balanceRatio");
    }

    /**
     * @dev 紧急提取代币（仅所有者可调用）
     * @param amount 提取数量
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTBuyback: Amount must be > 0");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "NFTBuyback: Insufficient balance");
        token.safeTransfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 最高回购倍率更新事件
     * @param newMultiplier 新的最高回购倍率
     */
    event MaxBuybackMultiplierUpdated(uint256 newMultiplier);
    
    /**
     * @dev 固定回购价格更新事件
     * @param newPrice 新的固定回购价格
     */
    event FixedBuybackPriceUpdated(uint256 newPrice);
    
    /**
     * @dev 固定回购开关更新事件
     * @param open 新的开关状态
     */
    event FixedBuybackOpenUpdated(bool open);
    
    /**
     * @dev 成长价回购开关更新事件
     * @param open 新的开关状态
     */
    event GrowthBuybackOpenUpdated(bool open);
    
    /**
     * @dev 余额比例回购开关更新事件
     * @param open 新的开关状态
     */
    event BalanceRatioBuybackOpenUpdated(bool open);
    
    /**
     * @dev NFT回购销毁事件
     * @param tokenId 销毁的NFT ID
     * @param seller 卖家地址
     * @param price 回购价格
     * @param mode 回购模式（growth/fixed）
     */
    event NFTBurnedForBuyback(uint256 indexed tokenId, address indexed seller, uint256 price, string mode);
    
    /**
     * @dev 紧急提取代币事件
     * @param operator 操作地址
     * @param to 接收地址
     * @param amount 提取数量
     */
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    /**
     * @dev 接收BNB并自动兑换为代币用于回购
     */
    receive() external payable {
        if (msg.value > 0) {
            _convertBNBToToken(msg.value);
        }
    }

    /**
     * @dev 记录收到的BNB并自动兑换为代币用于回购
     * @param amount 收到的BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        require(amount > 0, "NFTBuyback: Amount must be > 0");
        _convertBNBToToken(amount);
    }

    /**
     * @dev 内部函数：将BNB兑换为代币
     * 通过PancakeSwap路由将BNB兑换为游戏代币
     * @param bnbAmount 要兑换的BNB数量
     */
    function _convertBNBToToken(uint256 bnbAmount) internal {
        address token = IAuthorizer(authorizer).getAddressByName("token");
        address wbnb = IAuthorizer(authorizer).getAddressByName("wbnb");
        address router = IAuthorizer(authorizer).getAddressByName("pancakeSwapRouter");
        
        require(token != address(0) && wbnb != address(0) && router != address(0), "NFTBuyback: Missing config");

        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = token;

        uint256[] memory amounts = IDexRouter(router).getAmountsOut(bnbAmount, path);
        uint256 expectedOut = amounts[1];
        uint256 minOut = expectedOut * 95 / 100;

        try IDexRouter(router).swapExactETHForTokens{value: bnbAmount}(
            minOut,
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory outputAmounts) {
            emit BNBConverted(bnbAmount, outputAmounts[1]);
        } catch {
            emit BNBConversionFailed(bnbAmount);
            (bool refundSuccess, ) = payable(msg.sender).call{value: bnbAmount}("");
            if (refundSuccess) {
                emit BNBRefunded(msg.sender, bnbAmount);
            }
        }
    }

    /**
     * @dev 紧急提取BNB（仅所有者可调用）
     * 用于在紧急情况下提取合约持有的BNB
     * @param amount 提取数量
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTBuyback: Amount must be > 0");
        require(amount <= address(this).balance, "NFTBuyback: Insufficient BNB");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "NFTBuyback: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取WBNB（仅所有者可调用）
     * 用于在紧急情况下提取合约持有的WBNB
     * @param amount 提取数量
     */
    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        address wbnb = IAuthorizer(authorizer).getAddressByName("wbnb");
        require(amount > 0, "NFTBuyback: Amount must be > 0");
        require(IWBNB(wbnb).balanceOf(address(this)) >= amount, "NFTBuyback: Insufficient WBNB");
        
        IWBNB(wbnb).withdraw(amount);
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "NFTBuyback: BNB transfer failed");
        emit EmergencyWBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 回退函数
     */
    fallback() external payable {}

    /**
     * @dev BNB兑换成功事件
     * @param bnbAmount 兑换的BNB数量
     * @param tokenAmount 获得的代币数量
     */
    event BNBConverted(uint256 bnbAmount, uint256 tokenAmount);
    
    /**
     * @dev BNB兑换失败事件
     * @param bnbAmount 尝试兑换的BNB数量
     */
    event BNBConversionFailed(uint256 bnbAmount);
    
    /**
     * @dev BNB退款事件
     * @param to 接收地址
     * @param amount 退款金额
     */
    event BNBRefunded(address indexed to, uint256 amount);
    
    /**
     * @dev 紧急提取BNB事件
     * @param operator 操作地址
     * @param to 接收地址
     * @param amount 提取数量
     */
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    
    /**
     * @dev 紧急提取WBNB事件
     * @param operator 操作地址
     * @param to 接收地址
     * @param amount 提取数量
     */
    event EmergencyWBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);

    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        
        paused = false;
        pauseReason = "";
        maxBuybackMultiplier = 110;
        fixedBuybackPrice = 0;
        fixedBuybackOpen = false;
        growthBuybackOpen = false;
        balanceRatioBuybackOpen = false;
        lockedBalance = 0;
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }

    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);
}