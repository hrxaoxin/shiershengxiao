// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Breeding
 * @dev NFT繁殖合约，允许用户将两个等级6的NFT进行繁殖生成新NFT
 * 繁殖需要消耗代币，生成的NFT类型基于父母类型计算
 * 基于OpenZeppelin可升级合约实现
 */
import "./NFTData.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title Breeding
 * @dev NFT繁殖合约
 */
contract Breeding is Initializable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /** @dev 繁殖所需代币数量 */
    uint256 public constant BREEDING_COST = 100000 * 10**18;
    /** @dev 最小繁殖等级：必须达到6级才能繁殖 */
    uint8 public constant MIN_BREEDING_LEVEL = 6;
    /** @dev 黑洞地址，用于销毁NFT */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 繁殖事件 */
    event NFTBred(address indexed user, uint256 indexed tokenId1, uint256 indexed tokenId2, uint256 newTokenId, NFTDataTypes.ZodiacType newType, uint256 timestamp);
    /** @dev 繁殖失败事件 */
    event BreedFailed(address indexed user, uint256 indexed tokenId1, uint256 indexed tokenId2, string reason, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _nftContract NFT合约地址
     * @param _tokenContract 代币合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _nftContract, address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        nftContract = _nftContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
    }

    /**
     * @dev 繁殖NFT
     * 用户需要拥有两个等级为6的NFT才能进行繁殖
     * @param tokenId1 第一个NFT ID
     * @param tokenId2 第二个NFT ID
     * @return uint256 新生成的NFT ID
     */
    function breed(uint256 tokenId1, uint256 tokenId2) external nonReentrant whenNotPaused returns (uint256) {
        // 验证两个NFT不能相同
        require(tokenId1 != tokenId2, "Breeding: Cannot breed the same NFT");

        INFTMint nft = INFTMint(nftContract);
        
        // 验证用户拥有两个NFT
        require(nft.ownerOf(tokenId1) == msg.sender, "Breeding: Not owner of first NFT");
        require(nft.ownerOf(tokenId2) == msg.sender, "Breeding: Not owner of second NFT");

        // 验证两个NFT的等级都为6
        uint8 level1 = nft.tokenLevel(tokenId1);
        uint8 level2 = nft.tokenLevel(tokenId2);
        require(level1 >= MIN_BREEDING_LEVEL, "Breeding: First NFT level too low");
        require(level2 >= MIN_BREEDING_LEVEL, "Breeding: Second NFT level too low");
        require(level1 == 6, "Breeding: First NFT must be level 6");
        require(level2 == 6, "Breeding: Second NFT must be level 6");

        // 验证用户授权
        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                nft.getApproved(tokenId1) == address(this) && 
                nft.getApproved(tokenId2) == address(this), "Breeding: Contract not approved");

        // 扣除繁殖费用
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.balanceOf(msg.sender) >= BREEDING_COST, "Breeding: Insufficient tokens");
        require(token.transferFrom(msg.sender, BLACK_HOLE, BREEDING_COST), "Breeding: Token transfer failed");

        // 获取父母NFT的类型
        NFTDataTypes.ZodiacType type1 = nft.tokenType(tokenId1);
        NFTDataTypes.ZodiacType type2 = nft.tokenType(tokenId2);

        // 销毁父母NFT
        nft.transferFrom(msg.sender, BLACK_HOLE, tokenId1);
        nft.transferFrom(msg.sender, BLACK_HOLE, tokenId2);

        // 计算新NFT的类型
        NFTDataTypes.ZodiacType newType = _calculateNewType(type1, type2);

        // 铸造新NFT
        uint256 newTokenId = nft.mintBreedResult(msg.sender, newType);

        emit NFTBred(msg.sender, tokenId1, tokenId2, newTokenId, newType, block.timestamp);
        return newTokenId;
    }

    /**
     * @dev 计算繁殖产生的新NFT类型
     * 基于父母的属性和生肖计算
     * @param type1 父NFT类型
     * @param type2 母NFT类型
     * @return NFTDataTypes.ZodiacType 新NFT类型
     */
    function _calculateNewType(NFTDataTypes.ZodiacType type1, NFTDataTypes.ZodiacType type2) internal view returns (NFTDataTypes.ZodiacType) {
        // 获取父母的属性和生肖
        NFTDataTypes.ElementType element1 = NFTDataTypes.getElement(type1);
        NFTDataTypes.ElementType element2 = NFTDataTypes.getElement(type2);
        NFTDataTypes.BaseZodiac zodiac1 = NFTDataTypes.getBaseZodiac(type1);
        NFTDataTypes.BaseZodiac zodiac2 = NFTDataTypes.getBaseZodiac(type2);
        NFTDataTypes.GenderType gender1 = NFTDataTypes.getGender(type1);
        NFTDataTypes.GenderType gender2 = NFTDataTypes.getGender(type2);

        // 随机选择新的属性（50%继承父方，50%继承母方）
        NFTDataTypes.ElementType newElement = (block.timestamp % 2) == 0 ? element1 : element2;

        // 计算新的生肖（基于父母生肖计算）
        NFTDataTypes.BaseZodiac newZodiac = _calculateZodiac(zodiac1, zodiac2);

        // 随机选择性别
        NFTDataTypes.GenderType newGender = (block.timestamp % 2) == 0 ? NFTDataTypes.GenderType.MALE : NFTDataTypes.GenderType.FEMALE;

        return NFTDataTypes.createZodiacType(newElement, newZodiac, newGender);
    }

    /**
     * @dev 根据父母生肖计算新生肖
     * @param zodiac1 父生肖
     * @param zodiac2 母生肖
     * @return NFTDataTypes.BaseZodiac 新生肖
     */
    function _calculateZodiac(NFTDataTypes.BaseZodiac zodiac1, NFTDataTypes.BaseZodiac zodiac2) internal view returns (NFTDataTypes.BaseZodiac) {
        // 简单的生肖遗传算法：随机选择父母之一的生肖
        // 可以根据需要实现更复杂的遗传规则
        return (block.timestamp % 2) == 0 ? zodiac1 : zodiac2;
    }

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Unauthorized");
        nftContract = _nftContract;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Unauthorized");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
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