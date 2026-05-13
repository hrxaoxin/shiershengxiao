// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";

contract Battle is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    INFTMint public nftContract;
    
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant FRONT_ROW_SIZE = 3;
    
    enum Element { Fire, Wind, Water, Light, Dark }
    
    enum SkillType { Attack, Defense, Heal, Special }
    
    struct Skill {
        string name;
        SkillType skillType;
        uint256 value;
        uint256 cooldown;
    }
    
    struct BattleResult {
        address attacker;
        address defender;
        uint256 attackerWinCount;
        uint256 defenderWinCount;
        uint256 timestamp;
        BattleRoundResult[] roundResults;
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
    
    mapping(uint256 => Skill) public zodiacSkills;
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
    
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    function setNFTContract(address _nftContract) external onlyOwner {
        nftContract = INFTMint(_nftContract);
    }
    
    function setBaseHealth(uint256 _baseHealth) external onlyOwner {
        baseHealth = _baseHealth;
    }
    
    function setDodgeBaseChance(uint256 _chance) external onlyOwner {
        require(_chance <= 10000, "Dodge chance too high");
        dodgeBaseChance = _chance;
    }
    
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
    
    function setZodiacSpeed(uint256 zodiacIndex, uint256 speed) external onlyOwner {
        require(zodiacIndex < 12, "Invalid zodiac");
        zodiacSpeed[zodiacIndex] = speed;
    }
    
    function getElementFromTokenType(uint256 tokenType) public pure returns (Element) {
        uint256 attrIndex = tokenType / 24;
        if (attrIndex == 0) return Element.Water;
        if (attrIndex == 1) return Element.Wind;
        if (attrIndex == 2) return Element.Fire;
        if (attrIndex == 3) return Element.Dark;
        return Element.Light;
    }
    
    function getZodiacIndex(uint256 tokenType) public pure returns (uint256) {
        return (tokenType % 24) / 2;
    }
    
    function getSpeed(uint256 zodiacIndex) public view returns (uint256) {
        return zodiacSpeed[zodiacIndex];
    }
    
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
    
    function calculateHealth(uint256 level) public view returns (uint256) {
        return baseHealth + (level - 1) * 100;
    }
    
    function calculateDodgeChance(uint256 attackerSpeed, uint256 defenderSpeed) public view returns (bool) {
        if (defenderSpeed >= attackerSpeed) {
            return false;
        }
        uint256 speedDiff = defenderSpeed * 10000 / attackerSpeed;
        uint256 dodgeChance = ((10000 - speedDiff) * dodgeBaseChance) / 10000;
        uint256 randomVal = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, msg.sender))) % 10000;
        return randomVal < dodgeChance;
    }
    
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
        
        bool[] memory attackerParticipated = new bool[](TEAM_SIZE);
        bool[] memory defenderParticipated = new bool[](TEAM_SIZE);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            if (!attackerTeam[i].isAlive) continue;
            
            uint256 targetIndex = _findTarget(defenderTeam, attackerTeam[i].isFrontRow);
            if (targetIndex == type(uint256).max) continue;
            
            defenderParticipated[targetIndex] = true;
            attackerParticipated[i] = true;
            
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
        
        if (attackerFirst) {
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
            
            if (attackerTotalDamage >= defender.currentHealth) {
                return (true, attackerTotalDamage, 0, attackerSkillName, "", defenderDodged, false);
            }
            
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
    
    function _getTokenInfo(uint256 tokenId) internal view returns (uint256, uint8) {
        uint256 tokenType = uint256(nftContract.tokenType(tokenId));
        uint8 level = nftContract.tokenLevel(tokenId);
        return (tokenType, level);
    }
    
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
    
    function getBattleResult(uint256 battleId) public view returns (BattleResult memory) {
        return battleHistory[battleId];
    }
    
    function getZodiacSpeedTable() external view returns (uint256[12] memory) {
        uint256[12] memory speeds;
        for (uint256 i = 0; i < 12; i++) {
            speeds[i] = zodiacSpeed[i];
        }
        return speeds;
    }
}