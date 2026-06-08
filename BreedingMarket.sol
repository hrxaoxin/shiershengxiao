// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";

contract BreedingMarket is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    address public authorizer;
    address public nftMintContract;
    address public breedingCoreContract;

    bool public paused;
    string public pauseReason;

    struct MarketListing { 
        uint256 tokenId; 
        address owner; 
        uint256 listTime; 
        bool isActive; 
    }

    mapping(uint256 => MarketListing) public marketListings;
    uint256[] public listedTokenIds;
    uint256[] public activeListedTokenIds;

    event Paused(address indexed account, string reason);
    event Unpaused(address indexed account);
    event MarketListingCreated(uint256 indexed tokenId, address indexed owner);
    event MarketListingRemoved(uint256 indexed tokenId, address indexed owner);

    modifier whenNotPaused() {
        require(!paused, "BM: Paused");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "BM: Not authorized");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizer, address _breedingCore) external initializer {
        require(_authorizer != address(0), "BM: Invalid authorizer address");
        require(_breedingCore != address(0), "BM: Invalid breeding core address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
        breedingCoreContract = _breedingCore;
    }

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "BM: Invalid authorizer address");
        authorizer = a;
    }

    function setBreedingCore(address _breedingCore) external onlyOwner {
        require(_breedingCore != address(0), "BM: Invalid breeding core address");
        breedingCoreContract = _breedingCore;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    function setNFTContract(address _nftContract) external onlyAuthorized { 
        require(_nftContract != address(0), "BM: Invalid NFT contract address"); 
        nftMintContract = _nftContract; 
    }

    receive() external payable {}
    fallback() external payable {}
}