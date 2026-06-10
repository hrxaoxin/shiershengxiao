// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract NFTMintBatch is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using NFTLib for uint256;
    
    address public nftMintCore;
    
    bool public paused;
    
    event BatchMint(address indexed to, uint256[] tokenIds);
    
    modifier whenNotPaused() {
        require(!paused, "NFTMintBatch: Contract paused");
        _;
    }
    
    function initialize(address _nftMintCore) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        nftMintCore = _nftMintCore;
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    function mintBatch(address to, uint256[] calldata zodiacTypes) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Zero address");
        uint256[] memory tokenIds = new uint256[](zodiacTypes.length);
        
        for (uint256 i = 0; i < zodiacTypes.length; i++) {
            // 修复：确保 zodiacTypes[i] 在有效范围内 (0-119)
            require(zodiacTypes[i] < 120, "NFTMint: Invalid type");
            uint256 tokenId = INFTMintCore(nftMintCore).mint(to, zodiacTypes[i]);
            tokenIds[i] = tokenId;
        }
        
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    function mintNormalTen(address to) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Zero address");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = INFTMintCore(nftMintCore).generateSecureRandom();
        
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            uint256 zodiacType = _mintNormalType(seed);
            uint8 growth = NFTLib.generateGrowthValue(seed);
            
            uint256 tokenId = INFTMintCore(nftMintCore).mintWithGrowth(to, zodiacType, growth);
            tokenIds[i] = tokenId;
        }
        
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    function mintRareTen(address to) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Zero address");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = INFTMintCore(nftMintCore).generateSecureRandom();
        
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            uint256 zodiacType = _mintRareType(seed);
            uint8 growth = NFTLib.generateGrowthValue(seed);
            
            uint256 tokenId = INFTMintCore(nftMintCore).mintWithGrowth(to, zodiacType, growth);
            tokenIds[i] = tokenId;
        }
        
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    function mintTargeted(address to, uint8 baseZodiac) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Zero address");
        require(baseZodiac < 12, "NFTMint: Invalid base zodiac");
        
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = INFTMintCore(nftMintCore).generateSecureRandom();
        
        for (uint256 element = 0; element < 5; element++) {
            for (uint256 gender = 0; gender < 2; gender++) {
                uint256 index = element * 2 + gender;
                uint256 zodiacType = NFTLib.calculateZodiacType(element, baseZodiac, gender);
                uint8 growth = NFTLib.generateGrowthValue(baseSeed + index * 9973);
                
                uint256 tokenId = INFTMintCore(nftMintCore).mintWithGrowth(to, zodiacType, growth);
                tokenIds[index] = tokenId;
            }
        }
        
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    function _mintNormalType(uint256 randomSeed) internal view returns (uint256) {
        uint256[5] memory probabilities = INFTMintCore(nftMintCore).elementProbabilities();
        uint256[5] memory cumulative;
        cumulative[0] = probabilities[0];
        for (uint256 i = 1; i < 5; i++) {
            cumulative[i] = cumulative[i-1] + probabilities[i];
        }
        
        uint256 roll = randomSeed % 100;
        uint256 element = 0;
        for (uint256 i = 0; i < 5; i++) {
            if (roll < cumulative[i]) {
                element = i;
                break;
            }
        }
        
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return NFTLib.calculateZodiacType(element, zodiac, gender);
    }
    
    function _mintRareType(uint256 randomSeed) internal view returns (uint256) {
        uint256[2] memory probabilities = INFTMintCore(nftMintCore).rareElementProbabilities();
        uint256 roll = randomSeed % 100;
        uint256 element = roll < probabilities[0] ? 3 : 4;
        
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return NFTLib.calculateZodiacType(element, zodiac, gender);
    }
    
    modifier onlyTokenBurner() {
        require(msg.sender == INFTMintCore(nftMintCore).tokenBurnerContract(), "NFTMintBatch: Only TokenBurner");
        _;
    }
    
    function setNftMintCore(address _nftMintCore) external onlyOwner {
        nftMintCore = _nftMintCore;
    }
    
    function pause() external onlyOwner {
        paused = true;
    }
    
    function unpause() external onlyOwner {
        paused = false;
    }
}