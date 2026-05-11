// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library NFTDataTypes {
    enum ElementType {
        WATER, WIND, FIRE, DARK, LIGHT
    }

    enum GenderType {
        FEMALE, MALE
    }

    enum BaseZodiac {
        RAT, OX, TIGER, RABBIT, DRAGON, SNAKE, HORSE, GOAT, MONKEY, ROOSTER, DOG, PIG
    }

    enum ZodiacType {
        ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1,
        ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
        ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0,
        ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,

        FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1,
        FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
        FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0,
        FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,

        HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1,
        HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
        HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0,
        HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,

        AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1,
        AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
        AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0,
        AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,

        GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1,
        GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
        GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0,
        GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
    }

    struct NFTInfo {
        uint256 tokenId;
        ZodiacType zodiacType;
        uint8 level;
        uint256 mintTime;
    }

    function getElement(ZodiacType zodiacType) internal pure returns (ElementType) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return ElementType(typeValue / 24);
    }

    function getGender(ZodiacType zodiacType) internal pure returns (GenderType) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return GenderType(typeValue % 2);
    }

    function getBaseZodiac(ZodiacType zodiacType) internal pure returns (BaseZodiac) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return BaseZodiac((typeValue / 2) % 12);
    }

    function createZodiacType(ElementType element, BaseZodiac zodiac, GenderType gender) internal pure returns (ZodiacType) {
        require(uint256(element) < 5, "NFTDataTypes: Invalid ElementType");
        require(uint256(zodiac) < 12, "NFTDataTypes: Invalid BaseZodiac");
        return ZodiacType(uint256(element) * 24 + uint256(zodiac) * 2 + uint256(gender));
    }

    function isValidZodiacType(ZodiacType zodiacType) internal pure returns (bool) {
        return uint256(zodiacType) < 120;
    }

    function getElementTypeValue(ElementType element) internal pure returns (uint256) {
        return uint256(element);
    }

    function getZodiacTypeValue(ZodiacType zodiacType) internal pure returns (uint256) {
        return uint256(zodiacType);
    }
}