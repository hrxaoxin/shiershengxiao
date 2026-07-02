// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

/**
 * @title BreedingMarket - 繁殖市场合约
 * @dev 管理NFT繁殖配对的市场列表
 * 
 * 核心职责：
 * 1. 市场挂牌：用户将NFT挂牌到繁殖市场，供其他用户选择配对
 * 2. 配对繁殖：其他用户可选择市场上的NFT进行繁殖
 * 3. 下架管理：用户可随时下架自己的NFT
 * 
 * 繁殖市场流程：
 * 1. 用户调用 listForMarketBreeding(tokenId) 将NFT挂牌到市场
 * 2. NFT被锁定在合约中，等待配对
 * 3. 其他用户选择该NFT进行繁殖（调用BreedingCore.createMarketBreedingPairPublic）
 * 4. 繁殖完成后，NFT解锁并返回给原所有者
 * 5. 用户可调用 delistFromMarketBreeding(tokenId) 提前下架NFT
 * 
 * 与BreedingCore的关系：
 * - BreedingCore调用本合约验证NFT是否在市场中
 * - 繁殖完成后，BreedingCore通知本合约更新状态
 * 
 * 数据结构：
 * - marketListings[tokenId]: 记录NFT的挂牌信息
 * - listedTokenIds: 所有已挂牌的NFT ID列表
 * - activeListedTokenIds: 当前活跃的挂牌NFT ID列表
 * 
 * 权限控制：
 * - onlyOwner: 设置授权合约、暂停合约、紧急操作
 * - onlyOwnerOrAuthorizer: owner或authorizer可调用特定函数
 * 
 * 安全机制：
 * - ReentrancyGuard: 防止重入攻击
 * - Pausable: 可暂停所有市场操作
 * - NFT锁定: 挂牌期间NFT被锁定，防止转移
 */
contract BreedingMarket is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    
    // ============================
    // 合约配置
    // ============================
    
    /// @dev 授权合约地址（Authorizer）- 通过此地址获取所有关联合约地址
    address public authorizer;

    /// @dev 是否暂停市场操作
    bool public paused;
    
    /// @dev 暂停原因
    string public pauseReason;

    // ============================
    // 数据结构
    // ============================
    
    /// @notice 市场挂牌信息结构体
    /// @dev 记录NFT在市场上挂牌的详细信息
    struct MarketListing { 
        uint256 tokenId;     // NFT ID
        address owner;       // NFT所有者
        uint256 listTime;    // 挂牌时间
        bool isActive;       // 是否活跃
    }

    // ============================
    // 市场数据映射
    // ============================
    
    /// @dev 纪元版本号，用于快速重置合约数据（循环复用，MAX_EPOCHS次后回到0）
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    /// @dev 市场挂牌映射（epoch => tokenId => 挂牌信息）
    mapping(uint256 => mapping(uint256 => MarketListing)) public marketListings;
    
    /// @dev 所有已挂牌的NFT ID列表（包含历史记录）
    uint256[] public listedTokenIds;
    
    /// @dev 当前活跃的挂牌NFT ID列表
    uint256[] public activeListedTokenIds;

    // ============================
    // 事件定义
    // ============================
    
    /// @dev 合约暂停事件
    event Paused(address indexed account, string reason);
    
    /// @dev 合约取消暂停事件
    event Unpaused(address indexed account);
    
    /// @dev 市场挂牌创建事件
    event MarketListingCreated(uint256 indexed tokenId, address indexed owner);
    
    /// @dev 市场挂牌移除事件
    event MarketListingRemoved(uint256 indexed tokenId, address indexed owner);

    /// @dev 合约数据重置事件
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    // ============================
    // 修饰器
    // ============================
    
    /// @dev 修饰器：确保合约未暂停
    modifier whenNotPaused() {
        require(!paused, "BM: Paused");
        _;
    }

    /// @dev 修饰器：仅授权用户（owner或authorizer或系统合约）
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "BM: Not authorized");
        _;
    }

    // ============================
    // 构造函数与初始化
    // ============================
    
    /// @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "BM: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        epoch = 1;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }

    // ============================
    // 授权与暂停管理
    // ============================
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "BM: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /// @dev UUPS升级授权检查
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

    // ============================
    // 市场挂牌功能
    // ============================
    
    /**
     * @dev 将NFT挂牌到繁殖市场
     * @param tokenId 要挂牌的NFT ID
     * 
     * 前提条件：
     * - NFT必须不处于冷却中
     * - NFT必须不处于活跃繁殖中
     * - NFT等级必须 >= 5
     * - 调用者必须是NFT所有者
     * - NFT不能在市场上已挂牌
     * 
     * 效果：
     * - NFT被转移到合约地址锁定
     * - 挂牌信息被记录
     */
    function listForMarketBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        address breedingCoreContract = IAuthorizer(authorizer).getAddressByName("breedingCore");
        require(nftMintContract != address(0), "BM: NFT contract not set");
        require(breedingCoreContract != address(0), "BM: Breeding core not set");
        require(INFTMint(nftMintContract).ownerOf(tokenId) == msg.sender, "BM: Not token owner");
        
        uint256 currentEpoch = _currentEpoch();
        require(!marketListings[currentEpoch][tokenId].isActive, "BM: Already listed");
        
        bool inCooldown = IBreedingCore(breedingCoreContract).isInCooldown(tokenId);
        require(!inCooldown, "BM: NFT in cooldown");
        
        bool inActiveBreeding = IBreedingCore(breedingCoreContract).isNFTInActiveBreeding(tokenId);
        require(!inActiveBreeding, "BM: NFT in active breeding");
        
        require(INFTMint(nftMintContract).tokenLevel(tokenId) >= 5, "BM: Level too low");

        marketListings[currentEpoch][tokenId] = MarketListing({ tokenId: tokenId, owner: msg.sender, listTime: block.timestamp, isActive: true });
        listedTokenIds.push(tokenId);
        activeListedTokenIds.push(tokenId);
        emit MarketListingCreated(tokenId, msg.sender);
    }

    /**
     * @dev 从繁殖市场下架NFT
     * @param tokenId 要下架的NFT ID
     * 
     * 前提条件：
     * - NFT必须在市场上挂牌
     * - 调用者必须是挂牌所有者
     * 
     * 效果：
     * - 挂牌信息被删除
     * - NFT返回给原所有者
     * - 从活跃列表中移除
     */
    function delistFromMarketBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        uint256 currentEpoch = _currentEpoch();
        require(marketListings[currentEpoch][tokenId].isActive, "BM: Not listed");
        require(marketListings[currentEpoch][tokenId].owner == msg.sender, "BM: Not listing owner");
        delete marketListings[currentEpoch][tokenId];
        
        // 从所有挂牌列表中移除
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (listedTokenIds[i] == tokenId) {
                for (uint256 j = i; j < listedTokenIds.length - 1; j++) {
                    listedTokenIds[j] = listedTokenIds[j + 1];
                }
                listedTokenIds.pop();
                break;
            }
        }
        
        // 从活跃挂牌列表中移除
        for (uint256 i = 0; i < activeListedTokenIds.length; i++) {
            if (activeListedTokenIds[i] == tokenId) {
                for (uint256 j = i; j < activeListedTokenIds.length - 1; j++) {
                    activeListedTokenIds[j] = activeListedTokenIds[j + 1];
                }
                activeListedTokenIds.pop();
                break;
            }
        }
        
        emit MarketListingRemoved(tokenId, msg.sender);
    }

    // ============================
    // 查询功能
    // ============================
    
    /**
     * @dev 获取所有活跃挂牌的NFT ID列表
     * @return uint256[] 活跃挂牌NFT ID数组
     */
    function getMarketListingIds() external view returns (uint256[] memory) {
        return activeListedTokenIds;
    }

    /**
     * @dev 获取特定NFT的挂牌信息
     * @param tokenId NFT ID
     * @return MarketListing 挂牌信息结构体
     */
    function getMarketListing(uint256 tokenId) external view returns (MarketListing memory) { 
        return marketListings[_currentEpoch()][tokenId]; 
    }

    /**
     * @dev 获取市场挂牌总数
     * @return uint256 挂牌总数
     */
    function getMarketListingCount() external view returns (uint256) { 
        return listedTokenIds.length; 
    }

    // ============================
    // 接收函数
    // ============================
    
    /// @dev 接收ETH转账
    receive() external payable {}
    
    /// @dev 接收ETH转账（备用）
    fallback() external payable {}

    // ============================
    // 数据重置功能
    // ============================

    /**
     * @dev 重置合约核心状态数据
     * @notice 仅owner或授权合约可调用，用于紧急情况下的数据重置
     * @dev 通过递增epoch版本号实现快速数据重置，旧mapping数据自动失效
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        
        // 清空挂牌数组
        delete listedTokenIds;
        delete activeListedTokenIds;

        // 重置暂停状态
        paused = false;
        pauseReason = "";

        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}