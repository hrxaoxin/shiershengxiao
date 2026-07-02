// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "./AddressLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";

library DividendManagerLib {
    uint256 internal constant SCALE = 1e18;
    uint256 internal constant MAX_NFT_LEVEL = 5;
    uint256 internal constant MAX_SNAPSHOTS = 100;

    error DM_Lib_InvalidIndex();
    error DM_Lib_Overflow();
    error DM_Lib_ScaleOverflow();
    error DM_Lib_CumOverflow();
    error DM_Lib_InvalidStart();
    error DM_Lib_InvalidCount();
    error DM_Lib_PendingOverflow();

    function getActualIndex(uint256 logicalIndex, uint256 snapshotStartIndex, uint256 snapshotsLength) internal pure returns (uint256) {
        if (snapshotsLength == 0) revert DM_Lib_InvalidIndex();
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
        if (newDividendPoolBalance < dividendPoolBalance) revert DM_Lib_Overflow();

        perWeightDividendIncrement = 0;
        if (totalWeight > 0) {
            if (amount > 0) {
                if (type(uint256).max / amount < SCALE) revert DM_Lib_ScaleOverflow();
            }
            perWeightDividendIncrement = (amount * SCALE) / totalWeight;
            newCumulativePerWeightDividend = cumulativePerWeightDividend + perWeightDividendIncrement;
            if (newCumulativePerWeightDividend < cumulativePerWeightDividend) revert DM_Lib_CumOverflow();
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
            if (snapshotStartIndex >= MAX_SNAPSHOTS) revert DM_Lib_InvalidIndex();
            snapshots[snapshotStartIndex] = snapshot;
            newSnapshotStartIndex = (snapshotStartIndex + 1) % MAX_SNAPSHOTS;
        }
    }

    function getSnapshot(
        DividendSnapshot[] storage snapshots,
        uint256 snapshotStartIndex,
        uint256 index
    ) internal view returns (uint256 totalWeight, uint256 totalDividend, uint256 perWeightDividend, uint256 timestamp) {
        if (index >= snapshots.length) revert DM_Lib_InvalidIndex();
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
        if (startIndex >= totalCount) revert DM_Lib_InvalidStart();
        if (count == 0) revert DM_Lib_InvalidCount();

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
        address nftDataAddr = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_DATA);
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

        address nftDataAddr = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_DATA);
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

    function settlePendingDividend(
        mapping(uint256 => mapping(address => uint256)) storage pendingDividends,
        uint256 currentEpoch,
        address user,
        uint256 userWeight,
        uint256 cumulativePerWeightDividend,
        uint256 userCumulativeSnapshot
    ) internal {
        if (userWeight == 0 || cumulativePerWeightDividend <= userCumulativeSnapshot) {
            return;
        }
        uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshot;
        uint256 weightedProduct = userWeight * cumulativeDiff;
        if (weightedProduct / userWeight != cumulativeDiff) revert DM_Lib_PendingOverflow();
        uint256 pending = weightedProduct / SCALE;
        uint256 newPending = pendingDividends[currentEpoch][user] + pending;
        if (newPending < pendingDividends[currentEpoch][user]) revert DM_Lib_PendingOverflow();
        pendingDividends[currentEpoch][user] = newPending;
    }

    function autoSyncDividendPool(
        address authorizer,
        uint256 lastAutoSyncTime,
        uint256 autoSyncInterval,
        uint256 lastSyncedBalance,
        uint256 totalWeight,
        uint256 dividendPoolBalance,
        uint256 cumulativePerWeightDividend,
        DividendSnapshot[] storage snapshots,
        uint256 snapshotStartIndex
    ) internal returns (
        uint256 newLastSyncedBalance,
        uint256 newLastAutoSyncTime,
        uint256 newDividendPoolBalance,
        uint256 newCumulativePerWeightDividend,
        uint256 newSnapshotStartIndex
    ) {
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        if (tokenContract == address(0)) {
            return (lastSyncedBalance, lastAutoSyncTime, dividendPoolBalance, cumulativePerWeightDividend, snapshotStartIndex);
        }

        if (block.timestamp < lastAutoSyncTime + autoSyncInterval) {
            return (lastSyncedBalance, lastAutoSyncTime, dividendPoolBalance, cumulativePerWeightDividend, snapshotStartIndex);
        }

        IERC20 token = IERC20(tokenContract);
        uint256 currentBalance = token.balanceOf(address(this));

        if (currentBalance <= lastSyncedBalance) {
            return (currentBalance, block.timestamp, dividendPoolBalance, cumulativePerWeightDividend, snapshotStartIndex);
        }

        uint256 newFunds = currentBalance - lastSyncedBalance;
        (newDividendPoolBalance, newCumulativePerWeightDividend, newSnapshotStartIndex, ) =
            addToDividendPool(newFunds, totalWeight, dividendPoolBalance, cumulativePerWeightDividend, snapshots, snapshotStartIndex);

        return (currentBalance, block.timestamp, newDividendPoolBalance, newCumulativePerWeightDividend, newSnapshotStartIndex);
    }
}
