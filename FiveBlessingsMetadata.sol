// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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

    function initialize(address initialOwner, address _authorizer) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        _initCardMetadata();

        collName = unicode"十二生肖NFT系列";
        collImage = "images/fu-cards/shuishu_1.png";
        collDesc = unicode"基于中国传统十二生肖文化的数字收藏品";
        sellerFeeBasisPoints = 500;

        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _initCardMetadata() internal {
        cardName[ZodiacType.ShuiShu_1] = unicode"水鼠（公）";
        cardName[ZodiacType.ShuiNiu_1] = unicode"水牛（公）";
        cardName[ZodiacType.ShuiHu_1] = unicode"水虎（公）";
        cardName[ZodiacType.ShuiTu_1] = unicode"水兔（公）";
        cardName[ZodiacType.ShuiLong_1] = unicode"水龙（公）";
        cardName[ZodiacType.ShuiShe_1] = unicode"水蛇（公）";
        cardName[ZodiacType.ShuiMa_1] = unicode"水马（公）";
        cardName[ZodiacType.ShuiYang_1] = unicode"水羊（公）";
        cardName[ZodiacType.ShuiHou_1] = unicode"水猴（公）";
        cardName[ZodiacType.ShuiJi_1] = unicode"水鸡（公）";
        cardName[ZodiacType.ShuiGou_1] = unicode"水狗（公）";
        cardName[ZodiacType.ShuiZhu_1] = unicode"水猪（公）";

        cardName[ZodiacType.ShuiShu_0] = unicode"水鼠（母）";
        cardName[ZodiacType.ShuiNiu_0] = unicode"水牛（母）";
        cardName[ZodiacType.ShuiHu_0] = unicode"水虎（母）";
        cardName[ZodiacType.ShuiTu_0] = unicode"水兔（母）";
        cardName[ZodiacType.ShuiLong_0] = unicode"水龙（母）";
        cardName[ZodiacType.ShuiShe_0] = unicode"水蛇（母）";
        cardName[ZodiacType.ShuiMa_0] = unicode"水马（母）";
        cardName[ZodiacType.ShuiYang_0] = unicode"水羊（母）";
        cardName[ZodiacType.ShuiHou_0] = unicode"水猴（母）";
        cardName[ZodiacType.ShuiJi_0] = unicode"水鸡（母）";
        cardName[ZodiacType.ShuiGou_0] = unicode"水狗（母）";
        cardName[ZodiacType.ShuiZhu_0] = unicode"水猪（母）";

        cardName[ZodiacType.FengShu_1] = unicode"风鼠（公）";
        cardName[ZodiacType.FengNiu_1] = unicode"风牛（公）";
        cardName[ZodiacType.FengHu_1] = unicode"风虎（公）";
        cardName[ZodiacType.FengTu_1] = unicode"风兔（公）";
        cardName[ZodiacType.FengLong_1] = unicode"风龙（公）";
        cardName[ZodiacType.FengShe_1] = unicode"风蛇（公）";
        cardName[ZodiacType.FengMa_1] = unicode"风马（公）";
        cardName[ZodiacType.FengYang_1] = unicode"风羊（公）";
        cardName[ZodiacType.FengHou_1] = unicode"风猴（公）";
        cardName[ZodiacType.FengJi_1] = unicode"风鸡（公）";
        cardName[ZodiacType.FengGou_1] = unicode"风狗（公）";
        cardName[ZodiacType.FengZhu_1] = unicode"风猪（公）";

        cardName[ZodiacType.FengShu_0] = unicode"风鼠（母）";
        cardName[ZodiacType.FengNiu_0] = unicode"风牛（母）";
        cardName[ZodiacType.FengHu_0] = unicode"风虎（母）";
        cardName[ZodiacType.FengTu_0] = unicode"风兔（母）";
        cardName[ZodiacType.FengLong_0] = unicode"风龙（母）";
        cardName[ZodiacType.FengShe_0] = unicode"风蛇（母）";
        cardName[ZodiacType.FengMa_0] = unicode"风马（母）";
        cardName[ZodiacType.FengYang_0] = unicode"风羊（母）";
        cardName[ZodiacType.FengHou_0] = unicode"风猴（母）";
        cardName[ZodiacType.FengJi_0] = unicode"风鸡（母）";
        cardName[ZodiacType.FengGou_0] = unicode"风狗（母）";
        cardName[ZodiacType.FengZhu_0] = unicode"风猪（母）";

        cardName[ZodiacType.HuoShu_1] = unicode"火鼠（公）";
        cardName[ZodiacType.HuoNiu_1] = unicode"火牛（公）";
        cardName[ZodiacType.HuoHu_1] = unicode"火虎（公）";
        cardName[ZodiacType.HuoTu_1] = unicode"火兔（公）";
        cardName[ZodiacType.HuoLong_1] = unicode"火龙（公）";
        cardName[ZodiacType.HuoShe_1] = unicode"火蛇（公）";
        cardName[ZodiacType.HuoMa_1] = unicode"火马（公）";
        cardName[ZodiacType.HuoYang_1] = unicode"火羊（公）";
        cardName[ZodiacType.HuoHou_1] = unicode"火猴（公）";
        cardName[ZodiacType.HuoJi_1] = unicode"火鸡（公）";
        cardName[ZodiacType.HuoGou_1] = unicode"火狗（公）";
        cardName[ZodiacType.HuoZhu_1] = unicode"火猪（公）";

        cardName[ZodiacType.HuoShu_0] = unicode"火鼠（母）";
        cardName[ZodiacType.HuoNiu_0] = unicode"火牛（母）";
        cardName[ZodiacType.HuoHu_0] = unicode"火虎（母）";
        cardName[ZodiacType.HuoTu_0] = unicode"火兔（母）";
        cardName[ZodiacType.HuoLong_0] = unicode"火龙（母）";
        cardName[ZodiacType.HuoShe_0] = unicode"火蛇（母）";
        cardName[ZodiacType.HuoMa_0] = unicode"火马（母）";
        cardName[ZodiacType.HuoYang_0] = unicode"火羊（母）";
        cardName[ZodiacType.HuoHou_0] = unicode"火猴（母）";
        cardName[ZodiacType.HuoJi_0] = unicode"火鸡（母）";
        cardName[ZodiacType.HuoGou_0] = unicode"火狗（母）";
        cardName[ZodiacType.HuoZhu_0] = unicode"火猪（母）";

        cardName[ZodiacType.AnShu_1] = unicode"暗鼠（公）";
        cardName[ZodiacType.AnNiu_1] = unicode"暗牛（公）";
        cardName[ZodiacType.AnHu_1] = unicode"暗虎（公）";
        cardName[ZodiacType.AnTu_1] = unicode"暗兔（公）";
        cardName[ZodiacType.AnLong_1] = unicode"暗龙（公）";
        cardName[ZodiacType.AnShe_1] = unicode"暗蛇（公）";
        cardName[ZodiacType.AnMa_1] = unicode"暗马（公）";
        cardName[ZodiacType.AnYang_1] = unicode"暗羊（公）";
        cardName[ZodiacType.AnHou_1] = unicode"暗猴（公）";
        cardName[ZodiacType.AnJi_1] = unicode"暗鸡（公）";
        cardName[ZodiacType.AnGou_1] = unicode"暗狗（公）";
        cardName[ZodiacType.AnZhu_1] = unicode"暗猪（公）";

        cardName[ZodiacType.AnShu_0] = unicode"暗鼠（母）";
        cardName[ZodiacType.AnNiu_0] = unicode"暗牛（母）";
        cardName[ZodiacType.AnHu_0] = unicode"暗虎（母）";
        cardName[ZodiacType.AnTu_0] = unicode"暗兔（母）";
        cardName[ZodiacType.AnLong_0] = unicode"暗龙（母）";
        cardName[ZodiacType.AnShe_0] = unicode"暗蛇（母）";
        cardName[ZodiacType.AnMa_0] = unicode"暗马（母）";
        cardName[ZodiacType.AnYang_0] = unicode"暗羊（母）";
        cardName[ZodiacType.AnHou_0] = unicode"暗猴（母）";
        cardName[ZodiacType.AnJi_0] = unicode"暗鸡（母）";
        cardName[ZodiacType.AnGou_0] = unicode"暗狗（母）";
        cardName[ZodiacType.AnZhu_0] = unicode"暗猪（母）";

        cardName[ZodiacType.GuangShu_1] = unicode"光鼠（公）";
        cardName[ZodiacType.GuangNiu_1] = unicode"光牛（公）";
        cardName[ZodiacType.GuangHu_1] = unicode"光虎（公）";
        cardName[ZodiacType.GuangTu_1] = unicode"光兔（公）";
        cardName[ZodiacType.GuangLong_1] = unicode"光龙（公）";
        cardName[ZodiacType.GuangShe_1] = unicode"光蛇（公）";
        cardName[ZodiacType.GuangMa_1] = unicode"光马（公）";
        cardName[ZodiacType.GuangYang_1] = unicode"光羊（公）";
        cardName[ZodiacType.GuangHou_1] = unicode"光猴（公）";
        cardName[ZodiacType.GuangJi_1] = unicode"光鸡（公）";
        cardName[ZodiacType.GuangGou_1] = unicode"光狗（公）";
        cardName[ZodiacType.GuangZhu_1] = unicode"光猪（公）";

        cardName[ZodiacType.GuangShu_0] = unicode"光鼠（母）";
        cardName[ZodiacType.GuangNiu_0] = unicode"光牛（母）";
        cardName[ZodiacType.GuangHu_0] = unicode"光虎（母）";
        cardName[ZodiacType.GuangTu_0] = unicode"光兔（母）";
        cardName[ZodiacType.GuangLong_0] = unicode"光龙（母）";
        cardName[ZodiacType.GuangShe_0] = unicode"光蛇（母）";
        cardName[ZodiacType.GuangMa_0] = unicode"光马（母）";
        cardName[ZodiacType.GuangYang_0] = unicode"光羊（母）";
        cardName[ZodiacType.GuangHou_0] = unicode"光猴（母）";
        cardName[ZodiacType.GuangJi_0] = unicode"光鸡（母）";
        cardName[ZodiacType.GuangGou_0] = unicode"光狗（母）";
        cardName[ZodiacType.GuangZhu_0] = unicode"光猪（母）";

        for (uint i = 0; i < 120; i++) {
            imgUrl[ZodiacType(i)] = _getImageUrl(ZodiacType(i));
            cardDesc[ZodiacType(i)] = _getCardDescription(ZodiacType(i));
        }
    }

    function _getImageUrl(ZodiacType z) internal pure returns (string memory) {
        string memory basePath1 = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/";
        string memory basePath2 = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/";

        uint256 zIndex = uint256(z);

        if (zIndex < 48) {
            if (z == ZodiacType.ShuiShu_1) return string(abi.encodePacked(basePath1, "shuishu_1.png"));
            if (z == ZodiacType.ShuiNiu_1) return string(abi.encodePacked(basePath1, "shuiniu_1.png"));
            if (z == ZodiacType.ShuiHu_1) return string(abi.encodePacked(basePath1, "shuihu_1.png"));
            if (z == ZodiacType.ShuiTu_1) return string(abi.encodePacked(basePath1, "shuitu_1.png"));
            if (z == ZodiacType.ShuiLong_1) return string(abi.encodePacked(basePath1, "shuilong_1.png"));
            if (z == ZodiacType.ShuiShe_1) return string(abi.encodePacked(basePath1, "shuishe_1.png"));
            if (z == ZodiacType.ShuiMa_1) return string(abi.encodePacked(basePath1, "shuima_1.png"));
            if (z == ZodiacType.ShuiYang_1) return string(abi.encodePacked(basePath1, "shuiyang_1.png"));
            if (z == ZodiacType.ShuiHou_1) return string(abi.encodePacked(basePath1, "shuihou_1.png"));
            if (z == ZodiacType.ShuiJi_1) return string(abi.encodePacked(basePath1, "shuiji_1.png"));
            if (z == ZodiacType.ShuiGou_1) return string(abi.encodePacked(basePath1, "shuigou_1.png"));
            if (z == ZodiacType.ShuiZhu_1) return string(abi.encodePacked(basePath1, "shuizhu_1.png"));

            if (z == ZodiacType.ShuiShu_0) return string(abi.encodePacked(basePath1, "shuishu_0.png"));
            if (z == ZodiacType.ShuiNiu_0) return string(abi.encodePacked(basePath1, "shuiniu_0.png"));
            if (z == ZodiacType.ShuiHu_0) return string(abi.encodePacked(basePath1, "shuihu_0.png"));
            if (z == ZodiacType.ShuiTu_0) return string(abi.encodePacked(basePath1, "shuitu_0.png"));
            if (z == ZodiacType.ShuiLong_0) return string(abi.encodePacked(basePath1, "shuilong_0.png"));
            if (z == ZodiacType.ShuiShe_0) return string(abi.encodePacked(basePath1, "shuishe_0.png"));
            if (z == ZodiacType.ShuiMa_0) return string(abi.encodePacked(basePath1, "shuima_0.png"));
            if (z == ZodiacType.ShuiYang_0) return string(abi.encodePacked(basePath1, "shuiyang_0.png"));
            if (z == ZodiacType.ShuiHou_0) return string(abi.encodePacked(basePath1, "shuihou_0.png"));
            if (z == ZodiacType.ShuiJi_0) return string(abi.encodePacked(basePath1, "shuiji_0.png"));
            if (z == ZodiacType.ShuiGou_0) return string(abi.encodePacked(basePath1, "shuigou_0.png"));
            if (z == ZodiacType.ShuiZhu_0) return string(abi.encodePacked(basePath1, "shuizhu_0.png"));

            if (z == ZodiacType.FengShu_1) return string(abi.encodePacked(basePath1, "fengshu_1.png"));
            if (z == ZodiacType.FengNiu_1) return string(abi.encodePacked(basePath1, "fengniu_1.png"));
            if (z == ZodiacType.FengHu_1) return string(abi.encodePacked(basePath1, "fenghu_1.png"));
            if (z == ZodiacType.FengTu_1) return string(abi.encodePacked(basePath1, "fengtu_1.png"));
            if (z == ZodiacType.FengLong_1) return string(abi.encodePacked(basePath1, "fenglong_1.png"));
            if (z == ZodiacType.FengShe_1) return string(abi.encodePacked(basePath1, "fengshe_1.png"));
            if (z == ZodiacType.FengMa_1) return string(abi.encodePacked(basePath1, "fengma_1.png"));
            if (z == ZodiacType.FengYang_1) return string(abi.encodePacked(basePath1, "fengyang_1.png"));
            if (z == ZodiacType.FengHou_1) return string(abi.encodePacked(basePath1, "fenghou_1.png"));
            if (z == ZodiacType.FengJi_1) return string(abi.encodePacked(basePath1, "fengji_1.png"));
            if (z == ZodiacType.FengGou_1) return string(abi.encodePacked(basePath1, "fenggou_1.png"));
            if (z == ZodiacType.FengZhu_1) return string(abi.encodePacked(basePath1, "fengzhu_1.png"));

            if (z == ZodiacType.FengShu_0) return string(abi.encodePacked(basePath1, "fengshu_0.png"));
            if (z == ZodiacType.FengNiu_0) return string(abi.encodePacked(basePath1, "fengniu_0.png"));
            if (z == ZodiacType.FengHu_0) return string(abi.encodePacked(basePath1, "fenghu_0.png"));
            if (z == ZodiacType.FengTu_0) return string(abi.encodePacked(basePath1, "fengtu_0.png"));
            if (z == ZodiacType.FengLong_0) return string(abi.encodePacked(basePath1, "fenglong_0.png"));
            if (z == ZodiacType.FengShe_0) return string(abi.encodePacked(basePath1, "fengshe_0.png"));
            if (z == ZodiacType.FengMa_0) return string(abi.encodePacked(basePath1, "fengma_0.png"));
            if (z == ZodiacType.FengYang_0) return string(abi.encodePacked(basePath1, "fengyang_0.png"));
            if (z == ZodiacType.FengHou_0) return string(abi.encodePacked(basePath1, "fenghou_0.png"));
            if (z == ZodiacType.FengJi_0) return string(abi.encodePacked(basePath1, "fengji_0.png"));
            if (z == ZodiacType.FengGou_0) return string(abi.encodePacked(basePath1, "fenggou_0.png"));
            if (z == ZodiacType.FengZhu_0) return string(abi.encodePacked(basePath1, "fengzhu_0.png"));

            if (z == ZodiacType.HuoShu_1) return string(abi.encodePacked(basePath1, "huoshu_1.png"));
            if (z == ZodiacType.HuoNiu_1) return string(abi.encodePacked(basePath1, "huoniu_1.png"));
            if (z == ZodiacType.HuoHu_1) return string(abi.encodePacked(basePath1, "huohu_1.png"));
            if (z == ZodiacType.HuoTu_1) return string(abi.encodePacked(basePath1, "huotu_1.png"));
            if (z == ZodiacType.HuoLong_1) return string(abi.encodePacked(basePath1, "huolong_1.png"));
            if (z == ZodiacType.HuoShe_1) return string(abi.encodePacked(basePath1, "huoshe_1.png"));
            if (z == ZodiacType.HuoMa_1) return string(abi.encodePacked(basePath1, "huoma_1.png"));
            if (z == ZodiacType.HuoYang_1) return string(abi.encodePacked(basePath1, "huoyang_1.png"));
            if (z == ZodiacType.HuoHou_1) return string(abi.encodePacked(basePath1, "huohou_1.png"));
            if (z == ZodiacType.HuoJi_1) return string(abi.encodePacked(basePath1, "huoji_1.png"));
            if (z == ZodiacType.HuoGou_1) return string(abi.encodePacked(basePath1, "huogou_1.png"));
            if (z == ZodiacType.HuoZhu_1) return string(abi.encodePacked(basePath1, "huozhu_1.png"));

            if (z == ZodiacType.HuoShu_0) return string(abi.encodePacked(basePath1, "huoshu_0.png"));
            if (z == ZodiacType.HuoNiu_0) return string(abi.encodePacked(basePath1, "huoniu_0.png"));
            if (z == ZodiacType.HuoHu_0) return string(abi.encodePacked(basePath1, "huohu_0.png"));
            if (z == ZodiacType.HuoTu_0) return string(abi.encodePacked(basePath1, "huotu_0.png"));
            if (z == ZodiacType.HuoLong_0) return string(abi.encodePacked(basePath1, "huolong_0.png"));
            if (z == ZodiacType.HuoShe_0) return string(abi.encodePacked(basePath1, "huoshe_0.png"));
            if (z == ZodiacType.HuoMa_0) return string(abi.encodePacked(basePath1, "huoma_0.png"));
            if (z == ZodiacType.HuoYang_0) return string(abi.encodePacked(basePath1, "huoyang_0.png"));
            if (z == ZodiacType.HuoHou_0) return string(abi.encodePacked(basePath1, "huohou_0.png"));
            if (z == ZodiacType.HuoJi_0) return string(abi.encodePacked(basePath1, "huoji_0.png"));
            if (z == ZodiacType.HuoGou_0) return string(abi.encodePacked(basePath1, "huogou_0.png"));
            if (z == ZodiacType.HuoZhu_0) return string(abi.encodePacked(basePath1, "huozhu_0.png"));
        } else {
            if (z == ZodiacType.AnShu_1) return string(abi.encodePacked(basePath2, "anshu_1.png"));
            if (z == ZodiacType.AnNiu_1) return string(abi.encodePacked(basePath2, "anniu_1.png"));
            if (z == ZodiacType.AnHu_1) return string(abi.encodePacked(basePath2, "anhu_1.png"));
            if (z == ZodiacType.AnTu_1) return string(abi.encodePacked(basePath2, "antu_1.png"));
            if (z == ZodiacType.AnLong_1) return string(abi.encodePacked(basePath2, "anlong_1.png"));
            if (z == ZodiacType.AnShe_1) return string(abi.encodePacked(basePath2, "anshe_1.png"));
            if (z == ZodiacType.AnMa_1) return string(abi.encodePacked(basePath2, "anma_1.png"));
            if (z == ZodiacType.AnYang_1) return string(abi.encodePacked(basePath2, "anyang_1.png"));
            if (z == ZodiacType.AnHou_1) return string(abi.encodePacked(basePath2, "anhhou_1.png"));
            if (z == ZodiacType.AnJi_1) return string(abi.encodePacked(basePath2, "anji_1.png"));
            if (z == ZodiacType.AnGou_1) return string(abi.encodePacked(basePath2, "angou_1.png"));
            if (z == ZodiacType.AnZhu_1) return string(abi.encodePacked(basePath2, "anzhu_1.png"));

            if (z == ZodiacType.AnShu_0) return string(abi.encodePacked(basePath2, "anshu_0.png"));
            if (z == ZodiacType.AnNiu_0) return string(abi.encodePacked(basePath2, "anniu_0.png"));
            if (z == ZodiacType.AnHu_0) return string(abi.encodePacked(basePath2, "anhu_0.png"));
            if (z == ZodiacType.AnTu_0) return string(abi.encodePacked(basePath2, "antu_0.png"));
            if (z == ZodiacType.AnLong_0) return string(abi.encodePacked(basePath2, "anlong_0.png"));
            if (z == ZodiacType.AnShe_0) return string(abi.encodePacked(basePath2, "anshe_0.png"));
            if (z == ZodiacType.AnMa_0) return string(abi.encodePacked(basePath2, "anma_0.png"));
            if (z == ZodiacType.AnYang_0) return string(abi.encodePacked(basePath2, "anyang_0.png"));
            if (z == ZodiacType.AnHou_0) return string(abi.encodePacked(basePath2, "anhhou_0.png"));
            if (z == ZodiacType.AnJi_0) return string(abi.encodePacked(basePath2, "anji_0.png"));
            if (z == ZodiacType.AnGou_0) return string(abi.encodePacked(basePath2, "angou_0.png"));
            if (z == ZodiacType.AnZhu_0) return string(abi.encodePacked(basePath2, "anzhu_0.png"));

            if (z == ZodiacType.GuangShu_1) return string(abi.encodePacked(basePath2, "guangshu_1.png"));
            if (z == ZodiacType.GuangNiu_1) return string(abi.encodePacked(basePath2, "guangniu_1.png"));
            if (z == ZodiacType.GuangHu_1) return string(abi.encodePacked(basePath2, "guanghu_1.png"));
            if (z == ZodiacType.GuangTu_1) return string(abi.encodePacked(basePath2, "guangtu_1.png"));
            if (z == ZodiacType.GuangLong_1) return string(abi.encodePacked(basePath2, "guanglong_1.png"));
            if (z == ZodiacType.GuangShe_1) return string(abi.encodePacked(basePath2, "guangshe_1.png"));
            if (z == ZodiacType.GuangMa_1) return string(abi.encodePacked(basePath2, "guangma_1.png"));
            if (z == ZodiacType.GuangYang_1) return string(abi.encodePacked(basePath2, "guangyang_1.png"));
            if (z == ZodiacType.GuangHou_1) return string(abi.encodePacked(basePath2, "guanghou_1.png"));
            if (z == ZodiacType.GuangJi_1) return string(abi.encodePacked(basePath2, "guangji_1.png"));
            if (z == ZodiacType.GuangGou_1) return string(abi.encodePacked(basePath2, "guanggou_1.png"));
            if (z == ZodiacType.GuangZhu_1) return string(abi.encodePacked(basePath2, "guangzhu_1.png"));

            if (z == ZodiacType.GuangShu_0) return string(abi.encodePacked(basePath2, "guangshu_0.png"));
            if (z == ZodiacType.GuangNiu_0) return string(abi.encodePacked(basePath2, "guangniu_0.png"));
            if (z == ZodiacType.GuangHu_0) return string(abi.encodePacked(basePath2, "guanghu_0.png"));
            if (z == ZodiacType.GuangTu_0) return string(abi.encodePacked(basePath2, "guangtu_0.png"));
            if (z == ZodiacType.GuangLong_0) return string(abi.encodePacked(basePath2, "guanglong_0.png"));
            if (z == ZodiacType.GuangShe_0) return string(abi.encodePacked(basePath2, "guangshe_0.png"));
            if (z == ZodiacType.GuangMa_0) return string(abi.encodePacked(basePath2, "guangma_0.png"));
            if (z == ZodiacType.GuangYang_0) return string(abi.encodePacked(basePath2, "guangyang_0.png"));
            if (z == ZodiacType.GuangHou_0) return string(abi.encodePacked(basePath2, "guanghou_0.png"));
            if (z == ZodiacType.GuangJi_0) return string(abi.encodePacked(basePath2, "guangji_0.png"));
            if (z == ZodiacType.GuangGou_0) return string(abi.encodePacked(basePath2, "guanggou_0.png"));
            if (z == ZodiacType.GuangZhu_0) return string(abi.encodePacked(basePath2, "guangzhu_0.png"));
        }

        return "";
    }

    function _getCardDescription(ZodiacType z) internal pure returns (string memory) {
        if (uint(z) < 24) {
            if (uint(z) % 2 == 1) return unicode"水属性生肖·公 · 持有可享受税收分红";
            else return unicode"水属性生肖·母 · 持有可享受税收分红";
        } else if (uint(z) < 48) {
            if (uint(z) % 2 == 1) return unicode"风属性生肖·公 · 持有可享受税收分红";
            else return unicode"风属性生肖·母 · 持有可享受税收分红";
        } else if (uint(z) < 72) {
            if (uint(z) % 2 == 1) return unicode"火属性生肖·公 · 持有可享受税收分红";
            else return unicode"火属性生肖·母 · 持有可享受税收分红";
        } else if (uint(z) < 96) {
            if (uint(z) % 2 == 1) return unicode"暗属性生肖·公 · 持有可享受税收分红";
            else return unicode"暗属性生肖·母 · 持有可享受税收分红";
        } else {
            if (uint(z) % 2 == 1) return unicode"光属性生肖·公 · 持有可享受税收分红";
            else return unicode"光属性生肖·母 · 持有可享受税收分红";
        }
    }

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
        require(msg.sender == owner() || msg.sender == authorizer, "FiveBlessingsMetadata: Unauthorized");
        rewardManager = rm;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

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
