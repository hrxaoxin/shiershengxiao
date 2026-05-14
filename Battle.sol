// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title Battle
 * @author Trae
 * @notice 战斗合约 - 实现6v6 NFT团队对战系统
 * @dev 支持五行相克、技能系统、闪避机制，包含120种独特技能（5属性×12生肖×2性别）
 */
contract Battle is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    INFTMint public nftContract;
    address public authorizer;
    
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant FRONT_ROW_SIZE = 3;
    
    enum Element { Fire, Wind, Water, Light, Dark }
    
    enum SkillType { 
        Attack,    // 攻击型技能
        Defense,   // 防御型技能
        Heal,      // 治疗型技能
        Special,   // 特殊技能（范围攻击）
        Buff,      // 增益型技能
        Debuff,    // 减益型技能
        Counter,   // 反击型技能
        Lifesteal, // 吸血型技能
        Shield     // 护盾型技能
    }
    
    struct FullSkill {
        string name;           // 技能名称
        SkillType skillType;   // 技能类型
        uint256 value;         // 技能数值（百分比）
        uint256 cooldown;      // 冷却回合数
        uint256 duration;      // 效果持续回合数
        bool isAoe;            // 是否为范围攻击
    }
    
    struct BattleResult {
        address attacker;        // 攻击方地址
        address defender;        // 防守方地址
        uint256 attackerWinCount;// 攻击方获胜场次
        uint256 defenderWinCount;// 防守方获胜场次
        uint256 timestamp;       // 战斗时间戳
        BattleRoundResult[] roundResults; // 每回合详细结果
    }
    
    struct BattleRoundResult {
        uint256 attackerTokenId; // 攻击方NFT ID
        uint256 defenderTokenId; // 防守方NFT ID
        bool attackerWon;        // 攻击方是否获胜
        uint256 attackerDamage;  // 攻击方造成伤害
        uint256 defenderDamage;  // 防守方造成伤害
        string attackerSkill;    // 攻击方使用技能
        string defenderSkill;    // 防守方使用技能
        bool attackerDodged;     // 攻击方是否闪避
        bool defenderDodged;     // 防守方是否闪避
    }
    
    struct NFTStatus {
        uint256 currentHealth; // 当前生命值
        uint256 maxHealth;     // 最大生命值
        uint256 level;         // NFT等级
        uint256 tokenId;       // NFT ID
        Element element;       // 属性（五行）
        uint256 zodiac;        // 生肖索引（0-11）
        uint256 gender;        // 性别（0=雄，1=雌）
        bool isFrontRow;       // 是否在前排
        bool isAlive;          // 是否存活
        uint256 speed;         // 速度值
    }
    
    mapping(uint256 => mapping(uint256 => mapping(uint256 => FullSkill))) public fullSkills;
    mapping(uint256 => uint256) public zodiacSpeed;
    mapping(uint256 => BattleResult) public battleHistory;
    
    uint256 public nextBattleId;
    uint256 public baseHealth;
    uint256 public dodgeBaseChance = 1500;
    
    event BattleCompleted(
        address indexed attacker,
        address indexed defender,
        bool attackerWon,
        uint256 attackerWinCount,
        uint256 defenderWinCount
    );

    event RoundCompleted(
        uint256 indexed battleId,
        uint256 attackerTokenId,
        uint256 defenderTokenId,
        bool attackerWon
    );
    
    /**
     * @notice 初始化合约
     * @param _nftContract NFT主合约地址
     */
    function initialize(address _nftContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        nftContract = INFTMint(_nftContract);
        nextBattleId = 1;
        baseHealth = 400;
        
        _initAllSkills();
        _initZodiacSpeed();
    }
    
    /**
     * @notice 授权升级（UUPS模式）
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @notice 初始化所有技能（内部函数）
     */
    function _initAllSkills() internal {
        _initFireSkills();
        _initWindSkills();
        _initWaterSkills();
        _initLightSkills();
        _initDarkSkills();
    }
    
    /**
     * @notice 初始化火属性技能（内部函数）
     * @dev 火属性技能偏向攻击，伤害较高，克制风属性，被水属性克制
     * 技能数组结构: fullSkills[elementIndex][zodiacIndex][skillIndex]
     * 元素索引: 0=火, 1=风, 2=水, 3=光, 4=暗
     * 生肖索引: 0=鼠, 1=牛, 2=虎, 3=兔, 4=龙, 5=蛇, 6=马, 7=羊
     * 技能索引: 0=主动技能, 1=被动技能
     * 技能类型: Attack=攻击, Counter=反击, Shield=护盾, Debuff=减益, Defense=防御
     *          Special=必杀, Lifesteal=吸血, Buff=增益, Heal=治疗
     * 数值参数: [伤害/效果值, 冷却回合, 持续回合, 是否需蓄力]
     */
    function _initFireSkills() internal {
        fullSkills[0][0][0] = FullSkill("烈焰穿梭", SkillType.Attack, 125, 3, 0, false);
        fullSkills[0][0][1] = FullSkill("炎影反击", SkillType.Counter, 110, 4, 0, false);
        fullSkills[0][1][0] = FullSkill("焚天巨力", SkillType.Attack, 145, 5, 0, false);
        fullSkills[0][1][1] = FullSkill("炽焰守护", SkillType.Shield, 95, 4, 2, false);
        fullSkills[0][2][0] = FullSkill("爆炎猛击", SkillType.Attack, 165, 5, 0, false);
        fullSkills[0][2][1] = FullSkill("烈焰威慑", SkillType.Debuff, 85, 4, 2, false);
        fullSkills[0][3][0] = FullSkill("疾风烈焰", SkillType.Attack, 130, 3, 0, false);
        fullSkills[0][3][1] = FullSkill("火焰跃闪", SkillType.Defense, 80, 3, 0, false);
        fullSkills[0][4][0] = FullSkill("龙焰焚天", SkillType.Special, 220, 6, 0, true);
        fullSkills[0][4][1] = FullSkill("炎龙守护", SkillType.Shield, 120, 5, 2, false);
        fullSkills[0][5][0] = FullSkill("火毒噬咬", SkillType.Lifesteal, 115, 4, 0, false);
        fullSkills[0][5][1] = FullSkill("烈焰反击", SkillType.Counter, 125, 4, 0, false);
        fullSkills[0][6][0] = FullSkill("燎原奔踏", SkillType.Attack, 140, 3, 0, false);
        fullSkills[0][6][1] = FullSkill("火云疾驰", SkillType.Buff, 85, 4, 2, false);
        fullSkills[0][7][0] = FullSkill("圣火治愈", SkillType.Heal, 110, 5, 0, false);
        fullSkills[0][7][1] = FullSkill("烈焰祈福", SkillType.Heal, 130, 6, 0, false);
        fullSkills[0][8][0] = FullSkill("火舞戏耍", SkillType.Attack, 115, 2, 0, false);
        fullSkills[0][8][1] = FullSkill("赤炎变幻", SkillType.Defense, 90, 3, 0, false);
        fullSkills[0][9][0] = FullSkill("火羽锐击", SkillType.Attack, 105, 3, 0, false);
        fullSkills[0][9][1] = FullSkill("烈焰警戒", SkillType.Buff, 75, 3, 2, false);
        fullSkills[0][10][0] = FullSkill("火獒追击", SkillType.Attack, 120, 4, 0, false);
        fullSkills[0][10][1] = FullSkill("炎犬反击", SkillType.Counter, 115, 4, 0, false);
        fullSkills[0][11][0] = FullSkill("火猪纳福", SkillType.Heal, 140, 6, 0, false);
        fullSkills[0][11][1] = FullSkill("烈焰厚积", SkillType.Defense, 100, 5, 0, false);
    }
    
    /**
     * @notice 初始化风属性技能（内部函数）
     * @dev 风属性技能速度快，闪避能力强，克制水属性，被火属性克制
     * 技能数组结构: fullSkills[elementIndex][zodiacIndex][skillIndex]
     * 元素索引: 0=火, 1=风, 2=水, 3=光, 4=暗
     * 生肖索引: 0=鼠, 1=牛, 2=虎, 3=兔, 4=龙, 5=蛇, 6=马, 7=羊
     * 技能索引: 0=主动技能, 1=被动技能
     * 风属性特点: 攻击速度快，冷却时间短，闪避率高
     */
    function _initWindSkills() internal {
        fullSkills[1][0][0] = FullSkill("疾风穿梭", SkillType.Attack, 135, 3, 0, false);
        fullSkills[1][0][1] = FullSkill("风影反击", SkillType.Counter, 115, 4, 0, false);
        fullSkills[1][1][0] = FullSkill("旋风巨力", SkillType.Attack, 130, 5, 0, false);
        fullSkills[1][1][1] = FullSkill("风之壁垒", SkillType.Shield, 105, 4, 2, false);
        fullSkills[1][2][0] = FullSkill("暴风猛击", SkillType.Attack, 155, 5, 0, false);
        fullSkills[1][2][1] = FullSkill("风啸威慑", SkillType.Debuff, 90, 4, 2, false);
        fullSkills[1][3][0] = FullSkill("风跃突袭", SkillType.Attack, 140, 3, 0, false);
        fullSkills[1][3][1] = FullSkill("疾风闪避", SkillType.Defense, 100, 3, 0, false);
        fullSkills[1][4][0] = FullSkill("风暴龙吟", SkillType.Special, 210, 6, 0, true);
        fullSkills[1][4][1] = FullSkill("风龙护盾", SkillType.Shield, 115, 5, 2, false);
        fullSkills[1][5][0] = FullSkill("风刃穿刺", SkillType.Attack, 125, 4, 0, false);
        fullSkills[1][5][1] = FullSkill("旋风反击", SkillType.Counter, 120, 4, 0, false);
        fullSkills[1][6][0] = FullSkill("追风踏燕", SkillType.Attack, 150, 3, 0, false);
        fullSkills[1][6][1] = FullSkill("风驰电掣", SkillType.Buff, 90, 3, 2, false);
        fullSkills[1][7][0] = FullSkill("清风治愈", SkillType.Heal, 105, 5, 0, false);
        fullSkills[1][7][1] = FullSkill("风之祈福", SkillType.Heal, 120, 6, 0, false);
        fullSkills[1][8][0] = FullSkill("风猴戏耍", SkillType.Attack, 120, 2, 0, false);
        fullSkills[1][8][1] = FullSkill("疾风变幻", SkillType.Defense, 95, 3, 0, false);
        fullSkills[1][9][0] = FullSkill("风羽振翅", SkillType.Attack, 110, 3, 0, false);
        fullSkills[1][9][1] = FullSkill("风之警戒", SkillType.Buff, 80, 3, 2, false);
        fullSkills[1][10][0] = FullSkill("风犬追击", SkillType.Attack, 125, 4, 0, false);
        fullSkills[1][10][1] = FullSkill("疾风反击", SkillType.Counter, 110, 4, 0, false);
        fullSkills[1][11][0] = FullSkill("风猪纳福", SkillType.Heal, 130, 6, 0, false);
        fullSkills[1][11][1] = FullSkill("风之厚积", SkillType.Defense, 95, 5, 0, false);
    }
    
    /**
     * @notice 初始化水属性技能（内部函数）
     * @dev 水属性技能平衡型，治疗能力较强，克制火属性，被风属性克制
     * 技能数组结构: fullSkills[elementIndex][zodiacIndex][skillIndex]
     * 元素索引: 0=火, 1=风, 2=水, 3=光, 4=暗
     * 生肖索引: 0=鼠, 1=牛, 2=虎, 3=兔, 4=龙, 5=蛇, 6=马, 7=羊
     * 技能索引: 0=主动技能, 1=被动技能
     * 水属性特点: 攻防平衡，治疗能力突出，护盾持续时间长
     */
    function _initWaterSkills() internal {
        fullSkills[2][0][0] = FullSkill("潮涌穿梭", SkillType.Attack, 120, 3, 0, false);
        fullSkills[2][0][1] = FullSkill("水影反击", SkillType.Counter, 105, 4, 0, false);
        fullSkills[2][1][0] = FullSkill("巨浪冲击", SkillType.Attack, 140, 5, 0, false);
        fullSkills[2][1][1] = FullSkill("水之磐石", SkillType.Shield, 110, 4, 2, false);
        fullSkills[2][2][0] = FullSkill("海啸猛击", SkillType.Attack, 160, 5, 0, false);
        fullSkills[2][2][1] = FullSkill("寒水威慑", SkillType.Debuff, 85, 4, 2, false);
        fullSkills[2][3][0] = FullSkill("水跃突袭", SkillType.Attack, 135, 3, 0, false);
        fullSkills[2][3][1] = FullSkill("碧水闪避", SkillType.Defense, 95, 3, 0, false);
        fullSkills[2][4][0] = FullSkill("海啸龙吟", SkillType.Special, 200, 6, 0, true);
        fullSkills[2][4][1] = FullSkill("水龙护盾", SkillType.Shield, 110, 5, 2, false);
        fullSkills[2][5][0] = FullSkill("毒水噬咬", SkillType.Lifesteal, 120, 4, 0, false);
        fullSkills[2][5][1] = FullSkill("寒水反击", SkillType.Counter, 115, 4, 0, false);
        fullSkills[2][6][0] = FullSkill("踏浪奔腾", SkillType.Attack, 145, 3, 0, false);
        fullSkills[2][6][1] = FullSkill("水之疾驰", SkillType.Buff, 85, 3, 2, false);
        fullSkills[2][7][0] = FullSkill("净水治愈", SkillType.Heal, 115, 5, 0, false);
        fullSkills[2][7][1] = FullSkill("水之祈福", SkillType.Heal, 135, 6, 0, false);
        fullSkills[2][8][0] = FullSkill("水猴戏耍", SkillType.Attack, 115, 2, 0, false);
        fullSkills[2][8][1] = FullSkill("碧水变幻", SkillType.Defense, 90, 3, 0, false);
        fullSkills[2][9][0] = FullSkill("水羽振翅", SkillType.Attack, 105, 3, 0, false);
        fullSkills[2][9][1] = FullSkill("水之警戒", SkillType.Buff, 75, 3, 2, false);
        fullSkills[2][10][0] = FullSkill("水犬追击", SkillType.Attack, 115, 4, 0, false);
        fullSkills[2][10][1] = FullSkill("碧水反击", SkillType.Counter, 100, 4, 0, false);
        fullSkills[2][11][0] = FullSkill("水猪纳福", SkillType.Heal, 145, 6, 0, false);
        fullSkills[2][11][1] = FullSkill("水之厚积", SkillType.Defense, 105, 5, 0, false);
    }
    
    /**
     * @notice 初始化光属性技能（内部函数）
     * @dev 光属性技能防御最强，护盾值最高，克制暗属性，被暗属性克制（光暗互克）
     * 技能数组结构: fullSkills[elementIndex][zodiacIndex][skillIndex]
     * 元素索引: 0=火, 1=风, 2=水, 3=光, 4=暗
     * 生肖索引: 0=鼠, 1=牛, 2=虎, 3=兔, 4=龙, 5=蛇, 6=马, 7=羊
     * 技能索引: 0=主动技能, 1=被动技能
     * 光属性特点: 稀有属性，防御最强，治疗效果最高，护盾值最大
     */
    function _initLightSkills() internal {
        fullSkills[3][0][0] = FullSkill("圣光穿梭", SkillType.Attack, 145, 3, 0, false);
        fullSkills[3][0][1] = FullSkill("光影反击", SkillType.Counter, 135, 4, 0, false);
        fullSkills[3][1][0] = FullSkill("光耀巨力", SkillType.Attack, 150, 5, 0, false);
        fullSkills[3][1][1] = FullSkill("光之壁垒", SkillType.Shield, 115, 4, 2, false);
        fullSkills[3][2][0] = FullSkill("圣光猛击", SkillType.Attack, 165, 5, 0, false);
        fullSkills[3][2][1] = FullSkill("光明威慑", SkillType.Debuff, 90, 4, 2, false);
        fullSkills[3][3][0] = FullSkill("光跃突袭", SkillType.Attack, 145, 3, 0, false);
        fullSkills[3][3][1] = FullSkill("圣光闪避", SkillType.Defense, 110, 3, 0, false);
        fullSkills[3][4][0] = FullSkill("圣光龙吟", SkillType.Special, 245, 6, 0, true);
        fullSkills[3][4][1] = FullSkill("光龙护盾", SkillType.Shield, 140, 5, 2, false);
        fullSkills[3][5][0] = FullSkill("光刃穿刺", SkillType.Attack, 135, 4, 0, false);
        fullSkills[3][5][1] = FullSkill("圣光反击", SkillType.Counter, 140, 4, 0, false);
        fullSkills[3][6][0] = FullSkill("踏光而行", SkillType.Attack, 160, 3, 0, false);
        fullSkills[3][6][1] = FullSkill("光明疾驰", SkillType.Buff, 100, 3, 2, false);
        fullSkills[3][7][0] = FullSkill("圣光治愈", SkillType.Heal, 140, 5, 0, false);
        fullSkills[3][7][1] = FullSkill("光之祈福", SkillType.Heal, 160, 6, 0, false);
        fullSkills[3][8][0] = FullSkill("灵猴戏耍", SkillType.Attack, 140, 2, 0, false);
        fullSkills[3][8][1] = FullSkill("圣光变幻", SkillType.Defense, 115, 3, 0, false);
        fullSkills[3][9][0] = FullSkill("光羽振翅", SkillType.Attack, 130, 3, 0, false);
        fullSkills[3][9][1] = FullSkill("光之警戒", SkillType.Buff, 95, 3, 2, false);
        fullSkills[3][10][0] = FullSkill("圣犬追击", SkillType.Attack, 145, 4, 0, false);
        fullSkills[3][10][1] = FullSkill("圣光反击", SkillType.Counter, 130, 4, 0, false);
        fullSkills[3][11][0] = FullSkill("圣猪纳福", SkillType.Heal, 165, 6, 0, false);
        fullSkills[3][11][1] = FullSkill("光之厚积", SkillType.Defense, 115, 5, 0, false);
    }
    
    /**
     * @notice 初始化暗属性技能（内部函数）
     * @dev 暗属性技能吸血能力最强，爆发最高，克制光属性，被光属性克制（光暗互克）
     * 技能数组结构: fullSkills[elementIndex][zodiacIndex][skillIndex]
     * 元素索引: 0=火, 1=风, 2=水, 3=光, 4=暗
     * 生肖索引: 0=鼠, 1=牛, 2=虎, 3=兔, 4=龙, 5=蛇, 6=马, 7=羊
     * 技能索引: 0=主动技能, 1=被动技能
     * 暗属性特点: 稀有属性，攻击力最高，吸血能力强，爆发伤害突出
     */
    function _initDarkSkills() internal {
        fullSkills[4][0][0] = FullSkill("暗影穿梭", SkillType.Attack, 150, 3, 0, false);
        fullSkills[4][0][1] = FullSkill("幽冥反击", SkillType.Counter, 140, 4, 0, false);
        fullSkills[4][1][0] = FullSkill("暗影重击", SkillType.Attack, 155, 5, 0, false);
        fullSkills[4][1][1] = FullSkill("冥之壁垒", SkillType.Shield, 110, 4, 2, false);
        fullSkills[4][2][0] = FullSkill("暗影猛击", SkillType.Attack, 170, 5, 0, false);
        fullSkills[4][2][1] = FullSkill("幽冥威慑", SkillType.Debuff, 100, 4, 2, false);
        fullSkills[4][3][0] = FullSkill("暗跃突袭", SkillType.Attack, 155, 3, 0, false);
        fullSkills[4][3][1] = FullSkill("暗影闪避", SkillType.Defense, 115, 3, 0, false);
        fullSkills[4][4][0] = FullSkill("暗影龙吟", SkillType.Special, 255, 6, 0, true);
        fullSkills[4][4][1] = FullSkill("暗龙护盾", SkillType.Shield, 130, 5, 2, false);
        fullSkills[4][5][0] = FullSkill("暗影吞噬", SkillType.Lifesteal, 145, 4, 0, false);
        fullSkills[4][5][1] = FullSkill("幽冥反击", SkillType.Counter, 145, 4, 0, false);
        fullSkills[4][6][0] = FullSkill("踏冥奔腾", SkillType.Attack, 165, 3, 0, false);
        fullSkills[4][6][1] = FullSkill("暗影疾驰", SkillType.Buff, 105, 3, 2, false);
        fullSkills[4][7][0] = FullSkill("暗影治愈", SkillType.Heal, 125, 5, 0, false);
        fullSkills[4][7][1] = FullSkill("冥之祈福", SkillType.Heal, 140, 6, 0, false);
        fullSkills[4][8][0] = FullSkill("冥猴戏耍", SkillType.Attack, 135, 2, 0, false);
        fullSkills[4][8][1] = FullSkill("暗影变幻", SkillType.Defense, 110, 3, 0, false);
        fullSkills[4][9][0] = FullSkill("暗羽振翅", SkillType.Attack, 125, 3, 0, false);
        fullSkills[4][9][1] = FullSkill("冥之警戒", SkillType.Buff, 95, 3, 2, false);
        fullSkills[4][10][0] = FullSkill("冥犬追击", SkillType.Attack, 150, 4, 0, false);
        fullSkills[4][10][1] = FullSkill("暗影反击", SkillType.Counter, 135, 4, 0, false);
        fullSkills[4][11][0] = FullSkill("冥猪纳福", SkillType.Heal, 150, 6, 0, false);
        fullSkills[4][11][1] = FullSkill("冥之厚积", SkillType.Defense, 110, 5, 0, false);
    }
    
    /**
     * @notice 初始化生肖速度值（内部函数）
     * @dev 猴(110) > 马(100) > 鼠(95) > 兔(90) > 蛇(85) > 龙(80) > 虎(70) > 狗(60) > 鸡(55) > 牛(40) > 羊(35) > 猪(30)
     */
    function _initZodiacSpeed() internal {
        zodiacSpeed[0] = 95;
        zodiacSpeed[1] = 40;
        zodiacSpeed[2] = 70;
        zodiacSpeed[3] = 90;
        zodiacSpeed[4] = 80;
        zodiacSpeed[5] = 85;
        zodiacSpeed[6] = 100;
        zodiacSpeed[7] = 35;
        zodiacSpeed[8] = 110;
        zodiacSpeed[9] = 55;
        zodiacSpeed[10] = 60;
        zodiacSpeed[11] = 30;
    }
    
    /**
     * @notice 根据tokenType获取属性（五行）
     * @param tokenType NFT类型编码
     * @return Element 属性枚举值
     */
    function getElementFromTokenType(uint256 tokenType) public pure returns (Element) {
        uint256 attrIndex = tokenType / 24;
        if (attrIndex == 0) return Element.Water;
        if (attrIndex == 1) return Element.Wind;
        if (attrIndex == 2) return Element.Fire;
        if (attrIndex == 3) return Element.Dark;
        return Element.Light;
    }
    
    /**
     * @notice 根据tokenType获取生肖索引
     * @param tokenType NFT类型编码
     * @return 生肖索引（0-11，对应鼠到猪）
     */
    function getZodiacIndex(uint256 tokenType) public pure returns (uint256) {
        return (tokenType % 24) / 2;
    }
    
    /**
     * @notice 根据tokenType获取性别
     * @param tokenType NFT类型编码
     * @return 性别（0=雄，1=雌）
     */
    function getGender(uint256 tokenType) public pure returns (uint256) {
        return tokenType % 2;
    }
    
    /**
     * @notice 获取指定NFT类型的技能
     * @param tokenType NFT类型编码
     * @return FullSkill 技能详情
     */
    function getSkill(uint256 tokenType) public view returns (FullSkill memory) {
        uint256 element = uint256(getElementFromTokenType(tokenType));
        uint256 zodiac = getZodiacIndex(tokenType);
        uint256 gender = getGender(tokenType);
        return fullSkills[element][zodiac][gender];
    }
    
    /**
     * @notice 执行6v6团队战斗
     * @param attackerTokens 攻击方NFT ID数组（必须6个）
     * @param defenderTokens 防守方NFT ID数组（必须6个）
     * @return 攻击方是否获胜、攻击方获胜场次、防守方获胜场次
     */
    function battle(uint256[] calldata attackerTokens, uint256[] calldata defenderTokens) 
        external nonReentrant returns (bool, uint256, uint256) {
        
        require(attackerTokens.length == TEAM_SIZE, "E01: Attacker must have 6 NFTs");
        require(defenderTokens.length == TEAM_SIZE, "E02: Defender must have 6 NFTs");
        
        INFTMint nft = INFTMint(nftContract);
        
        NFTStatus[] memory attackerTeam = new NFTStatus[](TEAM_SIZE);
        NFTStatus[] memory defenderTeam = new NFTStatus[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 attackerType, uint8 attackerLevel) = _getTokenInfo(attackerTokens[i]);
            (uint256 defenderType, uint8 defenderLevel) = _getTokenInfo(defenderTokens[i]);
            
            attackerTeam[i] = NFTStatus({
                currentHealth: calculateHealth(attackerLevel),
                maxHealth: calculateHealth(attackerLevel),
                level: attackerLevel,
                tokenId: attackerTokens[i],
                element: getElementFromTokenType(attackerType),
                zodiac: getZodiacIndex(attackerType),
                gender: getGender(attackerType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[getZodiacIndex(attackerType)]
            });
            
            defenderTeam[i] = NFTStatus({
                currentHealth: calculateHealth(defenderLevel),
                maxHealth: calculateHealth(defenderLevel),
                level: defenderLevel,
                tokenId: defenderTokens[i],
                element: getElementFromTokenType(defenderType),
                zodiac: getZodiacIndex(defenderType),
                gender: getGender(defenderType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[getZodiacIndex(defenderType)]
            });
        }
        
        uint256 attackerWins = 0;
        uint256 defenderWins = 0;
        BattleRoundResult[] memory roundResults = new BattleRoundResult[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (!attackerTeam[i].isAlive) continue;
            
            uint256 targetIndex = _findTarget(defenderTeam, attackerTeam[i].isFrontRow);
            if (targetIndex == type(uint256).max) continue;
            
            bool attackerFirst = attackerTeam[i].speed >= defenderTeam[targetIndex].speed;
            
            (bool attackerWon, uint256 atkDmg, uint256 defDmg, string memory atkSkill, string memory defSkill, bool atkDodged, bool defDodged) = 
                _singleBattle(attackerTeam[i], defenderTeam[targetIndex], attackerFirst);
            
            roundResults[i] = BattleRoundResult({
                attackerTokenId: attackerTeam[i].tokenId,
                defenderTokenId: defenderTeam[targetIndex].tokenId,
                attackerWon: attackerWon,
                attackerDamage: atkDmg,
                defenderDamage: defDmg,
                attackerSkill: atkSkill,
                defenderSkill: defSkill,
                attackerDodged: atkDodged,
                defenderDodged: defDodged
            });
            
            if (attackerWon) {
                attackerWins++;
                defenderTeam[targetIndex].isAlive = false;
            } else {
                defenderWins++;
                attackerTeam[i].isAlive = false;
            }
        }
        
        bool attackerTeamWon = attackerWins > defenderWins;
        
        BattleResult storage result = battleHistory[nextBattleId];
        result.attacker = msg.sender;
        result.defender = tx.origin;
        result.attackerWinCount = attackerWins;
        result.defenderWinCount = defenderWins;
        result.timestamp = block.timestamp;
        result.roundResults = roundResults;
        
        nextBattleId++;
        
        emit BattleCompleted(msg.sender, tx.origin, attackerTeamWon, attackerWins, defenderWins);
        
        return (attackerTeamWon, attackerWins, defenderWins);
    }
    
    /**
     * @notice 查找目标NFT（内部函数）
     * @dev 优先查找同排存活目标，若无则查找任意存活目标
     * @param team 目标团队
     * @param attackerFrontRow 攻击者是否在前排
     * @return 目标索引（若无则返回uint256最大值）
     */
    function _findTarget(NFTStatus[] memory team, bool attackerFrontRow) internal pure returns (uint256) {
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (team[i].isAlive && team[i].isFrontRow == attackerFrontRow) {
                return i;
            }
        }
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (team[i].isAlive) {
                return i;
            }
        }
        
        return type(uint256).max;
    }
    
    /**
     * @notice 执行单体战斗（内部函数）
     * @param attacker 攻击者状态
     * @param defender 防守者状态
     * @param attackerFirst 攻击者是否先手
     * @return 攻击者是否获胜、攻击者伤害、防守者伤害、攻击者技能名、防守者技能名、攻击者是否闪避、防守者是否闪避
     */
    function _singleBattle(NFTStatus memory attacker, NFTStatus memory defender, bool attackerFirst) 
        internal view returns (bool, uint256, uint256, string memory, string memory, bool, bool) {
        
        FullSkill memory attackerSkill = fullSkills[uint256(attacker.element)][attacker.zodiac][attacker.gender];
        FullSkill memory defenderSkill = fullSkills[uint256(defender.element)][defender.zodiac][defender.gender];
        
        bool attackerDodged = false;
        bool defenderDodged = false;
        
        uint256 attackerBaseDamage = attacker.level * 60;
        uint256 defenderBaseDamage = defender.level * 60;
        
        uint256 attackerTotalDamage = calculateDamage(attackerBaseDamage, attacker.element, defender.element);
        uint256 defenderTotalDamage = calculateDamage(defenderBaseDamage, defender.element, attacker.element);
        
        attackerTotalDamage = _applySkillEffect(attackerSkill, attackerTotalDamage);
        defenderTotalDamage = _applySkillEffect(defenderSkill, defenderTotalDamage);
        
        string memory attackerSkillName = attackerSkill.name;
        string memory defenderSkillName = defenderSkill.name;
        
        if (attackerFirst) {
            if (calculateDodgeChance(attacker.speed, defender.speed)) {
                defenderDodged = true;
                attackerTotalDamage = 0;
            }
            
            if (!defenderDodged && attackerTotalDamage >= defender.currentHealth) {
                return (true, attackerTotalDamage, 0, attackerSkillName, "", defenderDodged, false);
            }
            
            if (calculateDodgeChance(defender.speed, attacker.speed)) {
                attackerDodged = true;
                defenderTotalDamage = 0;
            }
        } else {
            if (calculateDodgeChance(defender.speed, attacker.speed)) {
                attackerDodged = true;
                defenderTotalDamage = 0;
            }
            
            if (!attackerDodged && defenderTotalDamage >= attacker.currentHealth) {
                return (false, 0, defenderTotalDamage, "", defenderSkillName, false, attackerDodged);
            }
            
            if (calculateDodgeChance(attacker.speed, defender.speed)) {
                defenderDodged = true;
                attackerTotalDamage = 0;
            }
        }
        
        bool attackerWon = attackerTotalDamage >= defender.currentHealth && defenderTotalDamage < attacker.currentHealth;
        
        return (attackerWon, attackerTotalDamage, defenderTotalDamage, attackerSkillName, attackerWon ? "" : defenderSkillName, attackerDodged, defenderDodged);
    }
    
    /**
     * @notice 应用技能效果（内部函数）
     * @param skill 技能
     * @param baseDamage 基础伤害
     * @return 应用技能后的伤害值
     */
    function _applySkillEffect(FullSkill memory skill, uint256 baseDamage) internal pure returns (uint256) {
        if (skill.skillType == SkillType.Attack || skill.skillType == SkillType.Special) {
            return (baseDamage * skill.value) / 100;
        } else if (skill.skillType == SkillType.Lifesteal) {
            return (baseDamage * skill.value) / 100;
        } else if (skill.skillType == SkillType.Counter) {
            return (baseDamage * skill.value) / 100;
        }
        return baseDamage;
    }
    
    /**
     * @notice 计算伤害（考虑五行相克）
     * @dev 火克风、风克水、水克火、光暗互克，克制时伤害×1.5，被克制时伤害×0.7
     * @param baseDamage 基础伤害
     * @param attackerElement 攻击者属性
     * @param defenderElement 防守者属性
     * @return 最终伤害值
     */
    function calculateDamage(uint256 baseDamage, Element attackerElement, Element defenderElement) 
        public pure returns (uint256) {
        if (attackerElement == Element.Fire && defenderElement == Element.Wind) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == Element.Wind && defenderElement == Element.Water) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == Element.Water && defenderElement == Element.Fire) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == Element.Light && defenderElement == Element.Dark) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == Element.Dark && defenderElement == Element.Light) {
            return (baseDamage * 15) / 10;
        }
        
        if (attackerElement == Element.Wind && defenderElement == Element.Fire) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == Element.Water && defenderElement == Element.Wind) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == Element.Fire && defenderElement == Element.Water) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == Element.Dark && defenderElement == Element.Light) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == Element.Light && defenderElement == Element.Dark) {
            return (baseDamage * 7) / 10;
        }
        
        return baseDamage;
    }
    
    /**
     * @notice 计算NFT生命值
     * @param level NFT等级
     * @return 生命值（基础400 + 每级+100）
     */
    function calculateHealth(uint256 level) public view returns (uint256) {
        return baseHealth + (level - 1) * 100;
    }
    
    /**
     * @notice 计算闪避几率
     * @param attackerSpeed 攻击者速度
     * @param defenderSpeed 防守者速度
     * @return 是否闪避成功
     */
    function calculateDodgeChance(uint256 attackerSpeed, uint256 defenderSpeed) public view returns (bool) {
        if (defenderSpeed >= attackerSpeed) {
            return false;
        }
        uint256 speedDiff = defenderSpeed * 10000 / attackerSpeed;
        uint256 dodgeChance = ((10000 - speedDiff) * dodgeBaseChance) / 10000;
        uint256 randomVal = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, msg.sender))) % 10000;
        return randomVal < dodgeChance;
    }
    
    /**
     * @notice 获取NFT信息（内部函数）
     * @param tokenId NFT ID
     * @return tokenType NFT类型编码、level NFT等级
     */
    function _getTokenInfo(uint256 tokenId) internal view returns (uint256, uint8) {
        uint256 tokenType = uint256(nftContract.tokenType(tokenId));
        uint8 level = nftContract.tokenLevel(tokenId);
        return (tokenType, level);
    }
    
    /**
     * @notice 模拟战斗（只读）
     * @dev 不消耗gas，用于预览战斗结果
     * @param attackerTokens 攻击方NFT ID数组（必须6个）
     * @param defenderTokens 防守方NFT ID数组（必须6个）
     * @return 攻击方是否获胜、攻击方获胜场次、防守方获胜场次
     */
    function simulateBattle(uint256[] calldata attackerTokens, uint256[] calldata defenderTokens) 
        external view returns (bool, uint256, uint256) {
        
        require(attackerTokens.length == TEAM_SIZE, "E01: Attacker must have 6 NFTs");
        require(defenderTokens.length == TEAM_SIZE, "E02: Defender must have 6 NFTs");
        
        INFTMint nft = INFTMint(nftContract);
        
        NFTStatus[] memory attackerTeam = new NFTStatus[](TEAM_SIZE);
        NFTStatus[] memory defenderTeam = new NFTStatus[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 attackerType, uint8 attackerLevel) = _getTokenInfo(attackerTokens[i]);
            (uint256 defenderType, uint8 defenderLevel) = _getTokenInfo(defenderTokens[i]);
            
            attackerTeam[i] = NFTStatus({
                currentHealth: calculateHealth(attackerLevel),
                maxHealth: calculateHealth(attackerLevel),
                level: attackerLevel,
                tokenId: attackerTokens[i],
                element: getElementFromTokenType(attackerType),
                zodiac: getZodiacIndex(attackerType),
                gender: getGender(attackerType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[getZodiacIndex(attackerType)]
            });
            
            defenderTeam[i] = NFTStatus({
                currentHealth: calculateHealth(defenderLevel),
                maxHealth: calculateHealth(defenderLevel),
                level: defenderLevel,
                tokenId: defenderTokens[i],
                element: getElementFromTokenType(defenderType),
                zodiac: getZodiacIndex(defenderType),
                gender: getGender(defenderType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[getZodiacIndex(defenderType)]
            });
        }
        
        uint256 attackerWins = 0;
        uint256 defenderWins = 0;
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (!attackerTeam[i].isAlive) continue;
            
            uint256 targetIndex = _findTarget(defenderTeam, attackerTeam[i].isFrontRow);
            if (targetIndex == type(uint256).max) continue;
            
            bool attackerFirst = attackerTeam[i].speed >= defenderTeam[targetIndex].speed;
            (bool attackerWon, , , , , , ) = _singleBattle(attackerTeam[i], defenderTeam[targetIndex], attackerFirst);
            
            if (attackerWon) {
                attackerWins++;
                defenderTeam[targetIndex].isAlive = false;
            } else {
                defenderWins++;
                attackerTeam[i].isAlive = false;
            }
        }
        
        return (attackerWins > defenderWins, attackerWins, defenderWins);
    }
    
    /**
     * @notice 获取战斗记录
     * @param battleId 战斗ID
     * @return BattleResult 战斗结果详情
     */
    function getBattleResult(uint256 battleId) public view returns (BattleResult memory) {
        return battleHistory[battleId];
    }
    
    /**
     * @notice 获取生肖速度表
     * @return 12个生肖的速度值数组
     */
    function getZodiacSpeedTable() external view returns (uint256[12] memory) {
        uint256[12] memory speeds;
        for (uint256 i = 0; i < 12; i++) {
            speeds[i] = zodiacSpeed[i];
        }
        return speeds;
    }
    
    /**
     * @notice 设置技能（仅Owner）
     * @param elementIndex 属性索引（0-4）
     * @param zodiacIndex 生肖索引（0-11）
     * @param gender 性别（0=雄，1=雌）
     * @param skill 技能详情
     */
    function setSkill(uint256 elementIndex, uint256 zodiacIndex, uint256 gender, FullSkill calldata skill) external onlyOwner {
        require(elementIndex < 5, "Invalid element");
        require(zodiacIndex < 12, "Invalid zodiac");
        require(gender < 2, "Invalid gender");
        fullSkills[elementIndex][zodiacIndex][gender] = skill;
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }
    
    /**
     * @notice 根据索引获取技能
     * @param elementIndex 属性索引（0-4）
     * @param zodiacIndex 生肖索引（0-11）
     * @param gender 性别（0=雄，1=雌）
     * @return FullSkill 技能详情
     */
    function getSkillByIndexes(uint256 elementIndex, uint256 zodiacIndex, uint256 gender) public view returns (FullSkill memory) {
        require(elementIndex < 5, "Invalid element");
        require(zodiacIndex < 12, "Invalid zodiac");
        require(gender < 2, "Invalid gender");
        return fullSkills[elementIndex][zodiacIndex][gender];
    }
}
