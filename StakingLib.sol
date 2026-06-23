// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StakingLib {
    uint256 public constant MAX_NFT_LEVEL = 5;
    
    function calculateNFTWeight(bool isRare, uint8 level) internal pure returns (uint256) {
        if (level == 0) return 0;
        
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        } else {
            uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        }
    }
    
    function getNormalNFTWeights() internal pure returns (uint256[5] memory) {
        return [uint256(1), 2, 6, 18, 66];
    }
    
    function getRareNFTWeights() internal pure returns (uint256[5] memory) {
        return [uint256(10), 12, 16, 28, 76];
    }
    
    function getNFTWeight(uint8 level, bool isRare) internal pure returns (uint256) {
        require(level >= 1 && level <= MAX_NFT_LEVEL, "Invalid level");
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            return weights[level - 1];
        } else {
            uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
            return weights[level - 1];
        }
    }
}