// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StakingLib {
    uint256 public constant MAX_NFT_LEVEL = 5;

    function getNormalNFTWeights() internal pure returns (uint256[5] memory) {
        return [uint256(1), 2, 6, 18, 66];
    }

    function getRareNFTWeights() internal pure returns (uint256[5] memory) {
        return [uint256(10), 12, 16, 28, 76];
    }

    function calculateNFTWeight(bool isRare, uint8 level) internal pure returns (uint256) {
        if (level == 0) return 0;
        uint256[5] memory weights = isRare ? getRareNFTWeights() : getNormalNFTWeights();
        if (level <= MAX_NFT_LEVEL) {
            return weights[level - 1];
        }
        return weights[MAX_NFT_LEVEL - 1];
    }
}