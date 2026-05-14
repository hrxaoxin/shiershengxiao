// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTDataTypes
 * @dev NFT数据类型库，定义十二生肖NFT的核心数据结构和枚举类型
 * 
 * NFT类型编码规则：
 * - 总共有120种不同的NFT类型（5属性 × 12生肖 × 2性别）
 * - ZodiacType值 = ElementType × 24 + BaseZodiac × 2 + GenderType
 * - ElementType: 水(0), 风(1), 火(2), 暗(3), 光(4)
 * - BaseZodiac: 鼠(0), 牛(1), 虎(2), 兔(3), 龙(4), 蛇(5), 马(6), 羊(7), 猴(8), 鸡(9), 狗(10), 猪(11)
 * - GenderType: 母(0), 公(1)
 */
library NFTDataTypes {
    /**
     * @dev 属性类型枚举
     * WATER: 水属性
     * WIND: 风属性
     * FIRE: 火属性
     * DARK: 暗属性（稀有）
     * LIGHT: 光属性（稀有）
     */
    enum ElementType {
        WATER,    // 0 - 水属性
        WIND,     // 1 - 风属性  
        FIRE,     // 2 - 火属性
        DARK,     // 3 - 暗属性（稀有）
        LIGHT     // 4 - 光属性（稀有）
    }

    /**
     * @dev 性别类型枚举
     * FEMALE: 母
     * MALE: 公
     */
    enum GenderType {
        FEMALE,   // 0 - 母
        MALE      // 1 - 公
    }

    /**
     * @dev 十二生肖基础类型枚举
     * RAT: 鼠
     * OX: 牛
     * TIGER: 虎
     * RABBIT: 兔
     * DRAGON: 龙
     * SNAKE: 蛇
     * HORSE: 马
     * GOAT: 羊
     * MONKEY: 猴
     * ROOSTER: 鸡
     * DOG: 狗
     * PIG: 猪
     */
    enum BaseZodiac {
        RAT,      // 0 - 鼠
        OX,       // 1 - 牛
        TIGER,    // 2 - 虎
        RABBIT,   // 3 - 兔
        DRAGON,   // 4 - 龙
        SNAKE,    // 5 - 蛇
        HORSE,    // 6 - 马
        GOAT,     // 7 - 羊
        MONKEY,   // 8 - 猴
        ROOSTER,  // 9 - 鸡
        DOG,      // 10 - 狗
        PIG       // 11 - 猪
    }

    /**
     * @dev 完整的生肖类型枚举（120种）
     * 命名规则: {属性}{生肖}_{性别}
     * 属性: Shui(水), Feng(风), Huo(火), An(暗), Guang(光)
     * 生肖: Shu(鼠), Niu(牛), Hu(虎), Tu(兔), Long(龙), She(蛇), Ma(马), Yang(羊), Hou(猴), Ji(鸡), Gou(狗), Zhu(猪)
     * 性别: 1(公), 0(母)
     */
    enum ZodiacType {
        // 水属性 - 公 (12种)
        ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1,
        ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
        // 水属性 - 母 (12种)
        ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0,
        ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,

        // 风属性 - 公 (12种)
        FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1,
        FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
        // 风属性 - 母 (12种)
        FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0,
        FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,

        // 火属性 - 公 (12种)
        HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1,
        HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
        // 火属性 - 母 (12种)
        HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0,
        HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,

        // 暗属性 - 公 (12种)
        AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1,
        AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
        // 暗属性 - 母 (12种)
        AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0,
        AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,

        // 光属性 - 公 (12种)
        GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1,
        GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
        // 光属性 - 母 (12种)
        GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0,
        GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
    }

    /**
     * @dev NFT信息结构体
     * @param tokenId NFT唯一标识
     * @param zodiacType NFT生肖类型
     * @param level NFT等级（1-5）
     * @param mintTime 铸造时间戳
     */
    struct NFTInfo {
        uint256 tokenId;
        ZodiacType zodiacType;
        uint8 level;
        uint256 mintTime;
    }

    /**
     * @dev 从生肖类型中提取属性类型
     * @param zodiacType 生肖类型
     * @return ElementType 属性类型
     */
    function getElement(ZodiacType zodiacType) internal pure returns (ElementType) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return ElementType(typeValue / 24);
    }

    /**
     * @dev 从生肖类型中提取性别类型
     * @param zodiacType 生肖类型
     * @return GenderType 性别类型
     */
    function getGender(ZodiacType zodiacType) internal pure returns (GenderType) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return GenderType(typeValue % 2);
    }

    /**
     * @dev 从生肖类型中提取基础生肖类型
     * @param zodiacType 生肖类型
     * @return BaseZodiac 基础生肖类型
     */
    function getBaseZodiac(ZodiacType zodiacType) internal pure returns (BaseZodiac) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return BaseZodiac((typeValue / 2) % 12);
    }

    /**
     * @dev 根据属性、生肖和性别创建完整的生肖类型
     * @param element 属性类型
     * @param zodiac 基础生肖类型
     * @param gender 性别类型
     * @return ZodiacType 完整的生肖类型
     */
    function createZodiacType(ElementType element, BaseZodiac zodiac, GenderType gender) internal pure returns (ZodiacType) {
        require(uint256(element) < 5, "NFTDataTypes: Invalid ElementType");
        require(uint256(zodiac) < 12, "NFTDataTypes: Invalid BaseZodiac");
        return ZodiacType(uint256(element) * 24 + uint256(zodiac) * 2 + uint256(gender));
    }

    /**
     * @dev 验证生肖类型是否有效
     * @param zodiacType 生肖类型
     * @return bool 是否有效
     */
    function isValidZodiacType(ZodiacType zodiacType) internal pure returns (bool) {
        return uint256(zodiacType) < 120;
    }

    /**
     * @dev 获取属性类型的数值表示
     * @param element 属性类型
     * @return uint256 数值表示
     */
    function getElementTypeValue(ElementType element) internal pure returns (uint256) {
        return uint256(element);
    }

    /**
     * @dev 获取生肖类型的数值表示
     * @param zodiacType 生肖类型
     * @return uint256 数值表示
     */
    function getZodiacTypeValue(ZodiacType zodiacType) internal pure returns (uint256) {
        return uint256(zodiacType);
    }
}