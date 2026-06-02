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
 * 交易规则：
 * 1. NFT所有者可以挂牌出售
 * 2. 购买者支付BNB购买NFT
 * 3. 卖家收到BNB（扣除手续费）
 * 4. 5%手续费全部进入手续费接收地址
 */
contract NFTTrading is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
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
     * @dev 上架事件
     */
    event NFTListed(uint256 indexed tokenId, address seller, uint256 priceWei);

    /**
     * @dev 下架事件
     */
    event NFTDelisted(uint256 indexed tokenId);

    /**
     * @dev 购买事件
     */
    event NFTBought(
        uint256 indexed tokenId,
        address buyer,
        address seller,
        uint256 priceWei,
        uint256 fee
    );
    event Paused(address account, string reason);
    event Unpaused(address account);

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
        require(INFTMint(nftContract).isApprovedForAll(msg.sender, address(this)), "NFTTrading: Contract not approved");

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

        delete listings[tokenId];
        _removeFromListedNFTs(tokenId);
        emit NFTDelisted(tokenId);
    }

    /**
     * @dev 购买NFT
     */
    function buyNFT(uint256 tokenId) external payable whenNotPaused nonReentrant {
        require(listings[tokenId].seller != address(0), "NFTTrading: Listing not found");
        require(msg.value >= listings[tokenId].priceWei, "NFTTrading: Insufficient payment");
        require(nftContract != address(0), "NFTTrading: NFT contract not set");

        Listing memory listing = listings[tokenId];
        address seller = listing.seller;
        uint256 price = listing.priceWei;
        uint256 fee = price * feePercent / 100;
        uint256 sellerAmount = price - fee;

        require(INFTMint(nftContract).ownerOf(tokenId) == seller, "NFTTrading: Seller no longer owns NFT");
        require(INFTMint(nftContract).isApprovedForAll(seller, address(this)), "NFTTrading: Contract not approved");

        delete listings[tokenId];
        _removeFromListedNFTs(tokenId);

        try INFTMint(nftContract).safeTransferFrom(seller, msg.sender, tokenId) {
            // 转账成功
        } catch {
            revert("NFTTrading: NFT transfer failed");
        }

        if (fee > 0) {
            (bool feeSuccess, ) = payable(feeReceiver).call{value: fee}("");
            if (!feeSuccess) {
                sellerAmount += fee;
            }
        }

        (bool sellerSuccess, ) = payable(seller).call{value: sellerAmount}("");
        require(sellerSuccess, "NFTTrading: Seller payment failed");

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
     * @dev 设置手续费率
     * 仅合约所有者可调用
     */
    function setFeePercent(uint256 percent) external onlyOwner {
        require(percent <= 100, "NFTTrading: Fee too high");
        feePercent = percent;
    }

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

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner {
        require(amount > 0, "NFTTrading: Amount must be > 0");
        require(amount <= address(this).balance, "NFTTrading: Insufficient balance");
        payable(owner()).transfer(amount);
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawNFT(uint256 tokenId) external onlyOwner {
        require(nftContract != address(0), "NFTTrading: NFT contract not set");
        INFTMint nft = INFTMint(nftContract);
        nft.safeTransferFrom(address(this), owner(), tokenId);
        emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenId);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);
}
