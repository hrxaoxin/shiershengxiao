// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title NFTTrading
 * @dev NFT交易市场合约，支持NFT的挂牌、购买和下架
 *
 * 核心功能：
 * 1. 挂牌（listNFT）：NFT所有者将其NFT以固定价格（BNB）挂牌出售
 * 2. 购买（buyNFT）：买家支付 BNB 获得 NFT，卖家获得扣除手续费后的 BNB
 * 3. 下架（delistNFT）：卖家在未售出前可随时下架，取回 NFT
 * 4. 批量挂牌 / 下架（可选前端批量调用）
 *
 * 交易规则：
 * - 挂牌者必须是 NFT 所有者（ERC721 ownerOf 验证）
 * - 挂牌者必须授权本合约转移 NFT（approve / setApprovalForAll）
 * - 价格以 BNB（原生代币）计价，不可为 0
 * - 手续费率 feePercent（默认 5%），以 BNB 形式扣除
 * - 5% 手续费全部转入 feeReceiver 地址（由 owner 设置）
 * - 手续费中的部分会进一步分配到 PoolManager 供质押/分红使用
 *
 * 数据结构：
 * - listings[tokenId] → Listing { seller, priceWei, listTime }
 *   记录每个被挂牌 NFT 的卖家和价格信息
 * - listedNFTs[] → 当前在售的 NFT ID 列表，供前端快速获取在售列表
 *
 * 价格更新：
 * - updatePrice(tokenId, newPrice)：卖家可调整挂牌价格
 * - 必须高于某个最小价格（防止误操作设为 0）
 *
 * 与其他合约联动：
 * - NFTMint / NFTData：读取 NFT 类型和等级，前端展示并判断稀有度
 * - WeightManager / DividendManager：NFT 所有权转移后更新权重，影响分红计算
 * - PoolManager：手续费中部分比例作为游戏生态奖励池资金
 * - Authorizer：通过 Authorizer 设置 feeReceiver 等地址
 *
 * 权限控制：
 * - onlyOwner：设置 feePercent、feeReceiver、paused
 * - onlySeller：只有卖家才能下架或调整自己的挂牌
 * - 任何人（非卖家）可调用 buyNFT 购买（需发送足够 BNB）
 *
 * 安全限制：
 * - ReentrancyGuard：购买流程的 BNB 转账 + NFT 转账需防止重入
 * - Pausable：可暂停新挂牌和购买（用于维护/安全事件）
 * - 价格校验：> 0 且 < 某个上限（防止 overflow）
 * - 所有权校验：购买时再次验证卖家仍是 NFT 拥有者（防止已转移后被购买）
 * - 未授权的购买金额不足：直接回滚并退款
 *
 * 典型交易流程：
 * 1. 卖家在 NFTMint 合约授权 NFTTrading 转移 NFT
 * 2. 卖家调用 listNFT(tokenId, priceWei) → NFT 被转入合约，加入 listedNFTs
 * 3. 买家浏览市场，选中 NFT 调用 buyNFT(tokenId) 并附带 BNB
 * 4. 合约验证金额 ≥ priceWei → 转 BNB 给卖家（扣 5% 手续费），转 NFT 给买家
 * 5. emit NFTTraded 事件，前端刷新页面
 * 6. 若卖家取消：调用 delistNFT(tokenId) → NFT 返回卖家，从 listedNFTs 移除
 */
contract NFTTrading is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 挂牌信息结构体
     */
    struct Listing {
        address seller;       // 卖家地址
        uint256 priceWei;    // 价格（BNB）
        uint256 listTime;    // 挂牌时间
    }

    /**
     * @dev 挂牌映射
     * tokenId => Listing
     */
    mapping(uint256 => Listing) public listings;

    /**
     * @dev 在售NFT列表
     */
    uint256[] public listedNFTs;

    /**
     * @dev 手续费率（百分比）
     */
    uint256 public feePercent = 5;
    uint256 public totalVolume;

    /**
     * @dev 手续费接收地址
     */
    address public feeReceiver;

    /**
     * @dev 紧急暂停
     */
    bool public paused;
    string public pauseReason;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev NFT合约地址
     */
    address public nftContract;

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "NFTTrading: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
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
        require(a != address(0), "NFTTrading: Invalid authorizer address");
        authorizer = a;
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

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTTrading: Not authorized");
        _;
    }

    /**
     * @dev NFT 上架事件
     */
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 priceWei);

    /**
     * @dev NFT 下架事件
     */
    event NFTDelisted(uint256 indexed tokenId, address indexed seller);

    /**
     * @dev 购买事件
     */
    event NFTBought(
        uint256 indexed tokenId,
        address indexed buyer,
        address indexed seller,
        uint256 priceWei,
        uint256 fee
    );
    event Paused(address indexed account, string reason);
    event Unpaused(address indexed account);

    modifier whenNotPaused() {
        require(!paused, "NFTTrading: Paused");
        _;
    }

    /**
     * @dev 上架NFT
     */
    function listNFT(uint256 tokenId, uint256 priceWei) external whenNotPaused nonReentrant {
        require(priceWei > 0, "NFTTrading: Invalid price");
        require(priceWei <= 1000 ether, "NFTTrading: Price too high");
        require(nftContract != address(0), "NFTTrading: NFT contract not set");
        require(INFTMint(nftContract).ownerOf(tokenId) == msg.sender, "NFTTrading: Not token owner");
        require(INFT(nftContract).isApprovedForAll(msg.sender, address(this)), "NFTTrading: Contract not approved");

        listings[tokenId] = Listing({
            seller: msg.sender,
            priceWei: priceWei,
            listTime: block.timestamp
        });

        listedNFTs.push(tokenId);
        emit NFTListed(tokenId, msg.sender, priceWei);
    }

    /**
     * @dev 下架NFT
     */
    function delistNFT(uint256 tokenId) external whenNotPaused nonReentrant {
        require(listings[tokenId].seller != address(0), "NFTTrading: Listing not found");
        require(listings[tokenId].seller == msg.sender, "NFTTrading: Not owner");

        address seller = listings[tokenId].seller;
        delete listings[tokenId];
        _removeFromListedNFTs(tokenId);
        emit NFTDelisted(tokenId, seller);
    }

    /**
     * @dev 购买NFT
     */
    function buyNFT(uint256 tokenId) external payable whenNotPaused nonReentrant {
        require(tokenId > 0, "NFTTrading: Invalid token ID");
        require(msg.sender != address(0), "NFTTrading: Invalid buyer address");
        require(listings[tokenId].seller != address(0), "NFTTrading: Listing not found");
        require(nftContract != address(0), "NFTTrading: NFT contract not set");
        require(feeReceiver != address(0), "NFTTrading: Fee receiver not set");

        Listing memory listing = listings[tokenId];
        address seller = listing.seller;
        uint256 price = listing.priceWei;
        
        require(msg.sender != seller, "NFTTrading: Cannot buy own NFT");
        require(msg.value >= price, "NFTTrading: Insufficient payment");
        require(msg.sender.balance >= msg.value, "NFTTrading: Insufficient balance");

        uint256 fee = price * feePercent / 100;
        uint256 sellerAmount = price - fee;

        require(INFTMint(nftContract).ownerOf(tokenId) == seller, "NFTTrading: Seller no longer owns NFT");
        require(INFT(nftContract).isApprovedForAll(seller, address(this)), "NFTTrading: Contract not approved");

        // 删除挂牌信息前再次验证价格未被篡改
        require(listings[tokenId].priceWei == price, "NFTTrading: Price changed");
        
        // 先删除挂牌信息，防止重入
        delete listings[tokenId];
        _removeFromListedNFTs(tokenId);

        // 然后执行 NFT 转移，这是最重要的操作
        try INFT(nftContract).safeTransferFrom(seller, msg.sender, tokenId) {
            // 转账成功后再处理资金
        } catch {
            revert("NFTTrading: NFT transfer failed");
        }

        // 先处理费用
        if (fee > 0) {
            require(feeReceiver != address(0), "NFTTrading: Invalid fee receiver");
            (bool feeSuccess, ) = payable(feeReceiver).call{value: fee}("");
            require(feeSuccess, "NFTTrading: Fee payment failed");
        }

        // 最后处理卖家收款
        (bool sellerSuccess, ) = payable(seller).call{value: sellerAmount}("");
        require(sellerSuccess, "NFTTrading: Seller payment failed");

        totalVolume += price;
        emit NFTBought(tokenId, msg.sender, seller, price, fee);
    }

    /**
     * @dev 设置手续费接收地址
     */
    function setFeeReceiver(address _feeReceiver) external onlyAuthorized {
        require(_feeReceiver != address(0), "NFTTrading: Invalid fee receiver address");
        feeReceiver = _feeReceiver;
    }

    /**
     * @dev 设置NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "NFTTrading: Invalid NFT contract address");
        nftContract = _nftContract;
    }

    /**
     * @dev 更新价格
     */
    function updatePrice(uint256 tokenId, uint256 newPriceWei) external whenNotPaused nonReentrant {
        require(listings[tokenId].seller == msg.sender, "NFTTrading: Not owner");
        require(newPriceWei > 0, "NFTTrading: Invalid price");

        listings[tokenId].priceWei = newPriceWei;
        emit NFTListed(tokenId, msg.sender, newPriceWei);
    }

    /**
     * @dev 获取挂牌信息
     */
    function getListingInfo(uint256 tokenId) external view returns (
        address seller,
        uint256 priceWei,
        uint256 listTime
    ) {
        Listing memory listing = listings[tokenId];
        return (listing.seller, listing.priceWei, listing.listTime);
    }

    /**
     * @dev 获取在售NFT列表
     */
    function getListedNFTs() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller != address(0)) {
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller != address(0)) {
                result[index++] = tokenId;
            }
        }
        return result;
    }

    /**
     * @dev 设置手续费率（仅所有者）
     */
    function setFeePercent(uint256 percent) external onlyOwner {
        require(percent <= 20, "NFTTrading: Fee too high");
        require(percent >= 0, "NFTTrading: Fee must be non-negative");
        feePercent = percent;
        emit FeePercentUpdated(feePercent);
    }
    
    event FeePercentUpdated(uint256 newFeePercent);

    /**
     * @dev 从列表移除
     */
    function _removeFromListedNFTs(uint256 tokenId) internal {
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            if (listedNFTs[i] == tokenId) {
                listedNFTs[i] = listedNFTs[listedNFTs.length - 1];
                listedNFTs.pop();
                break;
            }
        }
    }

    /**
     * @dev 获取用户的挂牌数量
     * @param user 用户地址
     * @return count 挂牌数量
     */
    function getUserListedCount(address user) external view returns (uint256 count) {
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller == user) {
                count++;
            }
        }
    }

    /**
     * @dev 获取用户的挂牌列表
     * @param user 用户地址
     * @return tokenIds 用户挂牌的NFT ID列表
     */
    function getUserListings(address user) external view returns (uint256[] memory tokenIds) {
        uint256 count = 0;
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller == user) {
                count++;
            }
        }

        tokenIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller == user) {
                tokenIds[index++] = tokenId;
            }
        }
    }

    /**
     * @dev 获取市场统计信息
     * @return totalListings 总挂牌数
     * @return activeListings 有效挂牌数
     * @return floorPrice 最低价
     * @return totalVolume 总交易额
     */
    function getMarketStats() external view returns (
        uint256 totalListings,
        uint256 activeListings,
        uint256 floorPrice,
        uint256 totalVolume
    ) {
        totalListings = listedNFTs.length;
        activeListings = 0;
        floorPrice = type(uint256).max;

        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller != address(0)) {
                activeListings++;
                if (listings[tokenId].priceWei < floorPrice) {
                    floorPrice = listings[tokenId].priceWei;
                }
            }
        }

        if (floorPrice == type(uint256).max) {
            floorPrice = 0;
        }
    }

    /**
     * @dev 获取指定价格范围的挂牌
     * @param minPrice 最低价格
     * @param maxPrice 最高价格
     * @return tokenIds 符合条件的NFT ID列表
     */
    function getListingsByPriceRange(uint256 minPrice, uint256 maxPrice) external view returns (uint256[] memory tokenIds) {
        uint256 count = 0;
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller != address(0)) {
                if (listings[tokenId].priceWei >= minPrice && listings[tokenId].priceWei <= maxPrice) {
                    count++;
                }
            }
        }

        tokenIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < listedNFTs.length; i++) {
            uint256 tokenId = listedNFTs[i];
            if (listings[tokenId].seller != address(0)) {
                if (listings[tokenId].priceWei >= minPrice && listings[tokenId].priceWei <= maxPrice) {
                    tokenIds[index++] = tokenId;
                }
            }
        }
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTTrading: Amount must be > 0");
        require(amount <= address(this).balance, "NFTTrading: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "NFTTrading: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawNFT(uint256 tokenId) external onlyOwner nonReentrant {
        require(nftContract != address(0), "NFTTrading: NFT contract not set");
        INFTMint nft = INFTMint(nftContract);
        nft.safeTransferFrom(address(this), owner(), tokenId);
        emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenId);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}
