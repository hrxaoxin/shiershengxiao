// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/ERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/Counters.sol";

/**
 * @dev NFT上架结构体
 * @param seller 卖家地址
 * @param price 价格（单位：BNB wei，1 BNB = 10^18 wei）
 * @param listedAt 上架时间戳
 * @param isActive 是否活跃
 */
struct NFTListing {
    address seller;
    uint256 price; // 价格（单位：BNB wei，1 BNB = 10^18 wei）
    uint256 listedAt; // 上架时间戳
    bool isActive; // 是否活跃
}

/**
 * @title NFTTrading
 * @dev 核心NFT交易合约，支持NFT上架、购买、下架等功能
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract NFTTrading is 
    Initializable, 
    OwnableUpgradeable, 
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC721HolderUpgradeable
{
    // 核心常量
    /** @dev 合约版本号 */
    uint256 public constant VERSION = 1;
    /** @dev 手续费分母（10000 = 100%）*/
    uint256 public constant FEE_DENOMINATOR = 10000;
    /** @dev 5%手续费（500/10000）*/
    uint256 public constant FEE_PERCENTAGE = 500;
    /** @dev BNB转wei的系数（1 BNB = 10^18 wei）*/
    uint256 public constant BNB_TO_WEI = 1e18;
    /** @dev 最小上架价格（0.001 BNB）*/
    uint256 public constant MIN_LISTING_PRICE_WEI = 1e15;
    /** @dev 最大超额支付比例（200%）*/
    uint256 public constant MAX_OVERPAY_RATIO = 200;
    /** @dev 超额支付分母 */
    uint256 public constant OVERPAY_DENOMINATOR = 100;

    // 可配置参数（替代硬编码）
    /** @dev 最大上架价格（BNB）*/
    uint256 private _maxListingPriceBNB;
    /** @dev 最大价格（wei）*/
    uint256 private _maxListingPrice;

    // 关键状态变量
    /** @dev 授权合约地址 */
    address private _authorizer;
    /** @dev 手续费接收钱包地址 */
    address private _royaltyWallet;

    // 核心状态变量
    /** @dev NFT合约地址（封装）*/
    address private _nftContract;
    /** @dev 奖励管理器地址（封装）*/
    address private _rewardManager;
    /** @dev 当前活跃上架数 */
    uint256 public activeListings;
    /** @dev 累计上架总数 */
    uint256 public totalListedCount;
    /** @dev 累计成交数 */
    uint256 public totalSales;
    /** @dev 累计手续费（单位：BNB wei）*/
    uint256 public totalFeesCollected;

    // 核心映射
    /** @dev tokenId => 上架信息 */
    mapping(uint256 => NFTListing) public listings;
    /** @dev 用户 => 上架的token列表 */
    mapping(address => uint256[]) public userListedTokens;
    /** @dev tokenId => 在用户列表中的索引 */
    mapping(uint256 => uint256) public tokenToListingIndex;
    /** @dev 活跃上架列表（优化查询效率）*/
    uint256[] public activeListingIds;
    /** @dev tokenId => 在活跃列表中的索引 */
    mapping(uint256 => uint256) public tokenToActiveIndex;
    /** @dev 所有上架记录（包括已下架）*/
    uint256[] public allListingIds;
    /** @dev 累计超额支付金额（作为合约运营费用）*/
    uint256 public totalOverpaid;

    // 事件定义
    /**
     * @dev NFT上架事件
     * @param tokenId NFT ID
     * @param seller 卖家地址
     * @param priceBNB 价格（BNB）
     * @param priceWEI 价格（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 priceBNB, uint256 priceWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev NFT下架事件
     * @param tokenId NFT ID
     * @param seller 卖家地址
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event NFTUnlisted(uint256 indexed tokenId, address indexed seller, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev NFT成交事件
     * @param tokenId NFT ID
     * @param seller 卖家地址
     * @param buyer 买家地址
     * @param priceBNB 价格（BNB）
     * @param priceWEI 价格（wei）
     * @param feeBNB 手续费（BNB）
     * @param feeWEI 手续费（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 priceBNB, uint256 priceWEI, uint256 feeBNB, uint256 feeWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 手续费收取事件
     * @param to 接收地址
     * @param amountBNB 金额（BNB）
     * @param amountWEI 金额（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event FeeCollected(address indexed to, uint256 amountBNB, uint256 amountWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 合约地址更新事件
     * @param oldAddress 旧地址
     * @param newAddress 新地址
     * @param contractType 合约类型
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event ContractUpdated(address indexed oldAddress, address indexed newAddress, string contractType, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev NFT退回事件
     * @param tokenId NFT ID
     * @param seller 卖家地址
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event NFTReturned(uint256 indexed tokenId, address indexed seller, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev NFT转账失败事件（用于追踪失败的交易）
     * @param tokenId NFT ID
     * @param buyer 买家地址
     * @param originalSeller 原始卖家地址
     * @param priceWEI 价格（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event NFTTransferFailed(uint256 indexed tokenId, address indexed buyer, address indexed originalSeller, uint256 priceWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 紧急提取BNB事件
     * @param owner 所有者地址
     * @param to 接收地址
     * @param amountBNB 金额（BNB）
     * @param amountWEI 金额（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event EmergencyWithdrawBNB(address indexed owner, address indexed to, uint256 amountBNB, uint256 amountWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 紧急提取NFT事件
     * @param owner 所有者地址
     * @param to 接收地址
     * @param tokenId NFT ID
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event EmergencyWithdrawNFT(address indexed owner, address indexed to, uint256 indexed tokenId, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 上架价格更新事件
     * @param tokenId NFT ID
     * @param seller 卖家地址
     * @param newPriceBNB 新价格（BNB）
     * @param newPriceWEI 新价格（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event ListingPriceUpdated(uint256 indexed tokenId, address indexed seller, uint256 newPriceBNB, uint256 newPriceWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 最大上架价格更新事件
     * @param oldPriceBNB 旧价格（BNB）
     * @param newPriceBNB 新价格（BNB）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event MaxListingPriceUpdated(uint256 oldPriceBNB, uint256 newPriceBNB, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 授权合约更新事件
     * @param oldAuthorizer 旧授权合约地址
     * @param newAuthorizer 新授权合约地址
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event AuthorizerUpdated(address indexed oldAuthorizer, address indexed newAuthorizer, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 超额支付接收事件
     * @param user 用户地址
     * @param amountWEI 金额（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event OverpaidReceived(address indexed user, uint256 amountWEI, uint256 timestamp, uint256 blockNumber);
    
    /**
     * @dev 超额支付提取事件
     * @param owner 所有者地址
     * @param to 接收地址
     * @param amountWEI 金额（wei）
     * @param timestamp 时间戳
     * @param blockNumber 区块号
     */
    event OverpaidWithdrawn(address indexed owner, address indexed to, uint256 amountWEI, uint256 timestamp, uint256 blockNumber);

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数（替代构造函数）
     * @param nftContract NFT合约地址
     * @param rewardManager 奖励管理器地址
     * @param authorizer 授权合约地址
     * @param maxListingPriceBNB 最大上架价格（BNB）
     * @param royaltyWallet 手续费接收钱包地址
     */
    function initialize(
        address nftContract, 
        address rewardManager, 
        address authorizer,
        uint256 maxListingPriceBNB,
        address royaltyWallet
    ) external initializer {
        __UUPSUpgradeable_init();
        __ERC721Holder_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(nftContract != address(0), "NFTTrading: invalid NFT contract");
        require(rewardManager != address(0), "NFTTrading: invalid RewardManager");
        require(maxListingPriceBNB > 0, "NFTTrading: max price must be > 0");

        _nftContract = nftContract;
        _rewardManager = rewardManager;
        _maxListingPriceBNB = maxListingPriceBNB;
        _maxListingPrice = _bnbToWei(maxListingPriceBNB);
        _authorizer = authorizer;
        _royaltyWallet = royaltyWallet;
    }

    /**
     * @dev UUPS升级授权
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(newImplementation != address(0), "NFTTrading: invalid new implementation");
    }

    /**
     * @dev 检查合约是否运行在UUPS代理上下文
     * @return bool 是否在代理上下文
     */
    function isProxy() public view returns (bool) {
        return address(this).code.length == 0;
    }

    /**
     * @dev BNB转wei（内部辅助函数）
     * @param amountBNB BNB数量
     * @return uint256 wei数量
     */
    function _bnbToWei(uint256 amountBNB) internal pure returns (uint256) {
        require(amountBNB <= type(uint256).max / BNB_TO_WEI, "NFTTrading: BNB amount overflow");
        return amountBNB * BNB_TO_WEI;
    }

    /**
     * @dev wei转BNB（带小数精度）
     * @param amountWEI wei数量
     * @return uint256 BNB数量（18位小数）
     */
    function _weiToBnbWithDecimals(uint256 amountWEI) internal pure returns (uint256) {
        return amountWEI;
    }

    /**
     * @dev wei转BNB（整数）
     * @param amountWEI wei数量
     * @return uint256 BNB数量（整数）
     */
    function _weiToBnb(uint256 amountWEI) internal pure returns (uint256) {
        return amountWEI / BNB_TO_WEI;
    }

    /**
     * @dev 带小数的BNB转wei
     * @param amount 数量
     * @param decimals 小数位数
     * @return uint256 wei数量
     */
    function _bnbWithDecimalsToWei(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        require(decimals <= 18, "NFTTrading: decimals exceed 18");
        uint256 multiplier = 10 ** decimals;
        require(amount <= type(uint256).max / (BNB_TO_WEI / multiplier), "NFTTrading: amount overflow");
        return amount * (BNB_TO_WEI / multiplier);
    }

    /**
     * @dev 接口兼容性检查
     * @return bool 是否兼容
     * @return string 错误信息（如果不兼容）
     */
    function checkInterfaceCompatibility() external view returns (bool, string memory) {
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;

        (bool supportsERC721, bytes memory data) = _nftContract.staticcall(
            abi.encodeWithSelector(bytes4(keccak256("supportsInterface(bytes4)")), ERC721_INTERFACE_ID)
        );
        if (!supportsERC721 || data.length == 0 || !abi.decode(data, (bool))) {
            return (false, "NFT contract does not support ERC721");
        }

        try INFTMint(_nftContract).tokenType(1) returns (NFTDataTypes.ZodiacType) {
        } catch {
            return (false, "NFT contract does not support tokenType");
        }

        return (true, "All interfaces are compatible");
    }

    /**
     * @dev 有效Token校验修饰器
     * @param tokenId NFT ID
     */
    modifier onlyValidToken(uint256 tokenId) {
        INFTMint nft = INFTMint(_nftContract);
        require(nft.ownerOf(tokenId) != address(0), "NFTTrading: token does not exist");
        _;
    }

    /**
     * @dev 卖家校验修饰器
     * @param tokenId NFT ID
     */
    modifier onlySeller(uint256 tokenId) {
        NFTListing storage listing = listings[tokenId];
        require(listing.isActive, "NFTTrading: NFT not listed");
        require(listing.seller == msg.sender, "NFTTrading: not the seller");
        _;
    }

    /**
     * @dev 上架NFT
     * @param tokenId NFT ID
     * @param priceWEI 价格（wei）
     */
    function listNFT(uint256 tokenId, uint256 priceWEI) external nonReentrant whenNotPaused onlyValidToken(tokenId) {
        INFTMint nft = INFTMint(_nftContract);

        require(nft.ownerOf(tokenId) == msg.sender, "NFTTrading: not the owner");
        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), "NFTTrading: contract not approved");
        require(!listings[tokenId].isActive, "NFTTrading: NFT already listed");
        require(priceWEI >= MIN_LISTING_PRICE_WEI && priceWEI <= _maxListingPrice, "NFTTrading: invalid WEI price");

        NFTDataTypes.ZodiacType zodiacType = nft.tokenType(tokenId);
        require(uint256(zodiacType) < 120, "NFTTrading: invalid ZodiacType");

        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        listings[tokenId] = NFTListing({
            seller: msg.sender,
            price: priceWEI,
            listedAt: block.timestamp,
            isActive: true
        });

        uint256[] storage userTokens = userListedTokens[msg.sender];
        tokenToListingIndex[tokenId] = userTokens.length;
        userTokens.push(tokenId);

        tokenToActiveIndex[tokenId] = activeListingIds.length;
        activeListingIds.push(tokenId);
        
        allListingIds.push(tokenId);

        activeListings++;
        totalListedCount++;

        uint256 priceBNB = _weiToBnbWithDecimals(priceWEI);
        emit NFTListed(tokenId, msg.sender, priceBNB, priceWEI, block.timestamp, block.number);
    }

    /**
     * @dev 修改上架价格
     * @param tokenId NFT ID
     * @param newPriceWEI 新价格（wei）
     */
    function updateListingPrice(uint256 tokenId, uint256 newPriceWEI) external nonReentrant whenNotPaused onlySeller(tokenId) {
        require(newPriceWEI >= MIN_LISTING_PRICE_WEI && newPriceWEI <= _maxListingPrice, "NFTTrading: invalid new WEI price");

        listings[tokenId].price = newPriceWEI;
        uint256 newPriceBNB = _weiToBnbWithDecimals(newPriceWEI);
        emit ListingPriceUpdated(tokenId, msg.sender, newPriceBNB, newPriceWEI, block.timestamp, block.number);
    }

    /**
     * @dev 下架NFT
     * @param tokenId NFT ID
     */
    function unlistNFT(uint256 tokenId) external nonReentrant whenNotPaused onlySeller(tokenId) {
        NFTListing storage listing = listings[tokenId];
        address seller = listing.seller;

        _removeListing(tokenId, seller);

        INFTMint(_nftContract).safeTransferFrom(address(this), seller, tokenId);

        emit NFTUnlisted(tokenId, seller, block.timestamp, block.number);
        emit NFTReturned(tokenId, seller, block.timestamp, block.number);
    }

    /**
     * @dev 购买NFT（按照Checks-Effects-Interactions模式）
     * @param tokenId NFT ID
     */
    function buyNFT(uint256 tokenId) external payable nonReentrant whenNotPaused {
        require(tokenId > 0, "NFTTrading: invalid token ID (must be > 0)");
        require(msg.value > 0, "NFTTrading: payment must be greater than 0");
        require(msg.value <= _maxListingPrice, "NFTTrading: payment exceeds maximum allowed price");
        require(msg.value <= type(uint128).max, "NFTTrading: payment amount too large");

        NFTListing storage listing = listings[tokenId];
        require(listing.isActive, "NFTTrading: NFT not listed or already sold");
        require(listing.price > 0, "NFTTrading: listing price is zero");
        require(msg.sender != listing.seller, "NFTTrading: cannot purchase your own NFT");
        
        INFTMint nft = INFTMint(_nftContract);
        require(nft.ownerOf(tokenId) == address(this), "NFTTrading: contract does not hold this NFT");
        
        uint256 maxAllowedPayment = (listing.price * MAX_OVERPAY_RATIO) / OVERPAY_DENOMINATOR;
        require(msg.value >= listing.price, string(abi.encodePacked(
            "NFTTrading: insufficient payment - required ", listing.price, " wei, sent ", msg.value, " wei"
        )));
        require(msg.value <= maxAllowedPayment, string(abi.encodePacked(
            "NFTTrading: payment exceeds max allowed (", maxAllowedPayment, " wei) - sent ", msg.value, " wei"
        )));

        address seller = listing.seller;
        uint256 priceWEI = listing.price;
        uint256 priceBNB = _weiToBnbWithDecimals(priceWEI);

        uint256 minSellerAmountWEI = 1e14;
        uint256 feeWEI = (priceWEI * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        uint256 sellerAmountWEI = priceWEI - feeWEI;
        
        if (sellerAmountWEI < minSellerAmountWEI && sellerAmountWEI > 0) {
            feeWEI = priceWEI - minSellerAmountWEI;
            sellerAmountWEI = minSellerAmountWEI;
        } else if (sellerAmountWEI == 0) {
            sellerAmountWEI = priceWEI;
            feeWEI = 0;
        }
        
        uint256 feeBNB = _weiToBnbWithDecimals(feeWEI);

        address royaltyWallet = _royaltyWallet;
        if (royaltyWallet == address(0)) {
            royaltyWallet = owner();
        }

        require(address(this).balance >= sellerAmountWEI, "NFTTrading: insufficient contract balance for seller payment");

        _removeListing(tokenId, seller);
        totalSales++;
        totalFeesCollected += feeWEI;

        bool nftTransferSuccess = false;
        
        try nft.safeTransferFrom(address(this), msg.sender, tokenId) {
            nftTransferSuccess = true;
        } catch {
            listings[tokenId] = NFTListing({
                seller: seller,
                price: priceWEI,
                listedAt: block.timestamp - 1,
                isActive: true
            });
            _addListingToUserTokens(seller, tokenId);
            _addToActiveListings(tokenId);
            totalSales--;
            totalFeesCollected -= feeWEI;
            
            (bool refundSuccess, ) = msg.sender.call{value: msg.value}("");
            require(refundSuccess, "NFTTrading: refund to buyer failed");
            
            emit NFTTransferFailed(tokenId, msg.sender, seller, priceWEI, block.timestamp, block.number);
            return;
        }
        
        if (nftTransferSuccess) {
            if (sellerAmountWEI > 0) {
                _safeTransferBNB(seller, sellerAmountWEI);
            }
            if (feeWEI > 0) {
                _safeTransferBNB(royaltyWallet, feeWEI);
            }
            if (msg.value > priceWEI) {
                uint256 overpaidWEI = msg.value - priceWEI;
                totalOverpaid += overpaidWEI;
                emit OverpaidReceived(msg.sender, overpaidWEI, block.timestamp, block.number);
            }
        }

        emit NFTSold(tokenId, seller, msg.sender, priceBNB, priceWEI, feeBNB, feeWEI, block.timestamp, block.number);
        emit FeeCollected(royaltyWallet, feeBNB, feeWEI, block.timestamp, block.number);
    }
    
    /**
     * @dev 将listing添加回用户上架列表
     * @param user 用户地址
     * @param tokenId token ID
     */
    function _addListingToUserTokens(address user, uint256 tokenId) internal {
        uint256[] storage userTokens = userListedTokens[user];
        tokenToListingIndex[tokenId] = userTokens.length;
        userTokens.push(tokenId);
    }
    
    /**
     * @dev 将token添加回活跃上架列表
     * @param tokenId token ID
     */
    function _addToActiveListings(uint256 tokenId) internal {
        tokenToActiveIndex[tokenId] = activeListingIds.length;
        activeListingIds.push(tokenId);
        activeListings++;
    }

    /**
     * @dev 安全转移BNB
     * @param to 接收地址
     * @param amountWEI 金额（wei）
     */
    function _safeTransferBNB(address to, uint256 amountWEI) internal {
        require(to != address(0), "NFTTrading: transfer to zero address");
        require(amountWEI > 0, "NFTTrading: transfer amount must be positive");
        require(address(this).balance >= amountWEI, "NFTTrading: contract BNB balance insufficient");

        (bool success, ) = to.call{value: amountWEI}("");
        require(success, string(abi.encodePacked(
            "NFTTrading: BNB transfer failed to ", to, " (amount: ", amountWEI, " wei)"
        )));
    }

    /**
     * @dev 合约拥有者提取指定金额BNB
     * @param to 接收地址
     * @param amountBNB BNB数量
     */
    function ownerWithdrawBNB(address payable to, uint256 amountBNB) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        require(amountBNB > 0, "NFTTrading: invalid BNB amount");
        
        uint256 amountWEI = _bnbToWei(amountBNB);
        require(amountWEI <= address(this).balance, "NFTTrading: insufficient BNB balance");

        _safeTransferBNB(to, amountWEI);

        emit EmergencyWithdrawBNB(msg.sender, to, amountBNB, amountWEI, block.timestamp, block.number);
    }

    /**
     * @dev 合约拥有者提取超额支付金额
     * @param to 接收地址
     * @param amountWEI 金额（wei）
     */
    function withdrawOverpaid(address payable to, uint256 amountWEI) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        require(amountWEI > 0, "NFTTrading: invalid amount");
        require(amountWEI <= totalOverpaid, "NFTTrading: insufficient overpaid balance");
        require(amountWEI <= address(this).balance, "NFTTrading: contract balance insufficient");
        
        totalOverpaid -= amountWEI;
        _safeTransferBNB(to, amountWEI);
        
        emit OverpaidWithdrawn(msg.sender, to, amountWEI, block.timestamp, block.number);
    }

    /**
     * @dev 合约拥有者提取所有BNB
     * @param to 接收地址
     */
    function ownerWithdrawAllBNB(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        uint256 balanceWEI = address(this).balance;
        require(balanceWEI > 0, "NFTTrading: no BNB to withdraw");
        
        uint256 balanceBNB = _weiToBnbWithDecimals(balanceWEI);
        
        totalOverpaid = 0;

        _safeTransferBNB(to, balanceWEI);

        emit EmergencyWithdrawBNB(msg.sender, to, balanceBNB, balanceWEI, block.timestamp, block.number);
    }

    /**
     * @dev 合约拥有者提取NFT
     * @param to 接收地址
     * @param tokenId NFT ID
     */
    function ownerWithdrawNFT(address to, uint256 tokenId) external onlyOwner nonReentrant {
        require(to != address(0), "NFTTrading: invalid recipient");
        INFTMint nft = INFTMint(_nftContract);

        require(nft.ownerOf(tokenId) == address(this), "NFTTrading: contract does not own NFT");
        require(!listings[tokenId].isActive, "NFTTrading: cannot withdraw listed NFT");

        nft.safeTransferFrom(address(this), to, tokenId);

        emit EmergencyWithdrawNFT(msg.sender, to, tokenId, block.timestamp, block.number);
    }

    /**
     * @dev 设置NFT合约地址
     * @param newNFTContract NFT合约地址
     */
    function setNFTContract(address newNFTContract) external {
        require(msg.sender == owner() || msg.sender == _authorizer, "NFTTrading: Unauthorized");
        require(newNFTContract != address(0), "NFTTrading: invalid NFT contract");
        address oldAddress = _nftContract;
        _nftContract = newNFTContract;
        emit ContractUpdated(oldAddress, newNFTContract, "NFTContract", block.timestamp, block.number);
    }

    /**
     * @dev 设置奖励管理器地址
     * @param newRewardManager 奖励管理器地址
     */
    function setRewardManager(address newRewardManager) external {
        require(msg.sender == owner() || msg.sender == _authorizer, "NFTTrading: Unauthorized");
        require(newRewardManager != address(0), "NFTTrading: invalid RewardManager");
        address oldAddress = _rewardManager;
        _rewardManager = newRewardManager;
        emit ContractUpdated(oldAddress, newRewardManager, "RewardManager", block.timestamp, block.number);
    }

    /**
     * @dev 设置授权合约地址
     * @param authorizer 授权合约地址
     */
    function setAuthorizer(address authorizer) external onlyOwner {
        address oldAuthorizer = _authorizer;
        _authorizer = authorizer;
        emit AuthorizerUpdated(oldAuthorizer, authorizer, block.timestamp, block.number);
    }

    /**
     * @dev 设置手续费接收钱包地址
     * @param wallet 手续费接收钱包地址
     */
    function setRoyaltyWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "NFTTrading: invalid royalty wallet");
        _royaltyWallet = wallet;
    }

    /**
     * @dev 获取手续费接收钱包地址
     * @return 手续费接收钱包地址
     */
    function getRoyaltyWallet() external view returns (address) {
        return _royaltyWallet;
    }

    /**
     * @dev 设置最大上架价格
     * @param newMaxListingPriceBNB 最大上架价格（BNB）
     */
    function setMaxListingPriceBNB(uint256 newMaxListingPriceBNB) external onlyOwner {
        require(newMaxListingPriceBNB > 0, "NFTTrading: max price must be > 0");
        uint256 oldPrice = _maxListingPriceBNB;
        _maxListingPriceBNB = newMaxListingPriceBNB;
        _maxListingPrice = _bnbToWei(newMaxListingPriceBNB);
        emit MaxListingPriceUpdated(oldPrice, newMaxListingPriceBNB, block.timestamp, block.number);
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 紧急下架NFT（合约拥有者）
     * @param tokenId NFT ID
     */
    function emergencyUnlistNFT(uint256 tokenId) external onlyOwner {
        NFTListing storage listing = listings[tokenId];
        if (listing.isActive) {
            address seller = listing.seller;
            INFTMint nft = INFTMint(_nftContract);

            require(nft.ownerOf(tokenId) == address(this), "NFTTrading: contract does not hold NFT");

            _removeListing(tokenId, seller);

            nft.safeTransferFrom(address(this), seller, tokenId);

            emit NFTUnlisted(tokenId, seller, block.timestamp, block.number);
            emit NFTReturned(tokenId, seller, block.timestamp, block.number);
        }
    }

    /**
     * @dev 移除上架记录（内部函数）
     * @param tokenId NFT ID
     * @param seller 卖家地址
     */
    function _removeListing(uint256 tokenId, address seller) internal {
        NFTListing storage listing = listings[tokenId];
        if (!listing.isActive) return;

        listing.isActive = false;

        uint256[] storage userTokens = userListedTokens[seller];
        uint256 index = tokenToListingIndex[tokenId];

        if (index < userTokens.length && userTokens[index] == tokenId) {
            uint256 lastIndex = userTokens.length - 1;
            if (index != lastIndex) {
                userTokens[index] = userTokens[lastIndex];
                tokenToListingIndex[userTokens[lastIndex]] = index;
            }
            userTokens.pop();
            delete tokenToListingIndex[tokenId];
        }

        _removeFromActiveListings(tokenId);

        activeListings = activeListings > 0 ? activeListings - 1 : 0;
    }

    /**
     * @dev 从活跃上架列表中移除token
     * @param tokenId NFT ID
     */
    function _removeFromActiveListings(uint256 tokenId) internal {
        uint256 index = tokenToActiveIndex[tokenId];
        uint256 lastIndex = activeListingIds.length - 1;
        
        if (index <= lastIndex && activeListingIds[index] == tokenId) {
            if (index != lastIndex) {
                uint256 lastTokenId = activeListingIds[lastIndex];
                activeListingIds[index] = lastTokenId;
                tokenToActiveIndex[lastTokenId] = index;
            }
            activeListingIds.pop();
            delete tokenToActiveIndex[tokenId];
        }
    }

    /**
     * @dev 获取NFT合约地址
     * @return NFT合约地址
     */
    function getNFTContract() external view returns (address) {
        return _nftContract;
    }

    /**
     * @dev 获取奖励管理器地址
     * @return 奖励管理器地址
     */
    function getRewardManager() external view returns (address) {
        return _rewardManager;
    }

    /**
     * @dev 获取授权合约地址
     * @return 授权合约地址
     */
    function getAuthorizer() external view returns (address) {
        return _authorizer;
    }

    /**
     * @dev 获取最大上架价格（BNB）
     * @return 最大上架价格（BNB）
     */
    function getMaxListingPriceBNB() external view returns (uint256) {
        return _maxListingPriceBNB;
    }

    /**
     * @dev 获取最大上架价格（wei）
     * @return 最大上架价格（wei）
     */
    function getMaxListingPrice() external view returns (uint256) {
        return _maxListingPrice;
    }

    /**
     * @dev 获取合约统计数据
     * @return _activeListings 活跃上架数
     * @return _totalListedCount 累计上架数
     * @return _totalSales 累计成交数
     * @return _totalFeesCollectedBNB 累计手续费（BNB）
     * @return _totalFeesCollectedWEI 累计手续费（wei）
     * @return _contractBalanceBNB 合约余额（BNB）
     * @return _contractBalanceWEI 合约余额（wei）
     */
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

    /**
     * @dev 获取上架信息
     * @param tokenId NFT ID
     * @return listing 上架信息
     * @return priceBNB 价格（BNB）
     * @return priceWEI 价格（wei）
     */
    function getListing(uint256 tokenId) external view returns (NFTListing memory listing, uint256 priceBNB, uint256 priceWEI) {
        listing = listings[tokenId];
        priceBNB = _weiToBnbWithDecimals(listing.price);
        priceWEI = listing.price;
        return (listing, priceBNB, priceWEI);
    }

    /**
     * @dev 获取用户上架的NFT列表
     * @param user 用户地址
     * @return uint256[] NFT ID列表
     */
    function getUserListedTokens(address user) external view returns (uint256[] memory) {
        return userListedTokens[user];
    }

    /**
     * @dev 获取卖家上架列表
     * @param seller 卖家地址
     * @return uint256[] NFT ID列表
     */
    function getSellerListings(address seller) external view returns (uint256[] memory) {
        return userListedTokens[seller];
    }

    /**
     * @dev 取消上架（与unlistNFT同义）
     * @param tokenId NFT ID
     */
    function cancelListing(uint256 tokenId) external nonReentrant whenNotPaused {
        unlistNFT(tokenId);
    }

    /**
     * @dev 获取用户活跃上架数量
     * @param user 用户地址
     * @return uint256 活跃上架数量
     */
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

    /**
     * @dev 查询NFT价格
     * @param tokenId NFT ID
     * @return priceWEI 价格（wei）
     * @return priceBNB 价格（BNB）
     */
    function getNFTPrice(uint256 tokenId) external view returns (uint256 priceWEI, uint256 priceBNB) {
        require(listings[tokenId].isActive, "NFTTrading: NFT not listed");
        priceWEI = listings[tokenId].price;
        priceBNB = _weiToBnbWithDecimals(priceWEI);
        return (priceWEI, priceBNB);
    }

    /**
     * @dev 上架NFT结构体（用于批量查询）
     */
    struct ListedNFT {
        uint256 tokenId;
        address seller;
        uint256 priceWEI;
        uint256 priceBNB;
        uint256 listedAt;
    }

    /**
     * @dev 获取所有上架记录
     * @return tokenIds NFT ID列表
     * @return sellers 卖家列表
     * @return prices 价格列表
     * @return actives 活跃状态列表
     */
    function getAllListings() external view returns (uint256[] memory, address[] memory, uint256[] memory, bool[] memory) {
        uint256 count = allListingIds.length;
        uint256[] memory tokenIds = new uint256[](count);
        address[] memory sellers = new address[](count);
        uint256[] memory prices = new uint256[](count);
        bool[] memory actives = new bool[](count);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = allListingIds[i];
            NFTListing storage listing = listings[tokenId];
            tokenIds[i] = tokenId;
            sellers[i] = listing.seller;
            prices[i] = listing.price;
            actives[i] = listing.isActive;
        }
        
        return (tokenIds, sellers, prices, actives);
    }

    /**
     * @dev 分页获取上架记录
     * @param offset 偏移量
     * @param limit 每页数量
     * @return tokenIds NFT ID列表
     * @return sellers 卖家列表
     * @return prices 价格列表
     * @return actives 活跃状态列表
     * @return total 总数量
     */
    function getPaginatedListings(uint256 offset, uint256 limit) external view returns (
        uint256[] memory tokenIds,
        address[] memory sellers,
        uint256[] memory prices,
        bool[] memory actives,
        uint256 total
    ) {
        total = allListingIds.length;
        
        if (offset >= total) {
            tokenIds = new uint256[](0);
            sellers = new address[](0);
            prices = new uint256[](0);
            actives = new bool[](0);
            return (tokenIds, sellers, prices, actives, total);
        }
        
        uint256 actualLimit = limit;
        if (offset + limit > total) {
            actualLimit = total - offset;
        }
        
        tokenIds = new uint256[](actualLimit);
        sellers = new address[](actualLimit);
        prices = new uint256[](actualLimit);
        actives = new bool[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            uint256 tokenId = allListingIds[offset + i];
            NFTListing storage listing = listings[tokenId];
            tokenIds[i] = tokenId;
            sellers[i] = listing.seller;
            prices[i] = listing.price;
            actives[i] = listing.isActive;
        }
        
        return (tokenIds, sellers, prices, actives, total);
    }
    
    /**
     * @dev 获取所有活跃上架
     * @return ListedNFT[] 活跃上架列表
     */
    function getAllActiveListings() external view returns (ListedNFT[] memory) {
        uint256 count = activeListingIds.length;
        ListedNFT[] memory result = new ListedNFT[](count);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = activeListingIds[i];
            NFTListing storage listing = listings[tokenId];
            result[i] = ListedNFT({
                tokenId: tokenId,
                seller: listing.seller,
                priceWEI: listing.price,
                priceBNB: _weiToBnbWithDecimals(listing.price),
                listedAt: listing.listedAt
            });
        }
        
        return result;
    }

    /**
     * @dev 获取活跃上架数量
     * @return uint256 活跃上架数量
     */
    function getActiveListingsCount() external view returns (uint256) {
        return activeListingIds.length;
    }

    /**
     * @dev 获取合约健康状态
     * @return nftContractAlive NFT合约是否正常
     * @return availableBNBBalance 可用BNB余额
     * @return status 合约状态
     */
    function getContractHealth() external view returns (
        bool nftContractAlive,
        uint256 availableBNBBalance,
        string memory status
    ) {
        nftContractAlive = false;
        try INFTMint(_nftContract).supportsInterface(0x80ac58cd) returns (bool) {
            nftContractAlive = true;
        } catch {}

        availableBNBBalance = _weiToBnbWithDecimals(address(this).balance);

        if (nftContractAlive && !paused()) {
            status = "HEALTHY";
        } else if (paused()) {
            status = "PAUSED";
        } else {
            status = "UNHEALTHY";
        }

        return (nftContractAlive, availableBNBBalance, status);
    }

    /**
     * @dev 禁止直接BNB转账
     */
    receive() external payable {
        revert("NFTTrading: direct BNB transfers are forbidden - use buyNFT()");
    }

    function withdrawSpecificBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "NFTTrading: insufficient balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "NFTTrading: BNB transfer failed");
    }

    function withdrawNFTs(uint256[] calldata tokenIds) external onlyOwner nonReentrant {
        INFTMint nft = INFTMint(_nftContract);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (nft.ownerOf(tokenIds[i]) == address(this) && !listings[tokenIds[i]].isActive) {
                nft.safeTransferFrom(address(this), owner(), tokenIds[i]);
            }
        }
    }
}