// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";
import "./BattleLib.sol";
import "./BattleSkills.sol";

contract BattleSkillData {
    mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) public fullSkills;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function initAllSkills() external onlyOwner {
        BattleSkills.initAllSkills(fullSkills);
    }

    function getSkillByIndexes(uint256 elementIndex, uint256 zodiacIndex, uint256 gender) external view returns (BattleLib.FullSkill memory) {
        return fullSkills[elementIndex][zodiacIndex][gender];
    }

    function getZodiacSpeed(uint256 zodiac) external pure returns (uint256) {
        uint256[12] memory speeds = [uint256(95), uint256(40), uint256(70), uint256(90), uint256(80), uint256(85), uint256(100), uint256(35), uint256(110), uint256(55), uint256(60), uint256(30)];
        return speeds[zodiac];
    }
}
