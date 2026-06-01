// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTInterface
 * @dev NFT合约接口，供Staking、ArenaRanking等合约调用
 */
interface INFTDataInterface {
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function setTokenLevel(uint256 tokenId, uint8 level) external;
    function calcUserWeight(address user) external view returns (uint256);
}

interface INFTMint {
    function mint(address to, uint256 zodiacType) external returns (uint256);
    function mintNormal(address to) external returns (uint256);
    function mintRare(address to) external returns (uint256);
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function tokenGrowth(uint256 tokenId) external view returns (uint8);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isRare(uint256 tokenId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface INFT {
    /**
     * @dev 查询NFT是否为稀有NFT
     * @param tokenId NFT ID
     * @return 是否为稀有NFT
     */
    function isRare(uint256 tokenId) external view returns (bool);

    /**
     * @dev 转移NFT
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 获取NFT的tokenType
     */
    function tokenType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT的等级
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 获取NFT的所有者
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev 获取某用户的NFT余额
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev 按索引获取用户拥有的NFT ID
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /**
     * @dev 获取用户所有NFT ID列表
     */
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
}
