// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTInterface
 * @dev NFT合约接口集合，供Staking、ArenaRanking等合约调用
 */

/**
 * @title INFTDataInterface
 * @dev NFT数据接口，提供NFT类型、等级、权重等数据查询
 */
interface INFTDataInterface {
    /**
     * @dev 获取NFT的生肖类型
     * @param tokenId NFT ID
     * @return 生肖类型值（编码了元素、生肖、性别信息）
     */
    function tokenType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT的等级
     * @param tokenId NFT ID
     * @return 等级值（1-100）
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 设置NFT的等级
     * @param tokenId NFT ID
     * @param level 新等级值
     */
    function setTokenLevel(uint256 tokenId, uint8 level) external;

    /**
     * @dev 计算用户的NFT总权重
     * @param user 用户地址
     * @return 权重值
     */
    function calcUserWeight(address user) external view returns (uint256);
}

/**
 * @title INFTMint
 * @dev NFT铸造接口，提供铸造和查询功能
 */
interface INFTMint {
    /**
     * @dev 铸造指定生肖类型的NFT
     * @param to 接收地址
     * @param zodiacType 生肖类型
     * @return 铸造的NFT ID
     */
    function mint(address to, uint256 zodiacType) external returns (uint256);

    /**
     * @dev 铸造普通NFT（随机生肖类型）
     * @param to 接收地址
     * @return 铸造的NFT ID
     */
    function mintNormal(address to) external returns (uint256);

    /**
     * @dev 铸造稀有NFT（随机稀有生肖类型）
     * @param to 接收地址
     * @return 铸造的NFT ID
     */
    function mintRare(address to) external returns (uint256);

    /**
     * @dev 获取NFT的生肖类型
     * @param tokenId NFT ID
     * @return 生肖类型值
     */
    function tokenType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT的等级
     * @param tokenId NFT ID
     * @return 等级值
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 获取NFT的成长值
     * @param tokenId NFT ID
     * @return 成长值（影响属性成长）
     */
    function tokenGrowth(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 获取NFT的所有者
     * @param tokenId NFT ID
     * @return 所有者地址
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev 检查NFT是否为稀有NFT
     * @param tokenId NFT ID
     * @return 是否为稀有NFT
     */
    function isRare(uint256 tokenId) external view returns (bool);

    /**
     * @dev 转移NFT（需授权）
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;
}

/**
 * @title INFT
 * @dev 标准NFT接口，提供所有权查询、转移等功能
 */
interface INFT {
    /**
     * @dev 查询NFT是否为稀有NFT
     * @param tokenId NFT ID
     * @return 是否为稀有NFT
     */
    function isRare(uint256 tokenId) external view returns (bool);

    /**
     * @dev 转移NFT（需授权）
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 安全转移NFT（需授权，支持接收合约）
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev 获取NFT的生肖类型
     * @param tokenId NFT ID
     * @return 生肖类型值
     */
    function tokenType(uint256 tokenId) external view returns (uint256);

    /**
     * @dev 获取NFT的等级
     * @param tokenId NFT ID
     * @return 等级值
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);

    /**
     * @dev 获取NFT的所有者
     * @param tokenId NFT ID
     * @return 所有者地址
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev 获取某用户的NFT余额
     * @param owner 用户地址
     * @return NFT数量
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev 按索引获取用户拥有的NFT ID
     * @param owner 用户地址
     * @param index 索引（从0开始）
     * @return NFT ID
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /**
     * @dev 获取用户所有NFT ID列表
     * @param owner 用户地址
     * @return NFT ID数组
     */
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);

    /**
     * @dev 检查是否授权给操作符
     * @param owner 所有者地址
     * @param operator 操作符地址
     * @return 是否授权
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}