// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

library DividendManagerLib {
    uint256 internal constant SCALE = 1e18;
    uint256 internal constant MAX_NFT_LEVEL = 5;
    uint256 internal constant MAX_SNAPSHOTS = 100;

    function getActualIndex(uint256 logicalIndex, uint256 snapshotStartIndex, uint256 snapshotsLength) internal pure returns (uint256) {
        require(snapshotsLength > 0, "DM: Invalid index");
        return (snapshotStartIndex + logicalIndex) % snapshotsLength;
    }

    function calculatePendingDividend(uint256 userWeight, uint256 cumulativePerWeightDividend, uint256 userSnapshot) internal pure returns (uint256) {
        if (userWeight == 0) return 0;
        if (cumulativePerWeightDividend <= userSnapshot) return 0;
        return (userWeight * (cumulativePerWeightDividend - userSnapshot)) / SCALE;
    }

    function calculateDividendPerWeight(uint256 amount, uint256 totalWeight) internal pure returns (uint256) {
        if (totalWeight == 0) return 0;
        return (amount * SCALE) / totalWeight;
    }

    function addToDividendPool(
        uint256 amount,
        uint256 totalWeight,
        uint256 dividendPoolBalance,
        uint256 cumulativePerWeightDividend,
        DividendSnapshot[] storage snapshots,
        uint256 snapshotStartIndex
    ) internal returns (
        uint256 newDividendPoolBalance,
        uint256 newCumulativePerWeightDividend,
        uint256 newSnapshotStartIndex,
        uint256 perWeightDividendIncrement
    ) {
        newDividendPoolBalance = dividendPoolBalance + amount;
        require(newDividendPoolBalance >= dividendPoolBalance, "DM: Overflow");

        perWeightDividendIncrement = 0;
        if (totalWeight > 0) {
            if (amount > 0) {
                require(type(uint256).max / amount >= SCALE, "DM: Scale overflow");
            }
            perWeightDividendIncrement = (amount * SCALE) / totalWeight;
            newCumulativePerWeightDividend = cumulativePerWeightDividend + perWeightDividendIncrement;
            require(newCumulativePerWeightDividend >= cumulativePerWeightDividend, "DM: Cum overflow");
        } else {
            newCumulativePerWeightDividend = cumulativePerWeightDividend;
        }

        DividendSnapshot memory snapshot = DividendSnapshot({
            totalWeight: totalWeight,
            totalDividend: newDividendPoolBalance,
            perWeightDividend: perWeightDividendIncrement,
            timestamp: block.timestamp
        });

        if (snapshots.length < MAX_SNAPSHOTS) {
            snapshots.push(snapshot);
            newSnapshotStartIndex = snapshotStartIndex;
        } else {
            require(snapshotStartIndex < MAX_SNAPSHOTS, "DM: Invalid index");
            snapshots[snapshotStartIndex] = snapshot;
            newSnapshotStartIndex = (snapshotStartIndex + 1) % MAX_SNAPSHOTS;
        }
    }

    function getSnapshot(
        DividendSnapshot[] storage snapshots,
        uint256 snapshotStartIndex,
        uint256 index
    ) internal view returns (uint256 totalWeight, uint256 totalDividend, uint256 perWeightDividend, uint256 timestamp) {
        require(index < snapshots.length, "DM: Invalid index");
        uint256 actualIndex = getActualIndex(index, snapshotStartIndex, snapshots.length);
        DividendSnapshot storage snapshot = snapshots[actualIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend, snapshot.timestamp);
    }

    function getCurrentSnapshot(DividendSnapshot[] storage snapshots, uint256 snapshotStartIndex) internal view returns (uint256 totalWeight, uint256 totalDividend, uint256 perWeightDividend) {
        if (snapshots.length == 0) {
            return (0, 0, 0);
        }
        uint256 latestIndex = snapshots.length < MAX_SNAPSHOTS ? snapshots.length - 1 : (snapshotStartIndex + MAX_SNAPSHOTS - 1) % MAX_SNAPSHOTS;
        DividendSnapshot storage snapshot = snapshots[latestIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend);
    }

    function getSnapshotHistory(
        DividendSnapshot[] storage snapshots,
        uint256 snapshotStartIndex,
        uint256 startIndex,
        uint256 count
    ) internal view returns (DividendSnapshot[] memory) {
        uint256 totalCount = snapshots.length;
        require(startIndex < totalCount, "DM: Invalid start");
        require(count > 0, "DM: Invalid count");

        uint256 endIndex = startIndex + count;
        if (endIndex > totalCount) {
            endIndex = totalCount;
        }

        DividendSnapshot[] memory result = new DividendSnapshot[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 actualIndex = getActualIndex(i, snapshotStartIndex, totalCount);
            result[i - startIndex] = snapshots[actualIndex];
        }

        return result;
    }

    function getWeightConfig(address authorizer) internal view returns (uint256[5] memory normalWeights, uint256[5] memory rareWeights) {
        address nftDataAddr = IAuthorizer(authorizer).getAddressByName(\"nftData\");
        if (nftDataAddr != address(0)) {
            bool hasData = true;
            for (uint8 i = 0; i < 5; i++) {
                try INFTData(nftDataAddr).getWeightByLevel(i + 1, false) returns (uint256 w) {
                    if (w == 0) {
                        hasData = false;
                        break;
                    }
                    normalWeights[i] = w;
                } catch {
                    hasData = false;
                    break;
                }
            }
            if (hasData) {
                for (uint8 i = 0; i < 5; i++) {
                    try INFTData(nftDataAddr).getWeightByLevel(i + 1, true) returns (uint256 w) {
                        if (w == 0) {
                            hasData = false;
                            break;
                        }
                        rareWeights[i] = w;
                    } catch {
                        hasData = false;
                        break;
                    }
                }
            }
            if (hasData) return (normalWeights, rareWeights);
        }

        normalWeights = [uint256(1), 2, 6, 18, 66];
        rareWeights = [uint256(10), 12, 16, 28, 76];
    }

    function getRecentSnapshots(DividendSnapshot[] storage snapshots, uint256 snapshotStartIndex, uint256 count) internal view returns (DividendSnapshot[] memory) {
        if (snapshots.length == 0) {
            return new DividendSnapshot[](0);
        }

        uint256 totalCount = snapshots.length;
        if (count > totalCount) {
            count = totalCount;
        }

        DividendSnapshot[] memory result = new DividendSnapshot[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 logicalIndex = totalCount - count + i;
            uint256 actualIndex = (snapshotStartIndex + logicalIndex) % totalCount;
            result[i] = snapshots[actualIndex];
        }

        return result;
    }

    function getWeightByConfig(uint256 level, bool isRare, address authorizer) internal view returns (uint256) {
        if (level == 0) return 0;

        address nftDataAddr = IAuthorizer(authorizer).getAddressByName(\"nftData\");
        if (nftDataAddr != address(0)) {
            try INFTData(nftDataAddr).getWeightByLevel(uint8(level), isRare) returns (uint256 w) {
                if (w > 0) return w;
            } catch {
            }
        }

        return _fallbackWeight(level, isRare);
    }

    function _fallbackWeight(uint256 level, bool isRare) private pure returns (uint256) {
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        }

        uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
        if (level <= MAX_NFT_LEVEL) {
            return weights[level - 1];
        }
        return weights[MAX_NFT_LEVEL - 1];
    }
}
