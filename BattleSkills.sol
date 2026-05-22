// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";

library BattleSkills {
    function initFireSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement0(skills);
    }
    
    function initWindSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement1(skills);
    }
    
    function initWaterSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement2(skills);
    }
    
    function initLightSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement3(skills);
    }
    
    function initDarkSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        _initElement4(skills);
    }
    
    function _initElement0(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 0, 0, 0, 125, 3, false); _setS(skills, 0, 0, 1, 110, 4, false);
        _setS(skills, 0, 1, 0, 145, 5, false); _setS(skills, 0, 1, 1, 95, 4, true);
        _setS(skills, 0, 2, 0, 165, 5, false); _setS(skills, 0, 2, 1, 85, 4, true);
        _setS(skills, 0, 3, 0, 130, 3, false); _setS(skills, 0, 3, 1, 80, 3, false);
        _setS(skills, 0, 4, 0, 220, 6, true); _setS(skills, 0, 4, 1, 120, 5, true);
        _setS(skills, 0, 5, 0, 115, 4, false); _setS(skills, 0, 5, 1, 125, 4, false);
        _copy6To11(skills, 0);
    }
    
    function _initElement1(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 1, 0, 0, 135, 3, false); _setS(skills, 1, 0, 1, 115, 4, false);
        _setS(skills, 1, 1, 0, 130, 5, false); _setS(skills, 1, 1, 1, 105, 4, true);
        _setS(skills, 1, 2, 0, 155, 5, false); _setS(skills, 1, 2, 1, 90, 4, true);
        _setS(skills, 1, 3, 0, 140, 3, false); _setS(skills, 1, 3, 1, 100, 3, false);
        _setS(skills, 1, 4, 0, 210, 6, true); _setS(skills, 1, 4, 1, 115, 5, true);
        _setS(skills, 1, 5, 0, 125, 4, false); _setS(skills, 1, 5, 1, 120, 4, false);
        _copy6To11(skills, 1);
    }
    
    function _initElement2(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 2, 0, 0, 120, 3, false); _setS(skills, 2, 0, 1, 105, 4, false);
        _setS(skills, 2, 1, 0, 140, 5, false); _setS(skills, 2, 1, 1, 110, 4, true);
        _setS(skills, 2, 2, 0, 160, 5, false); _setS(skills, 2, 2, 1, 85, 4, true);
        _setS(skills, 2, 3, 0, 145, 3, false); _setS(skills, 2, 3, 1, 95, 3, false);
        _setS(skills, 2, 4, 0, 200, 6, true); _setS(skills, 2, 4, 1, 110, 5, true);
        _setS(skills, 2, 5, 0, 120, 4, false); _setS(skills, 2, 5, 1, 115, 4, false);
        _copy6To11(skills, 2);
    }
    
    function _initElement3(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 3, 0, 0, 145, 3, false); _setS(skills, 3, 0, 1, 135, 4, false);
        _setS(skills, 3, 1, 0, 150, 5, false); _setS(skills, 3, 1, 1, 115, 4, true);
        _setS(skills, 3, 2, 0, 165, 5, false); _setS(skills, 3, 2, 1, 90, 4, true);
        _setS(skills, 3, 3, 0, 160, 3, false); _setS(skills, 3, 3, 1, 100, 3, false);
        _setS(skills, 3, 4, 0, 245, 6, true); _setS(skills, 3, 4, 1, 140, 5, true);
        _setS(skills, 3, 5, 0, 145, 4, false); _setS(skills, 3, 5, 1, 130, 4, false);
        _copy6To11(skills, 3);
    }
    
    function _initElement4(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) private {
        _setS(skills, 4, 0, 0, 150, 3, false); _setS(skills, 4, 0, 1, 140, 4, false);
        _setS(skills, 4, 1, 0, 155, 5, false); _setS(skills, 4, 1, 1, 110, 4, true);
        _setS(skills, 4, 2, 0, 170, 5, false); _setS(skills, 4, 2, 1, 100, 4, true);
        _setS(skills, 4, 3, 0, 165, 3, false); _setS(skills, 4, 3, 1, 105, 3, false);
        _setS(skills, 4, 4, 0, 255, 6, true); _setS(skills, 4, 4, 1, 130, 5, true);
        _setS(skills, 4, 5, 0, 150, 4, false); _setS(skills, 4, 5, 1, 135, 4, false);
        _copy6To11(skills, 4);
    }
    
    function _setS(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills, uint256 e, uint256 z, uint256 g, uint256 v, uint256 cd, bool aoe) private {
        bytes32 h = bytes32(uint256(keccak256(abi.encodePacked(e, z, g))));
        skills[e][z][g] = BattleLib.FullSkill(h, _getSkillType(z, g), v, cd, 0, aoe);
    }
    
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
    
    function _copy6To11(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills, uint256 e) private {
        for (uint256 i = 6; i < 12; i++) {
            uint256 b = i - 6;
            skills[e][i][0] = skills[e][b][0];
            skills[e][i][1] = skills[e][b][1];
        }
    }
    
    function initAllSkills(mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) storage skills) internal {
        initWaterSkills(skills);
        initWindSkills(skills);
        initFireSkills(skills);
        initDarkSkills(skills);
        initLightSkills(skills);
    }
}
