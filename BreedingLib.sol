// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BreedingLib
 * @dev 繁殖工具库，提供繁殖相关的计算和验证函数
 * 
 * 核心功能：
 * 1. 子代类型计算：根据父母类型计算子代的生肖类型
 * 2. 成长值生成：生成子代的成长值
 * 3. 繁殖配对验证：验证父母是否可以繁殖
 * 4. 每日繁殖限制：检查和更新每日繁殖次数
 * 5. 活跃订单管理：管理用户的活跃繁殖订单
 * 
 * 繁殖规则：
 * - 父母必须是同一生肖（鼠配鼠、牛配牛等）
 * - 父母必须性别不同（一公一母）
 * - 子代继承父母的生肖和属性
 * - 子代性别随机决定
 * 
 * 成长值范围：10-100（包含边界）
 */
library BreedingLib {
    /**
     * @dev 计算子代的生肖类型
     * @param fatherType 父NFT类型
     * @param motherType 母NFT类型
     * @param timestamp 繁殖时间戳（用于随机数生成）
     * @return 子代NFT类型
     */
    function getChildZodiacType(uint256 fatherType, uint256 motherType, uint256 timestamp) internal pure returns (uint256) {
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "B: Z");
        uint256 seed = uint256(keccak256(abi.encodePacked(fatherType, motherType, timestamp)));
        uint256 childGender = seed % 2;
        uint256 element = fatherType / 24;
        return element * 24 + fatherZodiac * 2 + childGender;
    }

    /**
     * @dev 生成子代成长值
     * @param seed 随机种子
     * @param offset 偏移量（用于生成不同的成长值）
     * @return 成长值（10-100）
     */
    function generateGrowth(uint256 seed, uint256 offset) internal pure returns (uint8) {
        return uint8((seed + offset) % 91 + 10);
    }

    /**
     * @dev 验证繁殖配对是否有效
     * @param fatherType 父NFT类型
     * @param motherType 母NFT类型
     * @return 是否有效
     */
    function isValidBreedingPair(uint256 fatherType, uint256 motherType) internal pure returns (bool) {
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        uint256 fatherGender = fatherType % 2;
        uint256 motherGender = motherType % 2;
        return fatherZodiac == motherZodiac && fatherGender != motherGender;
    }

    /**
     * @dev 检查每日繁殖限制
     * @param user 用户地址
     * @param dailyBreedings 每日繁殖次数映射
     * @param lastDay 上次繁殖日期映射
     * @param maxDaily 每日最大繁殖次数
     */
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

    /**
     * @dev 更新每日繁殖次数计数
     * @param user 用户地址
     * @param dailyBreedings 每日繁殖次数映射
     * @param lastDay 上次繁殖日期映射
     */
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

    /**
     * @dev 添加活跃繁殖订单
     * @param user 用户地址
     * @param pairId 繁殖配对ID
     * @param activeOrders 活跃订单映射
     */
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

    /**
     * @dev 移除活跃繁殖订单
     * @param user 用户地址
     * @param pairId 繁殖配对ID
     * @param activeOrders 活跃订单映射
     */
    function removeActiveOrder(
        address user,
        uint256 pairId,
        mapping(address => uint256[]) storage activeOrders
    ) internal {
        uint256[] storage list = activeOrders[user];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == pairId) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }
}
}