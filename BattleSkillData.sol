// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTDataType.sol";
import "./BattleLib.sol";
import "./BattleSkills.sol";

contract BattleSkillData is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) public fullSkills;

    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initAllSkills() external onlyOwner {
        BattleSkills.initAllSkills(fullSkills);
    }

    function getSkillByIndexes(uint256 elementIndex, uint256 zodiacIndex, uint256 gender) external view returns (BattleLib.FullSkill memory) {
        return fullSkills[elementIndex][zodiacIndex][gender];
    }

    /**
     * @dev 通过一维tokenType获取技能（与Battle.sol接口兼容）
     * @param tokenType 生肖类型 (0-119)
     * formula: tokenType = elementIndex * 24 + zodiacIndex * 2 + gender
     */
    function getSkill(uint256 tokenType) external view returns (BattleLib.FullSkill memory) {
        uint256 elementIndex = tokenType / 24;
        uint256 remainder = tokenType % 24;
        uint256 zodiacIndex = remainder / 2;
        uint256 gender = remainder % 2;
        return fullSkills[elementIndex][zodiacIndex][gender];
    }

    function getZodiacSpeed(uint256 zodiac) external pure returns (uint256) {
        uint256[12] memory speeds = [uint256(95), uint256(55), uint256(70), uint256(90), uint256(80), uint256(85), uint256(100), uint256(50), uint256(110), uint256(60), uint256(65), uint256(45)];
        return speeds[zodiac];
    }
}
