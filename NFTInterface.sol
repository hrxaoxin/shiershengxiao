// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";

/**
 * @title ITokenBurner
 * @dev 代币销毁合约接口
 */
interface ITokenBurner {
    /**
     * @dev 销毁普通铸造费用的代币
     * @return bool 是否成功
     */
    function burnTokenForMint() external returns (bool);
    
    /**
     * @dev 销毁稀有铸造费用的代币
     * @return bool 是否成功
     */
    function burnTokenForRareMint() external returns (bool);
    
    /**
     * @dev 销毁代币并铸造
     * @param user 用户地址
     * @param isRare 是否稀有铸造
     * @return bool 是否成功
     */
    function burnAndMint(address user, bool isRare) external returns (bool);
    
    /**
     * @dev 获取普通铸造费用
     * @return uint256 费用（代币数量）
     */
    function normalMintCost() external view returns (uint256);
    
    /**
     * @dev 获取稀有铸造费用
     * @return uint256 费用（代币数量）
     */
    function rareMintCost() external view returns (uint256);
    
    /**
     * @dev 设置授权的NFT合约地址
     * @param nftContract NFT合约地址
     */
    function setAuthorizedNFTContract(address nftContract) external;
    
    /**
     * @dev 设置代币合约地址
     * @param tokenContract 代币合约地址
     */
    function setTokenContract(address tokenContract) external;
}

/**
 * @title IToken
 * @dev ERC20代币接口
 */
interface IToken {
    /**
     * @dev 转账
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 数量
     * @return bool 是否成功
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    /**
     * @dev 获取余额
     * @param account 账户地址
     * @return uint256 余额
     */
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title IPriceOracle
 * @dev 价格预言机接口
 */
interface IPriceOracle {
    /**
     * @dev 获取代币价格（USD）
     * @return uint256 价格（精度18位）
     */
    function getTokenPriceInUSD() external view returns (uint256);
    
    /**
     * @dev 获取价格更新时间戳
     * @return uint256 时间戳
     */
    function getPriceTimestamp() external view returns (uint256);
}

/**
 * @title IPancakeSwapPair
 * @dev PancakeSwap流动性池接口
 */
interface IPancakeSwapPair {
    /**
     * @dev 获取储备量
     * @return reserve0 token0储备量
     * @return reserve1 token1储备量
     * @return blockTimestampLast 最后更新时间戳
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    
    /**
     * @dev 获取token0地址
     * @return address token0地址
     */
    function token0() external view returns (address);
    
    /**
     * @dev 获取token1地址
     * @return address token1地址
     */
    function token1() external view returns (address);
}

/**
 * @title IBEP20
 * @dev BEP20代币接口（获取小数位数）
 */
interface IBEP20 {
    /**
     * @dev 获取小数位数
     * @return uint8 小数位数
     */
    function decimals() external view returns (uint8);
}

/**
 * @title IERC2981
 * @dev ERC2981版税标准接口
 */
interface IERC2981 {
    /**
     * @dev 获取版税信息
     * @param tokenId NFT ID
     * @param salePrice 销售价格
     * @return receiver 版税接收地址
     * @return royaltyAmount 版税金额
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

/**
 * @title INFTMint
 * @dev NFT铸造合约接口
 */
interface INFTMint {
    /**
     * @dev 获取NFT类型
     * @param tokenId NFT ID
     * @return NFTDataTypes.ZodiacType 生肖类型
     */
    function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType);
    
    /**
     * @dev 获取NFT等级
     * @param tokenId NFT ID
     * @return uint8 等级（1-5）
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    
    /**
     * @dev 获取NFT成长值
     * @param tokenId NFT ID
     * @return uint256 成长值(10-100)
     */
    function tokenGrowthValue(uint256 tokenId) external view returns (uint256);
    
    /**
     * @dev 普通铸造
     * @param to 接收地址
     * @return uint256 新NFT ID
     */
    function mintNormal(address to) external returns (uint256);
    
    /**
     * @dev 稀有铸造
     * @param to 接收地址
     * @return uint256 新NFT ID
     */
    function mintRare(address to) external returns (uint256);
    
    /**
     * @dev 指定类型铸造
     * @param to 接收地址
     * @param zodiacType 指定的生肖类型
     * @return uint256 新NFT ID
     */
    function mintCustom(address to, NFTDataTypes.ZodiacType zodiacType) external returns (uint256);
    
    /**
     * @dev 铸造繁殖结果
     * @param to 接收地址
     * @param zodiacType 生肖类型
     * @return uint256 新NFT ID
     */
    function mintBreedResult(address to, NFTDataTypes.ZodiacType zodiacType) external returns (uint256);
    
    /**
     * @dev 使用NFT升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithNFT(uint256 tokenId) external returns (uint8);
    
    /**
     * @dev 使用代币升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithToken(uint256 tokenId) external returns (uint8);
    
    /**
     * @dev 使用USD价值升级
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8);
    
    /**
     * @dev 获取NFT所有者
     * @param tokenId NFT ID
     * @return address 所有者地址
     */
    function ownerOf(uint256 tokenId) external view returns (address);
    
    /**
     * @dev 安全转移NFT
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    
    /**
     * @dev 检查是否已授权全部NFT
     * @param owner 所有者地址
     * @param operator 操作方地址
     * @return bool 是否已授权
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    
    /**
     * @dev 获取单个NFT的授权地址
     * @param tokenId NFT ID
     * @return address 授权地址
     */
    function getApproved(uint256 tokenId) external view returns (address);
    
    /**
     * @dev 授权单个NFT
     * @param to 授权地址
     * @param tokenId NFT ID
     */
    function approve(address to, uint256 tokenId) external;
    
    /**
     * @dev 检查是否支持接口
     * @param interfaceId 接口ID
     * @return bool 是否支持
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    
    /**
     * @dev 转移NFT
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;
    
    /**
     * @dev 设置合约地址
     * @param tb TokenBurner地址
     * @param rm RewardManager地址
     */
    function setAddresses(address tb, address rm) external;
    
    /**
     * @dev 设置元数据合约地址
     * @param a 元数据合约地址
     */
    function setMetadataContract(address a) external;
    
    /**
     * @dev 设置代币合约地址
     * @param a 代币合约地址
     */
    function setTokenContract(address a) external;
    
    /**
     * @dev 设置繁殖合约地址
     * @param a 繁殖合约地址
     */
    function setBreedingContract(address a) external;
    
    /**
     * @dev 获取用户权重缓存
     * @param user 用户地址
     * @return uint256 用户权重缓存值
     */
    function calcUserWeight(address user) external view returns (uint256);
}

/**
 * @title IRewardManager
 * @dev 奖励管理合约接口
 */
interface IRewardManager {
    /**
     * @dev 获取版税钱包地址
     * @return address 版税钱包地址
     */
    function royaltyWallet() external view returns (address);
    
    /**
     * @dev 获取版税信息
     * @param tokenId NFT ID
     * @param salePrice 销售价格
     * @return address 版税接收地址
     * @return uint256 版税金额
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256);
    
    /**
     * @dev 领取分红
     */
    function claimDividend() external;
    
    /**
     * @dev 获取用户持有指定类型卡牌数量
     * @param user 用户地址
     * @param zodiacType 生肖类型
     * @return uint256 卡牌数量
     */
    function cardCount(address user, NFTDataTypes.ZodiacType zodiacType) external view returns (uint256);
    
    /**
     * @dev 外部更新用户卡牌信息
     * @param user 用户地址
     * @param zodiacType 生肖类型
     * @param count 卡牌数量
     * @return bool 是否成功
     */
    function updateCardExternal(address user, NFTDataTypes.ZodiacType zodiacType, uint256 count) external returns (bool);
    
    /**
     * @dev 原子性增加卡牌计数（解决时序问题）
     * @param user 用户地址
     * @param zodiacType 生肖类型
     * @return bool 是否成功
     */
    function addCardCount(address user, NFTDataTypes.ZodiacType zodiacType) external returns (bool);
    
    /**
     * @dev 原子性减少卡牌计数（解决时序问题）
     * @param user 用户地址
     * @param zodiacType 生肖类型
     * @return bool 是否成功
     */
    function subCardCount(address user, NFTDataTypes.ZodiacType zodiacType) external returns (bool);
    
    /**
     * @dev 设置授权的NFT合约
     * @param nft NFT合约地址
     * @param ok 是否授权
     */
    function setAuthorizedNFTContract(address nft, bool ok) external;
    
    /**
     * @dev 设置NFT合约地址
     * @param _newNFTContract 新NFT合约地址
     */
    function setNFTContract(address _newNFTContract) external;
    
    /**
     * @dev 设置NFT数据合约地址
     * @param _nftDataContract NFT数据合约地址
     */
    function setNFTDataContract(address _nftDataContract) external;
    
    /**
     * @dev 设置NFT质押合约地址
     * @param _stakingContract 质押合约地址
     */
    function setStakingContract(address _stakingContract) external;
    
    /**
     * @dev 设置代币质押合约地址
     * @param _tokenStakingContract 代币质押合约地址
     */
    function setTokenStakingContract(address _tokenStakingContract) external;
    
    /**
     * @dev 设置竞技场排名合约地址
     * @param _arenaContract 竞技场合约地址
     */
    function setArenaContract(address _arenaContract) external;
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external;
}

/**
 * @title INFTDataInterface
 * @dev NFT数据合约接口
 */
interface INFTDataInterface {
    /**
     * @dev 获取NFT信息
     * @param tokenId NFT ID
     * @return NFTDataTypes.NFTInfo NFT信息结构体
     */
    function getNFTInfo(uint256 tokenId) external view returns (NFTDataTypes.NFTInfo memory);
    
    /**
     * @dev 设置NFT信息
     * @param tokenId NFT ID
     * @param info NFT信息结构体
     */
    function setNFTInfo(uint256 tokenId, NFTDataTypes.NFTInfo memory info) external;
    
    /**
     * @dev 清除NFT信息
     * @param tokenId NFT ID
     */
    function clearNFTInfo(uint256 tokenId) external;
    
    /**
     * @dev 获取属性名称
     * @param element 属性类型
     * @return string memory 属性名称
     */
    function getElementName(NFTDataTypes.ElementType element) external view returns (string memory);
    
    /**
     * @dev 获取生肖名称
     * @param zodiac 生肖类型
     * @return string memory 生肖名称
     */
    function getZodiacName(NFTDataTypes.BaseZodiac zodiac) external view returns (string memory);
    
    /**
     * @dev 获取性别名称
     * @param gender 性别类型
     * @return string memory 性别名称
     */
    function getGenderName(NFTDataTypes.GenderType gender) external view returns (string memory);
    
    /**
     * @dev 获取完整类型名称
     * @param zodiacType 生肖类型
     * @return string memory 完整名称
     */
    function getFullTypeName(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    
    /**
     * @dev 获取集合名称
     * @return string memory 集合名称
     */
    function collName() external pure returns (string memory);
    
    /**
     * @dev 获取集合描述
     * @return string memory 集合描述
     */
    function collDesc() external pure returns (string memory);
    
    /**
     * @dev 获取集合图片
     * @return string memory 图片URL
     */
    function collImage() external pure returns (string memory);
    
    /**
     * @dev 获取卖家费用比例
     * @return uint256 费用比例（千分比）
     */
    function sellerFeeBasisPoints() external pure returns (uint256);
    
    /**
     * @dev 获取卡牌名称
     * @param zodiacType 生肖类型
     * @return string memory 卡牌名称
     */
    function getCardName(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    
    /**
     * @dev 获取卡牌描述
     * @param zodiacType 生肖类型
     * @return string memory 卡牌描述
     */
    function getCardDesc(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    
    /**
     * @dev 获取卡牌图片
     * @param zodiacType 生肖类型
     * @return string memory 图片URL
     */
    function getCardImage(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    
    /**
     * @dev 获取NFT类型
     * @param tokenId NFT ID
     * @return NFTDataTypes.ZodiacType 生肖类型
     */
    function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType);
    
    /**
     * @dev 获取NFT等级
     * @param tokenId NFT ID
     * @return uint8 等级
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    
    /**
     * @dev 获取NFT成长值
     * @param tokenId NFT ID
     * @return uint256 成长值(10-100)
     */
    function tokenGrowthValue(uint256 tokenId) external view returns (uint256);
    
    /**
     * @dev 获取用户持有的指定类型NFT列表
     * @param user 用户地址
     * @param type_ 生肖类型
     * @return uint256[] NFT ID列表
     */
    function userTokens(address user, NFTDataTypes.ZodiacType type_) external view returns (uint256[] memory);
    
    /**
     * @dev 获取用户持有的所有NFT列表
     * @param user 用户地址
     * @return uint256[] NFT ID列表
     */
    function userAllTokens(address user) external view returns (uint256[] memory);
    
    /**
     * @dev 获取用户权重缓存
     * @param user 用户地址
     * @return uint256 权重值
     */
    function userWeightCache(address user) external view returns (uint256);
    
    /**
     * @dev 设置NFT类型
     * @param tokenId NFT ID
     * @param type_ 生肖类型
     */
    function setTokenType(uint256 tokenId, NFTDataTypes.ZodiacType type_) external;
    
    /**
     * @dev 设置NFT等级
     * @param tokenId NFT ID
     * @param level 等级
     */
    function setTokenLevel(uint256 tokenId, uint8 level) external;
    
    /**
     * @dev 设置NFT成长值
     * @param tokenId NFT ID
     * @param growth 成长值（10-100）
     */
    function setTokenGrowthValue(uint256 tokenId, uint256 growth) external;
    
    /**
     * @dev 添加用户NFT
     * @param user 用户地址
     * @param type_ 生肖类型
     * @param tokenId NFT ID
     */
    function addUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external;
    
    /**
     * @dev 移除用户NFT
     * @param user 用户地址
     * @param type_ 生肖类型
     * @param tokenId NFT ID
     */
    function removeUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external;
    
    /**
     * @dev 更新用户权重缓存
     * @param user 用户地址
     * @param weight 权重值
     */
    function updateUserWeightCache(address user, uint256 weight) external;
    
    /**
     * @dev 统一的权重更新函数（计算并更新用户权重）
     * @param user 用户地址
     * @param level NFT等级
     * @param add 是否增加（true增加，false减少）
     * @param element 属性类型
     */
    function updateUserWeight(address user, uint8 level, bool add, NFTDataTypes.ElementType element) external;
    
    /**
     * @dev 直接计算用户权重（遍历所有NFT）
     * @param user 用户地址
     * @return uint256 用户权重
     */
    function calcUserWeight(address user) external view returns (uint256);
    
    /**
     * @dev 获取用户持有的指定类型NFT数量
     * @param user 用户地址
     * @param type_ 生肖类型
     * @return uint256 数量
     */
    function getUserTokenCount(address user, NFTDataTypes.ZodiacType type_) external view returns (uint256);
    
    /**
     * @dev 获取用户持有的NFT总数
     * @param user 用户地址
     * @return uint256 总数
     */
    function getUserTotalTokenCount(address user) external view returns (uint256);
    
    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者
     */
    function initialize(address initialOwner) external;
    
    /**
     * @dev 设置授权的NFT合约
     * @param nftContract NFT合约地址
     */
    function setAuthorizedNFTContract(address nftContract) external;
    
    /**
     * @dev 检查用户是否有资格（持有NFT）
     * @param user 用户地址
     * @return bool 是否有资格
     */
    function hasEligibility(address user) external view returns (bool);
    
    /**
     * @dev 获取用户持有的NFT类型列表
     * @param user 用户地址
     * @return NFTDataTypes.ZodiacType[] 类型列表
     */
    function getUserTokenTypes(address user) external view returns (NFTDataTypes.ZodiacType[] memory);
}

/**
 * @title INFTTrading
 * @dev NFT交易合约接口
 */
interface INFTTrading {
    /**
     * @dev 设置NFT合约地址
     * @param newNFTContract NFT合约地址
     */
    function setNFTContract(address newNFTContract) external;
    
    /**
     * @dev 设置奖励管理器地址
     * @param newRewardManager 奖励管理器地址
     */
    function setRewardManager(address newRewardManager) external;
}

/**
 * @title IBreeding
 * @dev 繁殖合约接口
 */
interface IBreeding {
    /**
     * @dev 设置NFT合约地址
     * @param nftContract NFT合约地址
     */
    function setNFTContract(address nftContract) external;
    
    /**
     * @dev 开始自繁殖
     * @param tokenId1 第一个NFT ID
     * @param tokenId2 第二个NFT ID
     */
    function startSelfBreeding(uint256 tokenId1, uint256 tokenId2) external;
    
    /**
     * @dev 上架繁殖
     * @param tokenId NFT ID
     */
    function listForBreeding(uint256 tokenId) external;
    
    /**
     * @dev 加入繁殖
     * @param orderId 订单ID
     * @param tokenId NFT ID
     */
    function joinBreeding(uint256 orderId, uint256 tokenId) external;
    
    /**
     * @dev 完成自繁殖
     * @param orderId 订单ID
     */
    function completeSelfBreeding(uint256 orderId) external;
    
    /**
     * @dev 完成市场繁殖
     * @param orderId 订单ID
     */
    function completeMarketBreeding(uint256 orderId) external;
    
    /**
     * @dev 取消繁殖上架
     * @param orderId 订单ID
     */
    function cancelBreedingListing(uint256 orderId) external;
    
    /**
     * @dev 获取市场繁殖订单列表
     * @return uint256[] 订单ID列表
     */
    function getMarketBreedingOrders() external view returns (uint256[] memory);
    
    /**
     * @dev 获取用户繁殖订单列表
     * @param user 用户地址
     * @return uint256[] 订单ID列表
     */
    function getUserBreedingOrders(address user) external view returns (uint256[] memory);
    
    /**
     * @dev 获取繁殖订单详情
     * @param orderId 订单ID
     * @return address owner1
     * @return address owner2
     * @return uint256 tokenId1
     * @return uint256 tokenId2
     * @return uint256 startTime
     * @return bool completed
     * @return bool cancelled
     */
    function breedingOrders(uint256 orderId) external view returns (address, address, uint256, uint256, uint256, bool, bool);
    
    /**
     * @dev 设置NFT合约地址
     * @param nftContract NFT合约地址
     */
    function setNFTContract(address nftContract) external;
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external;
    
    /**
     * @dev 设置竞技场排名合约地址
     * @param _arenaRankingContract 竞技场排名合约地址
     */
    function setArenaRankingContract(address _arenaRankingContract) external;
}

/**
 * @title IStaking
 * @dev NFT质押合约接口
 */
interface IStaking {
    /**
     * @dev 设置NFT合约地址
     * @param nftContract NFT合约地址
     */
    function setNFTContract(address nftContract) external;
    
    /**
     * @dev 设置代币合约地址
     * @param tokenContract 代币合约地址
     */
    function setTokenContract(address tokenContract) external;
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external;
    
    /**
     * @dev 设置竞技场排名合约地址
     * @param _arenaRankingContract 竞技场排名合约地址
     */
    function setArenaRankingContract(address _arenaRankingContract) external;
}

/**
 * @title ITokenStaking
 * @dev 代币质押合约接口
 */
interface ITokenStaking {
    /**
     * @dev 设置代币合约地址
     * @param tokenContract 代币合约地址
     */
    function setTokenContract(address tokenContract) external;
    
    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external;
}

/**
 * @title INFTUpdate
 * @dev NFT升级合约接口
 */
interface INFTUpdate {
    /**
     * @dev 使用NFT升级
     * @param tokenId NFT ID
     * @return uint8 新等级
     */
    function upgradeWithNFT(uint256 tokenId) external returns (uint8);
    
    /**
     * @dev 使用代币升级
     * @param tokenId NFT ID
     * @return uint8 新等级
     */
    function upgradeWithToken(uint256 tokenId) external returns (uint8);
    
    /**
     * @dev 使用USD价值升级
     * @param tokenId NFT ID
     * @return uint8 新等级
     */
    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8);
    
    /**
     * @dev 从PancakeSwap获取代币价格
     * @return uint256 价格（精度18位）
     */
    function getTokenPriceFromPancakeSwap() external view returns (uint256);
    
    /**
     * @dev 设置NFT合约地址
     * @param a NFT合约地址
     */
    function setNFTContract(address a) external;
    
    /**
     * @dev 设置元数据合约地址
     * @param a 元数据合约地址
     */
    function setMetadataContract(address a) external;
    
    /**
     * @dev 设置代币合约地址
     * @param a 代币合约地址
     */
    function setTokenContract(address a) external;
    
    /**
     * @dev 设置PancakeSwap流动性池地址
     * @param pair 流动性池地址
     */
    function setPancakeSwapPair(address pair) external;
    
    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external;
    
    /**
     * @dev 设置价格过期时间
     * @param seconds_ 过期时间（秒）
     */
    function setPriceExpirySeconds(uint256 seconds_) external;
    
    /**
     * @dev 设置价格偏差阈值
     * @param threshold 阈值（千分比）
     */
    function setPriceDeviationThreshold(uint256 threshold) external;
    
    /**
     * @dev 重置价格缓存
     */
    function resetPriceCache() external;
    
    /**
     * @dev 设置1级升级费用
     * @param cost 费用（代币数量）
     */
    function setLevel1UpgradeCost(uint256 cost) external;
    
    /**
     * @dev 设置2级升级费用
     * @param cost 费用（代币数量）
     */
    function setLevel2UpgradeCost(uint256 cost) external;
    
    /**
     * @dev 设置3级升级费用
     * @param cost 费用（代币数量）
     */
    function setLevel3UpgradeCost(uint256 cost) external;
    
    /**
     * @dev 设置4级升级费用
     * @param cost 费用（代币数量）
     */
    function setLevel4UpgradeCost(uint256 cost) external;
}

/**
 * @title ISwapRouter
 * @dev PancakeSwap交换路由器接口
 */
interface ISwapRouter {
    /**
     * @dev 使用ETH交换代币
     * @param amountOutMin 最小输出数量
     * @param path 交换路径
     * @param to 接收地址
     * @param deadline 截止时间
     * @return uint256[] 输出数量数组
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

/**
 * @title IPancakeFactory
 * @dev PancakeSwap工厂合约接口
 */
interface IPancakeFactory {
    /**
     * @dev 获取流动性池地址
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @return address 流动性池地址
     */
    function getPair(address tokenA, address tokenB) external view returns (address);
}

/**
 * @title IStakingContract
 * @dev 质押合约接口
 */
interface IStakingContract {
    /**
     * @dev 存入代币
     * @param amount 数量
     */
    function depositToken(uint256 amount) external;
}

/**
 * @title IERC20
 * @dev ERC20代币接口
 */
interface IERC20 {
    /**
     * @dev 转账
     * @param to 转入地址
     * @param amount 数量
     * @return bool 是否成功
     */
    function transfer(address to, uint256 amount) external returns (bool);
    
    /**
     * @dev 授权
     * @param spender 授权地址
     * @param amount 授权数量
     * @return bool 是否成功
     */
    function approve(address spender, uint256 amount) external returns (bool);
    
    /**
     * @dev 获取余额
     * @param account 账户地址
     * @return uint256 余额
     */
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title ITokenStaking
 * @dev 代币质押合约接口
 */
interface ITokenStaking {
    /**
     * @dev 质押代币
     * @param amount 数量
     */
    function stakeTokens(uint256 amount) external;
    
    /**
     * @dev 解除质押
     * @param amount 数量
     */
    function unstakeTokens(uint256 amount) external;
    
    /**
     * @dev 领取奖励
     */
    function claimRewards() external;
    
    /**
     * @dev 提取BNB
     * @param amount 数量
     */
    function withdrawBNB(uint256 amount) external;
    
    /**
     * @dev 获取合约BNB余额
     * @return uint256 BNB余额
     */
    function getContractBNBBalance() external view returns (uint256);
    
    /**
     * @dev 获取合约代币余额
     * @return uint256 代币余额
     */
    function getContractTokenBalance() external view returns (uint256);
    
    /**
     * @dev 获取用户质押信息
     * @param user 用户地址
     * @return NFTDataTypes.NFTInfo 质押信息
     */
    function getUserStake(address user) external view returns (NFTDataTypes.NFTInfo memory);
    
    /**
     * @dev 获取总质押量
     * @return uint256 总质押量
     */
    function getTotalStaked() external view returns (uint256);
}

/**
 * @title IBattle
 * @dev 战斗合约接口
 */
interface IBattle {
    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external;
    
    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external;
}

/**
 * @title IArenaRanking
 * @dev 竞技场排名合约接口
 */
interface IArenaRanking {
    /**
     * @dev 设置战斗队伍
     * @param tokenIds NFT ID数组（必须为6个）
     */
    function setBattleTeam(uint256[] calldata tokenIds) external;
    
    /**
     * @dev 清除战斗队伍
     */
    function clearBattleTeam() external;
    
    /**
     * @dev 挑战玩家
     * @param defender 防守方地址
     * @return bool 挑战是否成功
     * @return uint256 攻击方胜利场数
     * @return uint256 防守方胜利场数
     */
    function challenge(address defender) external returns (bool, uint256, uint256);
    
    /**
     * @dev 充值挑战次数
     */
    function rechargeChallengeAttempts() external;
    
    /**
     * @dev 获取剩余挑战次数
     * @param player 玩家地址
     * @return uint256 剩余次数
     */
    function getRemainingAttempts(address player) external view returns (uint256);
    
    /**
     * @dev 设置挑战模式（仅所有者可调用）
     * @param mode 模式（0=积分模式，1=排名交换模式）
     */
    function setChallengeMode(uint8 mode) external;
    
    /**
     * @dev 获取当前挑战模式
     * @return uint8 当前模式
     */
    function currentMode() external view returns (uint8);
    
    /**
     * @dev 检查NFT是否在竞技场中
     * @param tokenId NFT ID
     * @return bool 是否在竞技场中
     */
    function isNFTInArena(uint256 tokenId) external view returns (bool);
    
    /**
     * @dev 设置战斗合约地址
     * @param _battleContract 战斗合约地址
     */
    function setBattleContract(address _battleContract) external;
    
    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external;
    
    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external;
}
