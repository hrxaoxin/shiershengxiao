// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title Battle
 * @dev 十二生肖NFT竞技场战斗合约
 * 支持6v6的NFT团队对战，包含五行相克系统和技能系统
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract Battle is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /** @dev NFT合约地址 */
    INFTMint public nftContract;
    
    /** @dev 团队大小：每队6个NFT */
    uint256 public constant TEAM_SIZE = 6;
    /** @dev 前排大小：每队前排3个NFT */
    uint256 public constant FRONT_ROW_SIZE = 3;
    
    /** @dev 五行属性枚举：火、风、水、光、暗 */
    enum Element { Fire, Wind, Water, Light, Dark }
    
    /** @dev 技能类型枚举：攻击、防御、治疗、特殊 */
    enum SkillType { Attack, Defense, Heal, Special }
    
    /**
     * @dev 技能结构体
     * @param name 技能名称
     * @param skillType 技能类型
     * @param value 技能数值（百分比加成）
     * @param cooldown 技能冷却回合
     */
    struct Skill {
        string name;
        SkillType skillType;
        uint256 value;
        uint256 cooldown;
    }
    
    /**
     * @dev 战斗结果结构体
     * @param attacker 攻击者地址
     * @param defender 防御者地址
     * @param attackerWinCount 攻击者获胜场次
     * @param defenderWinCount 防御者获胜场次
     * @param timestamp 战斗时间戳
     * @param roundResults 每回合详细结果
     */
    struct BattleResult {
        address attacker;
        address defender;
        uint256 attackerWinCount;
        uint256 defenderWinCount;
        uint256 timestamp;
        BattleRoundResult[] roundResults;
    }
    
    /**
     * @dev 单回合战斗结果结构体
     * @param attackerTokenId 攻击者NFT ID
     * @param defenderTokenId 防御者NFT ID
     * @param attackerWon 攻击者是否获胜
     * @param attackerDamage 攻击者造成伤害
     * @param defenderDamage 防御者造成伤害
     * @param attackerSkill 攻击者使用技能
     * @param defenderSkill 防御者使用技能
     * @param attackerDodged 攻击者是否闪避
     * @param defenderDodged 防御者是否闪避
     */
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
    
    /**
     * @dev NFT战斗状态结构体
     * @param currentHealth 当前生命值
     * @param maxHealth 最大生命值
     * @param level NFT等级
     * @param tokenId NFT ID
     * @param element 属性类型
     * @param zodiac 生肖索引
     * @param isFrontRow 是否在前排
     * @param isAlive 是否存活
     * @param speed 速度值
     */
    struct NFTStatus {
        uint256 currentHealth;
        uint256 maxHealth;
        uint256 level;
        uint256 tokenId;
        Element element;
        uint256 zodiac;
        bool isFrontRow;
        bool isAlive;
        uint256 speed;
    }
    
    /** @dev 生肖技能映射（生肖索引 => 技能） */
    mapping(uint256 => Skill) public zodiacSkills;
    /** @dev 生肖速度映射（生肖索引 => 速度值） */
    mapping(uint256 => uint256) public zodiacSpeed;
    /** @dev 战斗历史记录（战斗ID => 战斗结果） */
    mapping(uint256 => BattleResult) public battleHistory;
    
    /** @dev 下一个战斗ID */
    uint256 public nextBattleId;
    /** @dev 基础生命值 */
    uint256 public baseHealth;
    /** @dev 基础闪避概率（千分比，默认1500 = 15%） */
    uint256 public dodgeBaseChance = 1500;
    
    /**
     * @dev 战斗完成事件
     * @param attacker 攻击者地址
     * @param defender 防御者地址
     * @param attackerWon 攻击者是否获胜
     * @param attackerWinCount 攻击者获胜场次
     * @param defenderWinCount 防御者获胜场次
     */
    event BattleCompleted(
        address indexed attacker,
        address indexed defender,
        bool attackerWon,
        uint256 attackerWinCount,
        uint256 defenderWinCount
    );

    /**
     * @dev 回合完成事件
     * @param battleId 战斗ID
     * @param attackerTokenId 攻击者NFT ID
     * @param defenderTokenId 防御者NFT ID
     * @param attackerWon 攻击者是否获胜
     */
    event RoundCompleted(
        uint256 indexed battleId,
        uint256 attackerTokenId,
        uint256 defenderTokenId,
        bool attackerWon
    );
    
    /**
     * @dev 初始化合约
     * @param _nftContract NFT合约地址
     */
    function initialize(address _nftContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        nftContract = INFTMint(_nftContract);
        nextBattleId = 1;
        baseHealth = 400;
        
        _initZodiacSkills();
        _initZodiacSpeed();
    }
    
    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        nftContract = INFTMint(_nftContract);
    }
    
    /**
     * @dev 设置基础生命值
     * @param _baseHealth 基础生命值
     */
    function setBaseHealth(uint256 _baseHealth) external onlyOwner {
        baseHealth = _baseHealth;
    }
    
    /**
     * @dev 设置基础闪避概率（千分比，0-10000）
     * @param _chance 闪避概率（千分比）
     */
    function setDodgeBaseChance(uint256 _chance) external onlyOwner {
        require(_chance <= 10000, "Dodge chance too high");
        dodgeBaseChance = _chance;
    }
    
    /**
     * @dev 初始化生肖技能（内部函数）
     * 为12个生肖分别设置独特技能
     */
    function _initZodiacSkills() internal {
        zodiacSkills[0] = Skill("鼠之敏捷", SkillType.Attack, 120, 3);
        zodiacSkills[1] = Skill("牛之坚韧", SkillType.Defense, 80, 4);
        zodiacSkills[2] = Skill("虎之猛击", SkillType.Attack, 150, 5);
        zodiacSkills[3] = Skill("兔之闪避", SkillType.Defense, 100, 3);
        zodiacSkills[4] = Skill("龙之吐息", SkillType.Special, 200, 6);
        zodiacSkills[5] = Skill("蛇之毒液", SkillType.Attack, 130, 4);
        zodiacSkills[6] = Skill("马之奔腾", SkillType.Attack, 140, 3);
        zodiacSkills[7] = Skill("羊之治愈", SkillType.Heal, 100, 5);
        zodiacSkills[8] = Skill("猴之灵活", SkillType.Attack, 110, 2);
        zodiacSkills[9] = Skill("鸡之警戒", SkillType.Defense, 90, 3);
        zodiacSkills[10] = Skill("狗之忠诚", SkillType.Defense, 95, 4);
        zodiacSkills[11] = Skill("猪之福气", SkillType.Heal, 120, 6);
    }
    
    /**
     * @dev 初始化生肖速度（内部函数）
     * 为12个生肖设置不同的速度值
     */
    function _initZodiacSpeed() internal {
        zodiacSpeed[0] = 95;  // 鼠 - 非常敏捷
        zodiacSpeed[1] = 40;  // 牛 - 稳重
        zodiacSpeed[2] = 70;  // 虎 - 勇猛
        zodiacSpeed[3] = 90; // 兔 - 灵活
        zodiacSpeed[4] = 80; // 龙 - 威严
        zodiacSpeed[5] = 85; // 蛇 - 迅猛
        zodiacSpeed[6] = 100;// 马 - 奔腾
        zodiacSpeed[7] = 35; // 羊 - 温和
        zodiacSpeed[8] = 110;// 猴 - 极其灵活
        zodiacSpeed[9] = 55; // 鸡 - 警觉
        zodiacSpeed[10] = 60;// 狗 - 忠诚
        zodiacSpeed[11] = 30;// 猪 - 迟缓
    }
    
    /**
     * @dev 设置生肖速度
     * @param zodiacIndex 生肖索引（0-11）
     * @param speed 速度值
     */
    function setZodiacSpeed(uint256 zodiacIndex, uint256 speed) external onlyOwner {
        require(zodiacIndex < 12, "Invalid zodiac");
        zodiacSpeed[zodiacIndex] = speed;
    }
    
    /**
     * @dev 从NFT类型获取属性类型
     * @param tokenType NFT类型编码
     * @return Element 属性类型
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
     * @dev 从NFT类型获取生肖索引
     * @param tokenType NFT类型编码
     * @return uint256 生肖索引（0-11）
     */
    function getZodiacIndex(uint256 tokenType) public pure returns (uint256) {
        return (tokenType % 24) / 2;
    }
    
    /**
     * @dev 获取生肖速度
     * @param zodiacIndex 生肖索引（0-11）
     * @return uint256 速度值
     */
    function getSpeed(uint256 zodiacIndex) public view returns (uint256) {
        return zodiacSpeed[zodiacIndex];
    }
    
    /**
     * @dev 计算伤害（考虑五行相克）
     * 相克关系：火克风、风克水、水克火、光暗互克
     * @param baseDamage 基础伤害
     * @param attackerElement 攻击者属性
     * @param defenderElement 防御者属性
     * @return uint256 最终伤害
     */
    function calculateDamage(uint256 baseDamage, Element attackerElement, Element defenderElement) 
        public pure returns (uint256) {
        // 克制关系：伤害提升50%
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
        
        // 被克制关系：伤害降低30%
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
     * @dev 计算生命值（基于等级）
     * @param level NFT等级
     * @return uint256 生命值
     */
    function calculateHealth(uint256 level) public view returns (uint256) {
        return baseHealth + (level - 1) * 100;
    }
    
    /**
     * @dev 计算闪避概率
     * @param attackerSpeed 攻击者速度
     * @param defenderSpeed 防御者速度
     * @return bool 是否闪避成功
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
     * @dev 执行战斗（6v6团队对战）
     * @param attackerTokens 攻击者NFT ID数组（6个）
     * @param defenderTokens 防御者NFT ID数组（6个）
     * @return bool 攻击者是否获胜
     * @return uint256 攻击者获胜场次
     * @return uint256 防御者获胜场次
     */
    function battle(uint256[] calldata attackerTokens, uint256[] calldata defenderTokens) 
        external nonReentrant returns (bool, uint256, uint256) {
        require(attackerTokens.length == TEAM_SIZE, "E01: Attacker must have 6 NFTs");
        require(defenderTokens.length == TEAM_SIZE, "E02: Defender must have 6 NFTs");
        
        INFTMint nft = INFTMint(nftContract);
        
        NFTStatus[] memory attackerTeam = new NFTStatus[](TEAM_SIZE);
        NFTStatus[] memory defenderTeam = new NFTStatus[](TEAM_SIZE);
        
        // 初始化两队NFT状态
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 attackerType, uint8 attackerLevel) = _getTokenInfo(attackerTokens[i]);
            (uint256 defenderType, uint8 defenderLevel) = _getTokenInfo(defenderTokens[i]);
            uint256 attackerZodiac = getZodiacIndex(attackerType);
            uint256 defenderZodiac = getZodiacIndex(defenderType);
            
            attackerTeam[i] = NFTStatus({
                currentHealth: calculateHealth(attackerLevel),
                maxHealth: calculateHealth(attackerLevel),
                level: attackerLevel,
                tokenId: attackerTokens[i],
                element: getElementFromTokenType(attackerType),
                zodiac: attackerZodiac,
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[attackerZodiac]
            });
            
            defenderTeam[i] = NFTStatus({
                currentHealth: calculateHealth(defenderLevel),
                maxHealth: calculateHealth(defenderLevel),
                level: defenderLevel,
                tokenId: defenderTokens[i],
                element: getElementFromTokenType(defenderType),
                zodiac: defenderZodiac,
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[defenderZodiac]
            });
        }
        
        uint256 attackerWins = 0;
        uint256 defenderWins = 0;
        BattleRoundResult[] memory roundResults = new BattleRoundResult[](TEAM_SIZE);
        
        // 依次进行6场单人对战
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
        
        // 保存战斗结果
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
     * @dev 查找目标（优先攻击同排，再攻击后排）
     * @param team 目标团队
     * @param attackerFrontRow 攻击者是否在前排
     * @return uint256 目标索引，无目标返回type(uint256).max
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
     * @dev 单场战斗（内部函数）
     * @param attacker 攻击者状态
     * @param defender 防御者状态
     * @param attackerFirst 攻击者是否先手
     * @return bool 攻击者是否获胜
     * @return uint256 攻击者伤害
     * @return uint256 防御者伤害
     * @return string 攻击者技能
     * @return string 防御者技能
     * @return bool 攻击者是否闪避
     * @return bool 防御者是否闪避
     */
    function _singleBattle(NFTStatus memory attacker, NFTStatus memory defender, bool attackerFirst) 
        internal view returns (bool, uint256, uint256, string memory, string memory, bool, bool) {
        
        bool attackerDodged = false;
        bool defenderDodged = false;
        
        Skill storage attackerSkill = zodiacSkills[attacker.zodiac];
        Skill storage defenderSkill = zodiacSkills[defender.zodiac];
        
        uint256 attackerBaseDamage = attacker.level * 60;
        uint256 defenderBaseDamage = defender.level * 60;
        
        uint256 attackerTotalDamage = calculateDamage(attackerBaseDamage, attacker.element, defender.element);
        uint256 defenderTotalDamage = calculateDamage(defenderBaseDamage, defender.element, attacker.element);
        
        string memory attackerSkillName = attackerSkill.name;
        string memory defenderSkillName = defenderSkill.name;
        
        // 根据速度决定先手顺序
        if (attackerFirst) {
            // 攻击者先手
            if (calculateDodgeChance(attacker.speed, defender.speed)) {
                defenderDodged = true;
                attackerTotalDamage = 0;
            }
            
            // 应用技能效果
            if (!defenderDodged && attackerSkill.skillType == SkillType.Attack) {
                attackerTotalDamage = (attackerTotalDamage * attackerSkill.value) / 100;
            } else if (!defenderDodged && attackerSkill.skillType == SkillType.Defense) {
                defenderTotalDamage = (defenderTotalDamage * (100 - attackerSkill.value)) / 100;
            } else if (!defenderDodged && attackerSkill.skillType == SkillType.Heal) {
                uint256 healAmount = attackerSkill.value;
                attacker.currentHealth = attacker.currentHealth + healAmount > attacker.maxHealth 
                    ? attacker.maxHealth 
                    : attacker.currentHealth + healAmount;
            }
            
            if (attackerTotalDamage >= defender.currentHealth) {
                return (true, attackerTotalDamage, 0, attackerSkillName, "", defenderDodged, false);
            }
            
            // 防御者反击
            if (calculateDodgeChance(defender.speed, attacker.speed)) {
                attackerDodged = true;
                defenderTotalDamage = 0;
            }
            
            if (!attackerDodged && defenderSkill.skillType == SkillType.Attack) {
                defenderTotalDamage = (defenderTotalDamage * defenderSkill.value) / 100;
            } else if (!attackerDodged && defenderSkill.skillType == SkillType.Defense) {
                attackerTotalDamage = (attackerTotalDamage * (100 - defenderSkill.value)) / 100;
            } else if (!attackerDodged && defenderSkill.skillType == SkillType.Heal) {
                uint256 healAmount = defenderSkill.value;
                defender.currentHealth = defender.currentHealth + healAmount > defender.maxHealth 
                    ? defender.maxHealth 
                    : defender.currentHealth + healAmount;
            }
        } else {
            // 防御者先手
            if (calculateDodgeChance(defender.speed, attacker.speed)) {
                attackerDodged = true;
                defenderTotalDamage = 0;
            }
            
            if (!attackerDodged && defenderSkill.skillType == SkillType.Attack) {
                defenderTotalDamage = (defenderTotalDamage * defenderSkill.value) / 100;
            } else if (!attackerDodged && defenderSkill.skillType == SkillType.Defense) {
                attackerTotalDamage = (attackerTotalDamage * (100 - defenderSkill.value)) / 100;
            } else if (!attackerDodged && defenderSkill.skillType == SkillType.Heal) {
                uint256 healAmount = defenderSkill.value;
                defender.currentHealth = defender.currentHealth + healAmount > defender.maxHealth 
                    ? defender.maxHealth 
                    : defender.currentHealth + healAmount;
            }
            
            if (defenderTotalDamage >= attacker.currentHealth) {
                return (false, 0, defenderTotalDamage, "", defenderSkillName, false, attackerDodged);
            }
            
            // 攻击者反击
            if (calculateDodgeChance(attacker.speed, defender.speed)) {
                defenderDodged = true;
                attackerTotalDamage = 0;
            }
            
            if (!defenderDodged && attackerSkill.skillType == SkillType.Attack) {
                attackerTotalDamage = (attackerTotalDamage * attackerSkill.value) / 100;
            } else if (!defenderDodged && attackerSkill.skillType == SkillType.Defense) {
                defenderTotalDamage = (defenderTotalDamage * (100 - attackerSkill.value)) / 100;
            } else if (!defenderDodged && attackerSkill.skillType == SkillType.Heal) {
                uint256 healAmount = attackerSkill.value;
                attacker.currentHealth = attacker.currentHealth + healAmount > attacker.maxHealth 
                    ? attacker.maxHealth 
                    : attacker.currentHealth + healAmount;
            }
        }
        
        bool attackerWon = attackerTotalDamage >= defender.currentHealth && defenderTotalDamage < attacker.currentHealth;
        
        return (attackerWon, attackerTotalDamage, defenderTotalDamage, attackerSkillName, attackerWon ? "" : defenderSkillName, attackerDodged, defenderDodged);
    }
    
    /**
     * @dev 获取NFT信息（类型和等级）
     * @param tokenId NFT ID
     * @return uint256 NFT类型编码
     * @return uint8 NFT等级
     */
    function _getTokenInfo(uint256 tokenId) internal view returns (uint256, uint8) {
        uint256 tokenType = uint256(nftContract.tokenType(tokenId));
        uint8 level = nftContract.tokenLevel(tokenId);
        return (tokenType, level);
    }
    
    /**
     * @dev 模拟战斗（只读，不记录历史）
     * @param attackerTokens 攻击者NFT ID数组
     * @param defenderTokens 防御者NFT ID数组
     * @return bool 攻击者是否获胜
     * @return uint256 攻击者获胜场次
     * @return uint256 防御者获胜场次
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
            uint256 attackerZodiac = getZodiacIndex(attackerType);
            uint256 defenderZodiac = getZodiacIndex(defenderType);
            
            attackerTeam[i] = NFTStatus({
                currentHealth: calculateHealth(attackerLevel),
                maxHealth: calculateHealth(attackerLevel),
                level: attackerLevel,
                tokenId: attackerTokens[i],
                element: getElementFromTokenType(attackerType),
                zodiac: attackerZodiac,
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[attackerZodiac]
            });
            
            defenderTeam[i] = NFTStatus({
                currentHealth: calculateHealth(defenderLevel),
                maxHealth: calculateHealth(defenderLevel),
                level: defenderLevel,
                tokenId: defenderTokens[i],
                element: getElementFromTokenType(defenderType),
                zodiac: defenderZodiac,
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: zodiacSpeed[defenderZodiac]
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
     * @dev 获取战斗结果
     * @param battleId 战斗ID
     * @return BattleResult 战斗结果结构体
     */
    function getBattleResult(uint256 battleId) public view returns (BattleResult memory) {
        return battleHistory[battleId];
    }
    
    /**
     * @dev 获取所有生肖速度表
     * @return uint256[12] 12生肖速度数组
     */
    function getZodiacSpeedTable() external view returns (uint256[12] memory) {
        uint256[12] memory speeds;
        for (uint256 i = 0; i < 12; i++) {
            speeds[i] = zodiacSpeed[i];
        }
        return speeds;
    }
}
