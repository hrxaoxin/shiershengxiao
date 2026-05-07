// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NFT数据类型库
library NFTDataTypes {
    // 元素类型枚举
    enum ElementType {
        WATER,    // 水
        WIND,     // 风
        FIRE,     // 火
        DARK,     // 暗
        LIGHT     // 光
    }

    // 性别类型枚举
    enum GenderType {
        FEMALE,   // 母 (0)
        MALE      // 公 (1)
    }

    // 生肖基础类型枚举
    enum BaseZodiac {
        RAT,      // 鼠
        OX,       // 牛
        TIGER,    // 虎
        RABBIT,   // 兔
        DRAGON,   // 龙
        SNAKE,    // 蛇
        HORSE,    // 马
        GOAT,     // 羊
        MONKEY,   // 猴
        ROOSTER,  // 鸡
        DOG,      // 狗
        PIG       // 猪
    }

    // 十二生肖类型枚举 (5元素 × 12生肖 × 2性别 = 120种)
    // 编码规则: elementIndex * 24 + zodiacIndex * 2 + genderIndex
    enum ZodiacType {
        // 水属性 (0-23)
        ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1,
        ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
        ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0,
        ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,
        
        // 风属性 (24-47)
        FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1,
        FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
        FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0,
        FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,
        
        // 火属性 (48-71)
        HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1,
        HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
        HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0,
        HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,
        
        // 暗属性 (72-95)
        AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1,
        AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
        AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0,
        AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,
        
        // 光属性 (96-119)
        GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1,
        GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
        GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0,
        GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
    }

    // NFT信息结构体
    struct NFTInfo {
        uint256 tokenId;
        ZodiacType zodiacType;
        uint8 level;
        uint256 mintTime;
    }

    // 类型转换辅助函数
    function getElement(ZodiacType zodiacType) internal pure returns (ElementType) {
        uint256 typeValue = uint256(zodiacType);
        uint256 elementIndex = typeValue / 24;
        return ElementType(elementIndex);
    }

    function getGender(ZodiacType zodiacType) internal pure returns (GenderType) {
        uint256 typeValue = uint256(zodiacType);
        uint256 genderIndex = typeValue % 2;
        return GenderType(genderIndex);
    }

    function getBaseZodiac(ZodiacType zodiacType) internal pure returns (BaseZodiac) {
        uint256 typeValue = uint256(zodiacType);
        uint256 zodiacIndex = (typeValue / 2) % 12;
        return BaseZodiac(zodiacIndex);
    }

    function createZodiacType(ElementType element, BaseZodiac zodiac, GenderType gender) internal pure returns (ZodiacType) {
        uint256 typeValue = uint256(element) * 24 + uint256(zodiac) * 2 + uint256(gender);
        return ZodiacType(typeValue);
    }

    function getElementTypeValue(ElementType element) internal pure returns (uint256) {
        return uint256(element);
    }

    function getZodiacTypeValue(ZodiacType zodiacType) internal pure returns (uint256) {
        return uint256(zodiacType);
    }
}

// NFT铸造接口
interface INFTMint {
    function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function mint(address to) external returns (uint256);
    function mintSpecificType(address to, NFTDataTypes.ZodiacType zodiacType) external returns (uint256);
    function mintLightDark(address to, bool isLight) external returns (uint256);
    function mintBreedResult(address to, NFTDataTypes.ZodiacType zodiacType) external returns (uint256);
    function upgradeWithNFT(uint256 tokenId) external returns (uint8);
    function upgradeWithToken(uint256 tokenId) external returns (uint8);
    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function getApproved(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

// NFT权重接口
interface INFTMintWeight {
    function calcUserWeight(address user) external view returns (uint256);
}

// 奖励管理器接口
interface IRewardManager {
    function royaltyWallet() external view returns (address);
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256);
    function claimDividend() external;
    function cardCount(address user, NFTDataTypes.ZodiacType zodiacType) external view returns (uint256);
    function updateCardExternal(address user, NFTDataTypes.ZodiacType zodiacType, uint256 count) external returns (bool);
    function setAuthorizedNFTContract(address nft, bool ok) external;
}

// NFT数据接口
interface INFTData {
    function getNFTInfo(uint256 tokenId) external view returns (NFTDataTypes.NFTInfo memory);
    function getElementName(NFTDataTypes.ElementType element) external pure returns (string memory);
    function getZodiacName(NFTDataTypes.BaseZodiac zodiac) external pure returns (string memory);
    function getGenderName(NFTDataTypes.GenderType gender) external pure returns (string memory);
    function getFullTypeName(NFTDataTypes.ZodiacType zodiacType) external pure returns (string memory);
    function collName() external view returns (string memory);
    function collDesc() external view returns (string memory);
    function collImage() external view returns (string memory);
    function sellerFeeBasisPoints() external view returns (uint256);
    function getCardName(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    function getCardDesc(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    function getCardImage(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
}

// NFT数据管理合约
contract NFTData is INFTData {
    using NFTDataTypes for NFTDataTypes.ZodiacType;

    // 元素名称映射
    string[] private _elementNames = ["水", "风", "火", "暗", "光"];
    
    // 生肖名称映射
    string[] private _zodiacNames = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"];
    
    // 性别名称映射
    string[] private _genderNames = ["母", "公"];

    // NFT信息存储
    mapping(uint256 => NFTDataTypes.NFTInfo) private _nftInfos;

    /**
     * @dev 获取NFT信息
     * @param tokenId NFT代币ID
     * @return NFTInfo结构体
     */
    function getNFTInfo(uint256 tokenId) external view override returns (NFTDataTypes.NFTInfo memory) {
        return _nftInfos[tokenId];
    }

    /**
     * @dev 设置NFT信息
     * @param tokenId NFT代币ID
     * @param info NFT信息
     */
    function setNFTInfo(uint256 tokenId, NFTDataTypes.NFTInfo memory info) external {
        _nftInfos[tokenId] = info;
    }

    /**
     * @dev 获取元素名称
     * @param element 元素类型
     * @return 元素名称（中文）
     */
    function getElementName(NFTDataTypes.ElementType element) external pure override returns (string memory) {
        uint256 index = NFTDataTypes.getElementTypeValue(element);
        require(index < _elementNames.length, "NFTData: invalid element type");
        return _elementNames[index];
    }

    /**
     * @dev 获取生肖名称
     * @param zodiac 生肖类型
     * @return 生肖名称（中文）
     */
    function getZodiacName(NFTDataTypes.BaseZodiac zodiac) external pure override returns (string memory) {
        uint256 index = uint256(zodiac);
        require(index < _zodiacNames.length, "NFTData: invalid zodiac type");
        return _zodiacNames[index];
    }

    /**
     * @dev 获取性别名称
     * @param gender 性别类型
     * @return 性别名称（中文）
     */
    function getGenderName(NFTDataTypes.GenderType gender) external pure override returns (string memory) {
        uint256 index = uint256(gender);
        require(index < _genderNames.length, "NFTData: invalid gender type");
        return _genderNames[index];
    }

    /**
     * @dev 获取完整类型名称
     * @param zodiacType 生肖类型
     * @return 完整名称（如：水鼠（公））
     */
    function getFullTypeName(NFTDataTypes.ZodiacType zodiacType) external pure override returns (string memory) {
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(zodiacType);
        NFTDataTypes.BaseZodiac zodiac = NFTDataTypes.getBaseZodiac(zodiacType);
        NFTDataTypes.GenderType gender = NFTDataTypes.getGender(zodiacType);
        
        string memory elementName = getElementName(element);
        string memory zodiacName = getZodiacName(zodiac);
        string memory genderName = getGenderName(gender);
        
        return string(abi.encodePacked(elementName, zodiacName, "（", genderName, "）"));
    }

    /**
     * @dev 获取集合名称
     * @return 集合名称
     */
    function collName() external view override returns (string memory) {
        return "Twelve Zodiacs";
    }

    /**
     * @dev 获取集合描述
     * @return 集合描述
     */
    function collDesc() external view override returns (string memory) {
        return "十二生肖NFT系列 - 120种独特的生肖卡牌，包含5种属性（水、风、火、暗、光）和12种生肖";
    }

    /**
     * @dev 获取集合图片URL
     * @return 集合图片URL
     */
    function collImage() external view override returns (string memory) {
        return "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/logo.png";
    }

    /**
     * @dev 获取卖家手续费比例（basis points）
     * @return 手续费比例（500 = 5%）
     */
    function sellerFeeBasisPoints() external view override returns (uint256) {
        return 500;
    }

    /**
     * @dev 获取卡牌名称
     * @param zodiacType 生肖类型
     * @return 卡牌名称
     */
    function getCardName(NFTDataTypes.ZodiacType zodiacType) external view override returns (string memory) {
        return getFullTypeName(zodiacType);
    }

    /**
     * @dev 获取卡牌描述
     * @param zodiacType 生肖类型
     * @return 卡牌描述
     */
    function getCardDesc(NFTDataTypes.ZodiacType zodiacType) external view override returns (string memory) {
        string memory fullName = getFullTypeName(zodiacType);
        return string(abi.encodePacked("十二生肖NFT - ", fullName));
    }

    /**
     * @dev 获取卡牌图片URL
     * @param zodiacType 生肖类型
     * @return 卡牌图片URL
     */
    function getCardImage(NFTDataTypes.ZodiacType zodiacType) external view override returns (string memory) {
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(zodiacType);
        NFTDataTypes.BaseZodiac zodiac = NFTDataTypes.getBaseZodiac(zodiacType);
        NFTDataTypes.GenderType gender = NFTDataTypes.getGender(zodiacType);
        
        string memory elementName = getElementName(element);
        string memory zodiacName = getZodiacName(zodiac);
        string memory genderSuffix = gender == NFTDataTypes.GenderType.MALE ? "_1" : "_0";
        
        return string(abi.encodePacked(
            "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/",
            elementName, zodiacName, genderSuffix, ".png"
        ));
    }
}