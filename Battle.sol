// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";
import "./BattleSkills.sol";

/**
 * @title Battle
 * @author Trae
 * @notice 战斗合约 - 实现6v6 NFT团队对战系统
 * @dev 支持五行相克、技能系统、闪避机制，包含120种独特技能（5属性×12生肖×2性别）
 */
contract Battle is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IBattle {
    using BattleSkills for *;
    
    INFTMint public nftContract;
    address public authorizer;
    
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant FRONT_ROW_SIZE = 3;
    

    
    struct BattleResult {
        address attacker;
        address defender;
        uint256 attackerWinCount;
        uint256 defenderWinCount;
        uint256 timestamp;
        BattleSkills.BattleRoundResult[] roundResults;
    }
    
    struct NFTStatus {
        uint256 currentHealth;
        uint256 maxHealth;
        uint256 level;
        uint256 growthValue;
        uint256 tokenId;
        NFTDataTypes.ElementType element;
        uint256 zodiac;
        uint256 gender;
        bool isFrontRow;
        bool isAlive;
        uint256 speed;
    }
    
    mapping(uint256 => mapping(uint256 => mapping(uint256 => BattleSkills.FullSkill))) public fullSkills;
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
        BattleSkills.initAllSkills(fullSkills);
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
    function getElementFromTokenType(uint256 tokenType) public pure returns (NFTDataTypes.ElementType) {
        uint256 attrIndex = tokenType / 24;
        if (attrIndex == 0) return NFTDataTypes.ElementType.WATER;
        if (attrIndex == 1) return NFTDataTypes.ElementType.WIND;
        if (attrIndex == 2) return NFTDataTypes.ElementType.FIRE;
        if (attrIndex == 3) return NFTDataTypes.ElementType.DARK;
        return NFTDataTypes.ElementType.LIGHT;
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
     * @return BattleSkills.FullSkill 技能详情
     */
    function getSkill(uint256 tokenType) public view returns (BattleSkills.FullSkill memory) {
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
        
        require(attackerTokens.length == TEAM_SIZE, "E01");
        require(defenderTokens.length == TEAM_SIZE, "E02");
        
        NFTStatus[] memory attackerTeam = new NFTStatus[](TEAM_SIZE);
        NFTStatus[] memory defenderTeam = new NFTStatus[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 attackerType, uint8 attackerLevel, uint256 attackerGrowth) = _getTokenInfo(attackerTokens[i]);
            attackerTeam[i] = NFTStatus({
                currentHealth: calculateHealth(attackerLevel, attackerGrowth),
                maxHealth: calculateHealth(attackerLevel, attackerGrowth),
                level: attackerLevel,
                growthValue: attackerGrowth,
                tokenId: attackerTokens[i],
                element: getElementFromTokenType(attackerType),
                zodiac: getZodiacIndex(attackerType),
                gender: getGender(attackerType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: calculateSpeed(zodiacSpeed[getZodiacIndex(attackerType)], attackerGrowth)
            });
        }
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 defenderType, uint8 defenderLevel, uint256 defenderGrowth) = _getTokenInfo(defenderTokens[i]);
            defenderTeam[i] = NFTStatus({
                currentHealth: calculateHealth(defenderLevel, defenderGrowth),
                maxHealth: calculateHealth(defenderLevel, defenderGrowth),
                level: defenderLevel,
                growthValue: defenderGrowth,
                tokenId: defenderTokens[i],
                element: getElementFromTokenType(defenderType),
                zodiac: getZodiacIndex(defenderType),
                gender: getGender(defenderType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: calculateSpeed(zodiacSpeed[getZodiacIndex(defenderType)], defenderGrowth)
            });
        }
        
        uint256 attackerWins = 0;
        uint256 defenderWins = 0;
        BattleSkills.BattleRoundResult[] memory roundResults = new BattleSkills.BattleRoundResult[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (!attackerTeam[i].isAlive) continue;
            
            uint256 targetIndex = _findTarget(defenderTeam, attackerTeam[i].isFrontRow);
            if (targetIndex == type(uint256).max) continue;
            
            BattleSkills.BattleRoundResult memory roundResult = _executeSingleBattle(
                attackerTeam[i], 
                defenderTeam[targetIndex]
            );
            
            roundResults[i] = roundResult;
            
            if (roundResult.attackerWon) {
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
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            result.roundResults.push(roundResults[i]);
        }
        
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
     * @notice 执行单体战斗并返回完整结果（内部函数）
     * @param attacker 攻击者状态
     * @param defender 防守者状态
     * @return BattleRoundResult 单轮战斗结果
     */
    function _executeSingleBattle(NFTStatus memory attacker, NFTStatus memory defender) 
        internal view returns (BattleSkills.BattleRoundResult memory) {
        
        bool attackerFirst = attacker.speed >= defender.speed;
        BattleSkills.SingleBattleResult memory battleResult = _singleBattle(attacker, defender, attackerFirst);
        
        return BattleSkills.BattleRoundResult({
            attackerTokenId: attacker.tokenId,
            defenderTokenId: defender.tokenId,
            attackerWon: battleResult.attackerWon,
            attackerDamage: battleResult.attackerDamage,
            defenderDamage: battleResult.defenderDamage,
            attackerSkill: battleResult.attackerSkill,
            defenderSkill: battleResult.defenderSkill,
            attackerDodged: battleResult.attackerDodged,
            defenderDodged: battleResult.defenderDodged
        });
    }
    
    /**
     * @notice 执行单体战斗（内部函数）
     * @param attacker 攻击者状态
     * @param defender 防守者状态
     * @param attackerFirst 攻击者是否先手
     * @return 攻击者是否获胜、攻击者伤害、防守者伤害、攻击者技能名、防守者技能名、攻击者是否闪避、防守者是否闪避
     */
    function _singleBattle(NFTStatus memory attacker, NFTStatus memory defender, bool attackerFirst) 
        internal view returns (BattleSkills.SingleBattleResult memory) {
        
        if (attackerFirst) {
            return _battleAttackerFirst(attacker, defender);
        } else {
            return _battleDefenderFirst(attacker, defender);
        }
    }
    
    function _battleAttackerFirst(NFTStatus memory attacker, NFTStatus memory defender) 
        internal view returns (BattleSkills.SingleBattleResult memory) {
        
        BattleSkills.SingleBattleResult memory result;
        
        (result.attackerDamage, result.attackerSkill) = _calculateDamage(attacker, defender.element);
        (result.defenderDamage, result.defenderSkill) = _calculateDamage(defender, attacker.element);
        
        if (calculateDodgeChance(attacker.speed, defender.speed)) {
            result.defenderDodged = true;
            result.attackerDamage = 0;
        }
        
        if (!result.defenderDodged && result.attackerDamage >= defender.currentHealth) {
            result.attackerWon = true;
            result.defenderDamage = 0;
            result.defenderSkill = "";
            return result;
        }
        
        if (calculateDodgeChance(defender.speed, attacker.speed)) {
            result.attackerDodged = true;
            result.defenderDamage = 0;
        }
        
        result.attackerWon = result.attackerDamage >= defender.currentHealth && result.defenderDamage < attacker.currentHealth;
        if (result.attackerWon) {
            result.defenderSkill = "";
        }
        
        return result;
    }
    
    function _battleDefenderFirst(NFTStatus memory attacker, NFTStatus memory defender) 
        internal view returns (BattleSkills.SingleBattleResult memory) {
        
        BattleSkills.SingleBattleResult memory result;
        
        (result.attackerDamage, result.attackerSkill) = _calculateDamage(attacker, defender.element);
        (result.defenderDamage, result.defenderSkill) = _calculateDamage(defender, attacker.element);
        
        if (calculateDodgeChance(defender.speed, attacker.speed)) {
            result.attackerDodged = true;
            result.defenderDamage = 0;
        }
        
        if (!result.attackerDodged && result.defenderDamage >= attacker.currentHealth) {
            result.attackerWon = false;
            result.attackerDamage = 0;
            result.attackerSkill = "";
            return result;
        }
        
        if (calculateDodgeChance(attacker.speed, defender.speed)) {
            result.defenderDodged = true;
            result.attackerDamage = 0;
        }
        
        result.attackerWon = result.attackerDamage >= defender.currentHealth && result.defenderDamage < attacker.currentHealth;
        if (result.attackerWon) {
            result.defenderSkill = "";
        }
        
        return result;
    }
    
    function _calculateDamage(NFTStatus memory attacker, NFTDataTypes.ElementType defenderElement) internal view returns (uint256, string memory) {
        BattleSkills.FullSkill memory skill = fullSkills[uint256(attacker.element)][attacker.zodiac][attacker.gender];
        
        uint256 growthBonus = 1000 + (attacker.growthValue * 5);
        uint256 baseDamage = (attacker.level * 60 * growthBonus) / 1000;
        uint256 totalDamage = calculateDamage(baseDamage, attacker.element, defenderElement);
        totalDamage = _applySkillEffect(skill, totalDamage);
        
        return (totalDamage, skill.name);
    }
    
    /**
     * @notice 应用技能效果（内部函数）
     * @param skill 技能
     * @param baseDamage 基础伤害
     * @return 应用技能后的伤害值
     */
    function _applySkillEffect(BattleSkills.FullSkill memory skill, uint256 baseDamage) internal pure returns (uint256) {
        uint8 ATTACK = 0;
        uint8 SPECIAL = 3;
        uint8 LIFESTEAL = 7;
        uint8 COUNTER = 6;
        
        if (skill.skillType == ATTACK || skill.skillType == SPECIAL) {
            return (baseDamage * skill.value) / 100;
        } else if (skill.skillType == LIFESTEAL) {
            return (baseDamage * skill.value) / 100;
        } else if (skill.skillType == COUNTER) {
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
    function calculateDamage(uint256 baseDamage, NFTDataTypes.ElementType attackerElement, NFTDataTypes.ElementType defenderElement) 
        public pure returns (uint256) {
        if (attackerElement == NFTDataTypes.ElementType.FIRE && defenderElement == NFTDataTypes.ElementType.WIND) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.WIND && defenderElement == NFTDataTypes.ElementType.WATER) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.WATER && defenderElement == NFTDataTypes.ElementType.FIRE) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.LIGHT && defenderElement == NFTDataTypes.ElementType.DARK) {
            return (baseDamage * 15) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.DARK && defenderElement == NFTDataTypes.ElementType.LIGHT) {
            return (baseDamage * 15) / 10;
        }
        
        if (attackerElement == NFTDataTypes.ElementType.WIND && defenderElement == NFTDataTypes.ElementType.FIRE) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.WATER && defenderElement == NFTDataTypes.ElementType.WIND) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.FIRE && defenderElement == NFTDataTypes.ElementType.WATER) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.DARK && defenderElement == NFTDataTypes.ElementType.LIGHT) {
            return (baseDamage * 7) / 10;
        }
        if (attackerElement == NFTDataTypes.ElementType.LIGHT && defenderElement == NFTDataTypes.ElementType.DARK) {
            return (baseDamage * 7) / 10;
        }
        
        return baseDamage;
    }
    
    /**
     * @notice 计算NFT生命值
     * @param level NFT等级
     * @param growthValue 成长值（10-100），成长值越高生命值越高
     * @return 生命值（基础400 + 每级+100）× 成长值系数
     */
    function calculateHealth(uint256 level, uint256 growthValue) public view returns (uint256) {
        // 成长值系数：10-100映射到0.9-1.5
        uint256 growthMultiplier = 900 + (growthValue * 6); // 1000倍精度
        return ((baseHealth + (level - 1) * 100) * growthMultiplier) / 1000;
    }
    
    /**
     * @notice 计算NFT速度（考虑成长值加成）
     * @param baseSpeed 基础速度（生肖固定速度）
     * @param growthValue 成长值（10-100），成长值越高速度越快
     * @return 最终速度值
     */
    function calculateSpeed(uint256 baseSpeed, uint256 growthValue) public pure returns (uint256) {
        // 成长值系数：10-100映射到0.95-1.2
        uint256 growthMultiplier = 950 + (growthValue * 25) / 10; // 100倍精度
        return (baseSpeed * growthMultiplier) / 100;
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
     * @return tokenType NFT类型编码、level NFT等级、growthValue 成长值
     */
    function _getTokenInfo(uint256 tokenId) internal view returns (uint256, uint8, uint256) {
        uint256 tokenType = uint256(nftContract.tokenType(tokenId));
        uint8 level = nftContract.tokenLevel(tokenId);
        uint256 growthValue = nftContract.tokenGrowthValue(tokenId);
        return (tokenType, level, growthValue);
    }
    
    /**
     * @notice 生成战斗随机种子（用于链下计算）
     * @dev 返回一个可验证的随机种子，用于链下计算后在上链验证
     * @param attackerTokens 攻击方NFT ID数组
     * @param defenderTokens 防守方NFT ID数组
     * @return bytes32 随机种子
     */
    function generateBattleSeed(uint256[] calldata attackerTokens, uint256[] calldata defenderTokens) 
        external view returns (bytes32) {
        return keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            msg.sender,
            attackerTokens,
            defenderTokens
        ));
    }

    /**
     * @notice 模拟战斗（只读）
     * @dev 不消耗gas，用于预览战斗结果和验证链下计算
     * @param attackerTokens 攻击方NFT ID数组（必须6个）
     * @param defenderTokens 防守方NFT ID数组（必须6个）
     * @return 攻击方是否获胜、攻击方获胜场次、防守方获胜场次
     */
    function simulateBattle(uint256[] calldata attackerTokens, uint256[] calldata defenderTokens) 
        public view returns (bool, uint256, uint256) {
        
        require(attackerTokens.length == TEAM_SIZE, "E01");
        require(defenderTokens.length == TEAM_SIZE, "E02");
        
        NFTStatus[] memory attackerTeam = new NFTStatus[](TEAM_SIZE);
        NFTStatus[] memory defenderTeam = new NFTStatus[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 attackerType, uint8 attackerLevel, uint256 attackerGrowth) = _getTokenInfo(attackerTokens[i]);
            attackerTeam[i] = NFTStatus({
                currentHealth: calculateHealth(attackerLevel, attackerGrowth),
                maxHealth: calculateHealth(attackerLevel, attackerGrowth),
                level: attackerLevel,
                growthValue: attackerGrowth,
                tokenId: attackerTokens[i],
                element: getElementFromTokenType(attackerType),
                zodiac: getZodiacIndex(attackerType),
                gender: getGender(attackerType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: calculateSpeed(zodiacSpeed[getZodiacIndex(attackerType)], attackerGrowth)
            });
        }
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            (uint256 defenderType, uint8 defenderLevel, uint256 defenderGrowth) = _getTokenInfo(defenderTokens[i]);
            defenderTeam[i] = NFTStatus({
                currentHealth: calculateHealth(defenderLevel, defenderGrowth),
                maxHealth: calculateHealth(defenderLevel, defenderGrowth),
                level: defenderLevel,
                growthValue: defenderGrowth,
                tokenId: defenderTokens[i],
                element: getElementFromTokenType(defenderType),
                zodiac: getZodiacIndex(defenderType),
                gender: getGender(defenderType),
                isFrontRow: i < FRONT_ROW_SIZE,
                isAlive: true,
                speed: calculateSpeed(zodiacSpeed[getZodiacIndex(defenderType)], defenderGrowth)
            });
        }
        
        uint256 attackerWins = 0;
        uint256 defenderWins = 0;
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (!attackerTeam[i].isAlive) continue;
            
            uint256 targetIndex = _findTarget(defenderTeam, attackerTeam[i].isFrontRow);
            if (targetIndex == type(uint256).max) continue;
            
            bool attackerFirst = attackerTeam[i].speed >= defenderTeam[targetIndex].speed;
            BattleSkills.SingleBattleResult memory battleResult = _singleBattle(attackerTeam[i], defenderTeam[targetIndex], attackerFirst);
            
            if (battleResult.attackerWon) {
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
     * @notice 验证链下战斗结果
     * @dev 允许用户提交链下计算的战斗结果进行验证，减少链上计算消耗
     * @param attackerTokens 攻击方NFT ID数组（必须6个）
     * @param defenderTokens 防守方NFT ID数组（必须6个）
     * @param claimedAttackerWins 声称的攻击方获胜场次
     * @param claimedDefenderWins 声称的防守方获胜场次
     * @param seed 随机种子（用于验证结果一致性）
     * @return bool 是否验证通过
     */
    function verifyBattleResult(
        uint256[] calldata attackerTokens,
        uint256[] calldata defenderTokens,
        uint256 claimedAttackerWins,
        uint256 claimedDefenderWins,
        bytes32 seed
    ) public view returns (bool) {
        require(attackerTokens.length == TEAM_SIZE, "E01");
        require(defenderTokens.length == TEAM_SIZE, "E02");
        require(claimedAttackerWins + claimedDefenderWins <= TEAM_SIZE, "E03");
        
        bytes32 expectedSeed = keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            msg.sender,
            attackerTokens,
            defenderTokens
        ));
        
        if (seed != expectedSeed) {
            return false;
        }
        
        (bool success, uint256 actualAttackerWins, uint256 actualDefenderWins) = simulateBattle(attackerTokens, defenderTokens);
        
        return actualAttackerWins == claimedAttackerWins && actualDefenderWins == claimedDefenderWins;
    }

    /**
     * @notice 提交链下计算的战斗结果（轻量版本）
     * @dev 先验证结果再记录，减少链上计算压力
     * @param attackerTokens 攻击方NFT ID数组（必须6个）
     * @param defenderTokens 防守方NFT ID数组（必须6个）
     * @param claimedAttackerWins 声称的攻击方获胜场次
     * @param claimedDefenderWins 声称的防守方获胜场次
     * @param seed 随机种子
     * @return bool 攻击方是否获胜
     */
    function commitBattleResult(
        uint256[] calldata attackerTokens,
        uint256[] calldata defenderTokens,
        uint256 claimedAttackerWins,
        uint256 claimedDefenderWins,
        bytes32 seed
    ) external nonReentrant returns (bool) {
        require(verifyBattleResult(attackerTokens, defenderTokens, claimedAttackerWins, claimedDefenderWins, seed), "E04");
        
        bool attackerWon = claimedAttackerWins > claimedDefenderWins;
        
        BattleResult storage result = battleHistory[nextBattleId];
        result.attacker = msg.sender;
        result.defender = tx.origin;
        result.attackerWinCount = claimedAttackerWins;
        result.defenderWinCount = claimedDefenderWins;
        result.timestamp = block.timestamp;
        
        nextBattleId++;
        
        emit BattleCompleted(msg.sender, tx.origin, attackerWon, claimedAttackerWins, claimedDefenderWins);
        
        return attackerWon;
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
    function setSkill(uint256 elementIndex, uint256 zodiacIndex, uint256 gender, BattleSkills.FullSkill calldata skill) external onlyOwner {
        require(elementIndex < 5, "E05");
        require(zodiacIndex < 12, "E06");
        require(gender < 2, "E07");
        fullSkills[elementIndex][zodiacIndex][gender] = skill;
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "E08");
        nftContract = INFTMint(_nftContract);
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }
    
    /**
     * @notice 根据索引获取技能
     * @param elementIndex 属性索引（0-4）
     * @param zodiacIndex 生肖索引（0-11）
     * @param gender 性别（0=雄，1=雌）
     * @return BattleSkills.FullSkill 技能详情
     */
    function getSkillByIndexes(uint256 elementIndex, uint256 zodiacIndex, uint256 gender) public view returns (BattleSkills.FullSkill memory) {
        require(elementIndex < 5, "E05");
        require(zodiacIndex < 12, "E06");
        require(gender < 2, "E07");
        return fullSkills[elementIndex][zodiacIndex][gender];
    }
}
