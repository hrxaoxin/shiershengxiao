// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title NFTMintBatch
 * @dev NFT批量铸造合约，支持批量铸造多个NFT
 * 
 * 核心职责：
 * 1. 批量铸造：支持一次性铸造多个NFT
 * 2. 十连抽：支持一次铸造10个普通或稀有NFT
 * 3. 随机生成：使用安全随机数生成NFT类型和成长值
 * 
 * 批量铸造方式：
 * 1. mintBatch(): 指定多个类型进行批量铸造
 * 2. mintNormalTen(): 一次铸造10个普通NFT（水/风/火属性）
 * 3. mintRareTen(): 一次铸造10个稀有NFT（暗/光属性）
 * 
 * 随机数生成：
 * - 使用baseSeed + i * 7919生成每个NFT的种子
 * - 确保每个NFT有独立的随机值
 * - 7919是一个大质数，用于分散种子
 * 
 * 安全机制：
 * - ReentrancyGuard: 防止重入攻击
 * - Pausable: 可暂停铸造
 * - 权限控制：仅TokenBurner合约可调用
 * 
 * 与NFTMintCore的交互：
 * - 调用NFTMintCore的mint()和mintWithGrowth()方法
 * - 批量铸造时逐个调用
 */
contract NFTMintBatch is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using NFTLib for uint256;
    
    /**
     * @dev NFT铸造核心合约地址
     */
    address public nftMintCore;
    
    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;
    
    /**
     * @dev 是否暂停铸造
     */
    bool public paused;
    
    /**
     * @dev 批量铸造事件
     */
    event BatchMint(address indexed to, uint256[] tokenIds);
    
    /**
     * @dev 修饰器：确保合约未暂停
     */
    modifier whenNotPaused() {
        require(!paused, "NFTMintBatch: Contract paused");
        _;
    }
    
    /**
     * @dev 修饰器：仅TokenBurner合约可调用
     */
    modifier onlyTokenBurner() {
        require(msg.sender == INFTMintCore(nftMintCore).tokenBurnerContract(), "NFTMintBatch: Only TokenBurner");
        _;
    }
    
    /**
     * @dev 修饰器：仅所有者或授权器可调用
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTMintBatch: Not owner or authorizer");
        _;
    }
    
    /**
     * @dev 初始化函数
     * @param _nftMintCoreAddress NFT铸造核心合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _nftMintCoreAddress, address _authorizerAddress) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        require(_nftMintCoreAddress != address(0), "NFTMintBatch: Invalid NFTMintCore address");
        require(_authorizerAddress != address(0), "NFTMintBatch: Invalid authorizer address");
        nftMintCore = _nftMintCoreAddress;
        authorizer = _authorizerAddress;
    }
    
    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev 批量铸造NFT（指定类型）
     * @param to 接收地址
     * @param zodiacTypes NFT类型数组
     * @return tokenIds 铸造的NFT ID数组
     */
    function mintBatch(address to, uint256[] calldata zodiacTypes) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Zero address");
        uint256[] memory tokenIds = new uint256[](zodiacTypes.length);
        
        for (uint256 i = 0; i < zodiacTypes.length; i++) {
            require(zodiacTypes[i] < 120, "NFTMint: Invalid type");
            uint256 tokenId = INFTMintCore(nftMintCore).mint(to, zodiacTypes[i]);
            tokenIds[i] = tokenId;
        }
        
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    /**
     * @dev 十连抽普通NFT（水/风/火属性）
     * @param to 接收地址
     * @return tokenIds 铸造的NFT ID数组
     */
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
    
    /**
     * @dev 十连抽稀有NFT（暗/光属性）
     * @param to 接收地址
     * @return tokenIds 铸造的NFT ID数组
     */
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
    
    function setNftMintCore(address _nftMintCoreAddress) external onlyOwnerOrAuthorizer {
        require(_nftMintCoreAddress != address(0), "NFTMintBatch: Invalid address");
        nftMintCore = _nftMintCoreAddress;
    }
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "NFTMintBatch: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }
    
    function pause() external onlyOwner {
        paused = true;
    }
    
    function unpause() external onlyOwner {
        paused = false;
    }
}