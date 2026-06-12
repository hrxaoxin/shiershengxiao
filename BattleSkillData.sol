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
 * 核心职责：
 * 1. 技能数据存储：为每种 zodiacType（共 120 种）存储对应的技能配置
 * 2. 技能初始化：部署时通过 initAllSkills() 从 BattleSkills 库初始化所有默认技能
 * 3. 技能查询：为 Battle 合约提供 getSkill(tokenType) 接口读取技能
 *
 * 技能数据结构（基于 BattleLib.FullSkill）：
 * - 每个 zodiacType 对应一套完整技能（普攻 + 3 个技能 + 终极技）
 * - 属性影响技能伤害（火→高爆发、水→控制、风→速攻、暗→吸血、光→治疗）
 * - 等级影响技能强度（升级时由 Battle 合约读取伤害倍率加成）
 *
 * 三维映射存储（为了减少索引开销，使用两层嵌套 mapping）：
 *   fullSkills[elementIndex][zodiacIndex][genderIndex] = FullSkill
 * - elementIndex: 0=水, 1=风, 2=火, 3=暗, 4=光
 * - zodiacIndex: 0-11 (鼠到猪)
 * - genderIndex: 0=母, 1=公
 *
 * 也可以直接使用一维 tokenType（0-119）查询：
 *   getSkill(tokenType) = fullSkills[tokenType/24][(tokenType%24)/2][tokenType%2]
 *
 * 初始化流程（两步确认，防止恶意注入）：
 * 1. 部署时调用 initialize() → skillsInitializationPending = true
 * 2. owner 调用 confirmSkillInitialization() → 执行 _initAllSkills()，
 *    调用 BattleSkills.initAllSkills(fullSkills) 填充 120 种类型技能
 *    → skillsInitializationPending = false, skillsInitialized = true
 * 3. owner 可调用 initAllSkills() 再次覆盖（更新技能平衡）
 *
 * 访问权限：
 * - onlyOwner：可调用 initAllSkills 重新初始化或更新技能
 * - 任何地址：可公开 view 读取 getSkill / getSkillByIndexes（只读查询免费）
 *
 * 与其他合约联动：
 * - Battle.sol：战斗时读取技能配置，计算伤害、冷却、触发效果
 * - BattleSkills.sol：技能初始化逻辑（library，无状态）
 * - NFTMint / NFTData：根据 zodiacType 获取对应 NFT 的技能信息在前端展示
 *
 * 升级与治理：
 * - UUPS 可升级：未来可扩展新技能类型、调整伤害公式、增加被动技能
 * - owner 可重新初始化技能以做平衡性调整（nerf/buff）
 *
 * 注意：本合约不直接参与战斗结算，仅提供只读数据，战斗逻辑由 Battle 合约负责。
 */
contract BattleSkillData is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 技能数据映射
     * elementIndex (0-4) => zodiacIndex (0-11) => gender (0-1) => FullSkill
     */
    mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleLib.FullSkill))) public fullSkills;

    bool public skillsInitialized;

    bool public skillsInitializationPending;

    /**
     * @dev 修饰器：仅所有者或授权器可调用
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "BattleSkillData: Not owner or authorizer");
        _;
    }

    /**
     * @dev 初始化函数（仅部署时调用一次）
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        require(_authorizer != address(0), "BattleSkillData: Invalid authorizer address");
        authorizer = _authorizer;
        skillsInitializationPending = true;
    }

    /**
     * @dev 确认并执行技能初始化
     * 两步初始化机制：部署后owner需手动确认初始化
     */
    function confirmSkillInitialization() external onlyOwner {
        require(skillsInitializationPending, "BattleSkillData: No pending initialization");
        _initAllSkills();
        skillsInitializationPending = false;
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
        require(skillsInitialized, "BattleSkillData: Skills not initialized yet");
        _initAllSkills();
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 新的授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "BattleSkillData: Invalid authorizer address");
        authorizer = _authorizer;
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
     * @dev 获取生肖基础速度（与NFTLib.BASE_SPEED保持一致）
     * @param zodiac 生肖索引 (0-11)
     * @return uint256 基础速度值
     */
    function getZodiacSpeed(uint256 zodiac) external pure returns (uint256) {
        uint256[12] memory speeds = [
            uint256(95),   // RAT (0) - 鼠
            uint256(40),   // OX (1) - 牛
            uint256(70),   // TIGER (2) - 虎
            uint256(90),   // RABBIT (3) - 兔
            uint256(80),   // DRAGON (4) - 龙
            uint256(85),   // SNAKE (5) - 蛇
            uint256(100),  // HORSE (6) - 马
            uint256(35),   // GOAT (7) - 羊
            uint256(110),  // MONKEY (8) - 猴
            uint256(55),   // ROOSTER (9) - 鸡
            uint256(60),   // DOG (10) - 狗
            uint256(30)    // PIG (11) - 猪
        ];
        return speeds[zodiac];
    }
}
