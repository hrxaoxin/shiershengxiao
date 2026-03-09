// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

enum ZodiacType { Rat, Ox, Tiger, Rabbit, Dragon, Snake, Horse, Goat, Monkey, Rooster, Dog, Pig }

interface IRewardManager {
    function royaltyWallet() external view returns (address);
}

contract ZodiacMetadata is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // 元数据存储
    mapping(ZodiacType => mapping(uint8 => string)) private imgUrl;
    mapping(ZodiacType => string) private cardName;
    mapping(ZodiacType => string) private cardDesc;
    
    // 合集元数据
    string public collImage;
    string public collName;
    string public collDesc;
    uint256 public sellerFeeBasisPoints;
    
    // 外部依赖
    address public rewardManager;
    address public authorizer;
    
    // 存储间隙
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _authorizer) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        
        // 初始化卡片元数据
        _initCardMetadata();
        
        // 初始化合集元数据
        collName = unicode"十二生肖NFT系列";
        // 使用龙图片作为封面
        collImage = "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20dragon%20NFT%20art%20with%20golden%20details%20and%20traditional%20chinese%20elements&image_size=square_hd";
        collDesc = unicode"基于中国传统十二生肖文化的数字收藏品";
        sellerFeeBasisPoints = 500;
        
        // 初始化授权合约地址
        authorizer = _authorizer;
    }

    // UUPS升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // 初始化卡片元数据
    function _initCardMetadata() internal {
        // 图片URL配置 - 使用Trae API生成图片
        for (uint8 starLevel = 1; starLevel <= 6; starLevel++) {
            imgUrl[ZodiacType.Rat][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20rat%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Ox][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20ox%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Tiger][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20tiger%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Rabbit][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20rabbit%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Dragon][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20dragon%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Snake][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20snake%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Horse][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20horse%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Goat][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20goat%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Monkey][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20monkey%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Rooster][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20rooster%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Dog][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20dog%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
            imgUrl[ZodiacType.Pig][starLevel] = string(abi.encodePacked(
                "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=chinese%20zodiac%20pig%20NFT%20art%20level%20",
                _uint2str(starLevel),
                "%20with%20traditional%20chinese%20elements&image_size=square_hd"
            ));
        }
        
        // 卡片名称
        cardName[ZodiacType.Rat] = unicode"鼠";
        cardName[ZodiacType.Ox] = unicode"牛";
        cardName[ZodiacType.Tiger] = unicode"虎";
        cardName[ZodiacType.Rabbit] = unicode"兔";
        cardName[ZodiacType.Dragon] = unicode"龙";
        cardName[ZodiacType.Snake] = unicode"蛇";
        cardName[ZodiacType.Horse] = unicode"马";
        cardName[ZodiacType.Goat] = unicode"羊";
        cardName[ZodiacType.Monkey] = unicode"猴";
        cardName[ZodiacType.Rooster] = unicode"鸡";
        cardName[ZodiacType.Dog] = unicode"狗";
        cardName[ZodiacType.Pig] = unicode"猪";
        
        // 卡片描述
        cardDesc[ZodiacType.Rat] = unicode"聪明伶俐，机智过人";
        cardDesc[ZodiacType.Ox] = unicode"勤劳踏实，任劳任怨";
        cardDesc[ZodiacType.Tiger] = unicode"勇猛威武，气势磅礴";
        cardDesc[ZodiacType.Rabbit] = unicode"温柔可爱，机智灵敏";
        cardDesc[ZodiacType.Dragon] = unicode"神龙见首，威风凛凛";
        cardDesc[ZodiacType.Snake] = unicode"灵活多变，神秘莫测";
        cardDesc[ZodiacType.Horse] = unicode"奔腾不息，自由奔放";
        cardDesc[ZodiacType.Goat] = unicode"温顺善良，祥和安康";
        cardDesc[ZodiacType.Monkey] = unicode"活泼好动，聪明机智";
        cardDesc[ZodiacType.Rooster] = unicode"鸡鸣报晓，勤奋努力";
        cardDesc[ZodiacType.Dog] = unicode"忠诚可靠，守护家园";
        cardDesc[ZodiacType.Pig] = unicode"福运临门，吉祥如意";
    }

    // ========== 元数据读取接口 ==========
    function getCardImage(ZodiacType t, uint8 starLevel) external view returns (string memory) {
        return imgUrl[t][starLevel];
    }

    function getCardName(ZodiacType t) external view returns (string memory) {
        return cardName[t];
    }

    function getCardDesc(ZodiacType t) external view returns (string memory) {
        return cardDesc[t];
    }

    function getNFTName(ZodiacType t, uint256 tokenId) external view returns (string memory) {
        return string(abi.encodePacked(cardName[t], " #", _uint2str(tokenId)));
    }

    // ========== 管理员接口 ==========
    function updateCardImage(ZodiacType t, uint8 starLevel, string calldata url) external onlyOwner {
        imgUrl[t][starLevel] = url;
    }

    function updateCollectionImage(string calldata img) external onlyOwner {
        collImage = img;
    }

    function updateCollectionInfo(string calldata name, string calldata img, string calldata desc) external onlyOwner {
        collName = name;
        collImage = img;
        collDesc = desc;
    }

    function setRoyaltyInfo(uint256 _sellerFeeBasisPoints) external onlyOwner {
        require(_sellerFeeBasisPoints <= 10000, "Royalty cannot exceed 100%");
        sellerFeeBasisPoints = _sellerFeeBasisPoints;
    }

    function setRewardManager(address rm) external {
        require(msg.sender == owner() || msg.sender == authorizer, "ZodiacMetadata: Unauthorized");
        rewardManager = rm;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    // ========== 工具函数 ==========
    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function _uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 len;
        while (temp != 0) {
            len++;
            temp /= 10;
        }
        bytes memory buf = new bytes(len);
        while (n != 0) {
            len--;
            buf[len] = bytes1(uint8(48 + n % 10));
            n /= 10;
        }
        return string(buf);
    }
}