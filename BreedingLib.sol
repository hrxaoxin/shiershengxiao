// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BreedingLib
 * @dev NFT繁殖工具库，提供繁殖相关的计算函数
 *
 * 功能：
 * 1. 子代类型计算：根据父母类型生成子代的类型
 * 2. 成长值生成：根据种子生成子代的成长值
 * 3. 繁殖对验证：验证繁殖对是否有效
 * 4. 每日繁殖限制：检查用户是否超过每日繁殖次数限制
 *
 * 繁殖规则：
 * - 父母必须是同一生肖，不同性别
 * - 子代继承父母的生肖和属性
 * - 子代性别由随机数决定
 * - 成长值在10-100之间随机生成
 *
 * 冷却时间：
 * - 场内繁殖：3小时
 * - 市场繁殖：24小时
 */
library BreedingLib {
    using SafeERC20 for IERC20;

    struct BreedingPairData {
        uint256 fatherId;
        uint256 motherId;
        address maleOwner;
        address femaleOwner;
        uint256 maleCoOwnerId;
        uint256 femaleCoOwnerId;
        uint256 startTime;
        uint256 breedingType;
        uint256 status;
        uint256 childId;
        uint256 maleChildId;
        bool rewardsClaimed;
        uint256 cancelledAt;
    }

    function getChildZodiacType(uint256 fatherType, uint256 motherType, uint256 timestamp) internal pure returns (uint256) {
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "B: Z");
        uint256 seed = uint256(keccak256(abi.encodePacked(fatherType, motherType, timestamp)));
        uint256 childGender = seed % 2;
        uint256 element = fatherType / 24;
        return element * 24 + fatherZodiac * 2 + childGender;
    }

    function generateGrowth(uint256 seed, uint256 offset) internal pure returns (uint8) {
        return uint8((seed + offset) % 91 + 10);
    }

    function isValidBreedingPair(uint256 fatherType, uint256 motherType) internal pure returns (bool) {
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        uint256 fatherGender = fatherType % 2;
        uint256 motherGender = motherType % 2;
        return fatherZodiac == motherZodiac && fatherGender != motherGender;
    }

    function checkDailyBreedingLimit(
        address user,
        mapping(address => uint256) storage dailyBreedings,
        mapping(address => uint256) storage lastDay,
        uint256 maxDaily
    ) internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastDay[user] != currentDay) {
            dailyBreedings[user] = 0;
            lastDay[user] = currentDay;
        }
        require(dailyBreedings[user] < maxDaily, "B: D");
    }

    function updateDailyBreedingCount(
        address user,
        mapping(address => uint256) storage dailyBreedings,
        mapping(address => uint256) storage lastDay
    ) internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastDay[user] != currentDay) {
            dailyBreedings[user] = 1;
            lastDay[user] = currentDay;
        } else {
            dailyBreedings[user]++;
        }
    }

    function addActiveOrder(
        address user,
        uint256 pairId,
        mapping(address => uint256[]) storage activeOrders
    ) internal {
        uint256[] storage list = activeOrders[user];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == pairId) return;
        }
        list.push(pairId);
    }

    function removeActiveOrder(
        address user,
        uint256 pairId,
        mapping(address => uint256[]) storage activeOrders
    ) internal {
        uint256[] storage list = activeOrders[user];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == pairId) {
                for (uint256 j = i; j < list.length - 1; j++) {
                    list[j] = list[j + 1];
                }
                list.pop();
                break;
            }
        }
    }

    function getBreedingPairData(
        mapping(uint256 => mapping(uint256 => BreedingPairData)) storage breedingPairs,
        uint256 currentEpoch,
        uint256 pairId
    ) internal view returns (BreedingPairData memory) {
        return breedingPairs[currentEpoch][pairId];
    }

    function getUserActiveOrders(
        mapping(uint256 => mapping(address => uint256[])) storage userActiveOrderIds,
        mapping(uint256 => mapping(uint256 => BreedingPairData)) storage breedingPairs,
        uint256 currentEpoch,
        address user,
        uint256 activeStatus
    ) internal view returns (uint256[] memory) {
        uint256[] storage orderIds = userActiveOrderIds[currentEpoch][user];
        uint256 length = orderIds.length;
        uint256[] memory result = new uint256[](length);
        uint256 idx = 0;
        for (uint256 i = 0; i < length; i++) {
            if (breedingPairs[currentEpoch][orderIds[i]].status == activeStatus) {
                result[idx] = orderIds[i];
                idx++;
            }
        }
        assembly {
            mstore(result, idx)
        }
        return result;
    }

    function getUserBreedingStats(
        mapping(uint256 => mapping(address => uint256[])) storage userAllOrderIds,
        mapping(uint256 => mapping(uint256 => BreedingPairData)) storage breedingPairs,
        uint256 currentEpoch,
        address user,
        address nftMintContract
    ) internal view returns (uint256 totalPairs, uint256 activePairs, uint256 completedPairs, uint256 claimablePairs) {
        uint256[] storage orderIds = userAllOrderIds[currentEpoch][user];
        for (uint256 i = 0; i < orderIds.length; i++) {
            BreedingPairData memory pair = breedingPairs[currentEpoch][orderIds[i]];
            bool isRelated = (pair.maleOwner == user || pair.femaleOwner == user);
            if (!isRelated && nftMintContract != address(0)) {
                INFTMint nftMint = INFTMint(nftMintContract);
                if (pair.maleCoOwnerId != 0 && nftMint.ownerOf(pair.maleCoOwnerId) == user) isRelated = true;
                if (!isRelated && pair.femaleCoOwnerId != 0 && nftMint.ownerOf(pair.femaleCoOwnerId) == user) isRelated = true;
            }

            if (isRelated) {
                totalPairs++;
                if (pair.status == 0) activePairs++;
                else if (pair.status == 1) {
                    completedPairs++;
                    if (!pair.rewardsClaimed) claimablePairs++;
                }
            }
        }
    }

    function getBreedingPairWithCooldown(
        uint256 fatherId,
        uint256 motherId,
        uint256 pairStatus,
        uint256 pairStartTime,
        mapping(uint256 => mapping(uint256 => uint256)) storage breedingCooldowns,
        uint256 currentEpoch,
        uint256 cooldown,
        uint256 currentTimestamp
    ) internal view returns (
        uint256 fatherCooldown,
        uint256 motherCooldown,
        uint256 remainingTime
    ) {
        fatherCooldown = breedingCooldowns[currentEpoch][fatherId];
        motherCooldown = breedingCooldowns[currentEpoch][motherId];
        remainingTime = 0;
        if (pairStatus == 0 && pairStartTime > 0) {
            uint256 endTime = pairStartTime + cooldown;
            if (currentTimestamp < endTime) {
                remainingTime = endTime - currentTimestamp;
            }
        }
    }

    function calculateChildZodiacType(
        INFTMint nftMint,
        uint256 fatherId,
        uint256 motherId,
        uint256 randomSeed,
        uint256 currentTimestamp,
        address caller
    ) internal view returns (uint256) {
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "BC: PZM");

        uint256 seed = uint256(keccak256(abi.encodePacked(
            fatherId,
            motherId,
            randomSeed,
            currentTimestamp,
            block.number,
            block.prevrandao,
            tx.gasprice,
            caller
        )));
        uint256 fatherElement = fatherType / 24;
        uint256 motherElement = motherType / 24;
        uint256 inheritedElement = (seed % 2 == 0) ? fatherElement : motherElement;
        uint256 inheritedGender = (seed / 2) % 2;
        return inheritedElement * 24 + fatherZodiac * 2 + inheritedGender;
    }

    function burnFee(
        uint256 breedingType,
        address authorizer,
        uint256 selfBreedingFee,
        uint256 marketBreedingFee,
        address blackHole
    ) internal {
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "BC: TNS");
        uint256 fee = breedingType == 0 ? selfBreedingFee : marketBreedingFee;
        if (fee == 0) return;

        IERC20 token = IERC20(tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= fee, "BC: IBFB");

        token.safeTransfer(blackHole, fee);
    }

    function syncWeightAfterTransfer(
        address authorizer,
        address from,
        address to,
        uint256 tokenId
    ) internal {
        address nftDataContract = IAuthorizer(authorizer).getAddressByName("nftData");
        if (nftDataContract != address(0)) {
            try INFTDataInterface(nftDataContract).removeUserNFT(from, tokenId) {
            } catch {
            }
            try INFTDataInterface(nftDataContract).addUserNFT(to, tokenId) {
            } catch {
            }
        }

        address dividendManager = IAuthorizer(authorizer).getAddressByName("dividendManager");
        if (dividendManager != address(0)) {
            try IDividendManager(dividendManager).syncUserWeight(from) {
            } catch {
            }
            try IDividendManager(dividendManager).syncUserWeight(to) {
            } catch {
            }
        }

        address weightManager = IAuthorizer(authorizer).getAddressByName("weightManager");
        if (weightManager != address(0)) {
            try IWeightManager(weightManager).syncUserWeight(from) {
            } catch {
            }
            try IWeightManager(weightManager).syncUserWeight(to) {
            } catch {
            }
        }
    }
}