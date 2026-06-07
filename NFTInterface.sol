// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTInterface
 * @dev NFT合约接口集合，供 Staking、ArenaRanking、WeightManager 等合约调用
 *
 * 本文件定义了系统中所有核心合约的接口，使跨合约调用类型安全、ABI 一致。
 * 所有接口均以 `I` 前缀命名（INFTDataInterface、INFTMint、INFT、IBattle、
 * IStaking、IBreeding、IERC20Extended），部署时业务合约通过这些接口与主合约交互。
 *
 * 接口一览：
 * - INFTDataInterface：NFT 元数据查询接口（类型、等级、铸造时间）
 * - INFTMint：NFT 铸造合约接口（mint、burn、查询供应量）
 * - INFT：完整的 ERC721 + 扩展接口（ownerOf、balanceOf、safeTransferFrom 等）
 * - IBattle：战斗合约接口（发起战斗、查询战绩）
 * - IStaking：NFT 质押合约接口（stake、unstake、claimReward）
 * - IBreeding：繁殖合约接口（createBreedingPair、completeBreeding）
 * - IERC20Extended：游戏代币合约接口（扩展 ERC20，支持 mint/burn 控制）
 *
 * 使用方法：
 *   import "./NFTInterface.sol";
 *   contract MyContract {
 *       INFT public nft;
 *       function doSomething(uint256 tokenId) external {
 *           address owner = nft.ownerOf(tokenId);
 *           ...
 *       }
 *   }
 *
 * 注意：修改接口签名会导致所有引用合约需要重新编译部署，
 * 建议新增功能时新增函数签名而不是修改已有签名。
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

/**
 * @title IBattle
 * @dev 战斗合约接口，提供战斗挑战功能
 */
interface IBattle {
    /**
     * @dev 发起挑战
     * @param challengerId 挑战者代表NFT ID
     * @param challengedId 被挑战者代表NFT ID
     * @param challengerTeam 挑战者队伍（6个NFT）
     * @param challengedTeam 被挑战者队伍（6个NFT）
     * @param challengedAddress 被挑战者地址（address(0)表示模拟战斗）
     * @return success 是否成功
     * @return winner 获胜方（1=挑战者，2=被挑战者，0=平局）
     */
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam,
        address challengedAddress
    ) external returns (bool, uint256);
}

/**
 * @title IStaking
 * @dev NFT质押合约接口，提供质押信息查询功能
 */
interface IStaking {
    /**
     * @dev 获取NFT质押信息
     * @param tokenId NFT ID
     * @return owner 所有者地址
     * @return stakeTime 质押时间
     * @return lastClaimTime 上次领取时间
     * @return accumulatedReward 累积奖励
     * @return isRare 是否稀有NFT
     */
    function stakingInfo(uint256 tokenId) external view returns (address, uint256, uint256, uint256, bool);
}

/**
 * @title IBreeding
 * @dev NFT繁殖合约接口，提供繁殖状态查询功能
 */
interface IBreeding {
    /**
     * @dev 检查NFT是否正在繁殖中
     * @param tokenId NFT ID
     * @return 是否正在繁殖中
     */
    function isNFTInActiveBreeding(uint256 tokenId) external view returns (bool);
}

/**
 * @title IERC20Extended
 * @dev 扩展ERC20代币接口，提供额外功能
 */
interface IERC20Extended {
    /**
     * @dev 转移代币
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 转移数量
     * @return 是否成功
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @dev 销毁代币
     * @param account 账户地址
     * @param amount 销毁数量
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @dev 查询授权额度
     * @param owner 所有者地址
     * @param spender 花费者地址
     * @return 授权额度
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev 安全转移代币
     * @param to 转入地址
     * @param amount 转移数量
     */
    function safeTransfer(address to, uint256 amount) external;

    /**
     * @dev 查询余额
     * @param account 账户地址
     * @return 余额
     */
    function balanceOf(address account) external view returns (uint256);
}