// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ArenaRankingLib {
    uint256 public constant DAILY_ATTEMPTS = 5;
    uint256 public constant INITIAL_SCORE = 1000;
    
    function calculateDynamicPoints(uint256 mockIndex) internal pure returns (uint256) {
        if (mockIndex == 0) return 50;
        if (mockIndex <= 2) return 40;
        if (mockIndex <= 5) return 30;
        if (mockIndex <= 10) return 25;
        if (mockIndex <= 20) return 20;
        if (mockIndex <= 50) return 15;
        return 10;
    }

    function calculateMockLevel(uint256 mockIndex) internal pure returns (uint256) {
        if (mockIndex == 0) return 5;
        if (mockIndex <= 4) return 5;
        if (mockIndex <= 9) return 4;
        if (mockIndex <= 19) return 4;
        if (mockIndex <= 39) return 3;
        if (mockIndex <= 69) return 2;
        return 1;
    }

    function calculateMockGrowth(uint256 mockIndex) internal pure returns (uint256) {
        if (mockIndex == 0) return 80;
        if (mockIndex <= 4) return 78;
        if (mockIndex <= 9) return 72;
        if (mockIndex <= 19) return 66;
        if (mockIndex <= 39) return 58;
        if (mockIndex <= 69) return 48;
        if (mockIndex <= 99) return 38;
        return 28;
    }

    function calculateRareElementCount(uint256 mockIndex) internal pure returns (uint256) {
        if (mockIndex == 0) return 6;
        if (mockIndex <= 2) return 5;
        if (mockIndex <= 4) return 4;
        if (mockIndex <= 7) return 3;
        if (mockIndex <= 11) return 3;
        if (mockIndex <= 17) return 2;
        if (mockIndex <= 24) return 2;
        if (mockIndex <= 34) return 1;
        return 0;
    }

    function calculateRankReward(uint256 rank, uint256 pool, uint256 totalRealPlayers) internal pure returns (uint256) {
        if (totalRealPlayers == 0 || pool == 0 || rank > totalRealPlayers) return 0;

        if (totalRealPlayers <= 3) {
            return calculateRewardForSmallGroup(rank, pool, totalRealPlayers);
        }

        if (totalRealPlayers <= 10) {
            return calculateRewardForMediumGroup(rank, pool, totalRealPlayers);
        }

        return calculateRewardForLargeGroup(rank, pool, totalRealPlayers);
    }

    function calculateRewardForSmallGroup(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        if (totalPlayers == 1) {
            return pool;
        } else if (totalPlayers == 2) {
            if (rank == 1) return pool * 6000 / 10000;
            return pool * 4000 / 10000;
        } else {
            if (rank == 1) return pool * 4500 / 10000;
            if (rank == 2) return pool * 3000 / 10000;
            return pool * 2500 / 10000;
        }
    }

    function calculateRewardForMediumGroup(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        uint256[] memory ratios = new uint256[](10);
        ratios[0] = 2000;
        ratios[1] = 1500;
        ratios[2] = 1200;
        ratios[3] = 1000;
        ratios[4] = 800;
        ratios[5] = 700;
        ratios[6] = 600;
        ratios[7] = 500;
        ratios[8] = 400;
        ratios[9] = 300;

        uint256 sum = 0;
        for (uint256 i = 0; i < totalPlayers; i++) {
            sum += ratios[i];
        }

        return pool * ratios[rank - 1] / sum;
    }

    function calculateRewardForLargeGroup(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        uint256 guaranteedPool = pool * 1000 / 10000;
        uint256 tierPool = pool * 9000 / 10000;

        uint256 guaranteedReward = guaranteedPool / totalPlayers;
        uint256 tierReward = calculateTierBasedReward(rank, tierPool, totalPlayers);

        return guaranteedReward + tierReward;
    }

    function calculateTierBasedReward(uint256 rank, uint256 pool, uint256 totalPlayers) internal pure returns (uint256) {
        if (rank > totalPlayers || pool == 0) return 0;

        uint256 tier1Size = totalPlayers > 100 ? 100 : totalPlayers;
        uint256 tier2Size = totalPlayers > 500 ? 400 : (totalPlayers > 100 ? totalPlayers - 100 : 0);
        uint256 tier3Size = totalPlayers > 1000 ? 500 : (totalPlayers > 500 ? totalPlayers - 500 : 0);
        uint256 tier4Size = totalPlayers > 1000 ? totalPlayers - 1000 : 0;

        uint256 tier1Pool = pool * 5000 / 9000;
        uint256 tier2Pool = pool * 2500 / 9000;
        uint256 tier3Pool = pool * 1000 / 9000;
        uint256 tier4Pool = pool * 500 / 9000;

        if (rank <= tier1Size) {
            return calculateTier1Reward(rank, tier1Pool, tier1Size);
        } else if (rank <= tier1Size + tier2Size) {
            return calculateTier2Reward(rank - tier1Size, tier2Pool, tier2Size);
        } else if (rank <= tier1Size + tier2Size + tier3Size) {
            return calculateTier3Reward(rank - tier1Size - tier2Size, tier3Pool, tier3Size);
        } else {
            return calculateTier4Reward(rank - tier1Size - tier2Size - tier3Size, tier4Pool, tier4Size);
        }
    }

    function calculateTier1Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (rank == 1) return pool * 2500 / 5000;
        if (rank == 2) return pool * 1500 / 5000;
        if (rank == 3) return pool * 600 / 5000;

        uint256 remaining = pool * 400 / 5000;
        uint256 remainingPlayers = total > 3 ? total - 3 : 0;

        if (remainingPlayers == 0) return 0;

        uint256 baseWeight = 100;
        uint256 sumWeight = 0;

        for (uint256 i = 0; i < remainingPlayers; i++) {
            uint256 weight = baseWeight > i ? baseWeight - i : 10;
            sumWeight += weight;
        }

        uint256 currentWeight = baseWeight > (rank - 4) ? baseWeight - (rank - 4) : 10;

        return remaining * currentWeight / sumWeight;
    }

    function calculateTier2Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;

        uint256 baseWeight = 50;
        uint256 sumWeight = 0;

        for (uint256 i = 0; i < total; i++) {
            uint256 decay = i / 2;
            uint256 weight = baseWeight > decay ? baseWeight - decay : 10;
            sumWeight += weight;
        }

        uint256 currentDecay = (rank - 1) / 2;
        uint256 currentWeight = baseWeight > currentDecay ? baseWeight - currentDecay : 10;

        return pool * currentWeight / sumWeight;
    }

    function calculateTier3Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;

        uint256 weight = total - rank + 1;
        uint256 sumWeight = total * (total + 1) / 2;

        return pool * weight / sumWeight;
    }

    function calculateTier4Reward(uint256 rank, uint256 pool, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;

        return pool / total;
    }
}