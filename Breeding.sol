// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Breeding
 * @dev NFT繁殖合约，允许用户将两个等级6的NFT进行繁殖生成新NFT
 * 繁殖需要消耗代币，生成的NFT类型基于父母类型计算
 * 基于OpenZeppelin UUPS可升级合约实现
 */
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title Breeding
 * @dev NFT繁殖合约
 */
contract Breeding is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    
    /** @dev 最小繁殖等级：必须达到5级才能繁殖 */
    uint8 public constant MIN_BREEDING_LEVEL = 5;
    /** @dev 黑洞地址，用于销毁NFT - 使用标准的0x000000000000000000000000000000000000dEaD */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 繁殖事件 */
    event NFTBred(address indexed user, uint256 indexed tokenId1, uint256 indexed tokenId2, uint256 newTokenId, NFTDataTypes.ZodiacType newType, uint256 timestamp);
    /** @dev 繁殖失败事件 */
    event BreedFailed(address indexed user, uint256 indexed tokenId1, uint256 indexed tokenId2, string reason, uint256 timestamp);

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
    }

    /**
     * @dev 升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 繁殖NFT
     * 用户需要拥有两个等级为5的NFT才能进行繁殖
     * @param tokenId1 第一个NFT ID
     * @param tokenId2 第二个NFT ID
     * @return uint256 新生成的NFT ID
     */
    function breed(uint256 tokenId1, uint256 tokenId2) external nonReentrant whenNotPaused returns (uint256) {
        require(tokenId1 != tokenId2, "Breeding: Cannot breed the same NFT");

        INFTMint nft = INFTMint(nftContract);
        
        require(nft.ownerOf(tokenId1) == msg.sender, "Breeding: Not owner of first NFT");
        require(nft.ownerOf(tokenId2) == msg.sender, "Breeding: Not owner of second NFT");

        uint8 level1 = nft.tokenLevel(tokenId1);
        uint8 level2 = nft.tokenLevel(tokenId2);
        require(level1 == MIN_BREEDING_LEVEL, "Breeding: First NFT level too low");
        require(level2 == MIN_BREEDING_LEVEL, "Breeding: Second NFT level too low");

        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                nft.getApproved(tokenId1) == address(this) && 
                nft.getApproved(tokenId2) == address(this), "Breeding: Contract not approved");

        NFTDataTypes.ZodiacType type1 = nft.tokenType(tokenId1);
        NFTDataTypes.ZodiacType type2 = nft.tokenType(tokenId2);

        NFTDataTypes.ZodiacType newType = _calculateNewType(type1, type2);

        uint256 newTokenId = nft.mintBreedResult(msg.sender, newType);

        // 保留父母NFT，不再销毁
        emit NFTBred(msg.sender, tokenId1, tokenId2, newTokenId, newType, block.timestamp);
        return newTokenId;
    }

    /**
     * @dev 安全随机数生成器
     * 使用多种链上数据源增加随机性
     */
    function _random(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(
            abi.encodePacked(
                blockhash(block.number > 1 ? block.number - 1 : block.number),
                seed,
                msg.sender,
                block.timestamp,
                gasleft(),
                block.prevrandao,
                address(this).balance,
                block.difficulty,
                block.coinbase
            )
        ));
    }

    /**
     * @dev 计算繁殖产生的新NFT类型
     * 基于父母的属性和生肖计算
     * @param type1 父NFT类型
     * @param type2 母NFT类型
     * @return NFTDataTypes.ZodiacType 新NFT类型
     */
    function _calculateNewType(NFTDataTypes.ZodiacType type1, NFTDataTypes.ZodiacType type2) internal view returns (NFTDataTypes.ZodiacType) {
        NFTDataTypes.ElementType element1 = NFTDataTypes.getElement(type1);
        NFTDataTypes.ElementType element2 = NFTDataTypes.getElement(type2);
        NFTDataTypes.BaseZodiac zodiac1 = NFTDataTypes.getBaseZodiac(type1);
        NFTDataTypes.BaseZodiac zodiac2 = NFTDataTypes.getBaseZodiac(type2);

        uint256 rand1 = _random(uint256(type1));
        uint256 rand2 = _random(uint256(type2));
        
        NFTDataTypes.ElementType newElement = (rand1 % 2) == 0 ? element1 : element2;
        NFTDataTypes.BaseZodiac newZodiac = (rand2 % 2) == 0 ? zodiac1 : zodiac2;
        NFTDataTypes.GenderType newGender = (rand1 % 2) == 0 ? NFTDataTypes.GenderType.FEMALE : NFTDataTypes.GenderType.MALE;

        return NFTDataTypes.createZodiacType(newElement, newZodiac, newGender);
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
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "Breeding: Zero address");
        authorizer = _authorizer;
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}