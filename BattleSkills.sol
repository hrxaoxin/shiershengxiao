// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library BattleSkills {
    uint8 constant ATTACK = 0;
    uint8 constant DEFENSE = 1;
    uint8 constant HEAL = 2;
    uint8 constant SPECIAL = 3;
    uint8 constant BUFF = 4;
    uint8 constant DEBUFF = 5;
    uint8 constant COUNTER = 6;
    uint8 constant LIFESTEAL = 7;
    uint8 constant SHIELD = 8;
    
    struct FullSkill {
        string name;           // 技能名称
        uint8 skillType;       // 技能类型
        uint256 value;         // 技能数值（百分比）
        uint256 cooldown;      // 冷却回合数
        uint256 duration;      // 效果持续回合数
        bool isAoe;            // 是否为范围攻击
    }
    
    struct BattleRoundResult {
        uint256 attackerTokenId;
        uint256 defenderTokenId;
        bool attackerWon;
        uint256 attackerDamage;
        uint256 defenderDamage;
        string attackerSkill;
        string defenderSkill;
        bool attackerDodged;
        bool defenderDodged;
    }
    
    struct SingleBattleResult {
        bool attackerWon;
        uint256 attackerDamage;
        uint256 defenderDamage;
        string attackerSkill;
        string defenderSkill;
        bool attackerDodged;
        bool defenderDodged;
    }
    
    function initFireSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) storage skills) internal {
        skills[0][0][0] = FullSkill(unicode"烈焰穿梭", ATTACK, 125, 3, 0, false);
        skills[0][0][1] = FullSkill(unicode"炎影反击", COUNTER, 110, 4, 0, false);
        skills[0][1][0] = FullSkill(unicode"焚天巨力", ATTACK, 145, 5, 0, false);
        skills[0][1][1] = FullSkill(unicode"炽焰守护", SHIELD, 95, 4, 2, false);
        skills[0][2][0] = FullSkill(unicode"爆炎猛击", ATTACK, 165, 5, 0, false);
        skills[0][2][1] = FullSkill(unicode"烈焰威慑", DEBUFF, 85, 4, 2, false);
        skills[0][3][0] = FullSkill(unicode"疾风烈焰", ATTACK, 130, 3, 0, false);
        skills[0][3][1] = FullSkill(unicode"火焰跃闪", DEFENSE, 80, 3, 0, false);
        skills[0][4][0] = FullSkill(unicode"龙焰焚天", SPECIAL, 220, 6, 0, true);
        skills[0][4][1] = FullSkill(unicode"炎龙守护", SHIELD, 120, 5, 2, false);
        skills[0][5][0] = FullSkill(unicode"火毒噬咬", LIFESTEAL, 115, 4, 0, false);
        skills[0][5][1] = FullSkill(unicode"烈焰反击", COUNTER, 125, 4, 0, false);
        skills[0][6][0] = FullSkill(unicode"燎原奔踏", ATTACK, 140, 3, 0, false);
        skills[0][6][1] = FullSkill(unicode"火云疾驰", BUFF, 85, 4, 2, false);
        skills[0][7][0] = FullSkill(unicode"圣火治愈", HEAL, 110, 5, 0, false);
        skills[0][7][1] = FullSkill(unicode"烈焰祈福", HEAL, 130, 6, 0, false);
        skills[0][8][0] = FullSkill(unicode"火舞戏耍", ATTACK, 115, 2, 0, false);
        skills[0][8][1] = FullSkill(unicode"赤炎变幻", DEFENSE, 90, 3, 0, false);
        skills[0][9][0] = FullSkill(unicode"火羽锐击", ATTACK, 105, 3, 0, false);
        skills[0][9][1] = FullSkill(unicode"烈焰警戒", BUFF, 75, 3, 2, false);
        skills[0][10][0] = FullSkill(unicode"火獒追击", ATTACK, 120, 4, 0, false);
        skills[0][10][1] = FullSkill(unicode"炎犬反击", COUNTER, 115, 4, 0, false);
        skills[0][11][0] = FullSkill(unicode"火猪纳福", HEAL, 140, 6, 0, false);
        skills[0][11][1] = FullSkill(unicode"烈焰厚积", DEFENSE, 100, 5, 0, false);
    }
    
    function initWindSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) storage skills) internal {
        skills[1][0][0] = FullSkill(unicode"疾风穿梭", ATTACK, 135, 3, 0, false);
        skills[1][0][1] = FullSkill(unicode"风影反击", COUNTER, 115, 4, 0, false);
        skills[1][1][0] = FullSkill(unicode"旋风巨力", ATTACK, 130, 5, 0, false);
        skills[1][1][1] = FullSkill(unicode"风之壁垒", SHIELD, 105, 4, 2, false);
        skills[1][2][0] = FullSkill(unicode"暴风猛击", ATTACK, 155, 5, 0, false);
        skills[1][2][1] = FullSkill(unicode"风啸威慑", DEBUFF, 90, 4, 2, false);
        skills[1][3][0] = FullSkill(unicode"风跃突袭", ATTACK, 140, 3, 0, false);
        skills[1][3][1] = FullSkill(unicode"疾风闪避", DEFENSE, 100, 3, 0, false);
        skills[1][4][0] = FullSkill(unicode"风暴龙吟", SPECIAL, 210, 6, 0, true);
        skills[1][4][1] = FullSkill(unicode"风龙护盾", SHIELD, 115, 5, 2, false);
        skills[1][5][0] = FullSkill(unicode"风刃穿刺", ATTACK, 125, 4, 0, false);
        skills[1][5][1] = FullSkill(unicode"旋风反击", COUNTER, 120, 4, 0, false);
        skills[1][6][0] = FullSkill(unicode"追风踏燕", ATTACK, 150, 3, 0, false);
        skills[1][6][1] = FullSkill(unicode"风驰电掣", BUFF, 90, 3, 2, false);
        skills[1][7][0] = FullSkill(unicode"清风治愈", HEAL, 105, 5, 0, false);
        skills[1][7][1] = FullSkill(unicode"风之祈福", HEAL, 120, 6, 0, false);
        skills[1][8][0] = FullSkill(unicode"风猴戏耍", ATTACK, 120, 2, 0, false);
        skills[1][8][1] = FullSkill(unicode"疾风变幻", DEFENSE, 95, 3, 0, false);
        skills[1][9][0] = FullSkill(unicode"风羽振翅", ATTACK, 110, 3, 0, false);
        skills[1][9][1] = FullSkill(unicode"风之警戒", BUFF, 80, 3, 2, false);
        skills[1][10][0] = FullSkill(unicode"风犬追击", ATTACK, 125, 4, 0, false);
        skills[1][10][1] = FullSkill(unicode"疾风反击", COUNTER, 110, 4, 0, false);
        skills[1][11][0] = FullSkill(unicode"风猪纳福", HEAL, 130, 6, 0, false);
        skills[1][11][1] = FullSkill(unicode"风之厚积", DEFENSE, 95, 5, 0, false);
    }
    
    function initWaterSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) storage skills) internal {
        skills[2][0][0] = FullSkill(unicode"潮涌穿梭", ATTACK, 120, 3, 0, false);
        skills[2][0][1] = FullSkill(unicode"水影反击", COUNTER, 105, 4, 0, false);
        skills[2][1][0] = FullSkill(unicode"巨浪冲击", ATTACK, 140, 5, 0, false);
        skills[2][1][1] = FullSkill(unicode"水之磐石", SHIELD, 110, 4, 2, false);
        skills[2][2][0] = FullSkill(unicode"海啸猛击", ATTACK, 160, 5, 0, false);
        skills[2][2][1] = FullSkill(unicode"寒水威慑", DEBUFF, 85, 4, 2, false);
        skills[2][3][0] = FullSkill(unicode"水跃突袭", ATTACK, 135, 3, 0, false);
        skills[2][3][1] = FullSkill(unicode"碧水闪避", DEFENSE, 95, 3, 0, false);
        skills[2][4][0] = FullSkill(unicode"海啸龙吟", SPECIAL, 200, 6, 0, true);
        skills[2][4][1] = FullSkill(unicode"水龙护盾", SHIELD, 110, 5, 2, false);
        skills[2][5][0] = FullSkill(unicode"毒水噬咬", LIFESTEAL, 120, 4, 0, false);
        skills[2][5][1] = FullSkill(unicode"寒水反击", COUNTER, 115, 4, 0, false);
        skills[2][6][0] = FullSkill(unicode"踏浪奔腾", ATTACK, 145, 3, 0, false);
        skills[2][6][1] = FullSkill(unicode"水之疾驰", BUFF, 85, 3, 2, false);
        skills[2][7][0] = FullSkill(unicode"净水治愈", HEAL, 115, 5, 0, false);
        skills[2][7][1] = FullSkill(unicode"水之祈福", HEAL, 135, 6, 0, false);
        skills[2][8][0] = FullSkill(unicode"水猴戏耍", ATTACK, 115, 2, 0, false);
        skills[2][8][1] = FullSkill(unicode"碧水变幻", DEFENSE, 90, 3, 0, false);
        skills[2][9][0] = FullSkill(unicode"水羽振翅", ATTACK, 105, 3, 0, false);
        skills[2][9][1] = FullSkill(unicode"水之警戒", BUFF, 75, 3, 2, false);
        skills[2][10][0] = FullSkill(unicode"水犬追击", ATTACK, 115, 4, 0, false);
        skills[2][10][1] = FullSkill(unicode"碧水反击", COUNTER, 100, 4, 0, false);
        skills[2][11][0] = FullSkill(unicode"水猪纳福", HEAL, 145, 6, 0, false);
        skills[2][11][1] = FullSkill(unicode"水之厚积", DEFENSE, 105, 5, 0, false);
    }
    
    function initLightSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) storage skills) internal {
        skills[3][0][0] = FullSkill(unicode"圣光穿梭", ATTACK, 145, 3, 0, false);
        skills[3][0][1] = FullSkill(unicode"光影反击", COUNTER, 135, 4, 0, false);
        skills[3][1][0] = FullSkill(unicode"光耀巨力", ATTACK, 150, 5, 0, false);
        skills[3][1][1] = FullSkill(unicode"光之壁垒", SHIELD, 115, 4, 2, false);
        skills[3][2][0] = FullSkill(unicode"圣光猛击", ATTACK, 165, 5, 0, false);
        skills[3][2][1] = FullSkill(unicode"光明威慑", DEBUFF, 90, 4, 2, false);
        skills[3][3][0] = FullSkill(unicode"光跃突袭", ATTACK, 145, 3, 0, false);
        skills[3][3][1] = FullSkill(unicode"圣光闪避", DEFENSE, 110, 3, 0, false);
        skills[3][4][0] = FullSkill(unicode"圣光龙吟", SPECIAL, 245, 6, 0, true);
        skills[3][4][1] = FullSkill(unicode"光龙护盾", SHIELD, 140, 5, 2, false);
        skills[3][5][0] = FullSkill(unicode"光刃穿刺", ATTACK, 135, 4, 0, false);
        skills[3][5][1] = FullSkill(unicode"圣光反击", COUNTER, 140, 4, 0, false);
        skills[3][6][0] = FullSkill(unicode"踏光而行", ATTACK, 160, 3, 0, false);
        skills[3][6][1] = FullSkill(unicode"光明疾驰", BUFF, 100, 3, 2, false);
        skills[3][7][0] = FullSkill(unicode"圣光治愈", HEAL, 140, 5, 0, false);
        skills[3][7][1] = FullSkill(unicode"光之祈福", HEAL, 160, 6, 0, false);
        skills[3][8][0] = FullSkill(unicode"灵猴戏耍", ATTACK, 140, 2, 0, false);
        skills[3][8][1] = FullSkill(unicode"圣光变幻", DEFENSE, 115, 3, 0, false);
        skills[3][9][0] = FullSkill(unicode"光羽振翅", ATTACK, 130, 3, 0, false);
        skills[3][9][1] = FullSkill(unicode"光之警戒", BUFF, 95, 3, 2, false);
        skills[3][10][0] = FullSkill(unicode"圣犬追击", ATTACK, 145, 4, 0, false);
        skills[3][10][1] = FullSkill(unicode"圣光反击", COUNTER, 130, 4, 0, false);
        skills[3][11][0] = FullSkill(unicode"圣猪纳福", HEAL, 165, 6, 0, false);
        skills[3][11][1] = FullSkill(unicode"光之厚积", DEFENSE, 115, 5, 0, false);
    }
    
    function initDarkSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) storage skills) internal {
        skills[4][0][0] = FullSkill(unicode"暗影穿梭", ATTACK, 150, 3, 0, false);
        skills[4][0][1] = FullSkill(unicode"幽冥反击", COUNTER, 140, 4, 0, false);
        skills[4][1][0] = FullSkill(unicode"暗影重击", ATTACK, 155, 5, 0, false);
        skills[4][1][1] = FullSkill(unicode"冥之壁垒", SHIELD, 110, 4, 2, false);
        skills[4][2][0] = FullSkill(unicode"暗影猛击", ATTACK, 170, 5, 0, false);
        skills[4][2][1] = FullSkill(unicode"幽冥威慑", DEBUFF, 100, 4, 2, false);
        skills[4][3][0] = FullSkill(unicode"暗跃突袭", ATTACK, 155, 3, 0, false);
        skills[4][3][1] = FullSkill(unicode"暗影闪避", DEFENSE, 115, 3, 0, false);
        skills[4][4][0] = FullSkill(unicode"暗影龙吟", SPECIAL, 255, 6, 0, true);
        skills[4][4][1] = FullSkill(unicode"暗龙护盾", SHIELD, 130, 5, 2, false);
        skills[4][5][0] = FullSkill(unicode"暗影吞噬", LIFESTEAL, 145, 4, 0, false);
        skills[4][5][1] = FullSkill(unicode"幽冥反击", COUNTER, 145, 4, 0, false);
        skills[4][6][0] = FullSkill(unicode"踏冥奔腾", ATTACK, 165, 3, 0, false);
        skills[4][6][1] = FullSkill(unicode"暗影疾驰", BUFF, 105, 3, 2, false);
        skills[4][7][0] = FullSkill(unicode"暗影治愈", HEAL, 125, 5, 0, false);
        skills[4][7][1] = FullSkill(unicode"冥之祈福", HEAL, 140, 6, 0, false);
        skills[4][8][0] = FullSkill(unicode"冥猴戏耍", ATTACK, 135, 2, 0, false);
        skills[4][8][1] = FullSkill(unicode"暗影变幻", DEFENSE, 110, 3, 0, false);
        skills[4][9][0] = FullSkill(unicode"暗羽振翅", ATTACK, 125, 3, 0, false);
        skills[4][9][1] = FullSkill(unicode"冥之警戒", BUFF, 95, 3, 2, false);
        skills[4][10][0] = FullSkill(unicode"冥犬追击", ATTACK, 150, 4, 0, false);
        skills[4][10][1] = FullSkill(unicode"暗影反击", COUNTER, 135, 4, 0, false);
        skills[4][11][0] = FullSkill(unicode"冥猪纳福", HEAL, 150, 6, 0, false);
        skills[4][11][1] = FullSkill(unicode"冥之厚积", DEFENSE, 110, 5, 0, false);
    }
    
    function initAllSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) storage skills) internal {
        initWaterSkills(skills);
        initWindSkills(skills);
        initFireSkills(skills);
        initDarkSkills(skills);
        initLightSkills(skills);
    }
}