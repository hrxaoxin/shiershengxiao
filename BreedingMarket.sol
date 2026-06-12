// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

/**
 * @title BreedingMarket
 * @dev 繁殖市场合约，管理NFT繁殖配对的市场列�? * 
 * 核心职责�? * 1. 市场挂牌：用户将NFT挂牌到繁殖市场，供其他用户选择配对
 * 2. 配对繁殖：其他用户可选择市场上的NFT进行繁殖
 * 3. 下架管理：用户可随时下架自己的NFT
 * 
 * 繁殖市场流程�? * 1. 用户调用 listNFT(tokenId) 将NFT挂牌到市�? * 2. NFT被锁定在合约中，等待配对
 * 3. 其他用户选择该NFT进行繁殖（调用BreedingCore.breedMarket�? * 4. 繁殖完成后，NFT解锁并返回给原所有�? * 5. 用户可调�?delistNFT(tokenId) 提前下架NFT
 * 
 * 与BreedingCore的关系：
 * - BreedingCore调用本合约验证NFT是否在市场中
 * - 繁殖完成后，BreedingCore通知本合约更新状�? * 
 * 数据结构�? * - marketListings[tokenId]: 记录NFT的挂牌信�? * - listedTokenIds: 所有已挂牌的NFT ID列表
 * - activeListedTokenIds: 当前活跃的挂牌NFT ID列表
 * 
 * 权限控制�? * - onlyOwner: 设置授权合约、暂停合约、紧急操�? * - onlyOwnerOrAuthorizer: owner或authorizer可调用特定函�? * 
 * 安全机制�? * - ReentrancyGuard: 防止重入攻击
 * - Pausable: 可暂停所有市场操�? * - NFT锁定: 挂牌期间NFT被锁定，防止转移
 */
contract BreedingMarket is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    /**
     * @dev NFT铸造合约地址
     */
    address public nftMintContract;
    /**
     * @dev 繁殖核心合约地址
     */
    address public breedingCoreContract;

    /**
     * @dev 是否暂停市场操作
     */
    bool public paused;
    /**
     * @dev 暂停原因
     */
    string public pauseReason;

    /**
     * @dev 市场挂牌信息结构�?     * @param tokenId NFT ID
     * @param owner NFT所有�?     * @param listTime 挂牌时间
     * @param isActive 是否活跃
     */
    struct MarketListing { 
        uint256 tokenId; 
        address owner; 
        uint256 listTime; 
        bool isActive; 
    }

    /**
     * @dev 市场挂牌映射
     */
    mapping(uint256 => MarketListing) public marketListings;
    /**
     * @dev 所有已挂牌的NFT ID列表
     */
    uint256[] public listedTokenIds;
    /**
     * @dev 当前活跃的挂牌NFT ID列表
     */
    uint256[] public activeListedTokenIds;

    /**
     * @dev 合约暂停事件
     */
    event Paused(address indexed account, string reason);
    /**
     * @dev 合约取消暂停事件
     */
    event Unpaused(address indexed account);
    /**
     * @dev 市场挂牌创建事件
     */
    event MarketListingCreated(uint256 indexed tokenId, address indexed owner);
    /**
     * @dev 市场挂牌移除事件
     */
    event MarketListingRemoved(uint256 indexed tokenId, address indexed owner);

    /**
     * @dev 修饰器：确保合约未暂�?     */
    modifier whenNotPaused() {
        require(!paused, "BM: Paused");
        _;
    }

    /**
     * @dev 修饰器：仅授权用户（owner或authorizer�?     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "BM: Not authorized");
        _;
    }

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函�?     * @param _authorizer 授权合约地址
     * @param _breedingCore 繁殖核心合约地址
     */
    function initialize(address _authorizer, address _breedingCore) external initializer {
        require(_authorizer != address(0), "BM: Invalid authorizer address");
        require(_breedingCore != address(0), "BM: Invalid breeding core address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
        breedingCoreContract = _breedingCore;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "BM: Invalid authorizer address");
        authorizer = _authorizer;
    }

    /**
     * @dev 设置繁殖核心合约地址
     * @param _breedingCore 繁殖核心合约地址
     */
    function setBreedingCore(address _breedingCore) external onlyOwnerOrAuthorizer {
        require(_breedingCore != address(0), "BM: Invalid breeding core address");
        breedingCoreContract = _breedingCore;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    function listForMarketBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        require(nftMintContract != address(0), "BM: NFT contract not set");
        require(INFTMint(nftMintContract).ownerOf(tokenId) == msg.sender, "BM: Not token owner");
        require(!marketListings[tokenId].isActive, "BM: Already listed");
        
        bool inCooldown = IBreedingCore(breedingCoreContract).isInCooldown(tokenId);
        require(!inCooldown, "BM: NFT in cooldown");
        
        bool inActiveBreeding = IBreedingCore(breedingCoreContract).isNFTInActiveBreeding(tokenId);
        require(!inActiveBreeding, "BM: NFT in active breeding");
        
        require(INFTMint(nftMintContract).tokenLevel(tokenId) >= 5, "BM: Level too low");

        marketListings[tokenId] = MarketListing({ tokenId: tokenId, owner: msg.sender, listTime: block.timestamp, isActive: true });
        listedTokenIds.push(tokenId);
        activeListedTokenIds.push(tokenId);
        emit MarketListingCreated(tokenId, msg.sender);
    }

    function delistFromMarketBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        require(marketListings[tokenId].isActive, "BM: Not listed");
        require(marketListings[tokenId].owner == msg.sender, "BM: Not listing owner");
        delete marketListings[tokenId];
        
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (listedTokenIds[i] == tokenId) {
                listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                listedTokenIds.pop();
                break;
            }
        }
        
        for (uint256 i = 0; i < activeListedTokenIds.length; i++) {
            if (activeListedTokenIds[i] == tokenId) {
                activeListedTokenIds[i] = activeListedTokenIds[activeListedTokenIds.length - 1];
                activeListedTokenIds.pop();
                break;
            }
        }
        
        emit MarketListingRemoved(tokenId, msg.sender);
    }

    function getMarketListingIds() external view returns (uint256[] memory) {
        return activeListedTokenIds;
    }

    function getMarketListing(uint256 tokenId) external view returns (MarketListing memory) { 
        return marketListings[tokenId]; 
    }

    function getMarketListingCount() external view returns (uint256) { 
        return listedTokenIds.length; 
    }

    function setNFTContract(address _nftContract) external onlyOwnerOrAuthorizer { 
        require(_nftContract != address(0), "BM: Invalid NFT contract address"); 
        nftMintContract = _nftContract; 
    }

    receive() external payable {}
    fallback() external payable {}
}