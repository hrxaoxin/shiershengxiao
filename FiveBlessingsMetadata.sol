// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";

enum ZodiacType {
    // Water zodiac (水) - tokens 1-24
    ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1, ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
    ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0, ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,
    // Wind zodiac (风) - tokens 25-48
    FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1, FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
    FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0, FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,
    // Fire zodiac (火) - tokens 49-72
    HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1, HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
    HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0, HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,
    // Dark zodiac (暗) - tokens 73-96
    AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1, AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
    AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0, AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,
    // Light zodiac (光) - tokens 97-120
    GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1, GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
    GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0, GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
}

interface IRewardManager {
    function royaltyWallet() external view returns (address);
}

contract FiveBlessingsMetadata is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    mapping(ZodiacType => string) private imgUrl;
    mapping(ZodiacType => string) private cardName;
    mapping(ZodiacType => string) private cardDesc;

    string public collImage;
    string public collName;
    string public collDesc;
    uint256 public sellerFeeBasisPoints;

    address public rewardManager;
    address public authorizer;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizer) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        _initCardMetadata();

        collName = unicode"十二生肖NFT系列";
        collImage = "images/fu-cards/shuishu_1.png";
        collDesc = unicode"基于中国传统十二生肖文化的数字收藏品";
        sellerFeeBasisPoints = 500;

        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ==============================================
    // 核心优化：自动生成名称 + 图片URL，无冗余代码
    // ==============================================
    function _initCardMetadata() internal {
        // string[5] memory elements = ["shui", "feng", "huo", "an", "guang"];
        string[5] memory elementsCN = [unicode"水", unicode"风", unicode"火", unicode"暗", unicode"光"];
        // string[12] memory animals = ["shu", "niu", "hu", "tu", "long", "she", "ma", "yang", "hou", "ji", "gou", "zhu"];
        string[12] memory animalsCN = [unicode"鼠", unicode"牛", unicode"虎", unicode"兔", unicode"龙", unicode"蛇", unicode"马", unicode"羊", unicode"猴", unicode"鸡", unicode"狗", unicode"猪"];

        for (uint256 i = 0; i < 120; i++) {
            ZodiacType z = ZodiacType(i);
            uint256 group = i / 24;
            uint256 posInGroup = i % 24;
            uint256 animalIdx = posInGroup / 2;
            uint256 gender = posInGroup % 2;

            // 生成名称
            cardName[z] = string(abi.encodePacked(
                elementsCN[group], animalsCN[animalIdx], gender == 1 ? unicode"（公）" : unicode"（母）"
            ));

            // 生成图片URL（自动拼接，无任何if）
            imgUrl[z] = _getImageUrl(z);

            // 生成描述
            cardDesc[z] = string(abi.encodePacked(
                elementsCN[group], unicode"属性生肖·", gender == 1 ? unicode"公" : unicode"母", unicode" · 持有可享受税收分红"
            ));
        }
    }

    // ==============================================
    // 自动生成URL，删除120个冗余if
    // ==============================================
    function _getImageUrl(ZodiacType z) internal pure returns (string memory) {
        string memory base1 = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/";
        string memory base2 = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/";
        
        uint256 idx = uint256(z);
        uint256 group = idx / 24;
        uint256 pos = idx % 24;
        uint256 animal = pos / 2;
        uint256 gender = pos % 2;

        string[5] memory e = ["shui", "feng", "huo", "an", "guang"];
        string[12] memory a = ["shu", "niu", "hu", "tu", "long", "she", "ma", "yang", "hou", "ji", "gou", "zhu"];
        
        return string(abi.encodePacked(
            group < 3 ? base1 : base2,
            e[group], a[animal], "_", gender == 1 ? "1" : "0", ".png"
        ));
    }

    // 外部查询方法（不变）
    function getCardImage(ZodiacType t) external view returns (string memory) {
        return imgUrl[t];
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

    // 管理员方法（全部保留）
    function updateCardImage(ZodiacType t, string calldata url) external onlyOwner {
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
        require(msg.sender == owner() || msg.sender == authorizer, "Unauthorized");
        rewardManager = rm;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    // 工具方法（保留）
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