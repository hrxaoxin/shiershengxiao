// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";

library BattleLib {
    uint256 constant DODGE_BASE_CHANCE = 1500;
    uint256 constant BASE_HEALTH = 400;

    struct NFTStatus {
        uint256 tokenId;
        NFTDataTypes.ElementType element;
        uint256 zodiac;
        uint256 gender;
        uint256 level;
        uint256 attackValue;
        uint256 defenseValue;
        bytes32 skillHash;
        uint8 skillType;
        uint256 skillValue;
    }

    struct FullSkill {
        bytes32 nameHash;
        uint8 skillType;
        uint256 value;
        uint256 cooldown;
        uint256 duration;
        bool isAoe;
    }

    struct SingleBattleResult {
        bool attackerWon;
        uint256 attackerDamage;
        uint256 defenderDamage;
        bytes32 attackerSkill;
        bytes32 defenderSkill;
        bool attackerDodged;
        bool defenderDodged;
    }

    function _getElementMultiplier(NFTDataTypes.ElementType attacker, NFTDataTypes.ElementType defender) internal pure returns (uint256) {
        if (attacker == NFTDataTypes.ElementType.FIRE && defender == NFTDataTypes.ElementType.WIND) return 150;
        if (attacker == NFTDataTypes.ElementType.WIND && defender == NFTDataTypes.ElementType.WATER) return 150;
        if (attacker == NFTDataTypes.ElementType.WATER && defender == NFTDataTypes.ElementType.FIRE) return 150;
        if (attacker == NFTDataTypes.ElementType.LIGHT && defender == NFTDataTypes.ElementType.DARK) return 150;
        if (attacker == NFTDataTypes.ElementType.DARK && defender == NFTDataTypes.ElementType.LIGHT) return 150;
        
        if (attacker == NFTDataTypes.ElementType.WIND && defender == NFTDataTypes.ElementType.FIRE) return 70;
        if (attacker == NFTDataTypes.ElementType.WATER && defender == NFTDataTypes.ElementType.WIND) return 70;
        if (attacker == NFTDataTypes.ElementType.FIRE && defender == NFTDataTypes.ElementType.WATER) return 70;
        if (attacker == NFTDataTypes.ElementType.DARK && defender == NFTDataTypes.ElementType.LIGHT) return 70;
        if (attacker == NFTDataTypes.ElementType.LIGHT && defender == NFTDataTypes.ElementType.DARK) return 70;
        
        return 100;
    }

    uint8 constant ATTACK = 0;
    uint8 constant SPECIAL = 3;
    uint8 constant LIFESTEAL = 7;
    uint8 constant COUNTER = 6;

    function calculateHealth(uint256 level, uint256 growthValue) internal pure returns (uint256) {
        uint256 growthMultiplier = 900 + (growthValue * 6);
        return ((BASE_HEALTH + (level - 1) * 100) * growthMultiplier) / 1000;
    }

    function calculateSpeed(uint256 baseSpeed, uint256 growthValue) internal pure returns (uint256) {
        uint256 growthMultiplier = 950 + (growthValue * 25) / 10;
        return (baseSpeed * growthMultiplier) / 100;
    }

    function calculateDamage(uint256 baseDamage, NFTDataTypes.ElementType attackerElement, NFTDataTypes.ElementType defenderElement) 
        internal pure returns (uint256) {
        uint256 multiplier = _getElementMultiplier(attackerElement, defenderElement);
        return (baseDamage * multiplier) / 100;
    }

    function _applySkillEffect(uint8 skillType, uint256 skillValue, uint256 baseDamage) internal pure returns (uint256) {
        if (skillType == ATTACK || skillType == SPECIAL || 
            skillType == LIFESTEAL || skillType == COUNTER) {
            return (baseDamage * skillValue) / 100;
        }
        return baseDamage;
    }

    function _calculateDamage(NFTStatus memory attacker, NFTDataTypes.ElementType defenderElement, uint256 attackMult) internal pure returns (uint256, bytes32) {
        uint256 growthBonus = 1000 + (attacker.level * 5);
        uint256 baseDamage = (attacker.attackValue * attackMult * growthBonus) / 1000;
        uint256 totalDamage = calculateDamage(baseDamage, attacker.element, defenderElement);
        totalDamage = _applySkillEffect(attacker.skillType, attacker.skillValue, totalDamage);
        
        return (totalDamage, attacker.skillHash);
    }

    function _calculateDefenderHealth(NFTStatus memory defender, uint256 defenseMult) internal pure returns (uint256) {
        uint256 growthBonus = 1000 + (defender.level * 6);
        return (defender.defenseValue * defenseMult * growthBonus) / 1000 + BASE_HEALTH;
    }

    function calculateDodgeChance(uint256 randomMult) internal view returns (bool) {
        uint256 randomVal = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, msg.sender))) % 10000;
        return randomVal < randomMult * 100;
    }

    function getZodiacSpeed(uint256 zodiac) internal pure returns (uint256) {
        uint256[12] memory speeds = [uint256(95), uint256(40), uint256(70), uint256(90), uint256(80), uint256(85), uint256(100), uint256(35), uint256(110), uint256(55), uint256(60), uint256(30)];
        return speeds[zodiac];
    }

    function battleCore(NFTStatus[] memory nftStatus, uint256 attackMult, uint256 defenseMult, uint256 randomMult) internal view returns (SingleBattleResult memory) {
        NFTStatus memory attacker = nftStatus[0];
        NFTStatus memory defender = nftStatus[1];
        
        SingleBattleResult memory result;
        
        uint256 attackerSpeed = getZodiacSpeed(attacker.zodiac);
        uint256 defenderSpeed = getZodiacSpeed(defender.zodiac);
        
        (result.attackerDamage, result.attackerSkill) = _calculateDamage(attacker, defender.element, attackMult);
        (result.defenderDamage, result.defenderSkill) = _calculateDamage(defender, attacker.element, attackMult);
        
        uint256 defenderHealth = _calculateDefenderHealth(defender, defenseMult);
        uint256 attackerHealth = _calculateDefenderHealth(attacker, defenseMult);
        
        if (calculateDodgeChance(randomMult)) {
            if (attackerSpeed > defenderSpeed) {
                result.defenderDodged = true;
                result.attackerDamage = 0;
            } else {
                result.attackerDodged = true;
                result.defenderDamage = 0;
            }
        }
        
        if (!result.defenderDodged && result.attackerDamage >= defenderHealth) {
            result.attackerWon = true;
            result.defenderDamage = 0;
            result.defenderSkill = bytes32(0);
            return result;
        }
        
        if (!result.attackerDodged && result.defenderDamage >= attackerHealth) {
            result.attackerWon = false;
            result.attackerDamage = 0;
            result.attackerSkill = bytes32(0);
            return result;
        }
        
        result.attackerWon = result.attackerDamage >= defenderHealth;
        if (result.attackerWon) {
            result.defenderSkill = bytes32(0);
        }
        
        return result;
    }

    function battleCoreSimulate(NFTStatus[] memory nftStatus, uint256 attackMult, uint256 defenseMult, uint256 randomMult) internal view returns (SingleBattleResult memory) {
        return battleCore(nftStatus, attackMult, defenseMult, randomMult);
    }
}
