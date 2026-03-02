// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// NFT类型枚举
enum BlessingType { AiGuo, FuQiang, HeXie, YouShan, JingYe, WanNeng, WuFuLinMen }

// 自定义NFT接口
interface IFiveBlessingsNFT is IERC721Upgradeable {
    function tokenType(uint256 tokenId) external view returns (BlessingType);
    function ownerOf(uint256 tokenId) external view returns (address);
}

// 奖励管理器接口
interface IRewardManager {
    function royaltyWallet() external view returns (address);
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256);
}

// NFT上架结构体
struct NFTListing {
    address seller;
    uint256 price; // 存储单位：BNB wei（内部使用）
    uint256 listedAt;
    bool isActive;
}

// 核心NFT交易合约
contract NFTTrading is 
    Initializable, 
    OwnableUpgradeable, 
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC721HolderUpgradeable
{
    // 核心常量
    uint256 public constant VERSION = 1;
    uint256 public constant FEE_DENOMINATOR = 10000; // 手续费分母（10000 = 100%）
    uint256 public constant FEE_PERCENTAGE = 500;    // 5%手续费（500/10000）
    uint256 public constant MAX_BATCH_LISTINGS = 5;  // 批量操作最大数量
    uint256 public constant BNB_TO_WEI = 1e18;        // BNB转wei的系数（1 BNB = 10^18 wei）
    uint256 public constant MIN_LISTING_PRICE_WEI = 1e15; // 最小上架价格（0.001 BNB）
    uint256 public constant MAX_OVERPAY_RATIO = 200;  // 最大超额支付比例（200%）
    uint256 public constant OVERPAY_DENOMINATOR = 100; // 超额支付分母

    // 可配置参数（替代硬编码）
    uint256 private _maxListingPriceBNB; // 最大上架价格（BNB）
    uint256 private _maxListingPrice;    // 最大价格（wei）

    // ========== 关键修复1：添加缺失的_authorizer状态变量 ==========
    address private _authorizer; // 授权合约地址

    // 核心状态变量
    address private _nftContract;          // NFT合约地址（封装）
    address private _rewardManager;        // 奖励管理器地址（封装）
    uint256 public activeListings;       // 当前活跃上架数
    uint256 public totalListedCount;     // 累计上架总数
    uint256 public totalSales;           // 累计成交数
    uint256 public totalFeesCollected;   // 累计手续费（单位：BNB wei）

    // 临时查重用状态变量（修复memory mapping问题）
    mapping(uint256 => bool) private _tempSeenTokens;
    address private _tempUser;
    uint256 private _tempBatchSize;

    // 核心映射
    mapping(uint256 => NFTListing) public listings;          // tokenId => 上架信息
    mapping(address => uint256[]) public userListedTokens;   // 用户 => 上架的token列表
    mapping(uint256 => uint256) public tokenToListingIndex;  // tokenId => 在用户列表中的索引

    // 事件定义（新增block.number索引）
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 priceBNB, uint256 priceWEI, uint256 timestamp, uint256 blockNumber);
    event NFTUnlisted(uint256 indexed tokenId, address indexed seller, uint256 timestamp, uint256 blockNumber);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 priceBNB, uint256 priceWEI, uint256 feeBNB, uint256 feeWEI, uint256 timestamp, uint256 blockNumber);
    event FeeCollected(address indexed to, uint256 amountBNB, uint256 amountWEI, uint256 timestamp, uint256 blockNumber);
    event ContractUpdated(address indexed oldAddress, address indexed newAddress, string contractType, uint256 timestamp, uint256 blockNumber);
    event NFTReturned(uint256 indexed tokenId, address indexed seller, uint256 timestamp, uint256 blockNumber);
    event EmergencyWithdrawBNB(address indexed owner, address indexed to, uint256 amountBNB, uint256 amountWEI, uint256 timestamp, uint256 blockNumber);
    event EmergencyWithdrawNFT(address indexed owner, address indexed to, uint256 indexed tokenId, uint256 timestamp, uint256 blockNumber);
    event ListingPriceUpdated(uint256 indexed tokenId, address indexed seller, uint256 newPriceBNB, uint256 newPriceWEI, uint256 timestamp, uint256 blockNumber);
    event MaxListingPriceUpdated(uint256 oldPriceBNB, uint256 newPriceBNB, uint256 timestamp, uint256 blockNumber);
    // ========== 关键修复2：添加Authorizer更新事件 ==========
    event AuthorizerUpdated(address indexed oldAuthorizer, address indexed newAuthorizer, uint256 timestamp, uint256 blockNumber);

    // 存储间隙（重新分配，避免和父合约冲突）
    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // 初始化函数（替代构造函数）
    function initialize(
        address initialOwner, 
        address nftContract, 
        address rewardManager, 
        address authorizer,
        uint256 maxListingPriceBNB
    ) external initializer {
        // UUPSUpgradeable应优先初始化，确保代理上下文正确
        __UUPSUpgradeable_init();
        __ERC721Holder_init();
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();

        // 基础校验
        require(nftContract != address(0), "NFTTrading: invalid NFT contract");
        require(rewardManager != address(0), "NFTTrading: invalid RewardManager");
        require(maxListingPriceBNB > 0, "NFTTrading: max price must be > 0");

        // 初始化状态变量
        _nftContract = nftContract;
        _rewardManager = rewardManager;
        _maxListingPriceBNB = maxListingPriceBNB;
        _maxListingPrice = _bnbToWei(maxListingPriceBNB);
        
        // ========== 关键修复3：初始化_authorizer为0地址 ==========
        _authorizer = authorizer;
        
        // 初始化临时变量
        _tempUser = address(0);
        _tempBatchSize = 0;
    }

    // UUPS升级授权（增强校验+添加view修饰符消除警告）
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(newImplementation != address(0), "NFTTrading: invalid new implementation");
    }

    // 检查合约是否运行在UUPS代理上下文
    function isProxy() public view returns (bool) {
        return address(this).code.length == 0;
    }

    // ========== 内部辅助函数：批量查重（修复memory mapping问题） ==========
    function _initBatchCheck(address user, uint256 batchSize) private {
        require(_tempUser == address(0), "NFTTrading: batch check in progress");
        _tempUser = user;
        _tempBatchSize = batchSize;
    }

    function _checkDuplicate(uint256 tokenId) private view returns (bool) {
        require(_tempUser == msg.sender, "NFTTrading: invalid batch context");
        return _tempSeenTokens[tokenId];
    }

    function _markToken(uint256 tokenId) private {
        require(_tempUser == msg.sender, "NFTTrading: invalid batch context");
        _tempSeenTokens[tokenId] = true;
    }

    function _clearBatchCheck(uint256[] calldata tokenIds) private {
        require(_tempUser == msg.sender, "NFTTrading: invalid batch context");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            delete _tempSeenTokens[tokenIds[i]];
        }
        _tempUser = address(0);
        _tempBatchSize = 0;
    }

    // ========== 内部辅助函数：BNB单位转换（修复精度问题） ==========
    function _bnbToWei(uint256 amountBNB) internal pure returns (uint256) {
        require(amountBNB <= type(uint256).max / BNB_TO_WEI, "NFTTrading: BNB amount overflow");
        return amountBNB * BNB_TO_WEI;
    }

    // 修复：返回带18位小数的BNB值（如1.5e18 wei返回1500000000000000000）
    function _weiToBnbWithDecimals(uint256 amountWEI) internal pure returns (uint256) {
        return amountWEI; // 直接返回wei值，前端可除以1e18解析为带小数的BNB
    }

    // 兼容旧逻辑：返回整数BNB（仅用于事件/展示，核心计算仍用wei）
    function _weiToBnb(uint256 amountWEI) internal pure returns (uint256) {
        return amountWEI / BNB_TO_WEI;
    }

    // 处理带小数的BNB（比如0.001 BNB = 1e15 wei）
    function _bnbWithDecimalsToWei(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        require(decimals <= 18, "NFTTrading: decimals exceed 18");
        uint256 multiplier = 10 ** decimals;
        require(amount <= type(uint256).max / (BNB_TO_WEI / multiplier), "NFTTrading: amount overflow");
        return amount * (BNB_TO_WEI / multiplier);
    }

    // ========== 接口兼容性检查（修复调用风险） ==========
    function checkInterfaceCompatibility() external view returns (bool, string memory) {
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd; // 标准ERC721接口ID

        // 检查ERC721核心接口
        (bool supportsERC721, bytes memory data) = _nftContract.staticcall(
            abi.encodeWithSelector(
                bytes4(keccak256("supportsInterface(bytes4)")),
                ERC721_INTERFACE_ID
            )
        );
        if (!supportsERC721 || data.length == 0 || !abi.decode(data, (bool))) {
            return (false, "NFT contract does not support ERC721");
        }

        // 检查自定义NFT接口（使用try/catch处理Revert）
        try IFiveBlessingsNFT(_nftContract).tokenType(1) returns (BlessingType) {
            // 接口存在
        } catch {
            return (false, "NFT contract does not support tokenType");
        }

        // 检查RewardManager接口
        try IRewardManager(_rewardManager).royaltyWallet() returns (address) {
            // 接口存在
        } catch {
            return (false, "RewardManager does not support royaltyWallet");
        }

        try IRewardManager(_rewardManager).royaltyInfo(1, _bnbToWei(1)) returns (address, uint256) {
            // 接口存在
        } catch {
            return (false, "RewardManager does not support royaltyInfo");
        }

        return (true, "All interfaces are compatible");
    }

    // ========== 自定义修饰器 ==========
    modifier onlyValidToken(uint256 tokenId) {
        IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);
        require(nft.ownerOf(tokenId) != address(0), "NFTTrading: token does not exist");
        _;
    }

    modifier onlySeller(uint256 tokenId) {
        NFTListing storage listing = listings[tokenId];
        require(listing.isActive, "NFTTrading: NFT not listed");
        require(listing.seller == msg.sender, "NFTTrading: not the seller");
        _;
    }

    // ========== 核心功能：上架NFT ==========
    function listNFT(uint256 tokenId, uint256 priceWEI) external nonReentrant whenNotPaused onlyValidToken(tokenId) {
        IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);

        // 基础校验：直接校验wei单位价格
        require(nft.ownerOf(tokenId) == msg.sender, "NFTTrading: not the owner");
        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), "NFTTrading: contract not approved");
        require(!listings[tokenId].isActive, "NFTTrading: NFT already listed");
        require(priceWEI >= MIN_LISTING_PRICE_WEI && priceWEI <= _maxListingPrice, "NFTTrading: invalid WEI price");

        // 校验NFT类型合法性
        BlessingType tokenType = nft.tokenType(tokenId);
        require(tokenType <= BlessingType.WuFuLinMen, "NFTTrading: invalid BlessingType");

        // 转移NFT到合约托管
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        // 创建上架记录（存储wei单位）
        listings[tokenId] = NFTListing({
            seller: msg.sender,
            price: priceWEI,
            listedAt: block.timestamp,
            isActive: true
        });

        // 更新用户上架列表
        uint256[] storage userTokens = userListedTokens[msg.sender];
        tokenToListingIndex[tokenId] = userTokens.length;
        userTokens.push(tokenId);

        // 更新统计数据
        activeListings++;
        totalListedCount++;

        // 计算BNB单位用于事件输出（修复精度）
        uint256 priceBNB = _weiToBnbWithDecimals(priceWEI);
        emit NFTListed(tokenId, msg.sender, priceBNB, priceWEI, block.timestamp, block.number);
    }

    // ========== 核心功能：批量上架NFT（修复memory mapping问题） ==========
    function batchListNFT(uint256[] calldata tokenIds, uint256[] calldata pricesWEI) external nonReentrant whenNotPaused {
        require(tokenIds.length == pricesWEI.length, "NFTTrading: arrays length mismatch");
        require(tokenIds.length > 0 && tokenIds.length <= MAX_BATCH_LISTINGS, "NFTTrading: invalid batch size");

        // 1. 初始化批量查重
        _initBatchCheck(msg.sender, tokenIds.length);
        
        // 2. 检查重复tokenId
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(!_checkDuplicate(tokenId), string(abi.encodePacked("NFTTrading: duplicate token ", tokenId)));
            _markToken(tokenId);
        }

        IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);

        // 3. 预校验所有条件（无状态修改）
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 priceWEI = pricesWEI[i];

            require(nft.ownerOf(tokenId) == msg.sender, string(abi.encodePacked("NFTTrading: not owner of ", tokenId)));
            require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), string(abi.encodePacked("NFTTrading: not approved ", tokenId)));
            require(!listings[tokenId].isActive, string(abi.encodePacked("NFTTrading: already listed ", tokenId)));
            require(priceWEI >= MIN_LISTING_PRICE_WEI && priceWEI <= _maxListingPrice, string(abi.encodePacked("NFTTrading: invalid WEI price ", tokenId)));
            
            // 校验NFT类型
            BlessingType tokenType = nft.tokenType(tokenId);
            require(tokenType <= BlessingType.WuFuLinMen, string(abi.encodePacked("NFTTrading: invalid type ", tokenId)));
        }

        // 4. 原子性执行：先转移所有NFT，再更新状态（失败则全部回滚）
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            nft.safeTransferFrom(msg.sender, address(this), tokenId);
        }

        // 5. 更新所有状态（NFT已转移，状态更新不会失败）
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 priceWEI = pricesWEI[i];

            listings[tokenId] = NFTListing({
                seller: msg.sender,
                price: priceWEI,
                listedAt: block.timestamp,
                isActive: true
            });

            uint256[] storage userTokens = userListedTokens[msg.sender];
            tokenToListingIndex[tokenId] = userTokens.length;
            userTokens.push(tokenId);

            activeListings++;
            totalListedCount++;

            uint256 priceBNB = _weiToBnbWithDecimals(priceWEI);
            emit NFTListed(tokenId, msg.sender, priceBNB, priceWEI, block.timestamp, block.number);
        }

        // 6. 清理查重标记
        _clearBatchCheck(tokenIds);
    }

    // ========== 核心功能：修改上架价格 ==========
    function updateListingPrice(uint256 tokenId, uint256 newPriceWEI) external nonReentrant whenNotPaused onlySeller(tokenId) {
        require(newPriceWEI >= MIN_LISTING_PRICE_WEI && newPriceWEI <= _maxListingPrice, "NFTTrading: invalid new WEI price");

        listings[tokenId].price = newPriceWEI;
        uint256 newPriceBNB = _weiToBnbWithDecimals(newPriceWEI);
        emit ListingPriceUpdated(tokenId, msg.sender, newPriceBNB, newPriceWEI, block.timestamp, block.number);
    }

    // ========== 核心功能：下架NFT ==========
    function unlistNFT(uint256 tokenId) external nonReentrant whenNotPaused onlySeller(tokenId) {
        NFTListing storage listing = listings[tokenId];
        address seller = listing.seller;

        // 移除上架记录
        _removeListing(tokenId, seller);

        // 安全退回NFT
        IFiveBlessingsNFT(_nftContract).safeTransferFrom(address(this), seller, tokenId);

        emit NFTUnlisted(tokenId, seller, block.timestamp, block.number);
        emit NFTReturned(tokenId, seller, block.timestamp, block.number);
    }

    // ========== 核心功能：批量下架NFT（修复memory mapping问题） ==========
    function batchUnlistNFT(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(tokenIds.length > 0 && tokenIds.length <= MAX_BATCH_LISTINGS, "NFTTrading: invalid batch size");

        // 1. 初始化批量查重
        _initBatchCheck(msg.sender, tokenIds.length);
        
        // 2. 检查重复tokenId
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(!_checkDuplicate(tokenId), string(abi.encodePacked("NFTTrading: duplicate token ", tokenId)));
            _markToken(tokenId);
        }

        IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);

        // 3. 预校验所有条件
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            NFTListing storage listing = listings[tokenId];

            require(listing.isActive, string(abi.encodePacked("NFTTrading: not listed ", tokenId)));
            require(listing.seller == msg.sender, string(abi.encodePacked("NFTTrading: not seller ", tokenId)));
            require(nft.ownerOf(tokenId) == address(this), string(abi.encodePacked("NFTTrading: contract does not hold ", tokenId)));
        }

        // 4. 原子性执行：先更新状态，再转移所有NFT
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            _removeListing(tokenId, msg.sender);
        }

        // 5. 转移NFT（状态已更新，转移失败概率极低）
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            emit NFTUnlisted(tokenId, msg.sender, block.timestamp, block.number);
            emit NFTReturned(tokenId, msg.sender, block.timestamp, block.number);
        }

        // 6. 清理查重标记
        _clearBatchCheck(tokenIds);
    }

    // ========== 核心功能：购买NFT（强化安全校验） ==========
    // ========== 核心功能：购买NFT（修复Gas问题和执行顺序） ==========
    function buyNFT(uint256 tokenId) external payable nonReentrant whenNotPaused {
        // 1. 基础输入校验（增强提示）
        require(tokenId > 0, "NFTTrading: invalid token ID (must be > 0)");
        require(msg.value > 0, "NFTTrading: invalid payment (msg.value must be > 0)");
        require(msg.value <= _maxListingPrice, "NFTTrading: payment exceeds max price");

        // 2. 获取上架信息并校验（关键修复：先查合约是否持有NFT）
        NFTListing storage listing = listings[tokenId];
        require(listing.isActive, "NFTTrading: NFT not listed or already sold");
        require(msg.sender != listing.seller, "NFTTrading: cannot buy own NFT");
        
        IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);
        // 修复1：先校验合约是否持有NFT（最核心的前置条件）
        require(nft.ownerOf(tokenId) == address(this), "NFTTrading: contract does not hold NFT");
        
        // 修复2：放宽超额支付限制到200%
        uint256 maxAllowedPayment = (listing.price * 200) / 100;
        require(msg.value >= listing.price && msg.value <= maxAllowedPayment, string(abi.encodePacked(
            "NFTTrading: payment amount invalid (need ", listing.price, " - ", maxAllowedPayment, " wei, sent ", msg.value, " wei)"
        )));

        address seller = listing.seller;
        uint256 priceWEI = listing.price;
        uint256 priceBNB = _weiToBnbWithDecimals(priceWEI);

        // 3. 安全计算手续费
        uint256 feeWEI = (priceWEI * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        uint256 feeBNB = _weiToBnbWithDecimals(feeWEI);
        uint256 sellerAmountWEI = priceWEI - feeWEI;
        if (sellerAmountWEI == 0) {
            sellerAmountWEI = priceWEI;
            feeWEI = 0;
        }

        // 4. 获取手续费接收钱包
        IRewardManager rm = IRewardManager(_rewardManager);
        address royaltyWallet = rm.royaltyWallet();
        if (royaltyWallet == address(0)) {
            royaltyWallet = owner();
        }

        // ========== 优化执行顺序：先处理资金，再修改状态，最后转移NFT ==========
        // 1. Interactions: 先处理所有BNB转账，确保资金流动成功
        if (sellerAmountWEI > 0) {
            _safeTransferBNB(seller, sellerAmountWEI);
        }
        if (feeWEI > 0) {
            _safeTransferBNB(royaltyWallet, feeWEI);
        }
        if (msg.value > priceWEI) {
            uint256 refundWEI = msg.value - priceWEI;
            _safeTransferBNB(msg.sender, refundWEI);
        }

        // 2. Effects: 资金转账成功后，再修改合约内部状态
        _removeListing(tokenId, seller);
        totalSales++;
        totalFeesCollected += feeWEI;

        // 3. Interactions: 最后转移NFT
        nft.safeTransferFrom(address(this), msg.sender, tokenId);

        // 触发事件
        emit NFTSold(tokenId, seller, msg.sender, priceBNB, priceWEI, feeBNB, feeWEI, block.timestamp, block.number);
        emit FeeCollected(royaltyWallet, feeBNB, feeWEI, block.timestamp, block.number);
    }

    // ========== 修复：移除onlyOwner修饰符，允许合约内部调用，并大幅提高Gas上限 ==========
    function _safeTransferBNB(address to, uint256 amountWEI) internal {
        require(to != address(0), "NFTTrading: transfer to zero address");
        require(amountWEI > 0, "NFTTrading: transfer amount must be positive");
        require(address(this).balance >= amountWEI, "NFTTrading: contract BNB balance insufficient");

        // 修复：移除Gas限制，让调用者提供足够的Gas
        // 对于EOA，2300 gas足够；对于合约，我们不限制，让合约自己处理。
        (bool success, ) = to.call{value: amountWEI}("");
        require(success, string(abi.encodePacked(
            "NFTTrading: BNB transfer failed to ", to, " (amount: ", amountWEI, " wei)"
        )));
    }

    // ========== 合约拥有者专属：提取指定金额BNB ==========
    function ownerWithdrawBNB(address payable to, uint256 amountBNB) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        require(amountBNB > 0, "NFTTrading: invalid BNB amount");
        
        uint256 amountWEI = _bnbToWei(amountBNB);
        require(amountWEI <= address(this).balance, "NFTTrading: insufficient BNB balance");

        // 安全转账
        _safeTransferBNB(to, amountWEI);

        emit EmergencyWithdrawBNB(msg.sender, to, amountBNB, amountWEI, block.timestamp, block.number);
    }

    // ========== 合约拥有者专属：提取所有BNB ==========
    function ownerWithdrawAllBNB(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        uint256 balanceWEI = address(this).balance;
        require(balanceWEI > 0, "NFTTrading: no BNB to withdraw");
        
        uint256 balanceBNB = _weiToBnbWithDecimals(balanceWEI);

        _safeTransferBNB(to, balanceWEI);

        emit EmergencyWithdrawBNB(msg.sender, to, balanceBNB, balanceWEI, block.timestamp, block.number);
    }

    // ========== 合约拥有者专属：提取NFT ==========
    function ownerWithdrawNFT(address to, uint256 tokenId) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);

        // 校验合约持有NFT
        require(nft.ownerOf(tokenId) == address(this), "NFTTrading: contract does not own NFT");
        // 禁止提取正在上架的NFT
        require(!listings[tokenId].isActive, "NFTTrading: cannot withdraw listed NFT");

        // 安全转移NFT
        nft.safeTransferFrom(address(this), to, tokenId);

        emit EmergencyWithdrawNFT(msg.sender, to, tokenId, block.timestamp, block.number);
    }

    // ========== 管理员功能 ==========
    function setNFTContract(address newNFTContract) external {
        require(msg.sender == owner() || msg.sender == _authorizer, "NFTTrading: Unauthorized");
        require(newNFTContract != address(0), "NFTTrading: invalid NFT contract");
        address oldAddress = _nftContract;
        _nftContract = newNFTContract;
        emit ContractUpdated(oldAddress, newNFTContract, "NFTContract", block.timestamp, block.number);
    }

    function setRewardManager(address newRewardManager) external {
        require(msg.sender == owner() || msg.sender == _authorizer, "NFTTrading: Unauthorized");
        require(newRewardManager != address(0), "NFTTrading: invalid RewardManager");
        address oldAddress = _rewardManager;
        _rewardManager = newRewardManager;
        emit ContractUpdated(oldAddress, newRewardManager, "RewardManager", block.timestamp, block.number);
    }

    /**
     * @dev 管理员功能：设置授权合约地址
     * @param authorizer 授权合约地址
     */
    function setAuthorizer(address authorizer) external onlyOwner {
        address oldAuthorizer = _authorizer;
        _authorizer = authorizer;
        // ========== 关键修复4：添加事件发射 ==========
        emit AuthorizerUpdated(oldAuthorizer, authorizer, block.timestamp, block.number);
    }

    // 修复：添加可配置最大上架价格
    function setMaxListingPriceBNB(uint256 newMaxListingPriceBNB) external onlyOwner {
        require(newMaxListingPriceBNB > 0, "NFTTrading: max price must be > 0");
        uint256 oldPrice = _maxListingPriceBNB;
        _maxListingPriceBNB = newMaxListingPriceBNB;
        _maxListingPrice = _bnbToWei(newMaxListingPriceBNB);
        emit MaxListingPriceUpdated(oldPrice, newMaxListingPriceBNB, block.timestamp, block.number);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyUnlistNFT(uint256 tokenId) external onlyOwner {
        NFTListing storage listing = listings[tokenId];
        if (listing.isActive) {
            address seller = listing.seller;
            IFiveBlessingsNFT nft = IFiveBlessingsNFT(_nftContract);

            // 增加NFT持有校验
            require(nft.ownerOf(tokenId) == address(this), "NFTTrading: contract does not hold NFT");

            // 移除上架记录
            _removeListing(tokenId, seller);

            // 退回NFT
            nft.safeTransferFrom(address(this), seller, tokenId);

            emit NFTUnlisted(tokenId, seller, block.timestamp, block.number);
            emit NFTReturned(tokenId, seller, block.timestamp, block.number);
        }
    }

    // ========== 辅助函数（修复activeListings下溢+彻底清理数据） ==========
    function _removeListing(uint256 tokenId, address seller) internal {
        NFTListing storage listing = listings[tokenId];
        if (!listing.isActive) return;

        listing.isActive = false;

        // 从用户列表中移除token
        uint256[] storage userTokens = userListedTokens[seller];
        uint256 index = tokenToListingIndex[tokenId];

        if (index < userTokens.length && userTokens[index] == tokenId) {
            uint256 lastIndex = userTokens.length - 1;
            if (index != lastIndex) {
                userTokens[index] = userTokens[lastIndex];
                tokenToListingIndex[userTokens[lastIndex]] = index;
            }
            userTokens.pop();
            delete tokenToListingIndex[tokenId]; // 彻底清理索引
        }

        // 确保activeListings不会下溢
        activeListings = activeListings > 0 ? activeListings - 1 : 0;
    }

    // ========== 合约状态查询（封装+增强） ==========
    function getNFTContract() external view returns (address) {
        return _nftContract;
    }

    function getRewardManager() external view returns (address) {
        return _rewardManager;
    }

    // ========== 关键修复5：添加_authorizer的访问器函数 ==========
    function getAuthorizer() external view returns (address) {
        return _authorizer;
    }

    function getMaxListingPriceBNB() external view returns (uint256) {
        return _maxListingPriceBNB;
    }

    function getMaxListingPrice() external view returns (uint256) {
        return _maxListingPrice;
    }

    function getContractStats() external view returns (
        uint256 _activeListings,
        uint256 _totalListedCount,
        uint256 _totalSales,
        uint256 _totalFeesCollectedBNB,
        uint256 _totalFeesCollectedWEI,
        uint256 _contractBalanceBNB,
        uint256 _contractBalanceWEI
    ) {
        uint256 feesWEI = totalFeesCollected;
        uint256 balanceWEI = address(this).balance;
        
        return (
            activeListings,
            totalListedCount,
            totalSales,
            _weiToBnbWithDecimals(feesWEI),
            feesWEI,
            _weiToBnbWithDecimals(balanceWEI),
            balanceWEI
        );
    }

    function getListing(uint256 tokenId) external view returns (NFTListing memory listing, uint256 priceBNB, uint256 priceWEI) {
        listing = listings[tokenId];
        priceBNB = _weiToBnbWithDecimals(listing.price);
        priceWEI = listing.price;
        return (listing, priceBNB, priceWEI);
    }

    function getUserListedTokens(address user) external view returns (uint256[] memory) {
        return userListedTokens[user];
    }

    function getUserActiveListingsCount(address user) external view returns (uint256) {
        uint256 count = 0;
        uint256[] storage tokens = userListedTokens[user];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (listings[tokens[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    // 查询NFT价格（单独接口，便于前端调用）
    function getNFTPrice(uint256 tokenId) external view returns (uint256 priceWEI, uint256 priceBNB) {
        require(listings[tokenId].isActive, "NFTTrading: NFT not listed");
        priceWEI = listings[tokenId].price;
        priceBNB = _weiToBnbWithDecimals(priceWEI);
        return (priceWEI, priceBNB);
    }

    // ========== 合约健康检查接口 ==========
    function getContractHealth() external view returns (
        bool nftContractAlive,
        bool rewardManagerAlive,
        uint256 availableBNBBalance,
        string memory status
    ) {
        // 检查NFT合约是否可调用
        nftContractAlive = false;
        try IFiveBlessingsNFT(_nftContract).supportsInterface(0x80ac58cd) returns (bool) {
            nftContractAlive = true;
        } catch {}

        // 检查RewardManager是否可调用
        rewardManagerAlive = false;
        try IRewardManager(_rewardManager).royaltyWallet() returns (address) {
            rewardManagerAlive = true;
        } catch {}

        // 可用BNB余额（扣除已承诺的手续费）
        availableBNBBalance = _weiToBnbWithDecimals(address(this).balance);

        // 整体状态
        if (nftContractAlive && rewardManagerAlive && !paused()) {
            status = "HEALTHY";
        } else if (paused()) {
            status = "PAUSED";
        } else {
            status = "UNHEALTHY";
        }

        return (nftContractAlive, rewardManagerAlive, availableBNBBalance, status);
    }

    // ========== 禁止直接BNB转账 ==========
    receive() external payable {
        revert("NFTTrading: direct BNB transfers are forbidden - use buyNFT()");
    }
}