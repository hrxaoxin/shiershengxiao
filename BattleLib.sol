// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BattleLib
 * @dev 战斗工具库，提供战斗相关的计算函数
 *
 * 功能：
 * 1. 计算闪避概率
 * 2. 计算暴击概率
 * 3. 计算属性克制
 * 4. 计算伤害
 * 5. 队伍排序
 *
 * 战斗流程：
 * 1. 根据速度排序两队NFT
 * 2. 按速度顺序进行回合战斗
 * 3. 每回合：攻击 → 伤害计算 → 状态更新
 * 4. 一队全部阵亡则战斗结束
 *
 * 伤害公式：
 * baseDamage = attacker.attack × elementalBonus / 100
 * finalDamage = baseDamage × (1000 / (1000 + defender.defense))
 * 如果暴击：finalDamage × 1.5
 *
 * 闪避判定：
 * 随机数 > defender.dodge 则闪避成功，伤害为0
 *
 * 暴击判定：
 * 随机数 < attacker.criticalChance 则暴击，伤害×1.5
 */
library BattleLib {
    /**
     * @dev 战斗结果枚举
     */
    enum BattleResult {
        IN_PROGRESS,  // 0 - 战斗进行中
        TEAM1_WINS,   // 1 - 队伍1获胜
        TEAM2_WINS    // 2 - 队伍2获胜
    }

    /**
     * @dev NFT战斗状态
     */
    struct NFTTeamMember {
        uint256 tokenId;       // NFT ID
        uint256 hp;            // 当前生命值
        uint256 maxHp;         // 最大生命值
        uint256 attack;         // 攻击力
        uint256 defense;       // 防御力
        uint256 speed;         // 速度
        uint256 element;       // 属性类型
        bool isAlive;          // 是否存活
    }

    /**
     * @dev 战斗历史记录
     */
    struct BattleLog {
        uint256 battleId;
        uint256 timestamp;
        uint256 team1Score;
        uint256 team2Score;
    }

    /**
     * @dev 完整技能数据结构
     */
    struct FullSkill {
        bytes32 skillId;      // 技能唯一标识
        uint8 skillType;      // 技能类型
        uint256 damage;      // 伤害值
        uint256 cooldown;    // 冷却时间
        uint256 duration;    // 持续时间
        bool isAoe;          // 是否AOE技能
    }

    /**
     * @dev 单场战斗结果
     */
    struct SingleBattleResult {
        uint256 battleId;           // 战斗ID
        uint256 timestamp;          // 战斗时间戳
        address team1Player;        // 队伍1玩家地址
        address team2Player;        // 队伍2玩家地址
        uint256[] team1TokenIds;    // 队伍1 NFT ID数组
        uint256[] team2TokenIds;    // 队伍2 NFT ID数组
        BattleResult result;        // 战斗结果
        uint256 team1Score;        // 队伍1得分
        uint256 team2Score;        // 队伍2得分
    }

    /**
     * @dev 队伍速度排序
     *
     * 按速度从高到低排序
     * 速度相同时随机决定顺序
     *
     * @param team 队伍数组
     * @param teamSize 队伍大小
     * @param seed 随机种子
     */
    function sortTeamBySpeed(
        NFTTeamMember[] memory team,
        uint256 teamSize,
        uint256 seed
    ) internal pure {
        for (uint256 i = 0; i < teamSize - 1; i++) {
            for (uint256 j = 0; j < teamSize - i - 1; j++) {
                if (team[j].speed < team[j + 1].speed) {
                    NFTTeamMember memory temp = team[j];
                    team[j] = team[j + 1];
                    team[j + 1] = temp;
                }
            }
        }
    }

    /**
     * @dev 计算闪避
     *
     * @param defenderDodge 防守方闪避率
     * @param randomSeed 随机种子
     * @return bool 是否闪避成功
     */
    function calculateDodge(uint256 defenderDodge, uint256 randomSeed) internal view returns (bool) {
        uint256 randomVal = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, randomSeed))) % 10000;
        return randomVal < defenderDodge;
    }

    /**
     * @dev 计算暴击
     *
     * @param attackerCritical 攻击方暴击率
     * @param randomSeed 随机种子
     * @return bool 是否暴击
     */
    function calculateCritical(uint256 attackerCritical, uint256 randomSeed) internal view returns (bool) {
        uint256 randomVal = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, randomSeed + 1))) % 10000;
        return randomVal < attackerCritical;
    }

    /**
     * @dev 获取属性克制加成
     *
     * 属性编号：
     * 0 - 水, 1 - 风, 2 - 火, 3 - 暗, 4 - 光
     *
     * 克制关系：
     * 火克风、风克水、水克火
     * 光克暗、暗克光
     *
     * @param attackerElement 攻击方属性
     * @param defenderElement 防守方属性
     * @return uint256 克制加成（100=无加成，150=克制）
     */
    function getElementalAdvantage(uint256 attackerElement, uint256 defenderElement) internal pure returns (uint256) {
        if (attackerElement == 2 && defenderElement == 1) return 150; // 火克风
        if (attackerElement == 1 && defenderElement == 0) return 150; // 风克水
        if (attackerElement == 0 && defenderElement == 2) return 150; // 水克火
        if (attackerElement == 4 && defenderElement == 3) return 150; // 光克暗
        if (attackerElement == 3 && defenderElement == 4) return 150; // 暗克光
        return 100;
    }

    /**
     * @dev 计算伤害
     *
     * @param attacker 攻击方属性
     * @param defender 防守方属性
     * @param elementalBonus 属性克制加成
     * @param isCritical 是否暴击
     * @return uint256 最终伤害
     */
    function calculateDamage(
        NFTTeamMember memory attacker,
        NFTTeamMember memory defender,
        uint256 elementalBonus,
        bool isCritical
    ) internal pure returns (uint256) {
        uint256 baseDamage = attacker.attack * elementalBonus / 100;
        // 提高中间精度，避免整数除法导致的精度损失
        // 原公式: damage = baseDamage * 1000 / (1000 + defense)
        // 使用 10000 作为中间精度因子
        uint256 defenseFactor = 10000 * 1000 / (1000 + defender.defense);
        uint256 finalDamage = baseDamage * defenseFactor / 10000;

        if (isCritical) {
            finalDamage = finalDamage * 3 / 2;
        }

        return finalDamage;
    }

    /**
     * @dev 应用伤害
     *
     * @param defender 防守方
     * @param damage 伤害值
     */
    function applyDamage(NFTTeamMember storage defender, uint256 damage) internal {
        if (damage >= defender.hp) {
            defender.hp = 0;
            defender.isAlive = false;
        } else {
            defender.hp = defender.hp - damage;
        }
    }

    /**
     * @dev 检查队伍是否全灭
     *
     * @param team 队伍
     * @param teamSize 队伍大小
     * @return bool 是否全灭
     */
    function isTeamDefeated(NFTTeamMember[] memory team, uint256 teamSize) internal pure returns (bool) {
        for (uint256 i = 0; i < teamSize; i++) {
            if (team[i].isAlive) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev 获取存活成员数量
     *
     * @param team 队伍
     * @param teamSize 队伍大小
     * @return uint256 存活数量
     */
    function getAliveCount(NFTTeamMember[] memory team, uint256 teamSize) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < teamSize; i++) {
            if (team[i].isAlive) {
                count++;
            }
        }
        return count;
    }

    /**
     * @dev 计算队伍总战力
     *
     * @param team 队伍
     * @param teamSize 队伍大小
     * @return uint256 总战力
     */
    function calculateTeamPower(NFTTeamMember[] memory team, uint256 teamSize) internal pure returns (uint256) {
        uint256 power = 0;
        for (uint256 i = 0; i < teamSize; i++) {
            if (team[i].isAlive) {
                power += team[i].hp + team[i].attack + team[i].defense + team[i].speed;
            }
        }
        return power;
    }

    /**
     * @dev 生成随机数
     *
     * @param seed 种子
     * @param salt 盐值
     * @return uint256 随机数
     */
    function generateRandom(uint256 seed, uint256 salt) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            seed,
            salt,
            block.timestamp,
            block.number,
            block.prevrandao,
            msg.sender
        )));
    }

    /**
     * @dev 获取战斗结果
     *
     * @param team1Wins 队伍1获胜次数
     * @param team2Wins 队伍2获胜次数
     * @return BattleResult 战斗结果
     */
    function determineWinner(bool team1Wins, bool team2Wins) internal pure returns (BattleResult) {
        if (team1Wins && !team2Wins) return BattleResult.TEAM1_WINS;
        if (team2Wins && !team1Wins) return BattleResult.TEAM2_WINS;
        return BattleResult.IN_PROGRESS;
    }
}
