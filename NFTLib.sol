// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTLib
 * @dev NFT工具库，提供生肖NFT相关的数学计算和属性判断函数
 *
 * 本库包含以下功能模块：
 * 1. 战斗属性计算 - 攻击、防御、速度、生命值
 * 2. 属性克制判断 - 五行相克逻辑
 * 3. 伤害计算 - 技能伤害和暴击
 * 4. 权重系统 - 分红和质押的权重计算
 *
 * 战斗属性计算公式：
 * - 基础属性由生肖类型决定
 * - 最终属性 = 基础属性 × (1 + 等级加成)
 * - 等级加成 = (level - 1) × 0.1
 *
 * 属性克制关系：
 * - 火克风：火属性攻击风属性时伤害×1.5
 * - 风克水：风属性攻击水属性时伤害×1.5
 * - 水克火：水属性攻击火属性时伤害×1.5
 * - 光克暗：光属性攻击暗属性时伤害×1.5
 * - 暗克光：暗属性攻击光属性时伤害×1.5
 */
library NFTLib {
    uint256[12] internal constant BASE_HP = [
        uint256(1200), uint256(2000), uint256(1600), uint256(1000), uint256(1800), uint256(1400),
        uint256(1500), uint256(900), uint256(1100), uint256(800), uint256(1300), uint256(700)
    ];

    uint256[12] internal constant BASE_ATTACK = [
        uint256(120), uint256(80), uint256(150), uint256(90), uint256(180), uint256(140),
        uint256(130), uint256(60), uint256(160), uint256(70), uint256(100), uint256(50)
    ];

    uint256[12] internal constant BASE_DEFENSE = [
        uint256(80), uint256(120), uint256(100), uint256(70), uint256(130), uint256(110),
        uint256(90), uint256(60), uint256(100), uint256(50), uint256(110), uint256(40)
    ];

    uint256[12] internal constant BASE_CRITICAL = [
        uint256(800), uint256(500), uint256(900), uint256(600), uint256(850), uint256(750),
        uint256(700), uint256(400), uint256(950), uint256(550), uint256(650), uint256(350)
    ];

    uint256[12] internal constant BASE_DODGE = [
        uint256(600), uint256(200), uint256(500), uint256(800), uint256(300), uint256(700),
        uint256(400), uint256(250), uint256(900), uint256(550), uint256(450), uint256(350)
    ];

    uint256[12] internal constant BASE_SPEED = [
        uint256(95), uint256(40), uint256(70), uint256(90), uint256(80), uint256(85),
        uint256(100), uint256(35), uint256(110), uint256(55), uint256(60), uint256(30)
    ];

    /**
     * @dev 战斗属性结构体
     *
     * 存储NFT在战斗中的各项属性数值
     * 这些值由NFT的等级和基础属性决定
     */
    struct BattleAttributes {
        uint256 hp;         // 生命值
        uint256 attack;     // 攻击力
        uint256 defense;    // 防御力
        uint256 speed;      // 速度（决定先手顺序）
        uint256 critical;   // 暴击率（0-10000，表示0%-100%）
        uint256 dodge;      // 闪避率（0-10000，表示0%-100%）
    }

    /**
     * @dev 攻击结果结构体
     *
     * 存储一次攻击的所有相关信息
     * 包括是否暴击、是否闪避、最终伤害等
     */
    struct AttackResult {
        uint256 damage;        // 最终伤害
        bool isCritical;        // 是否暴击
        bool isDodged;          // 是否被闪避
        uint256 elementalBonus; // 属性克制加成（100=无加成，150=克制）
    }

    /**
     * @dev 根据生肖类型获取基础速度
     *
     * 速度影响战斗中的出手顺序，速度越高越先攻击
     * 速度还会影响闪避率的计算（速度越快越容易闪避）
     *
     * @param zodiacType 生肖类型（0-11对应十二生肖）
     * @return uint256 基础速度值
     *
     * 速度排名（从高到低）：
     * - 猴(MONKEY): 110 - 最快
     * - 马(HORSE): 100
     * - 鼠(RAT): 95
     * - 兔(RABBIT): 90
     * - 蛇(SNAKE): 85
     * - 龙(DRAGON): 80
     * - 虎(TIGER): 70
     * - 狗(DOG): 60
     * - 鸡(ROOSTER): 55
     * - 牛(OX): 40
     * - 羊(GOAT): 35
     * - 猪(PIG): 30 - 最慢
     */
    function getBaseSpeed(uint256 zodiacType) internal pure returns (uint256) {
        require(zodiacType < 12, "NFTLib: Invalid zodiac type");
        return BASE_SPEED[zodiacType];
    }

    /**
     * @dev 根据等级计算属性加成
     *
     * 等级加成公式: multiplier = 1 + (level - 1) × 0.1
     *
     * 示例：
     * - 1级: multiplier = 1.0 (无加成)
     * - 2级: multiplier = 1.1 (+10%)
     * - 3级: multiplier = 1.2 (+20%)
     * - 4级: multiplier = 1.3 (+30%)
     * - 5级: multiplier = 1.4 (+40%)
     *
     * @param level NFT等级（1-5）
     * @return uint256 加成倍数（精度2位小数，100=1.0）
     */
    function getLevelMultiplier(uint256 level) internal pure returns (uint256) {
        require(level >= 1 && level <= 5, "NFTLib: Invalid level");
        return 100 + (level - 1) * 10;
    }

    /**
     * @dev 计算战斗属性
     *
     * 根据NFT的基础属性和等级计算战斗时的完整属性
     *
     * @param zodiacType 生肖类型（0-11）
     * @param level NFT等级（1-5）
     * @return BattleAttributes 战斗属性结构体
     *
     * 属性计算：
     * - hp: 基础HP(500-2000) × 等级加成
     * - attack: 基础攻击(50-200) × 等级加成
     * - defense: 基础防御(30-150) × 等级加成
     * - speed: 基础速度 × 等级加成
     * - critical: 基础暴击 + 等级加成(每级+2%)
     * - dodge: 基础闪避 + 等级加成(每级+1%)
     */
    function calculateBattleAttributes(uint256 zodiacType, uint256 level) internal pure returns (BattleAttributes memory) {
        require(zodiacType < 12, "NFTLib: Invalid zodiac type");
        require(level >= 1 && level <= 5, "NFTLib: Invalid level");

        uint256 multiplier = getLevelMultiplier(level);

        BattleAttributes memory attrs;
        attrs.hp = BASE_HP[zodiacType] * multiplier / 100;
        attrs.attack = BASE_ATTACK[zodiacType] * multiplier / 100;
        attrs.defense = BASE_DEFENSE[zodiacType] * multiplier / 100;
        attrs.speed = BASE_SPEED[zodiacType] * multiplier / 100;
        attrs.critical = BASE_CRITICAL[zodiacType] + (level * 150);
        attrs.dodge = BASE_DODGE[zodiacType] + (level * 80);

        if (attrs.critical > 3000) attrs.critical = 3000;
        if (attrs.dodge > 1800) attrs.dodge = 1800;

        return attrs;
    }

    /**
     * @dev 判断属性克制关系
     *
     * 计算攻击方属性对被攻击方属性的克制加成
     *
     * 属性编号：
     * - 0: 水 (WATER)
     * - 1: 风 (WIND)
     * - 2: 火 (FIRE)
     * - 3: 暗 (DARK)
     * - 4: 光 (LIGHT)
     *
     * 克制关系：
     * - 火(2) → 风(1): 伤害×1.5
     * - 风(1) → 水(0): 伤害×1.5
     * - 水(0) → 火(2): 伤害×1.5
     * - 光(4) → 暗(3): 伤害×1.5
     * - 暗(3) → 光(4): 伤害×1.5
     * - 同属性或无克制关系: 伤害×1.0
     *
     * @param attackerElement 攻击方属性（0-4）
     * @param defenderElement 防守方属性（0-4）
     * @return uint256 克制加成（100=无加成，150=克制）
     */
    function getElementalBonus(uint256 attackerElement, uint256 defenderElement) internal pure returns (uint256) {
        if (attackerElement == 2 && defenderElement == 1) return 150; // 火克风
        if (attackerElement == 1 && defenderElement == 0) return 150; // 风克水
        if (attackerElement == 0 && defenderElement == 2) return 150; // 水克火
        if (attackerElement == 4 && defenderElement == 3) return 150; // 光克暗
        if (attackerElement == 3 && defenderElement == 4) return 150; // 暗克光
        return 100; // 无克制
    }

    /**
     * @dev 计算伤害
     *
     * 伤害公式：
     * baseDamage = attacker.attack × elementalBonus / 100
     * finalDamage = baseDamage × (defender.defense / 1000 + 1)
     *              × randomFactor / 100
     *
     * @param attacker 攻击方属性
     * @param defender 防守方属性
     * @param attackerElement 攻击方属性类型（0-4）
     * @param defenderElement 防守方属性类型（0-4）
     * @param randomValue 随机值（0-100）
     * @return AttackResult 攻击结果
     *
     * 暴击：randomValue < attacker.critical 时触发暴击，伤害×1.5
     * 闪避：randomValue < defender.dodge 时闪避成功，返回0伤害
     */
    function calculateDamage(
        BattleAttributes memory attacker,
        BattleAttributes memory defender,
        uint256 attackerElement,
        uint256 defenderElement,
        uint256 randomValue
    ) internal pure returns (AttackResult memory) {
        AttackResult memory result;

        if (randomValue < defender.dodge) {
            result.isDodged = true;
            result.damage = 0;
            return result;
        }

        result.elementalBonus = getElementalBonus(attackerElement, defenderElement);
        uint256 baseDamage = attacker.attack * result.elementalBonus / 100;
        uint256 defenseReduction = 1000 + defender.defense;
        uint256 finalDamage = baseDamage * 1000 / defenseReduction;

        result.isCritical = randomValue < attacker.critical;
        if (result.isCritical) {
            finalDamage = finalDamage * 3 / 2;
        }

        result.damage = finalDamage;
        return result;
    }

    /**
     * @dev 计算攻击力（简化版）
     *
     * 用于不需要完整战斗属性的场合
     *
     * @param zodiacType 生肖类型（0-11）
     * @param level 等级（1-5）
     * @return uint256 攻击力
     */
    function calculateAttack(uint256 zodiacType, uint256 level) internal pure returns (uint256) {
        require(zodiacType < 12, "NFTLib: Invalid zodiac type");
        require(level >= 1 && level <= 5, "NFTLib: Invalid level");
        uint256 multiplier = getLevelMultiplier(level);
        return BASE_ATTACK[zodiacType] * multiplier / 100;
    }

    /**
     * @dev 计算防御力（简化版）
     *
     * @param zodiacType 生肖类型（0-11）
     * @param level 等级（1-5）
     * @return uint256 防御力
     */
    function calculateDefense(uint256 zodiacType, uint256 level) internal pure returns (uint256) {
        require(zodiacType < 12, "NFTLib: Invalid zodiac type");
        require(level >= 1 && level <= 5, "NFTLib: Invalid level");
        uint256 multiplier = getLevelMultiplier(level);
        return BASE_DEFENSE[zodiacType] * multiplier / 100;
    }

    /**
     * @dev 计算生命值（简化版）
     *
     * @param zodiacType 生肖类型（0-11）
     * @param level 等级（1-5）
     * @return uint256 生命值
     */
    function calculateHP(uint256 zodiacType, uint256 level) internal pure returns (uint256) {
        require(zodiacType < 12, "NFTLib: Invalid zodiac type");
        require(level >= 1 && level <= 5, "NFTLib: Invalid level");
        uint256 multiplier = getLevelMultiplier(level);
        return BASE_HP[zodiacType] * multiplier / 100;
    }

    /**
     * @dev 计算速度（简化版）
     *
     * @param zodiacType 生肖类型（0-11）
     * @param level 等级（1-5）
     * @return uint256 速度值
     */
    function calculateSpeed(uint256 zodiacType, uint256 level) internal pure returns (uint256) {
        require(zodiacType < 12, "NFTLib: Invalid zodiac type");
        require(level >= 1 && level <= 5, "NFTLib: Invalid level");
        uint256 multiplier = getLevelMultiplier(level);
        return getBaseSpeed(zodiacType) * multiplier / 100;
    }

    /**
     * @dev 获取普通NFT的升级权重
     *
     * 权重用于分红和质押奖励的计算
     * 等级越高，权重越大
     *
     * @param level 等级（1-5）
     * @return uint256 权重值
     *
     * 权重表（普通NFT）：
     * - 1级: 1
     * - 2级: 2
     * - 3级: 6
     * - 4级: 18
     * - 5级: 66
     */
    function getCommonUpgradeWeight(uint256 level) internal pure returns (uint256) {
        uint256[6] memory weights = [
            uint256(0), uint256(1), uint256(2), uint256(6), uint256(18), uint256(66)
        ];
        require(level <= 5, "NFTLib: Invalid level");
        return weights[level];
    }

    /**
     * @dev 获取稀有NFT的升级权重
     *
     * 稀有NFT（暗/光属性）的权重更高
     *
     * @param level 等级（1-5）
     * @return uint256 权重值
     *
     * 权重表（稀有NFT）：
     * - 1级: 10
     * - 2级: 12
     * - 3级: 16
     * - 4级: 28
     * - 5级: 76
     */
    function getRareUpgradeWeight(uint256 level) internal pure returns (uint256) {
        uint256[6] memory weights = [
            uint256(0), uint256(10), uint256(12), uint256(16), uint256(28), uint256(76)
        ];
        require(level <= 5, "NFTLib: Invalid level");
        return weights[level];
    }

    /**
     * @dev 验证属性值是否有效
     *
     * @param element 属性类型值（0-4）
     * @return bool 是否有效
     */
    function isValidElement(uint256 element) internal pure returns (bool) {
        return element < 5;
    }

    /**
     * @dev 验证生肖类型值是否有效
     *
     * @param zodiacType 生肖类型值（0-11）
     * @return bool 是否有效
     */
    function isValidZodiac(uint256 zodiacType) internal pure returns (bool) {
        return zodiacType < 12;
    }

    /**
     * @dev 验证等级值是否有效
     *
     * @param level 等级值（1-5）
     * @return bool 是否有效
     */
    function isValidLevel(uint256 level) internal pure returns (bool) {
        return level >= 1 && level <= 5;
    }

    /**
     * @dev 判断是否为稀有属性
     *
     * 稀有属性包括：暗(3)、光(4)
     * 稀有属性NFT在战斗中有额外加成，权重也更高
     *
     * @param element 属性类型值（0-4）
     * @return bool 是否为稀有属性
     */
    function isRareElement(uint256 element) internal pure returns (bool) {
        return element == 3 || element == 4; // DARK or LIGHT
    }

    /**
     * @dev 获取属性名称
     *
     * @param element 属性类型值（0-4）
     * @return string 属性名称
     */
    function getElementName(uint256 element) internal pure returns (string memory) {
        if (element == 0) return "Water";
        if (element == 1) return "Wind";
        if (element == 2) return "Fire";
        if (element == 3) return "Dark";
        if (element == 4) return "Light";
        revert("NFTLib: Invalid element");
    }

    /**
     * @dev 获取生肖名称
     *
     * @param zodiac 生肖类型值（0-11）
     * @return string 生肖名称
     */
    function getZodiacName(uint256 zodiac) internal pure returns (string memory) {
        if (zodiac == 0) return "Rat";
        if (zodiac == 1) return "Ox";
        if (zodiac == 2) return "Tiger";
        if (zodiac == 3) return "Rabbit";
        if (zodiac == 4) return "Dragon";
        if (zodiac == 5) return "Snake";
        if (zodiac == 6) return "Horse";
        if (zodiac == 7) return "Goat";
        if (zodiac == 8) return "Monkey";
        if (zodiac == 9) return "Rooster";
        if (zodiac == 10) return "Dog";
        if (zodiac == 11) return "Pig";
        revert("NFTLib: Invalid zodiac");
    }

    /**
     * @dev 安全执行除法
     * 
     * Note: 在Solidity 0.8+中，safeAdd/safeSub的溢出检查已内置，但safeDiv仍需要
     * 因为除法不会自动检查除零错误。保留这些函数是为了：
     * 1. 与旧代码保持兼容性
     * 2. 提供统一的错误消息格式
     * 3. safeDiv的除零检查仍然必要
     *
     * @param a 被除数
     * @param b 除数
     * @return uint256 结果
     */
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "NFTLib: Division by zero");
        return a / b;
    }

    /**
     * @dev 安全执行加法（保留用于向后兼容）
     * 
     * Note: Solidity 0.8+已内置溢出检查，此函数主要用于保持与旧代码的兼容性。
     * 保留的原因：统一错误消息格式，便于调试和日志记录。
     *
     * @param a 加数
     * @param b 加数
     * @return uint256 结果
     */
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "NFTLib: Addition overflow");
        return c;
    }

    /**
     * @dev 安全执行减法（保留用于向后兼容）
     * 
     * Note: Solidity 0.8+已内置下溢检查，此函数主要用于保持与旧代码的兼容性。
     * 保留的原因：统一错误消息格式，便于调试和日志记录。
     *
     * @param a 被减数
     * @param b 减数
     * @return uint256 结果
     */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "NFTLib: Subtraction underflow");
        return a - b;
    }
}
