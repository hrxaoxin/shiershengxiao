// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";

/**
 * @title BattleSkills
 * @dev 战斗技能初始化库，负责初始化所有属性的技能数据
 *
 * 本合约为纯逻辑库（library），无状态，仅提供技能配置初始化函数。
 * 由 BattleSkillData 合约在部署 / 平衡调整时调用，将技能数据写入其 storage 中。
 *
 * 属性编号映射：
 * - 0: 水属性（WATER）→ initWaterSkills
 * - 1: 风属性（WIND）→ initWindSkills
 * - 2: 火属性（FIRE）→ initFireSkills
 * - 3: 暗属性（DARK）→ initDarkSkills
 * - 4: 光属性（LIGHT）→ initLightSkills
 *
 * 技能数据结构（基于 BattleLib.FullSkill）：
 * - 每个属性 × 12 生肖 × 2 性别 = 120 套完整技能配置
 * - 每套 FullSkill 包括：普攻、技能1、技能2、技能3、终极技能
 * - 每个技能包含：技能 ID、类型、基础伤害值、冷却回合数、是否 AOE
 *
 * 属性技能特性（基础设定，可由 owner 调整平衡）：
 * - 水属性：冰冻/减速类技能，偏控制与持续伤害
 * - 风属性：高暴击/多段攻击，偏快速进攻
 * - 火属性：高爆发/AOE 灼烧，偏群体输出
 * - 暗属性：吸血/减益，偏续航与削弱敌方
 * - 光属性：治疗/护盾，偏辅助与团队增益
 *
 * 使用流程：
 * 1. BattleSkillData 初始化时，调用 initAllSkills(skills)
 * 2. 内部依次调用 initWaterSkills / initWindSkills / initFireSkills /
 *    initDarkSkills / initLightSkills，填充 120 套技能
 * 3. 战斗时 Battle 合约从 BattleSkillData.getSkill(tokenType) 读取
 *
 * 平衡性调整：
 * - 可由 owner 重新执行 initAllSkills 覆盖全部技能（版本升级）
 * - 可新增单独函数更新特定属性技能（精细调整）
 * - 调整建议在测试网测试战斗数值后再上线主网
 */
library BattleSkills {
    /**
     * @dev 初始化火属性技能
     * @param skills 技能映射存储
     */
    function initFireSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement2(skills);
    }
    
    /**
     * @dev 初始化风属性技能
     * @param skills 技能映射存储
     */
    function initWindSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement1(skills);
    }
    
    /**
     * @dev 初始化水属性技能
     * @param skills 技能映射存储
     */
    function initWaterSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement0(skills);
    }
    
    /**
     * @dev 初始化光属性技能
     * @param skills 技能映射存储
     */
    function initLightSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement4(skills);
    }
    
    /**
     * @dev 初始化暗属性技能
     * @param skills 技能映射存储
     */
    function initDarkSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement3(skills);
    }
    
    /**
     * @dev 初始化水属性技能数据（内部函数）
     * @param skills 技能映射存储
     */
    function _initElement0(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 0, 0, 0, 125, 3, false); _setS(skills, 0, 0, 1, 110, 4, false);
        _setS(skills, 0, 1, 0, 145, 5, false); _setS(skills, 0, 1, 1, 95, 4, true);
        _setS(skills, 0, 2, 0, 165, 5, false); _setS(skills, 0, 2, 1, 85, 4, true);
        _setS(skills, 0, 3, 0, 130, 3, false); _setS(skills, 0, 3, 1, 80, 3, false);
        _setS(skills, 0, 4, 0, 185, 5, true); _setS(skills, 0, 4, 1, 100, 4, true);
        _setS(skills, 0, 5, 0, 115, 4, false); _setS(skills, 0, 5, 1, 125, 4, false);
        _copy6To11(skills, 0);
        _setS(skills, 0, 7, 0, 145, 5, false); _setS(skills, 0, 7, 1, 115, 4, true);
        _setS(skills, 0, 11, 0, 140, 5, false); _setS(skills, 0, 11, 1, 150, 4, true);
    }
    
    /**
     * @dev 初始化风属性技能数据（内部函数）
     * @param skills 技能映射存储
     */
    function _initElement1(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 1, 0, 0, 135, 3, false); _setS(skills, 1, 0, 1, 115, 4, false);
        _setS(skills, 1, 1, 0, 130, 5, false); _setS(skills, 1, 1, 1, 105, 4, true);
        _setS(skills, 1, 2, 0, 155, 5, false); _setS(skills, 1, 2, 1, 90, 4, true);
        _setS(skills, 1, 3, 0, 140, 3, false); _setS(skills, 1, 3, 1, 100, 3, false);
        _setS(skills, 1, 4, 0, 180, 5, true); _setS(skills, 1, 4, 1, 95, 4, true);
        _setS(skills, 1, 5, 0, 125, 4, false); _setS(skills, 1, 5, 1, 120, 4, false);
        _copy6To11(skills, 1);
        _setS(skills, 1, 7, 0, 150, 5, false); _setS(skills, 1, 7, 1, 125, 4, true);
        _setS(skills, 1, 11, 0, 145, 5, false); _setS(skills, 1, 11, 1, 140, 4, true);
    }
    
    /**
     * @dev 初始化火属性技能数据（内部函数）
     * @param skills 技能映射存储
     */
    function _initElement2(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 2, 0, 0, 120, 3, false); _setS(skills, 2, 0, 1, 105, 4, false);
        _setS(skills, 2, 1, 0, 140, 5, false); _setS(skills, 2, 1, 1, 110, 4, true);
        _setS(skills, 2, 2, 0, 160, 5, false); _setS(skills, 2, 2, 1, 85, 4, true);
        _setS(skills, 2, 3, 0, 145, 3, false); _setS(skills, 2, 3, 1, 95, 3, false);
        _setS(skills, 2, 4, 0, 170, 5, true); _setS(skills, 2, 4, 1, 95, 4, true);
        _setS(skills, 2, 5, 0, 120, 4, false); _setS(skills, 2, 5, 1, 115, 4, false);
        _copy6To11(skills, 2);
        _setS(skills, 2, 7, 0, 145, 5, false); _setS(skills, 2, 7, 1, 130, 4, true);
        _setS(skills, 2, 11, 0, 140, 5, false); _setS(skills, 2, 11, 1, 135, 4, true);
    }
    
    /**
     * @dev 初始化暗属性技能数据（内部函数）
     * @param skills 技能映射存储
     */
    function _initElement3(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 3, 0, 0, 145, 3, false); _setS(skills, 3, 0, 1, 135, 4, false);
        _setS(skills, 3, 1, 0, 150, 5, false); _setS(skills, 3, 1, 1, 115, 4, true);
        _setS(skills, 3, 2, 0, 165, 5, false); _setS(skills, 3, 2, 1, 90, 4, true);
        _setS(skills, 3, 3, 0, 160, 3, false); _setS(skills, 3, 3, 1, 100, 3, false);
        _setS(skills, 3, 4, 0, 220, 5, true); _setS(skills, 3, 4, 1, 125, 4, true);
        _setS(skills, 3, 5, 0, 145, 4, false); _setS(skills, 3, 5, 1, 130, 4, false);
        _copy6To11(skills, 3);
        _setS(skills, 3, 7, 0, 160, 5, false); _setS(skills, 3, 7, 1, 135, 4, true);
        _setS(skills, 3, 11, 0, 155, 5, false); _setS(skills, 3, 11, 1, 150, 4, true);
    }
    
    /**
     * @dev 初始化光属性技能数据（内部函数）
     * @param skills 技能映射存储
     */
    function _initElement4(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 4, 0, 0, 150, 3, false); _setS(skills, 4, 0, 1, 140, 4, false);
        _setS(skills, 4, 1, 0, 155, 5, false); _setS(skills, 4, 1, 1, 110, 4, true);
        _setS(skills, 4, 2, 0, 170, 5, false); _setS(skills, 4, 2, 1, 100, 4, true);
        _setS(skills, 4, 3, 0, 165, 3, false); _setS(skills, 4, 3, 1, 105, 3, false);
        _setS(skills, 4, 4, 0, 230, 5, true); _setS(skills, 4, 4, 1, 120, 4, true);
        _setS(skills, 4, 5, 0, 150, 4, false); _setS(skills, 4, 5, 1, 135, 4, false);
        _copy6To11(skills, 4);
        _setS(skills, 4, 7, 0, 165, 5, false); _setS(skills, 4, 7, 1, 130, 4, true);
        _setS(skills, 4, 11, 0, 160, 5, false); _setS(skills, 4, 11, 1, 155, 4, true);
    }
    
    /**
     * @dev 设置技能数据（内部函数）
     * @param skills 技能映射存储
     * @param e 属性编号
     * @param z 生肖编号
     * @param g 技能编号
     * @param v 技能伤害值
     * @param cd 冷却时间
     * @param aoe 是否AOE技能
     */
    function _setS(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills, uint256 e, uint256 z, uint256 g, uint256 v, uint256 cd, bool aoe) private {
        bytes32 h = bytes32(uint256(keccak256(abi.encodePacked(e, z, g))));
        skills[e][z][g] = BattleLib.FullSkill(h, _getSkillType(z, g), v, cd, 0, aoe);
    }
    
    /**
     * @dev 获取技能类型（内部函数）
     * @param z 生肖编号
     * @param g 技能编号
     * @return uint8 技能类型
     */
    function _getSkillType(uint256 z, uint256 g) private pure returns (uint8) {
        if (z == 0 && g == 0) return 0;
        if (z == 0 && g == 1) return 6;
        if (z == 1 && g == 0) return 0;
        if (z == 1 && g == 1) return 8;
        if (z == 2 && g == 0) return 0;
        if (z == 2 && g == 1) return 5;
        if (z == 3 && g == 0) return 0;
        if (z == 3 && g == 1) return 2;
        if (z == 4 && g == 0) return 3;
        if (z == 4 && g == 1) return 8;
        if (z == 5 && g == 0) return 7;
        return 6;
    }
    
    /**
     * @dev 复制技能数据到生肖6-11（内部函数）
     * @param skills 技能映射存储
     * @param e 属性编号
     */
    function _copy6To11(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills, uint256 e) private {
        for (uint256 i = 6; i < 12; i++) {
            uint256 b = i - 6;
            skills[e][i][0] = skills[e][b][0];
            skills[e][i][1] = skills[e][b][1];
        }
    }
    
    /**
     * @dev 初始化所有属性的技能
     * @param skills 技能映射存储
     */
    function initAllSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        initWaterSkills(skills);
        initWindSkills(skills);
        initFireSkills(skills);
        initDarkSkills(skills);
        initLightSkills(skills);
    }
}
