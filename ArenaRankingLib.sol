// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ArenaRankingLib {
    uint256 public constant BASE_WIN_POINTS = 100;
    uint256 public constant BASE_LOSS_POINTS = 50;
    uint256 public constant MAX_RANK_BONUS = 500;
    uint256 public constant BPS = 10000;

    struct Player {
        uint256 points;
        uint256 wins;
        uint256 losses;
        uint256 lastBattleTime;
        uint256 lastResetTime;
        uint256 remainingAttempts;
        uint256[] battleTeam;
        bool hasTeam;
    }

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

    function getMockPlayerRank(address player) internal pure returns (uint256) {
        return uint256(uint160(player));
    }

    function isMockPlayer(address player) internal pure returns (bool) {
        if (player == address(0)) return true;
        uint256 mockRank = uint256(uint160(player));
        return mockRank >= 1 && mockRank <= 20;
    }

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