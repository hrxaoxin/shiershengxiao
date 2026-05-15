// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title Breeding
 * @dev NFT繁殖合约，支持自繁殖和市场繁殖两种模式
 * 
 * 繁殖规则：
 * - 只有5级NFT可以繁殖
 * - 父母必须是同一生肖
 * - 繁殖时间：自繁殖12小时，市场繁殖24小时（可配置）
 * - 繁殖结果：产生一个新的NFT，属性继承自父母之一
 */
contract Breeding is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IBreeding {
    /** @dev 最小繁殖等级（必须是5级NFT才能繁殖） */
    uint8 public constant MIN_BREEDING_LEVEL = 5;
    /** @dev 自繁殖时长（默认12小时）*/
    uint256 public soloBreedDuration = 12 hours;
    /** @dev 市场繁殖时长（默认24小时）*/
    uint256 public pairBreedDuration = 24 hours;
    /** @dev 最大繁殖时间上限，防止时间绕过攻击（7天）*/
    uint256 public constant MAX_BREED_DURATION = 7 days;

    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 授权合约地址 */
    address public authorizer;
    /** @dev 竞技场排名合约地址（用于检查NFT是否在竞技场中）*/
    address public arenaRankingContract;

    /**
     * @dev 繁殖订单结构体
     * @param owner1 第一个NFT所有者
     * @param owner2 第二个NFT所有者（自繁殖时与owner1相同）
     * @param tokenId1 第一个NFT ID
     * @param tokenId2 第二个NFT ID
     * @param startTime 繁殖开始时间
     * @param completed 是否完成
     * @param cancelled 是否取消
     * @param resultType1 繁殖结果类型（owner1获得）
     * @param resultType2 繁殖结果类型（owner2获得）
     * @param owner1Claimed owner1是否已领取
     * @param owner2Claimed owner2是否已领取
     */
    struct BreedingOrder {
        address owner1;
        address owner2;
        uint256 tokenId1;
        uint256 tokenId2;
        uint256 startTime;
        bool completed;
        bool cancelled;
        NFTDataTypes.ZodiacType resultType1;
        NFTDataTypes.ZodiacType resultType2;
        bool owner1Claimed;
        bool owner2Claimed;
    }

    /** @dev 繁殖订单映射：orderId -> BreedingOrder */
    mapping(uint256 => BreedingOrder) public breedingOrders;
    /** @dev NFT到订单的映射：tokenId -> orderId（用于检查NFT是否正在繁殖）*/
    mapping(uint256 => uint256) public tokenToOrderId;
    /** @dev 用户繁殖订单列表：user -> orderId数组 */
    mapping(address => uint256[]) public userBreedingOrders;
    /** @dev 下一个订单ID */
    uint256 public nextOrderId;

    /**
     * @dev 自繁殖开始事件
     * @param orderId 订单ID
     * @param owner 所有者地址
     * @param tokenId1 第一个NFT ID
     * @param tokenId2 第二个NFT ID
     * @param startTime 开始时间
     */
    event SelfBreedingStarted(uint256 indexed orderId, address indexed owner, uint256 tokenId1, uint256 tokenId2, uint256 startTime);
    
    /**
     * @dev 繁殖上架事件
     * @param orderId 订单ID
     * @param owner 所有者地址
     * @param tokenId NFT ID
     */
    event BreedingListed(uint256 indexed orderId, address indexed owner, uint256 tokenId);
    
    /**
     * @dev 加入繁殖事件
     * @param orderId 订单ID
     * @param joiner 加入者地址
     * @param tokenId NFT ID
     */
    event BreedingJoined(uint256 indexed orderId, address indexed joiner, uint256 tokenId);
    
    /**
     * @dev 繁殖完成事件
     * @param orderId 订单ID
     * @param resultType1 结果类型1
     * @param resultType2 结果类型2
     */
    event BreedingCompleted(uint256 indexed orderId, NFTDataTypes.ZodiacType resultType1, NFTDataTypes.ZodiacType resultType2);
    
    /**
     * @dev 繁殖领取事件
     * @param orderId 订单ID
     * @param owner 所有者地址
     * @param newTokenId 新NFT ID
     */
    event BreedingClaimed(uint256 indexed orderId, address indexed owner, uint256 newTokenId);
    
    /**
     * @dev 繁殖取消事件
     * @param orderId 订单ID
     * @param owner 所有者地址
     */
    event BreedingCancelled(uint256 indexed orderId, address indexed owner);

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    /**
     * @dev 初始化合约
     * @param _nftContract NFT合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _nftContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        nftContract = _nftContract;
        authorizer = _authorizer;
        nextOrderId = 1;
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 开始自繁殖（用户使用自己的两个NFT繁殖）
     * @param tokenId1 第一个NFT ID
     * @param tokenId2 第二个NFT ID
     */
    function startSelfBreeding(uint256 tokenId1, uint256 tokenId2) external nonReentrant whenNotPaused {
        require(tokenId1 != tokenId2, "Breeding: Cannot breed the same NFT");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId1) == msg.sender, "Breeding: Not owner of first NFT");
        require(nft.ownerOf(tokenId2) == msg.sender, "Breeding: Not owner of second NFT");

        uint8 level1 = nft.tokenLevel(tokenId1);
        uint8 level2 = nft.tokenLevel(tokenId2);
        require(level1 == MIN_BREEDING_LEVEL, "Breeding: First NFT level too low");
        require(level2 == MIN_BREEDING_LEVEL, "Breeding: Second NFT level too low");

        if (arenaRankingContract != address(0)) {
            require(!IArenaRanking(arenaRankingContract).isNFTInArena(tokenId1), 
                    "Breeding: First NFT is in arena team");
            require(!IArenaRanking(arenaRankingContract).isNFTInArena(tokenId2), 
                    "Breeding: Second NFT is in arena team");
        }

        require(tokenToOrderId[tokenId1] == 0, "Breeding: Token1 already in breeding");
        require(tokenToOrderId[tokenId2] == 0, "Breeding: Token2 already in breeding");

        NFTDataTypes.ZodiacType type1 = nft.tokenType(tokenId1);
        NFTDataTypes.ZodiacType type2 = nft.tokenType(tokenId2);
        
        NFTDataTypes.BaseZodiac zodiac1 = NFTDataTypes.getBaseZodiac(type1);
        NFTDataTypes.BaseZodiac zodiac2 = NFTDataTypes.getBaseZodiac(type2);
        require(zodiac1 == zodiac2, "Breeding: Parents must have same zodiac");

        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                (nft.getApproved(tokenId1) == address(this) && nft.getApproved(tokenId2) == address(this)), 
                "Breeding: Contract not approved");

        nft.safeTransferFrom(msg.sender, address(this), tokenId1);
        nft.safeTransferFrom(msg.sender, address(this), tokenId2);

        uint256 orderId = nextOrderId++;
        breedingOrders[orderId] = BreedingOrder({
            owner1: msg.sender,
            owner2: msg.sender,
            tokenId1: tokenId1,
            tokenId2: tokenId2,
            startTime: block.timestamp,
            completed: false,
            cancelled: false,
            resultType1: NFTDataTypes.ZodiacType(0),
            resultType2: NFTDataTypes.ZodiacType(0),
            owner1Claimed: false,
            owner2Claimed: false
        });

        tokenToOrderId[tokenId1] = orderId;
        tokenToOrderId[tokenId2] = orderId;
        userBreedingOrders[msg.sender].push(orderId);

        emit SelfBreedingStarted(orderId, msg.sender, tokenId1, tokenId2, block.timestamp);
    }

    /**
     * @dev 上架繁殖（将NFT上架到市场等待其他用户配对）
     * @param tokenId NFT ID
     */
    function listForBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Breeding: Not owner of NFT");
        
        uint8 level = nft.tokenLevel(tokenId);
        require(level == MIN_BREEDING_LEVEL, "Breeding: NFT level too low");
        require(tokenToOrderId[tokenId] == 0, "Breeding: Token already in breeding");

        if (arenaRankingContract != address(0)) {
            require(!IArenaRanking(arenaRankingContract).isNFTInArena(tokenId), 
                    "Breeding: NFT is in arena team");
        }

        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), 
                "Breeding: Contract not approved");

        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        uint256 orderId = nextOrderId++;
        breedingOrders[orderId] = BreedingOrder({
            owner1: msg.sender,
            owner2: address(0),
            tokenId1: tokenId,
            tokenId2: 0,
            startTime: block.timestamp,
            completed: false,
            cancelled: false,
            resultType1: NFTDataTypes.ZodiacType(0),
            resultType2: NFTDataTypes.ZodiacType(0),
            owner1Claimed: false,
            owner2Claimed: false
        });

        tokenToOrderId[tokenId] = orderId;
        userBreedingOrders[msg.sender].push(orderId);

        emit BreedingListed(orderId, msg.sender, tokenId);
    }

    /**
     * @dev 加入繁殖（加入其他用户上架的繁殖订单）
     * @param orderId 订单ID
     * @param tokenId 用户提供的NFT ID
     */
    function joinBreeding(uint256 orderId, uint256 tokenId) external nonReentrant whenNotPaused {
        BreedingOrder storage order = breedingOrders[orderId];
        require(order.owner1 != address(0), "Breeding: Order not found");
        require(order.owner2 == address(0), "Breeding: Order already has two participants");
        require(order.completed == false, "Breeding: Order already completed");
        require(order.cancelled == false, "Breeding: Order cancelled");
        require(order.owner1 != msg.sender, "Breeding: Cannot join your own order");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Breeding: Not owner of NFT");
        
        uint8 level = nft.tokenLevel(tokenId);
        require(level == MIN_BREEDING_LEVEL, "Breeding: NFT level too low");
        require(tokenToOrderId[tokenId] == 0, "Breeding: Token already in breeding");

        if (arenaRankingContract != address(0)) {
            require(!IArenaRanking(arenaRankingContract).isNFTInArena(tokenId), 
                    "Breeding: NFT is in arena team");
        }

        NFTDataTypes.ZodiacType type1 = nft.tokenType(order.tokenId1);
        NFTDataTypes.ZodiacType type2 = nft.tokenType(tokenId);
        
        NFTDataTypes.BaseZodiac zodiac1 = NFTDataTypes.getBaseZodiac(type1);
        NFTDataTypes.BaseZodiac zodiac2 = NFTDataTypes.getBaseZodiac(type2);
        require(zodiac1 == zodiac2, "Breeding: Must have same zodiac");

        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), 
                "Breeding: Contract not approved");

        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        order.owner2 = msg.sender;
        order.tokenId2 = tokenId;
        order.startTime = block.timestamp;

        tokenToOrderId[tokenId] = orderId;
        userBreedingOrders[msg.sender].push(orderId);

        emit BreedingJoined(orderId, msg.sender, tokenId);
    }

    /**
     * @dev 完成自繁殖（领取繁殖结果）
     * @param orderId 订单ID
     */
    function completeSelfBreeding(uint256 orderId) external nonReentrant whenNotPaused {
        BreedingOrder storage order = breedingOrders[orderId];
        require(order.owner1 == msg.sender, "Breeding: Not the owner");
        require(order.completed == false, "Breeding: Already completed");
        require(order.cancelled == false, "Breeding: Order cancelled");
        require(order.owner1 == order.owner2, "Breeding: Not a self breeding");

        uint256 endTime = order.startTime + soloBreedDuration;
        uint256 maxEndTime = order.startTime + MAX_BREED_DURATION;
        require(block.timestamp >= endTime, "Breeding: Breeding not ready");
        require(block.timestamp <= maxEndTime, "Breeding: Breeding window expired");

        INFTMint nft = INFTMint(nftContract);
        
        NFTDataTypes.ZodiacType type1 = nft.tokenType(order.tokenId1);
        NFTDataTypes.ZodiacType type2 = nft.tokenType(order.tokenId2);
        
        NFTDataTypes.ZodiacType resultType = _calculateNewType(type1, type2);

        nft.safeTransferFrom(address(this), msg.sender, order.tokenId1);
        nft.safeTransferFrom(address(this), msg.sender, order.tokenId2);
        
        tokenToOrderId[order.tokenId1] = 0;
        tokenToOrderId[order.tokenId2] = 0;

        uint256 newTokenId = nft.mintBreedResult(msg.sender, resultType);

        order.completed = true;
        order.resultType1 = resultType;
        order.owner1Claimed = true;

        emit BreedingCompleted(orderId, resultType, NFTDataTypes.ZodiacType(0));
        emit BreedingClaimed(orderId, msg.sender, newTokenId);
    }

    /**
     * @dev 完成市场繁殖（领取繁殖结果）
     * @param orderId 订单ID
     */
    function completeMarketBreeding(uint256 orderId) external nonReentrant whenNotPaused {
        BreedingOrder storage order = breedingOrders[orderId];
        require(order.completed == false, "Breeding: Already completed");
        require(order.cancelled == false, "Breeding: Order cancelled");
        require(order.owner2 != address(0), "Breeding: Waiting for second participant");
        require(msg.sender == order.owner1 || msg.sender == order.owner2, "Breeding: Not a participant");

        uint256 endTime = order.startTime + pairBreedDuration;
        uint256 maxEndTime = order.startTime + MAX_BREED_DURATION;
        require(block.timestamp >= endTime, "Breeding: Breeding not ready");
        require(block.timestamp <= maxEndTime, "Breeding: Breeding window expired");

        INFTMint nft = INFTMint(nftContract);
        
        // 首次调用时计算繁殖结果并标记完成
        if (order.resultType1 == NFTDataTypes.ZodiacType(0)) {
            NFTDataTypes.ZodiacType type1 = nft.tokenType(order.tokenId1);
            NFTDataTypes.ZodiacType type2 = nft.tokenType(order.tokenId2);
            
            order.resultType1 = _calculateNewType(type1, type2);
            order.resultType2 = _calculateNewType(type2, type1);
            order.completed = true;
            
            emit BreedingCompleted(orderId, order.resultType1, order.resultType2);
        }

        bool claimed = false;
        
        if (msg.sender == order.owner1 && !order.owner1Claimed) {
            nft.safeTransferFrom(address(this), msg.sender, order.tokenId1);
            tokenToOrderId[order.tokenId1] = 0;
            
            uint256 newTokenId = nft.mintBreedResult(msg.sender, order.resultType1);
            order.owner1Claimed = true;
            claimed = true;
            
            emit BreedingClaimed(orderId, msg.sender, newTokenId);
        } else if (msg.sender == order.owner2 && !order.owner2Claimed) {
            nft.safeTransferFrom(address(this), msg.sender, order.tokenId2);
            tokenToOrderId[order.tokenId2] = 0;
            
            uint256 newTokenId = nft.mintBreedResult(msg.sender, order.resultType2);
            order.owner2Claimed = true;
            claimed = true;
            
            emit BreedingClaimed(orderId, msg.sender, newTokenId);
        }
        
        // 当双方都领取完成后，清理订单数据
        if (claimed && order.owner1Claimed && order.owner2Claimed) {
            _cleanupBreedingOrder(orderId);
        }
    }
    
    /**
     * @dev 清理繁殖订单数据
     * @param orderId 订单ID
     */
    function _cleanupBreedingOrder(uint256 orderId) internal {
        BreedingOrder storage order = breedingOrders[orderId];
        
        // 清理 tokenToOrderId（如果还有残留）
        if (order.tokenId1 != 0 && tokenToOrderId[order.tokenId1] == orderId) {
            tokenToOrderId[order.tokenId1] = 0;
        }
        if (order.tokenId2 != 0 && tokenToOrderId[order.tokenId2] == orderId) {
            tokenToOrderId[order.tokenId2] = 0;
        }
        
        // 清理用户订单列表引用
        _removeFromUserBreedingOrders(order.owner1, orderId);
        if (order.owner2 != address(0) && order.owner2 != order.owner1) {
            _removeFromUserBreedingOrders(order.owner2, orderId);
        }
        
        // 重置订单数据
        delete breedingOrders[orderId];
    }
    
    /**
     * @dev 从用户订单列表中移除指定订单
     * @param user 用户地址
     * @param orderId 订单ID
     */
    function _removeFromUserBreedingOrders(address user, uint256 orderId) internal {
        if (user == address(0)) return;
        uint256[] storage orders = userBreedingOrders[user];
        uint256 length = orders.length;
        for (uint256 i = 0; i < length; i++) {
            if (orders[i] == orderId) {
                if (length > 1) {
                    orders[i] = orders[length - 1];
                }
                orders.pop();
                break;
            }
        }
    }

    /**
     * @dev 取消繁殖上架（在其他用户加入前取消）
     * @param orderId 订单ID
     */
    function cancelBreedingListing(uint256 orderId) external nonReentrant whenNotPaused {
        BreedingOrder storage order = breedingOrders[orderId];
        require(order.owner1 == msg.sender, "Breeding: Not the owner");
        require(order.owner2 == address(0), "Breeding: Cannot cancel after joined");
        require(order.completed == false, "Breeding: Already completed");
        require(order.cancelled == false, "Breeding: Already cancelled");

        INFTMint nft = INFTMint(nftContract);
        nft.safeTransferFrom(address(this), msg.sender, order.tokenId1);
        tokenToOrderId[order.tokenId1] = 0;

        order.cancelled = true;

        emit BreedingCancelled(orderId, msg.sender);
    }

    /**
     * @dev 获取市场繁殖订单列表（等待配对的订单）
     * @return uint256[] 订单ID列表
     */
    function getMarketBreedingOrders() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextOrderId; i++) {
            BreedingOrder storage order = breedingOrders[i];
            if (order.owner1 != address(0) && order.owner2 == address(0) && !order.completed && !order.cancelled) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i < nextOrderId; i++) {
            BreedingOrder storage order = breedingOrders[i];
            if (order.owner1 != address(0) && order.owner2 == address(0) && !order.completed && !order.cancelled) {
                result[index++] = i;
            }
        }

        return result;
    }

    /**
     * @dev 获取用户繁殖订单列表
     * @param user 用户地址
     * @return uint256[] 订单ID列表
     */
    function getUserBreedingOrders(address user) external view returns (uint256[] memory) {
        return userBreedingOrders[user];
    }

    /**
     * @dev 计算新NFT类型（繁殖结果）
     * 属性随机继承自父母之一，性别随机
     * @param type1 父NFT类型
     * @param type2 母NFT类型
     * @return NFTDataTypes.ZodiacType 新NFT类型
     */
    function _calculateNewType(NFTDataTypes.ZodiacType type1, NFTDataTypes.ZodiacType type2) internal view returns (NFTDataTypes.ZodiacType) {
        NFTDataTypes.ElementType element1 = NFTDataTypes.getElement(type1);
        NFTDataTypes.ElementType element2 = NFTDataTypes.getElement(type2);
        NFTDataTypes.BaseZodiac zodiac = NFTDataTypes.getBaseZodiac(type1);

        uint256 rand = _random(uint256(type1) + uint256(type2));
        
        NFTDataTypes.ElementType newElement = (rand % 2) == 0 ? element1 : element2;
        NFTDataTypes.GenderType newGender = (rand % 2) == 0 ? NFTDataTypes.GenderType.FEMALE : NFTDataTypes.GenderType.MALE;

        return NFTDataTypes.createZodiacType(newElement, zodiac, newGender);
    }

    /**
     * @dev 生成随机数
     * @param seed 种子值
     * @return uint256 随机数
     */
    function _random(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(
            abi.encodePacked(
                blockhash(block.number > 1 ? block.number - 1 : block.number),
                seed,
                block.timestamp,
                gasleft(),
                block.prevrandao
            )
        ));
    }

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Unauthorized");
        require(_nftContract != address(0), "Breeding: Zero address");
        nftContract = _nftContract;
    }

    /**
     * @dev 设置竞技场排名合约地址
     * @param _arenaRankingContract 竞技场排名合约地址
     */
    function setArenaRankingContract(address _arenaRankingContract) external onlyOwner {
        arenaRankingContract = _arenaRankingContract;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "Breeding: Zero address");
        authorizer = _authorizer;
    }

    /**
     * @dev 设置自繁殖时长
     * @param _duration 新时长（秒），默认12小时
     */
    function setSoloBreedDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Breeding: Duration must be greater than 0");
        require(_duration <= MAX_BREED_DURATION, "Breeding: Duration exceeds maximum");
        soloBreedDuration = _duration;
    }

    /**
     * @dev 设置市场繁殖时长
     * @param _duration 新时长（秒），默认24小时
     */
    function setPairBreedDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Breeding: Duration must be greater than 0");
        require(_duration <= MAX_BREED_DURATION, "Breeding: Duration exceeds maximum");
        pairBreedDuration = _duration;
    }

    /**
     * @dev 批量设置繁殖时长
     * @param _soloDuration 自繁殖时长（秒）
     * @param _pairDuration 市场繁殖时长（秒）
     */
    function setBreedDurations(uint256 _soloDuration, uint256 _pairDuration) external onlyOwner {
        require(_soloDuration > 0, "Breeding: Solo duration must be greater than 0");
        require(_pairDuration > 0, "Breeding: Pair duration must be greater than 0");
        require(_soloDuration <= MAX_BREED_DURATION, "Breeding: Solo duration exceeds maximum");
        require(_pairDuration <= MAX_BREED_DURATION, "Breeding: Pair duration exceeds maximum");
        soloBreedDuration = _soloDuration;
        pairBreedDuration = _pairDuration;
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner { _pause(); }
    
    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner { _unpause(); }

    function withdrawNFTs(uint256[] calldata tokenIds) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721Upgradeable(nftContract).transferFrom(address(this), owner(), tokenIds[i]);
        }
    }
}