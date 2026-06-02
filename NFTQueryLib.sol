// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "./NFTDataType.sol";

/**
 * @title NFTQueryLib
 * @dev 查询/分页工具库，将大体积 view 函数从主合约中分离以减小 bytecode
 *
 * 功能：
 * 1. 分页获取用户NFT列表
 * 2. 分页获取用户NFT详情（包含类型和等级）
 * 3. 按索引获取用户NFT
 *
 * 设计目的：
 * - 减小主合约的字节码大小
 * - 提高查询效率
 * - 支持前端分页展示
 */
library NFTQueryLib {
    interface INFTQueryData {
        function userAllTokens(address owner) external view returns (uint256[] memory);
        function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType);
        function tokenLevel(uint256 tokenId) external view returns (uint8);
    }

    /**
     * @dev 分页获取用户持有的NFT列表
     * @param metadataContract 元数据合约地址
     * @param owner 用户地址
     * @param page 页码（从0开始）
     * @param pageSize 每页大小
     * @return tokenIds NFT ID数组
     * @return hasMore 是否还有更多数据
     */
    function getTokensByPage(address metadataContract, address owner, uint256 page, uint256 pageSize)
        public view returns (uint256[] memory tokenIds, bool hasMore)
    {
        INFTQueryData m = INFTQueryData(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        uint256 total = arr.length;
        uint256 start = page * pageSize;

        if (start >= total) {
            return (new uint256[](0), false);
        }

        uint256 end = start + pageSize;
        if (end > total) {
            end = total;
        }

        uint256 count = end - start;
        tokenIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            tokenIds[i] = arr[start + i];
        }

        return (tokenIds, end < total);
    }

    /**
     * @dev 分页获取用户持有的NFT详情列表
     * @param metadataContract 元数据合约地址
     * @param owner 用户地址
     * @param page 页码（从0开始）
     * @param pageSize 每页大小
     * @return tokenIds NFT ID数组
     * @return types 生肖类型数组
     * @return levels 等级数组
     * @return hasMore 是否还有更多数据
     */
    function getTokenDetailsByPage(address metadataContract, address owner, uint256 page, uint256 pageSize)
        public view returns (
            uint256[] memory tokenIds,
            NFTDataTypes.ZodiacType[] memory types,
            uint8[] memory levels,
            bool hasMore
        )
    {
        INFTQueryData m = INFTQueryData(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        uint256 total = arr.length;
        uint256 start = page * pageSize;

        if (start >= total) {
            return (new uint256[](0), new NFTDataTypes.ZodiacType[](0), new uint8[](0), false);
        }

        uint256 end = start + pageSize;
        if (end > total) {
            end = total;
        }

        uint256 count = end - start;
        tokenIds = new uint256[](count);
        types = new NFTDataTypes.ZodiacType[](count);
        levels = new uint8[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 tid = arr[start + i];
            tokenIds[i] = tid;
            types[i] = m.tokenType(tid);
            levels[i] = m.tokenLevel(tid);
        }

        return (tokenIds, types, levels, end < total);
    }

    /**
     * @dev 按索引获取用户持有的NFT
     * @param metadataContract 元数据合约地址
     * @param owner 用户地址
     * @param index 索引（从0开始）
     * @return uint256 NFT ID
     */
    function tokenOfOwnerByIndex(address metadataContract, address owner, uint256 index)
        public view returns (uint256)
    {
        INFTQueryData m = INFTQueryData(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        require(index < arr.length, "NFTQueryLib: Index out of bounds");
        return arr[index];
    }
}
