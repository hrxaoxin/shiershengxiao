// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入NFT接口
import "./NFTInterface.sol";
// 导入ERC20接口和安全转账工具
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
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
     * @dev NFT合约地址
     */
    address public nftContract;
    
    /**
     * @dev 代币合约地址
     */
    address public tokenContract;
    
    /**
     * @dev TokenBurner合约地址（用于获取铸造成本）
     */
    address public tokenBurnerContract;
    
    /**
     * @dev NFTUpdate合约地址（用于获取升级成本）
     */
    address public nftUpdateContract;
    
    /**
     * @dev NFTData合约地址（用于读取NFT铸造时间，计算持有天数加成）
     */
    address public nftDataContract;
    
    /**
     * @dev 授权者地址（可与所有者共同管理合约）
     */
    address public authorizer;

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
     * @dev 获取最高加成百分比
     * @return 最高加成百分比（maxBuybackMultiplier - 100）
     */
    function maxBonusPercent() public view returns (uint256) {
        return maxBuybackMultiplier - 100;
    }

    /**
     * @dev 获取自动回购（固定价回购）是否开启
     * @return 固定回购开启状态
     */
    function autoBuybackOpen() public view returns (bool) {
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
        require(msg.sender == owner() || msg.sender == authorizer, "NFTBuyback: Not authorized");
        _;
    }

    /**
     * @dev 初始化合约
     * @param _nftContractAddress NFT合约地址
     * @param _tokenContractAddress 代币合约地址
     * @param _tokenBurnerContractAddress 代币销毁合约地址
     * @param _nftUpdateContractAddress NFT升级合约地址
     * @param _nftDataContractAddress NFT数据合约地址
     * @param _authorizerAddress 授权者地址
     */
    function initialize(address _nftContractAddress, address _tokenContractAddress, address _tokenBurnerContractAddress, address _nftUpdateContractAddress, address _nftDataContractAddress, address _authorizerAddress) external initializer {
        require(_nftContractAddress != address(0), "NFTBuyback: Invalid NFT contract address");
        require(_tokenContractAddress != address(0), "NFTBuyback: Invalid token contract address");
        require(_tokenBurnerContractAddress != address(0), "NFTBuyback: Invalid token burner address");
        require(_nftUpdateContractAddress != address(0), "NFTBuyback: Invalid NFT update address");
        require(_nftDataContractAddress != address(0), "NFTBuyback: Invalid NFT data address");
        require(_authorizerAddress != address(0), "NFTBuyback: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        nftContract = _nftContractAddress;
        tokenContract = _tokenContractAddress;
        tokenBurnerContract = _tokenBurnerContractAddress;
        nftUpdateContract = _nftUpdateContractAddress;
        nftDataContract = _nftDataContractAddress;
        authorizer = _authorizerAddress;
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
     * @dev 设置NFT合约地址
     * @param _nftContractAddress NFT合约地址
     */
    function setNFTContract(address _nftContractAddress) external onlyOwnerOrAuthorizer {
        require(_nftContractAddress != address(0), "NFTBuyback: Invalid NFT contract address");
        nftContract = _nftContractAddress;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContractAddress 代币合约地址
     */
    function setTokenContract(address _tokenContractAddress) external onlyOwnerOrAuthorizer {
        require(_tokenContractAddress != address(0), "NFTBuyback: Invalid token contract address");
        tokenContract = _tokenContractAddress;
    }

    /**
     * @dev 设置TokenBurner合约地址
     * @param _tokenBurnerContractAddress TokenBurner合约地址
     */
    function setTokenBurnerContract(address _tokenBurnerContractAddress) external onlyOwnerOrAuthorizer {
        require(_tokenBurnerContractAddress != address(0), "NFTBuyback: Invalid token burner address");
        tokenBurnerContract = _tokenBurnerContractAddress;
    }

    /**
     * @dev 设置NFTUpdate合约地址
     * @param _nftUpdateContractAddress NFTUpdate合约地址
     */
    function setNFTUpdateContract(address _nftUpdateContractAddress) external onlyOwnerOrAuthorizer {
        require(_nftUpdateContractAddress != address(0), "NFTBuyback: Invalid NFT update address");
        nftUpdateContract = _nftUpdateContractAddress;
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
        require(tokenBurnerContract != address(0), "NFTBuyback: Token burner not set");
        
        // 获取铸造成本
        (uint256 normalCost, uint256 rareCost) = ITokenBurner(tokenBurnerContract).getAllCosts();
        uint256 baseCost = isRare ? rareCost : normalCost;

        // 1阶只需铸造成本
        if (level == 1) {
            return baseCost;
        }

        // 获取升级成本
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
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        uint8 level = nft.tokenLevel(tokenId);
        bool isRare = nft.isRare(tokenId);

        // 计算基础回购价
        uint256 totalCost = getNFTMintCost(level, isRare);
        uint256 discount = getBuybackDiscount(level);
        uint256 basePrice = (totalCost * discount) / 100;

        // 从NFTData合约读取铸造时间（持有时间加成基于链上真实铸造时间，避免需要手动同步）
        uint256 mintTime = 0;
        if (nftDataContract != address(0)) {
            try INFTData(nftDataContract).getNFTMintTime(tokenId) returns (uint256 m) {
                mintTime = m;
            } catch {}
        }

        // 如果没有铸造时间记录，返回基础价格
        if (mintTime == 0) {
            return basePrice;
        }

        // 计算持有天数和加成
        uint256 holdingDays = (block.timestamp - mintTime) / 1 days;
        uint256 daysToBreakEven = getDaysToBreakEven(level);
        uint256 maxBonusDays = ((maxBuybackMultiplier - 100) * daysToBreakEven) / (100 - discount);

        // 计算实际加成天数（不超过最大加成天数）
        uint256 bonusDays = holdingDays > maxBonusDays ? maxBonusDays : holdingDays;
        uint256 bonus = (basePrice * bonusDays) / daysToBreakEven;

        // 计算最终价格（不超过最高价格）
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
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        uint8 level = nft.tokenLevel(tokenId);
        bool isRare = nft.isRare(tokenId);

        uint256 totalCost = getNFTMintCost(level, isRare);
        uint256 discount = getBuybackDiscount(level);
        uint256 basePrice = (totalCost * discount) / 100;
        uint256 daysToMax = getDaysToBreakEven(level);

        // 从NFTData合约读取铸造时间
        uint256 mintTime = 0;
        if (nftDataContract != address(0)) {
            try INFTData(nftDataContract).getNFTMintTime(tokenId) returns (uint256 m) {
                mintTime = m;
            } catch {}
        }

        if (mintTime == 0) {
            return (basePrice, 0, basePrice, daysToMax);
        }

        // 使用mintTime替代存储映射
        return _calculateWithBonus(mintTime, totalCost, discount, basePrice, daysToMax);
    }

    function _calculateWithBonus(
        uint256 mintTime,
        uint256 totalCost,
        uint256 discount,
        uint256 basePrice,
        uint256 daysToBreakEven
    ) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 bonusDays = ((block.timestamp - mintTime) / 1 days);
        {
            uint256 maxBonusDays = ((maxBuybackMultiplier - 100) * daysToBreakEven) / (100 - discount);
            if (bonusDays > maxBonusDays) {
                bonusDays = maxBonusDays;
            }
        }

        uint256 bonusPercent = (bonusDays * (100 - discount)) / daysToBreakEven;
        if (bonusPercent > (maxBuybackMultiplier - 100)) {
            bonusPercent = maxBuybackMultiplier - 100;
        }

        uint256 finalPrice = basePrice + ((basePrice * bonusDays) / daysToBreakEven);
        
        {
            uint256 maxPrice = (totalCost * maxBuybackMultiplier) / 100;
            if (finalPrice > maxPrice) {
                finalPrice = maxPrice;
            }
        }

        return (basePrice, bonusPercent, finalPrice, daysToBreakEven);
    }

    /**
     * @dev 按成长价出售NFT
     * @param tokenId 要出售的NFT ID
     */
    function sellWithGrowthPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(growthBuybackOpen, "NFTBuyback: Growth buyback not open");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");

        // 计算回购价格
        uint256 buybackPrice = calculateGrowthPrice(tokenId);
        
        // 检查合约余额
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= buybackPrice, "NFTBuyback: Insufficient contract balance");

        // 转移NFT到黑洞（销毁）
        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        // 转移代币给卖家
        token.safeTransfer(msg.sender, buybackPrice);

        emit NFTBurnedForBuyback(tokenId, msg.sender, buybackPrice, "growth");
    }

    /**
     * @dev 按固定价出售NFT
     * @param tokenId 要出售的NFT ID
     */
    function sellWithFixedPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(fixedBuybackOpen, "NFTBuyback: Fixed buyback not open");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");
        require(fixedBuybackPrice > 0, "NFTBuyback: Fixed price not set");

        // 检查合约余额
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= fixedBuybackPrice, "NFTBuyback: Insufficient contract balance");

        // 转移NFT到黑洞（销毁）
        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        // 转移代币给卖家
        token.safeTransfer(msg.sender, fixedBuybackPrice);

        emit NFTBurnedForBuyback(tokenId, msg.sender, fixedBuybackPrice, "fixed");
    }
    
    /**
     * @dev 计算余额比例回购价格
     * @return 单张NFT的回购价格（合约余额/NFT总量）
     * @return 合约代币余额
     * @return NFT总供应量
     */
    function calculateBalanceRatioPrice() public view returns (uint256, uint256, uint256) {
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");
        
        IERC20 token = IERC20(tokenContract);
        uint256 balance = token.balanceOf(address(this));
        
        INFTMint nft = INFTMint(nftContract);
        uint256 totalSupply = nft.totalSupply();
        
        require(totalSupply > 0, "NFTBuyback: No NFT exists");
        
        uint256 pricePerNFT = balance / totalSupply;
        
        return (pricePerNFT, balance, totalSupply);
    }
    
    /**
     * @dev 按余额比例出售NFT
     * @param tokenId 要出售的NFT ID
     */
    function sellWithBalanceRatioPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(balanceRatioBuybackOpen, "NFTBuyback: Balance ratio buyback not open");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");
        
        // 计算回购价格
        (uint256 buybackPrice, , ) = calculateBalanceRatioPrice();
        require(buybackPrice > 0, "NFTBuyback: Buyback price is zero");
        
        // 检查合约余额
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= buybackPrice, "NFTBuyback: Insufficient contract balance");
        
        // 转移NFT到黑洞（销毁）
        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        // 转移代币给卖家
        token.safeTransfer(msg.sender, buybackPrice);
        
        emit NFTBurnedForBuyback(tokenId, msg.sender, buybackPrice, "balanceRatio");
    }

    /**
     * @dev 设置NFTData合约地址（仅授权者可调用）
     * @param _nftDataContractAddress NFTData合约地址
     */
    function setNFTDataContract(address _nftDataContractAddress) external onlyOwnerOrAuthorizer {
        require(_nftDataContractAddress != address(0), "NFTBuyback: Invalid NFT data address");
        nftDataContract = _nftDataContractAddress;
    }

    /**
     * @dev 紧急提取代币（仅所有者可调用）
     * @param amount 提取数量
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTBuyback: Amount must be > 0");
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
     * @dev 接收ETH（保留以防意外发送）
     */
    receive() external payable {}
    
    /**
     * @dev 回退函数
     */
    fallback() external payable {}
}