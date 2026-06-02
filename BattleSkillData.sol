// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTDataType.sol";
import "./BattleLib.sol";
import "./BattleSkills.sol";

/**
 * @title BattleSkillData
 * @dev 战斗技能数据合约，存储和管理所有NFT的战斗技能
 *
 * 技能数据结构：
 * - 三维映射: fullSkills[element][zodiac][gender] => FullSkill
 * - element: 属性类型 (0-4: 水、风、火、暗、光)
 * - zodiac: 生肖类型 (0-11: 鼠到猪)
 * - gender: 性别 (0-1: 母、公)
 *
 * 技能包含：ID、类型、伤害值、冷却时间、AOE标志
 */
contract BattleSkillData is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 技能数据映射
     * elementIndex (0-4) => zodiacIndex (0-11) => gender (0-1) => FullSkill
     */
    mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) public fullSkills;

    bool public skillsInitialized;

    /**
     * @dev 初始化函数
     */
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _initAllSkills();
    }

    /**
     * @dev UUPS升级授权
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 初始化所有属性的技能数据（内部）
     */
    function _initAllSkills() internal {
        BattleSkills.initAllSkills(fullSkills);
        skillsInitialized = true;
    }

    /**
     * @dev 重新初始化所有属性的技能数据（公开接口）
     * 调用BattleSkills库初始化水、风、火、暗、光五个属性的技能
     */
    function initAllSkills() external onlyOwner {
        _initAllSkills();
    }

    /**
     * @dev 通过属性、生肖、性别索引获取技能
     * @param elementIndex 属性索引 (0-4)
     * @param zodiacIndex 生肖索引 (0-11)
     * @param gender 性别 (0-1)
     * @return FullSkill 技能数据
     */
    function getSkillByIndexes(uint256 elementIndex, uint256 zodiacIndex, uint256 gender) external view returns (BattleLib.FullSkill memory) {
        return fullSkills[elementIndex][zodiacIndex][gender];
    }

    /**
     * @dev 通过一维tokenType获取技能（与Battle.sol接口兼容）
     * @param tokenType 生肖类型 (0-119)
     * formula: tokenType = elementIndex * 24 + zodiacIndex * 2 + gender
     * @return FullSkill 技能数据
     */
    function getSkill(uint256 tokenType) external view returns (BattleLib.FullSkill memory) {
        uint256 elementIndex = tokenType / 24;
        uint256 remainder = tokenType % 24;
        uint256 zodiacIndex = remainder / 2;
        uint256 gender = remainder % 2;
        return fullSkills[elementIndex][zodiacIndex][gender];
    }

    /**
     * @dev 获取生肖基础速度
     * @param zodiac 生肖索引 (0-11)
     * @return uint256 基础速度值
     */
    function getZodiacSpeed(uint256 zodiac) external pure returns (uint256) {
        uint256[12] memory speeds = [
            uint256(95),   // RAT (0) - 鼠
            uint256(55),   // OX (1) - 牛
            uint256(70),   // TIGER (2) - 虎
            uint256(90),   // RABBIT (3) - 兔
            uint256(80),   // DRAGON (4) - 龙
            uint256(85),   // SNAKE (5) - 蛇
            uint256(100),  // HORSE (6) - 马
            uint256(50),   // GOAT (7) - 羊
            uint256(110),  // MONKEY (8) - 猴
            uint256(60),   // ROOSTER (9) - 鸡
            uint256(65),   // DOG (10) - 狗
            uint256(45)    // PIG (11) - 猪
        ];
        return speeds[zodiac];
    }
}
