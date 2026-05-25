// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ArenaRankingLib
 * @dev 竞技场排名工具库，提供排名计算和验证函数
 *
 * 积分规则：
 * - 基础胜利积分：100分
 * - 基础失败扣分：50分
 * - 排名差距加成：最高500分
 *
 * 虚拟玩家：
 * - address(0) 是虚拟玩家
 * - address 1-20 也是虚拟玩家
 */
library ArenaRankingLib {
    /**
     * @dev 基础胜利积分
     */
    uint256 public constant BASE_WIN_POINTS = 100;

    /**
     * @dev 基础失败扣分
     */
    uint256 public constant BASE_LOSS_POINTS = 50;

    /**
     * @dev 最高排名加成
     */
    uint256 public constant MAX_RANK_BONUS = 500;

    /**
     * @dev 基点（用于百分比计算）
     */
    uint256 public constant BPS = 10000;

    /**
     * @dev 玩家排名信息结构
     */
    struct Player {
        uint256 points;            // 当前积分
        uint256 wins;              // 胜利次数
        uint256 losses;            // 失败次数
        uint256 lastBattleTime;    // 上次战斗时间
        uint256 lastResetTime;     // 上次重置时间
        uint256 remainingAttempts; // 剩余挑战次数
        uint256[] battleTeam;      // 战斗队伍NFT ID列表
        bool hasTeam;              // 是否已设置队伍
    }

    /**
     * @dev 计算胜利积分
     *
     * @param attackerRank 攻击方排名
     * @param defenderRank 防守方排名
     * @param winCount 连胜次数
     * @return int256 获得的积分（可正可负）
     */
    function calculateWinPoints(uint256 attackerRank, uint256 defenderRank, uint256 winCount) internal pure returns (int256) {
        uint256 rankDiff = attackerRank > defenderRank ? attackerRank - defenderRank : defenderRank - attackerRank;
        uint256 bonus = (rankDiff * MAX_RANK_BONUS) / 100;
        uint256 battlePoints = winCount * BASE_WIN_POINTS;

        if (attackerRank > defenderRank) {
            return int256(battlePoints + bonus);
        } else if (attackerRank < defenderRank) {
            uint256 penalty = (battlePoints * bonus) / 1000;
            return int256(battlePoints > penalty ? battlePoints - penalty : battlePoints / 2);
        } else {
            return int256(battlePoints);
        }
    }

    /**
     * @dev 计算失败扣分
     *
     * @param attackerRank 攻击方排名
     * @param defenderRank 防守方排名
     * @return uint256 扣除的积分
     */
    function calculateLossPoints(uint256 attackerRank, uint256 defenderRank) internal pure returns (uint256) {
        uint256 rankDiff = attackerRank > defenderRank ? attackerRank - defenderRank : defenderRank - attackerRank;
        uint256 bonus = (rankDiff * MAX_RANK_BONUS) / 100;

        if (attackerRank > defenderRank) {
            uint256 penalty = (BASE_LOSS_POINTS * bonus) / 1000;
            return penalty < BASE_LOSS_POINTS ? BASE_LOSS_POINTS - penalty : BASE_LOSS_POINTS / 2;
        } else if (attackerRank < defenderRank) {
            return BASE_LOSS_POINTS + bonus;
        } else {
            return BASE_LOSS_POINTS;
        }
    }

    /**
     * @dev 获取虚拟玩家排名
     *
     * @param player 玩家地址
     * @return uint256 虚拟玩家排名
     */
    function getMockPlayerRank(address player) internal pure returns (uint256) {
        return uint256(uint160(player));
    }

    /**
     * @dev 判断是否为虚拟玩家
     *
     * @param player 玩家地址
     * @return bool 是否为虚拟玩家
     */
    function isMockPlayer(address player) internal pure returns (bool) {
        if (player == address(0)) return true;
        uint256 mockRank = uint256(uint160(player));
        return mockRank >= 1 && mockRank <= 20;
    }

    /**
     * @dev 验证队伍中的NFT是否唯一
     *
     * @param tokenIds NFT ID数组
     */
    function validateUniqueTokens(uint256[] calldata tokenIds) internal pure {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                if (tokenIds[i] == tokenIds[j]) {
                    revert("E16: Duplicate NFT in team");
                }
            }
        }
    }
}