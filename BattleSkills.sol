// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";

/**
 * @title BattleSkills
 * @dev 战斗技能初始化库，负责初始化所有属性的技能数据
 *
 * 属性编号：
 * - 0: 水属性
 * - 1: 风属性
 * - 2: 火属性
 * - 3: 暗属性
 * - 4: 光属性
 *
 * 技能数据结构：
 * - 每个属性有12个生肖（0-11）
 * - 每个生肖有2个技能（0-1）
 * - 技能包含：ID、类型、伤害值、冷却时间、AOE标志
 */
library BattleSkills {
    /**
     * @dev 初始化火属性技能
     * @param skills 技能映射存储
     */
    function initFireSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement0(skills);
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
        _initElement2(skills);
    }
    
    /**
     * @dev 初始化光属性技能
     * @param skills 技能映射存储
     */
    function initLightSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement3(skills);
    }
    
    /**
     * @dev 初始化暗属性技能
     * @param skills 技能映射存储
     */
    function initDarkSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement4(skills);
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
        _setS(skills, 0, 4, 0, 220, 6, true); _setS(skills, 0, 4, 1, 120, 5, true);
        _setS(skills, 0, 5, 0, 115, 4, false); _setS(skills, 0, 5, 1, 125, 4, false);
        _copy6To11(skills, 0);
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
        _setS(skills, 1, 4, 0, 210, 6, true); _setS(skills, 1, 4, 1, 115, 5, true);
        _setS(skills, 1, 5, 0, 125, 4, false); _setS(skills, 1, 5, 1, 120, 4, false);
        _copy6To11(skills, 1);
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
        _setS(skills, 2, 4, 0, 200, 6, true); _setS(skills, 2, 4, 1, 110, 5, true);
        _setS(skills, 2, 5, 0, 120, 4, false); _setS(skills, 2, 5, 1, 115, 4, false);
        _copy6To11(skills, 2);
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
        _setS(skills, 3, 4, 0, 245, 6, true); _setS(skills, 3, 4, 1, 140, 5, true);
        _setS(skills, 3, 5, 0, 145, 4, false); _setS(skills, 3, 5, 1, 130, 4, false);
        _copy6To11(skills, 3);
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
        _setS(skills, 4, 4, 0, 255, 6, true); _setS(skills, 4, 4, 1, 130, 5, true);
        _setS(skills, 4, 5, 0, 150, 4, false); _setS(skills, 4, 5, 1, 135, 4, false);
        _copy6To11(skills, 4);
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
