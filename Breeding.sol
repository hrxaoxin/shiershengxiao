// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IFiveBlessingsNFT {
    enum ZodiacType {
        ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1, ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
        ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0, ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,
        FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1, FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
        FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0, FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,
        HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1, HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
        HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0, HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,
        AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1, AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
        AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0, AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,
        GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1, GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
        GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0, GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
    }

    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external payable;
    function safeTransferFrom(address from, address to, uint256 tokenId) external payable;
    function tokenType(uint256 tokenId) external view returns (ZodiacType);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function nextCardId() external view returns (uint256);
    function mintBreedResult(address to, ZodiacType t) external returns (uint256);
}

contract Breeding is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable
{
    using Counters for Counters.Counter;
    Counters.Counter private _nonce;

    uint256 public constant BREEDING_DURATION_SELF = 12 hours;
    uint256 public constant BREEDING_DURATION_MARKET = 24 hours;
    uint8 public constant MIN_BREEDING_LEVEL = 5;

    IFiveBlessingsNFT public nftContract;

    struct BreedingOrder {
        address owner1;
        address owner2;
        uint256 tokenId1;
        uint256 tokenId2;
        uint64 startTime;
        bool completed;
    }

    mapping(bytes32 => BreedingOrder) public breedingOrders;
    mapping(address => bytes32[]) public userBreedingOrders;

    uint256[60] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC721Holder_init();
        _nonce.increment();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setNFTContract(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "Invalid address");
        nftContract = IFiveBlessingsNFT(_nftContract);
    }

    function getZodiacIndex(IFiveBlessingsNFT.ZodiacType t) internal pure returns (uint8) {
        return uint8(uint256(t) % 12);
    }

    function getGender(IFiveBlessingsNFT.ZodiacType t) internal pure returns (uint8) {
        return uint8(uint256(t) % 2);
    }

    function isSameZodiacDifferentGender(IFiveBlessingsNFT.ZodiacType t1, IFiveBlessingsNFT.ZodiacType t2) internal pure returns (bool) {
        return getZodiacIndex(t1) == getZodiacIndex(t2) && getGender(t1) != getGender(t2);
    }

    function startSelfBreeding(uint256 tokenId1, uint256 tokenId2) external nonReentrant returns (bytes32) {
        require(nftContract.ownerOf(tokenId1) == msg.sender, "Not owner of token1");
        require(nftContract.ownerOf(tokenId2) == msg.sender, "Not owner of token2");
        require(tokenId1 != tokenId2, "Cannot breed same token");

        IFiveBlessingsNFT.ZodiacType t1 = nftContract.tokenType(tokenId1);
        IFiveBlessingsNFT.ZodiacType t2 = nftContract.tokenType(tokenId2);
        require(isSameZodiacDifferentGender(t1, t2), "Must be same zodiac different gender");

        uint8 level1 = nftContract.tokenLevel(tokenId1);
        uint8 level2 = nftContract.tokenLevel(tokenId2);
        require(level1 >= MIN_BREEDING_LEVEL && level2 >= MIN_BREEDING_LEVEL, "Level too low");

        nftContract.safeTransferFrom(msg.sender, address(this), tokenId1);
        nftContract.safeTransferFrom(msg.sender, address(this), tokenId2);

        bytes32 orderId = keccak256(abi.encodePacked(tokenId1, tokenId2, block.timestamp, msg.sender));
        breedingOrders[orderId] = BreedingOrder({
            owner1: msg.sender,
            owner2: msg.sender,
            tokenId1: tokenId1,
            tokenId2: tokenId2,
            startTime: uint64(block.timestamp),
            completed: false
        });
        userBreedingOrders[msg.sender].push(orderId);

        emit BreedingStarted(orderId, msg.sender, tokenId1, tokenId2, true);
        return orderId;
    }

    function completeSelfBreeding(bytes32 orderId) external nonReentrant returns (uint256) {
        BreedingOrder memory order = breedingOrders[orderId];
        require(order.owner1 == msg.sender, "Not the breeder");
        require(order.owner1 == order.owner2, "Not a self-breeding order");
        require(!order.completed, "Already completed");
        require(uint64(block.timestamp) >= order.startTime + BREEDING_DURATION_SELF, "Breeding not ready");

        breedingOrders[orderId].completed = true;

        nftContract.safeTransferFrom(address(this), msg.sender, order.tokenId1);
        nftContract.safeTransferFrom(address(this), msg.sender, order.tokenId2);

        _nonce.increment();
        uint256 r = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            orderId,
            block.timestamp,
            _nonce.current(),
            gasleft()
        ))) % 2;

        IFiveBlessingsNFT.ZodiacType parentType = r == 0 ? nftContract.tokenType(order.tokenId1) : nftContract.tokenType(order.tokenId2);
        uint8 zodiacIndex = getZodiacIndex(parentType);
        uint8 gender = uint8(uint256(keccak256(abi.encodePacked(orderId, "gender"))) % 2);
        IFiveBlessingsNFT.ZodiacType newType = IFiveBlessingsNFT.ZodiacType(zodiacIndex + gender * 12);

        uint256 newTokenId = nftContract.mintBreedResult(msg.sender, newType);

        emit BreedingCompleted(orderId, msg.sender, newTokenId, newType);
        return newTokenId;
    }

    function listForBreeding(uint256 tokenId) external nonReentrant returns (bytes32) {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not owner of token");
        require(nftContract.tokenLevel(tokenId) >= MIN_BREEDING_LEVEL, "Level too low");

        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);

        bytes32 orderId = keccak256(abi.encodePacked(tokenId, block.timestamp, msg.sender));
        breedingOrders[orderId] = BreedingOrder({
            owner1: msg.sender,
            owner2: address(0),
            tokenId1: tokenId,
            tokenId2: 0,
            startTime: 0,
            completed: false
        });
        userBreedingOrders[msg.sender].push(orderId);

        emit BreedingListed(orderId, msg.sender, tokenId);
        return orderId;
    }

    function joinBreeding(bytes32 orderId, uint256 tokenId) external nonReentrant {
        BreedingOrder memory order = breedingOrders[orderId];
        require(order.owner2 == address(0), "Already has participant");
        require(order.owner1 != msg.sender, "Cannot join own listing");
        require(!order.completed, "Order already completed");
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not owner of tokenId");

        IFiveBlessingsNFT.ZodiacType t1 = nftContract.tokenType(order.tokenId1);
        IFiveBlessingsNFT.ZodiacType t2 = nftContract.tokenType(tokenId);
        require(isSameZodiacDifferentGender(t1, t2), "Must be same zodiac different gender");

        uint8 level2 = nftContract.tokenLevel(tokenId);
        require(level2 >= MIN_BREEDING_LEVEL, "Level too low");

        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);

        breedingOrders[orderId].owner2 = msg.sender;
        breedingOrders[orderId].tokenId2 = tokenId;
        breedingOrders[orderId].startTime = uint64(block.timestamp);
        userBreedingOrders[msg.sender].push(orderId);

        emit BreedingJoined(orderId, msg.sender, tokenId);
    }

    function completeMarketBreeding(bytes32 orderId) external nonReentrant returns (uint256[2] memory) {
        BreedingOrder memory order = breedingOrders[orderId];
        require(order.owner2 != address(0), "No participant yet");
        require(!order.completed, "Already completed");
        require(order.owner1 == msg.sender || order.owner2 == msg.sender, "Not a participant");
        require(uint64(block.timestamp) >= order.startTime + BREEDING_DURATION_MARKET, "Breeding not ready");

        breedingOrders[orderId].completed = true;

        nftContract.safeTransferFrom(address(this), order.owner1, order.tokenId1);
        nftContract.safeTransferFrom(address(this), order.owner2, order.tokenId2);

        _nonce.increment();
        uint256 r = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            orderId,
            block.timestamp,
            _nonce.current(),
            gasleft()
        ))) % 2;

        IFiveBlessingsNFT.ZodiacType parentType = r == 0 ? nftContract.tokenType(order.tokenId1) : nftContract.tokenType(order.tokenId2);
        uint8 zodiacIndex = getZodiacIndex(parentType);

        _nonce.increment();
        uint8 gender1 = uint8(uint256(keccak256(abi.encodePacked(orderId, "gender1", _nonce.current()))) % 2);
        IFiveBlessingsNFT.ZodiacType newType1 = IFiveBlessingsNFT.ZodiacType(zodiacIndex + gender1 * 12);
        uint256 newTokenId1 = nftContract.mintBreedResult(order.owner1, newType1);

        _nonce.increment();
        uint8 gender2 = uint8(uint256(keccak256(abi.encodePacked(orderId, "gender2", _nonce.current()))) % 2);
        IFiveBlessingsNFT.ZodiacType newType2 = IFiveBlessingsNFT.ZodiacType(zodiacIndex + gender2 * 12);
        uint256 newTokenId2 = nftContract.mintBreedResult(order.owner2, newType2);

        emit BreedingCompleted(orderId, order.owner1, newTokenId1, newType1);
        emit BreedingCompleted(orderId, order.owner2, newTokenId2, newType2);

        return [newTokenId1, newTokenId2];
    }

    function getMarketBreedingOrders() external view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](userBreedingOrders[address(this)].length);
        for (uint256 i = 0; i < userBreedingOrders[address(this)].length; i++) {
            result[i] = userBreedingOrders[address(this)][i];
        }
        return result;
    }

    function getMarketBreedingOrder(bytes32 orderId) external view returns (
        address owner1,
        address owner2,
        uint256 tokenId1,
        uint256 tokenId2,
        uint64 startTime,
        bool completed
    ) {
        BreedingOrder memory order = breedingOrders[orderId];
        return (order.owner1, order.owner2, order.tokenId1, order.tokenId2, order.startTime, order.completed);
    }

    function cancelBreedingListing(bytes32 orderId) external nonReentrant {
        BreedingOrder memory order = breedingOrders[orderId];
        require(order.owner1 == msg.sender, "Not the owner");
        require(order.owner2 == address(0), "Already has participant");
        require(!order.completed, "Already completed");
        require(order.startTime == 0, "Breeding already started");

        nftContract.safeTransferFrom(address(this), msg.sender, order.tokenId1);
        breedingOrders[orderId].completed = true;

        emit BreedingCancelled(orderId);
    }

    function getUserBreedingOrders(address user) external view returns (bytes32[] memory) {
        return userBreedingOrders[user];
    }

    event BreedingStarted(bytes32 indexed orderId, address indexed breeder, uint256 tokenId1, uint256 tokenId2, bool isSelf);
    event BreedingListed(bytes32 indexed orderId, address indexed owner, uint256 tokenId);
    event BreedingJoined(bytes32 indexed orderId, address indexed participant, uint256 tokenId);
    event BreedingCompleted(bytes32 indexed orderId, address indexed owner, uint256 newTokenId, IFiveBlessingsNFT.ZodiacType newType);
    event BreedingCancelled(bytes32 indexed orderId);
}
