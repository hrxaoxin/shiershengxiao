// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

library BreedingLib {
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

    function syncWeightAfterTransfer(
        address authorizer,
        address from,
        address to,
        uint256 tokenId
    ) internal {
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        if (nftDataContract != address(0)) {
            INFTDataInterface(nftDataContract).removeUserNFT(from, tokenId);
            INFTDataInterface(nftDataContract).addUserNFT(to, tokenId);
        }
        
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        if (dividendManager != address(0)) {
            IDividendManager(dividendManager).syncUserWeight(from);
            IDividendManager(dividendManager).syncUserWeight(to);
        }
        
        address weightManager = IAuthorizer(authorizer).getWeightManager();
        if (weightManager != address(0)) {
            IWeightManager(weightManager).syncUserWeight(from);
            IWeightManager(weightManager).syncUserWeight(to);
        }
    }
}