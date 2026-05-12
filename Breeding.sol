// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

contract Breeding is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    uint8 public constant MIN_BREEDING_LEVEL = 5;
    uint256 public constant SOLO_BREED_DURATION = 12 hours;
    uint256 public constant PAIR_BREED_DURATION = 24 hours;
    /** @dev 最大繁殖时间上限，防止时间绕过攻击 */
    uint256 public constant MAX_BREED_DURATION = 7 days;

    address public nftContract;
    address public authorizer;

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

    mapping(uint256 => BreedingOrder) public breedingOrders;
    mapping(uint256 => uint256) public tokenToOrderId;
    mapping(address => uint256[]) public userBreedingOrders;
    uint256 public nextOrderId;

    event SelfBreedingStarted(uint256 indexed orderId, address indexed owner, uint256 tokenId1, uint256 tokenId2, uint256 startTime);
    event BreedingListed(uint256 indexed orderId, address indexed owner, uint256 tokenId);
    event BreedingJoined(uint256 indexed orderId, address indexed joiner, uint256 tokenId);
    event BreedingCompleted(uint256 indexed orderId, NFTDataTypes.ZodiacType resultType1, NFTDataTypes.ZodiacType resultType2);
    event BreedingClaimed(uint256 indexed orderId, address indexed owner, uint256 newTokenId);
    event BreedingCancelled(uint256 indexed orderId, address indexed owner);

    uint256[50] private __gap;

    constructor() { _disableInitializers(); }

    function initialize(address _nftContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        nftContract = _nftContract;
        authorizer = _authorizer;
        nextOrderId = 1;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function startSelfBreeding(uint256 tokenId1, uint256 tokenId2) external nonReentrant whenNotPaused {
        require(tokenId1 != tokenId2, "Breeding: Cannot breed the same NFT");
        
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId1) == msg.sender, "Breeding: Not owner of first NFT");
        require(nft.ownerOf(tokenId2) == msg.sender, "Breeding: Not owner of second NFT");

        uint8 level1 = nft.tokenLevel(tokenId1);
        uint8 level2 = nft.tokenLevel(tokenId2);
        require(level1 == MIN_BREEDING_LEVEL, "Breeding: First NFT level too low");
        require(level2 == MIN_BREEDING_LEVEL, "Breeding: Second NFT level too low");

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

    function listForBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Breeding: Not owner of NFT");
        
        uint8 level = nft.tokenLevel(tokenId);
        require(level == MIN_BREEDING_LEVEL, "Breeding: NFT level too low");
        require(tokenToOrderId[tokenId] == 0, "Breeding: Token already in breeding");

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

    function completeSelfBreeding(uint256 orderId) external nonReentrant whenNotPaused {
        BreedingOrder storage order = breedingOrders[orderId];
        require(order.owner1 == msg.sender, "Breeding: Not the owner");
        require(order.completed == false, "Breeding: Already completed");
        require(order.cancelled == false, "Breeding: Order cancelled");
        require(order.owner1 == order.owner2, "Breeding: Not a self breeding");

        uint256 endTime = order.startTime + SOLO_BREED_DURATION;
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

    function completeMarketBreeding(uint256 orderId) external nonReentrant whenNotPaused {
        BreedingOrder storage order = breedingOrders[orderId];
        require(order.completed == false, "Breeding: Already completed");
        require(order.cancelled == false, "Breeding: Order cancelled");
        require(order.owner2 != address(0), "Breeding: Waiting for second participant");
        require(msg.sender == order.owner1 || msg.sender == order.owner2, "Breeding: Not a participant");

        uint256 endTime = order.startTime + PAIR_BREED_DURATION;
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

    function getUserBreedingOrders(address user) external view returns (uint256[] memory) {
        return userBreedingOrders[user];
    }

    function _calculateNewType(NFTDataTypes.ZodiacType type1, NFTDataTypes.ZodiacType type2) internal view returns (NFTDataTypes.ZodiacType) {
        NFTDataTypes.ElementType element1 = NFTDataTypes.getElement(type1);
        NFTDataTypes.ElementType element2 = NFTDataTypes.getElement(type2);
        NFTDataTypes.BaseZodiac zodiac = NFTDataTypes.getBaseZodiac(type1);

        uint256 rand = _random(uint256(type1) + uint256(type2));
        
        NFTDataTypes.ElementType newElement = (rand % 2) == 0 ? element1 : element2;
        NFTDataTypes.GenderType newGender = (rand % 2) == 0 ? NFTDataTypes.GenderType.FEMALE : NFTDataTypes.GenderType.MALE;

        return NFTDataTypes.createZodiacType(newElement, zodiac, newGender);
    }

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

    function setNFTContract(address _nftContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Unauthorized");
        require(_nftContract != address(0), "Breeding: Zero address");
        nftContract = _nftContract;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "Breeding: Zero address");
        authorizer = _authorizer;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}