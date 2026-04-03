// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

enum BlessingType { AiGuo, FuQiang, HeXie, YouShan, JingYe, WanNeng, WuFuLinMen }

interface IRewardManager {
    function royaltyWallet() external view returns (address);
}

contract FiveBlessingsMetadata is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // 元数据存储
    mapping(BlessingType => string) private imgUrl;
    mapping(BlessingType => string) private cardName;
    mapping(BlessingType => string) private cardDesc;
    
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
        collName = unicode"五福临门NFT系列";
        // 使用五福临门图片作为封面
        collImage = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeich5jq6lv5zcf2ly4dwnxmvnh4nk5xoddy75fihq6bajxnxdxumnm";
        collDesc = unicode"基于中国传统五福文化的数字收藏品";
        sellerFeeBasisPoints = 500;
        
        // 初始化授权合约地址
        authorizer = _authorizer;
    }

    // UUPS升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // 初始化卡片元数据
    function _initCardMetadata() internal {
        // 图片URL配置 - 使用Pinata HTTP链接格式
        imgUrl[BlessingType.AiGuo] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeicmdlx35rjx7slj3ncmjynxzmwllkvujvcrqmdiynmijpkvnc734q";
        imgUrl[BlessingType.FuQiang] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeihkbyl6zlkx5vxxu366gwa5gpnd45twwlooczyolannp5ewcxaoja";
        imgUrl[BlessingType.HeXie] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifsojdpnspewquotpvbwhkfq6n5celzjtsyulbaecczkwm4y25yji";
        imgUrl[BlessingType.YouShan] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeiekctcxtyaews5udiumrogwxjdxkughjnhbycemgxvgpzhwhi564u";
        imgUrl[BlessingType.JingYe] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeibcse6fzqol32qrwlmsl7cz4ujhi7ctrxavfywzzqjgdvxla62m4e";
        imgUrl[BlessingType.WanNeng] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeig7ztsaeiddwpgjivwe7la6zxsck5q7hbael32thq4pw6amylxpgi";
        imgUrl[BlessingType.WuFuLinMen] = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeich5jq6lv5zcf2ly4dwnxmvnh4nk5xoddy75fihq6bajxnxdxumnm";
        
        // 卡片名称
        cardName[BlessingType.AiGuo] = unicode"爱国福";
        cardName[BlessingType.FuQiang] = unicode"富强福";
        cardName[BlessingType.HeXie] = unicode"和谐福";
        cardName[BlessingType.YouShan] = unicode"友善福";
        cardName[BlessingType.JingYe] = unicode"敬业福";
        cardName[BlessingType.WanNeng] = unicode"万能福";
        cardName[BlessingType.WuFuLinMen] = unicode"五福临门";
        
        // 卡片描述
        cardDesc[BlessingType.AiGuo] = unicode"爱我中华，福泽绵长";
        cardDesc[BlessingType.FuQiang] = unicode"国富民强，繁荣昌盛";
        cardDesc[BlessingType.HeXie] = unicode"和睦相处，幸福美满";
        cardDesc[BlessingType.YouShan] = unicode"友善待人，福报常在";
        cardDesc[BlessingType.JingYe] = unicode"敬业乐业，福禄安康";
        cardDesc[BlessingType.WanNeng] = unicode"万福齐聚，好运临门";
        cardDesc[BlessingType.WuFuLinMen] = unicode"五福齐聚，好运连连";
    }

    // ========== 元数据读取接口 ==========
    function getCardImage(BlessingType t) external view returns (string memory) {
        return imgUrl[t];
    }

    function getCardName(BlessingType t) external view returns (string memory) {
        return cardName[t];
    }

    function getCardDesc(BlessingType t) external view returns (string memory) {
        return cardDesc[t];
    }

    function getNFTName(BlessingType t, uint256 tokenId) external view returns (string memory) {
        return string(abi.encodePacked(cardName[t], " #", _uint2str(tokenId)));
    }

    // ========== 管理员接口 ==========
    function updateCardImage(BlessingType t, string calldata url) external onlyOwner {
        imgUrl[t] = url;
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
        require(msg.sender == owner() || msg.sender == authorizer, "FiveBlessingsMetadata: Unauthorized");
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