// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTQueryLib
 * @dev 查询/分页工具库，将大体积 view 函数从主合约中分离以减小 bytecode
 */
import "./NFTInterface.sol";
import "./NFTDataType.sol";

library NFTQueryLib {
    /**
     * @dev 分页获取用户持有的NFT列表
     */
    function getTokensByPage(address metadataContract, address owner, uint256 page, uint256 pageSize)
        public view returns (uint256[] memory, bool)
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
        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = arr[start + i];
        }

        return (result, end < total);
    }

    /**
     * @dev 分页获取用户持有的NFT详情列表
     */
    function getTokenDetailsByPage(address metadataContract, address owner, uint256 page, uint256 pageSize)
        public view returns (
            uint256[] memory,
            NFTDataTypes.ZodiacType[] memory,
            uint8[] memory,
            bool
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
        uint256[] memory tokenIds = new uint256[](count);
        NFTDataTypes.ZodiacType[] memory types = new NFTDataTypes.ZodiacType[](count);
        uint8[] memory levels = new uint8[](count);

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
     */
    function tokenOfOwnerByIndex(address metadataContract, address owner, uint256 index)
        public view returns (uint256)
    {
        INFTQueryData m = INFTQueryData(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        require(index < arr.length, "NFTMint: index out of bounds");
        return arr[index];
    }
}
