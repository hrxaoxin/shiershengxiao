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
 *
 * 类型索引分配：
 * - 0-23: 水 + 12生肖 + 2性别
 * - 24-47: 风 + 12生肖 + 2性别
 * - 48-71: 火 + 12生肖 + 2性别
 * - 72-95: 暗 + 12生肖 + 2性别
 * - 96-119: 光 + 12生肖 + 2性别
 */
library NFTDataTypes {
    /**
     * @dev 属性类型枚举
     * WATER: 水属性 - 代表灵活、智慧
     * WIND: 风属性 - 代表自由、速度
     * FIRE: 火属性 - 代表热情、攻击
     * DARK: 暗属性（稀有）- 代表神秘、强力
     * LIGHT: 光属性（稀有）- 代表神圣、治疗
     *
     * 属性克制关系：
     * - 火克风（火燃烧风）
     * - 风克水（风蒸发水）
     * - 水克火（水熄灭火焰）
     * - 光克暗（光驱逐黑暗）
     * - 暗克光（黑暗吞噬光明）
     */
    enum ElementType {
        WATER,    // 0 - 水属性
        WIND,     // 1 - 风属性
        FIRE,     // 2 - 火属性
        DARK,     // 3 - 暗属性（稀有，铸造概率低）
        LIGHT     // 4 - 光属性（稀有，铸造概率低）
    }

    /**
     * @dev 性别类型枚举
     * FEMALE: 母（阴性能量）
     * MALE: 公（阳性能量）
     *
     * 繁殖时会随机继承父母一方的属性和性别
     */
    enum GenderType {
        FEMALE,   // 0 - 母
        MALE      // 1 - 公
    }

    /**
     * @dev 十二生肖基础类型枚举
     * RAT: 鼠 - 速度95，聪明灵活
     * OX: 牛 - 速度40，稳重坚韧
     * TIGER: 虎 - 速度70，威猛有力
     * RABBIT: 兔 - 速度90，敏捷迅速
     * DRAGON: 龙 - 速度80，强大神秘
     * SNAKE: 蛇 - 速度85，阴险狡诈
     * HORSE: 马 - 速度100，奔放自由
     * GOAT: 羊 - 速度35，温和谦逊
     * MONKEY: 猴 - 速度110，聪明机智
     * ROOSTER: 鸡 - 速度55，准时警觉
     * DOG: 狗 - 速度60，忠诚可靠
     * PIG: 猪 - 速度30，憨厚可爱
     *
     * 每个生肖的基础速度会影响战斗中的先手顺序
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
     *
     * 命名规则: {属性}{生肖}_{性别}
     * 属性前缀: Shui(水), Feng(风), Huo(火), An(暗), Guang(光)
     * 生肖前缀: Shu(鼠), Niu(牛), Hu(虎), Tu(兔), Long(龙), She(蛇), Ma(马), Yang(羊), Hou(猴), Ji(鸡), Gou(狗), Zhu(猪)
     * 性别后缀: _1(公), _0(母)
     *
     * 示例:
     * - ShuiShu_1: 水鼠（公）
     * - GuangLong_0: 光龙（母）
     * - AnMa_1: 暗马（公）
     *
     * 铸造概率（普通铸造）:
     * - 水/风/火属性: 各约32%
     * - 暗/光属性: 各约2%
     *
     * 铸造概率（稀有铸造）:
     * - 暗属性: 50%
     * - 光属性: 50%
     */
    enum ZodiacType {
        // ==================== 水属性（0-23）====================
        // 水属性 - 公 (0-5)
        ShuiShu_1, // 0 - 水鼠（公）
        ShuiNiu_1, // 1 - 水牛（公）
        ShuiHu_1,  // 2 - 水虎（公）
        ShuiTu_1,  // 3 - 水兔（公）
        ShuiLong_1, // 4 - 水龙（公）
        ShuiShe_1, // 5 - 水蛇（公）
        // 水属性 - 公 (6-11)
        ShuiMa_1,  // 6 - 水马（公）
        ShuiYang_1, // 7 - 水羊（公）
        ShuiHou_1, // 8 - 水猴（公）
        ShuiJi_1,  // 9 - 水鸡（公）
        ShuiGou_1, // 10 - 水狗（公）
        ShuiZhu_1, // 11 - 水猪（公）
        // 水属性 - 母 (12-17)
        ShuiShu_0, // 12 - 水鼠（母）
        ShuiNiu_0, // 13 - 水牛（母）
        ShuiHu_0,  // 14 - 水虎（母）
        ShuiTu_0,  // 15 - 水兔（母）
        ShuiLong_0, // 16 - 水龙（母）
        ShuiShe_0, // 17 - 水蛇（母）
        // 水属性 - 母 (18-23)
        ShuiMa_0,  // 18 - 水马（母）
        ShuiYang_0, // 19 - 水羊（母）
        ShuiHou_0, // 20 - 水猴（母）
        ShuiJi_0,  // 21 - 水鸡（母）
        ShuiGou_0, // 22 - 水狗（母）
        ShuiZhu_0, // 23 - 水猪（母）

        // ==================== 风属性（24-47）====================
        // 风属性 - 公 (24-29)
        FengShu_1, // 24 - 风鼠（公）
        FengNiu_1, // 25 - 风牛（公）
        FengHu_1,  // 26 - 风虎（公）
        FengTu_1,  // 27 - 风兔（公）
        FengLong_1, // 28 - 风龙（公）
        FengShe_1, // 29 - 风蛇（公）
        // 风属性 - 公 (30-35)
        FengMa_1,  // 30 - 风马（公）
        FengYang_1, // 31 - 风羊（公）
        FengHou_1, // 32 - 风猴（公）
        FengJi_1,  // 33 - 风鸡（公）
        FengGou_1, // 34 - 风狗（公）
        FengZhu_1, // 35 - 风猪（公）
        // 风属性 - 母 (36-41)
        FengShu_0, // 36 - 风鼠（母）
        FengNiu_0, // 37 - 风牛（母）
        FengHu_0,  // 38 - 风虎（母）
        FengTu_0,  // 39 - 风兔（母）
        FengLong_0, // 40 - 风龙（母）
        FengShe_0, // 41 - 风蛇（母）
        // 风属性 - 母 (42-47)
        FengMa_0,  // 42 - 风马（母）
        FengYang_0, // 43 - 风羊（母）
        FengHou_0, // 44 - 风猴（母）
        FengJi_0,  // 45 - 风鸡（母）
        FengGou_0, // 46 - 风狗（母）
        FengZhu_0, // 47 - 风猪（母）

        // ==================== 火属性（48-71）====================
        // 火属性 - 公 (48-53)
        HuoShu_1, // 48 - 火鼠（公）
        HuoNiu_1, // 49 - 火牛（公）
        HuoHu_1,  // 50 - 火虎（公）
        HuoTu_1,  // 51 - 火兔（公）
        HuoLong_1, // 52 - 火龙（公）
        HuoShe_1, // 53 - 火蛇（公）
        // 火属性 - 公 (54-59)
        HuoMa_1,  // 54 - 火马（公）
        HuoYang_1, // 55 - 火羊（公）
        HuoHou_1, // 56 - 火猴（公）
        HuoJi_1,  // 57 - 火鸡（公）
        HuoGou_1, // 58 - 火狗（公）
        HuoZhu_1, // 59 - 火猪（公）
        // 火属性 - 母 (60-65)
        HuoShu_0, // 60 - 火鼠（母）
        HuoNiu_0, // 61 - 火牛（母）
        HuoHu_0,  // 62 - 火虎（母）
        HuoTu_0,  // 63 - 火兔（母）
        HuoLong_0, // 64 - 火龙（母）
        HuoShe_0, // 65 - 火蛇（母）
        // 火属性 - 母 (66-71)
        HuoMa_0,  // 66 - 火马（母）
        HuoYang_0, // 67 - 火羊（母）
        HuoHou_0, // 68 - 火猴（母）
        HuoJi_0,  // 69 - 火鸡（母）
        HuoGou_0, // 70 - 火狗（母）
        HuoZhu_0, // 71 - 火猪（母）

        // ==================== 暗属性（72-95）====================
        // 暗属性 - 公 (72-77)
        AnShu_1, // 72 - 暗鼠（公）
        AnNiu_1, // 73 - 暗牛（公）
        AnHu_1,  // 74 - 暗虎（公）
        AnTu_1,  // 75 - 暗兔（公）
        AnLong_1, // 76 - 暗龙（公）
        AnShe_1, // 77 - 暗蛇（公）
        // 暗属性 - 公 (78-83)
        AnMa_1,  // 78 - 暗马（公）
        AnYang_1, // 79 - 暗羊（公）
        AnHou_1, // 80 - 暗猴（公）
        AnJi_1,  // 81 - 暗鸡（公）
        AnGou_1, // 82 - 暗狗（公）
        AnZhu_1, // 83 - 暗猪（公）
        // 暗属性 - 母 (84-89)
        AnShu_0, // 84 - 暗鼠（母）
        AnNiu_0, // 85 - 暗牛（母）
        AnHu_0,  // 86 - 暗虎（母）
        AnTu_0,  // 87 - 暗兔（母）
        AnLong_0, // 88 - 暗龙（母）
        AnShe_0, // 89 - 暗蛇（母）
        // 暗属性 - 母 (90-95)
        AnMa_0,  // 90 - 暗马（母）
        AnYang_0, // 91 - 暗羊（母）
        AnHou_0, // 92 - 暗猴（母）
        AnJi_0,  // 93 - 暗鸡（母）
        AnGou_0, // 94 - 暗狗（母）
        AnZhu_0, // 95 - 暗猪（母）

        // ==================== 光属性（96-119）====================
        // 光属性 - 公 (96-101)
        GuangShu_1, // 96 - 光鼠（公）
        GuangNiu_1, // 97 - 光牛（公）
        GuangHu_1,  // 98 - 光虎（公）
        GuangTu_1,  // 99 - 光兔（公）
        GuangLong_1, // 100 - 光龙（公）
        GuangShe_1, // 101 - 光蛇（公）
        // 光属性 - 公 (102-107)
        GuangMa_1,  // 102 - 光马（公）
        GuangYang_1, // 103 - 光羊（公）
        GuangHou_1, // 104 - 光猴（公）
        GuangJi_1,  // 105 - 光鸡（公）
        GuangGou_1, // 106 - 光狗（公）
        GuangZhu_1, // 107 - 光猪（公）
        // 光属性 - 母 (108-113)
        GuangShu_0, // 108 - 光鼠（母）
        GuangNiu_0, // 109 - 光牛（母）
        GuangHu_0,  // 110 - 光虎（母）
        GuangTu_0,  // 111 - 光兔（母）
        GuangLong_0, // 112 - 光龙（母）
        GuangShe_0, // 113 - 光蛇（母）
        // 光属性 - 母 (114-119)
        GuangMa_0,  // 114 - 光马（母）
        GuangYang_0, // 115 - 光羊（母）
        GuangHou_0, // 116 - 光猴（母）
        GuangJi_0,  // 117 - 光鸡（母）
        GuangGou_0, // 118 - 光狗（母）
        GuangZhu_0  // 119 - 光猪（母）
    }

    /**
     * @dev NFT信息结构体
     *
     * 存储每个NFT的完整信息，包括ID、类型、等级和铸造时间
     * 这些信息存储在NFTData合约中，与ERC721代币分离
     *
     * @param tokenId NFT唯一标识符，从1开始递增
     * @param zodiacType NFT的完整生肖类型（120种之一）
     * @param level NFT当前等级（1-5）
     *        - 1级: 初始等级，铸造时随机成长值10-100
     *        - 2级: 需要1个同级NFT或10000代币升级
     *        - 3级: 需要2个同级NFT或40000代币升级
     *        - 4级: 需要3个同级NFT或120000代币升级
     *        - 5级: 需要4个同级NFT或480000代币升级，可用于繁殖
     * @param mintTime 铸造时间戳，用于计算某些基于时间的奖励
     */
    struct NFTInfo {
        uint256 tokenId;         // NFT唯一ID
        ZodiacType zodiacType;    // 生肖类型（属性+生肖+性别）
        uint8 level;              // 等级（1-5）
        uint256 mintTime;         // 铸造时间戳
    }

    /**
     * @dev 从生肖类型中提取属性类型
     *
     * 计算公式: ElementType = ZodiacType / 24
     * 因为每种属性包含12生肖×2性别=24种组合
     *
     * @param zodiacType 生肖类型（0-119）
     * @return ElementType 属性类型（水/风/火/暗/光）
     *
     * 使用示例:
     * - getElement(0) = WATER (水鼠/水牛...属于水属性)
     * - getElement(24) = WIND (风鼠/风牛...属于风属性)
     * - getElement(96) = LIGHT (光鼠/光牛...属于光属性)
     */
    function getElement(ZodiacType zodiacType) internal pure returns (ElementType) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return ElementType(typeValue / 24);
    }

    /**
     * @dev 从生肖类型中提取性别类型
     *
     * 计算公式: GenderType = ZodiacType % 2
     * 因为每种属性+生肖组合有公母两种
     *
     * @param zodiacType 生肖类型（0-119）
     * @return GenderType 性别类型（母/公）
     *
     * 使用示例:
     * - getGender(0) = MALE (水鼠_1，末尾为1表示公)
     * - getGender(12) = FEMALE (水鼠_0，末尾为0表示母)
     */
    function getGender(ZodiacType zodiacType) internal pure returns (GenderType) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return GenderType(typeValue % 2);
    }

    /**
     * @dev 从生肖类型中提取基础生肖类型
     *
     * 计算公式: BaseZodiac = (ZodiacType / 2) % 12
     * 先除以2是因为公母各占一半，再对12取模得到生肖索引
     *
     * @param zodiacType 生肖类型（0-119）
     * @return BaseZodiac 基础生肖类型（鼠/牛/虎.../猪）
     *
     * 使用示例:
     * - getBaseZodiac(0) = RAT (水鼠)
     * - getBaseZodiac(1) = RAT (水鼠_1)
     * - getBaseZodiac(2) = OX (水牛)
     */
    function getBaseZodiac(ZodiacType zodiacType) internal pure returns (BaseZodiac) {
        uint256 typeValue = uint256(zodiacType);
        require(typeValue < 120, "NFTDataTypes: Invalid ZodiacType");
        return BaseZodiac((typeValue / 2) % 12);
    }

    /**
     * @dev 根据属性、生肖和性别创建完整的生肖类型
     *
     * 这是getElement、getGender、getBaseZodiac的逆运算
     * 计算公式: ZodiacType = element × 24 + zodiac × 2 + gender
     *
     * @param element 属性类型（水/风/火/暗/光）
     * @param zodiac 基础生肖类型（鼠/牛/虎.../猪）
     * @param gender 性别类型（母/公）
     * @return ZodiacType 完整的生肖类型（0-119）
     *
     * 使用示例:
     * createZodiacType(WATER, RAT, MALE) = 0 (水鼠_1)
     * createZodiacType(LIGHT, DRAGON, FEMALE) = 112 (光龙_0)
     */
    function createZodiacType(ElementType element, BaseZodiac zodiac, GenderType gender) internal pure returns (ZodiacType) {
        require(uint256(element) < 5, "NFTDataTypes: Invalid ElementType");
        require(uint256(zodiac) < 12, "NFTDataTypes: Invalid BaseZodiac");
        return ZodiacType(uint256(element) * 24 + uint256(zodiac) * 2 + uint256(gender));
    }

    /**
     * @dev 验证生肖类型是否有效
     *
     * 用于在铸造和繁殖等操作前验证输入的生肖类型是否合法
     *
     * @param zodiacType 生肖类型
     * @return bool 是否有效（0-119为有效值）
     *
     * 使用示例:
     * isValidZodiacType(0) = true
     * isValidZodiacType(119) = true
     * isValidZodiacType(120) = false
     */
    function isValidZodiacType(ZodiacType zodiacType) internal pure returns (bool) {
        return uint256(zodiacType) < 120;
    }

    /**
     * @dev 获取属性类型的数值表示
     *
     * 用于需要数值计算的场合，如属性克制判断
     *
     * @param element 属性类型
     * @return uint256 数值表示（水=0, 风=1, 火=2, 暗=3, 光=4）
     */
    function getElementTypeValue(ElementType element) internal pure returns (uint256) {
        return uint256(element);
    }

    /**
     * @dev 获取生肖类型的数值表示
     *
     * 用于需要数值计算的场合，如随机选择
     *
     * @param zodiacType 生肖类型
     * @return uint256 数值表示（0-119）
     */
    function getZodiacTypeValue(ZodiacType zodiacType) internal pure returns (uint256) {
        return uint256(zodiacType);
    }
}
