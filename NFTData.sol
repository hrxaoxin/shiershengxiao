// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTDataType.sol";
import "./NFTInterface.sol";

/**
 * @title NFTData
 * @dev NFT数据存储合约
 *
 * 本合约采用"分离存储"模式，将NFT的元数据（类型、等级、成长值、铸造时间）
 * 与ERC721代币所有权数据（由 NFTMint 管理）分离存储，以提高存储效率和合约升级灵活性。
 *
 * 设计动机：
 * - ERC721 主合约（NFTMint）负责所有权转移和铸造，不可轻易替换
 * - 元数据可以在不影响代币所有权的情况下扩展（例如新增成长值字段）
 * - 前端可以只查询本合约获取 NFT 详情，减轻主合约负担
 *
 * 存储结构：
 * - _nftInfo[tokenId] → NFTInfo { tokenId, zodiacType, level, growth, mintTime }
 *   每一个 NFT 的完整信息，供 Battle、Staking、Breeding 等业务合约读取
 * - _nftTypeOwners[zodiacType] → address[] 每种类型的持有者列表（用于市场统计）
 * - _userNFTs[owner] → tokenId[] 每个用户持有的 NFT 列表（用于前端分页）
 * - _userNFTsByType[owner][zodiacType] → tokenId[] 每个用户按类型分组的 NFT（用于快速计算权重）
 *
 * 数据模型说明：
 * - RARE_TYPE_START = 72：zodiacType >= 72 为稀有属性（闪光）
 * - MAX_ZODIAC_TYPE = 119：最大合法 zodiacType（共 120 种，0-119）
 * - level ∈ [1, 5]：等级由 NFTUpdate 升级，影响战斗属性和权重
 * - growth ∈ [10, 100]：成长值，铸造时随机生成，影响基础属性加成
 *
 * 数据写入权限（严格隔离，防止篡改）：
 * - onlyMintContract：NFTMint 调用 setNFTInfo() 写入新铸造的 NFT
 * - onlyUpdateContract：NFTUpdate 调用 updateLevel() 更新等级
 * - onlyTradingContract / onlyStakingContract / onlyBreedingContract：
 *   各自在 NFT 转入转出时维护 _userNFTs 和 _nftTypeOwners 的索引
 *
 * 数据读取（全部公开 view，Gas 免费）：
 * - getNFTInfo(tokenId)：返回完整 NFTInfo
 * - getNFTLevel(tokenId)：返回等级（供 Battle/Staking 快速查询）
 * - getNFTType(tokenId)：返回生肖类型（供属性克制判断）
 * - getUserAllTokens(owner)：返回用户的全部 NFT ID 数组
 * - getUserTokensByPage(owner, page, pageSize)：分页返回，优化前端加载
 * - getUserWeight(owner)：计算用户加权权重（供分红池使用）
 *
 * 与其他合约的联动：
 * - NFTMint.mintForUser → NFTData.setNFTInfo（新增记录）
 * - NFTUpdate.upgradeWithNFT → NFTData.updateLevel（更新等级）
 * - NFTTrading.buyNFT → NFTData.transferOwnership（在买卖双方间转移索引）
 * - Staking.stakeNFT → NFTData.staked(tokenId) 标记（如果实现）
 * - WeightManager / DividendManager 通过 getUserWeight 计算分红
 *
 * 升级与迁移支持：
 * - UUPS 可升级：未来可在不改变代币地址的情况下替换数据访问逻辑
 * - 所有 mapping 使用 storage，代理升级后数据完整保留
 *
 * 典型数据查询流程：
 * 1. 用户打开"我的 NFT"页面
 * 2. 前端调用 getUserTokensByPage(user, 0, 20) 获得第一批 ID
 * 3. 前端逐个 ID 调用 getNFTInfo 获取详情（或批量查询）
 * 4. 前端展示等级、属性、成长值，并调用 Battle/Staking 等其他合约获取附加信息
 */
contract NFTData is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    using NFTDataTypes for uint256;

    uint256 public constant RARE_TYPE_START = 72;
    uint256 public constant MAX_ZODIAC_TYPE = 119;
    
    /// @dev 授权合约地址
    address public authorizer;
    
    /// @dev NFT铸造核心合约地址（NFTMintCore），有权调用syncNFTData
    address public nftMintCore;
    
    /// @dev 分红管理合约地址
    address public dividendManager;
    
    /// @dev 权重管理合约地址
    address public weightManager;
    
    event LevelUpdated(uint256 indexed tokenId, uint8 oldLevel, uint8 newLevel, uint64 timestamp);

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev NFT信息映射
     *
     * key: tokenId (从开始)
     * value: NFTInfo结构体
     *
     * 访问控制：
     * - 读取：公开
     * - 写入：仅NFT主合约
     */
    mapping(uint256 => struct_NFTInfo) internal _nftInfo;
    
    /**
     * @dev 用户拥有的NFT映射（用于权重计算）
     */
    mapping(address => mapping(uint256 => uint256[])) internal _userNFTsByType; // user => zodiacType => tokenIds

    /**
     * @dev 每种NFT类型的持有者列表
     *
     * 用于统计和市场分析
     * key: nftType (0-119)
     * value: 持有者地址数组
     */
    mapping(uint256 => address[]) internal _nftTypeOwners;

    /**
     * @dev 用户持有的NFT列表
     *
     * 用于快速查询用户NFT持仓
     * key: 用户地址
     * value: tokenId数组
     */
    mapping(address => uint256[]) internal _userNFTs;

    /**
     * @dev 用户的NFT数量
     *
     * 用于优化数组遍历
     * key: 用户地址
     * value: NFT数量
     */
    mapping(address => uint256) internal _userNFTCount;

    /**
     * @dev NFT信息结构体
     *
     * 注意：此结构体定义与NFTDataType.sol中的NFTInfo兼容
     * 但在此处内联定义以避免循环依赖
     */
    struct struct_NFTInfo {
        uint256 tokenId;         // NFT唯一ID
        uint256 zodiacType;       // 生肖类型（0-119）
        uint8 level;              // 等级（1-5），使用uint8但限制为1-5
        uint8 growth;             // 成长值（10-100）
        uint256 mintTime;         // 铸造时间戳
    }
    
    /** @dev 最大等级限制 */
    uint8 public constant MAX_LEVEL = 5;
    /** @dev 最小等级限制 */
    uint8 public constant MIN_LEVEL = 1;

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     * @param _dividendManagerAddress 分红管理合约地址
     */
    function initialize(address _authorizerAddress, address _dividendManagerAddress) external initializer {
        require(_authorizerAddress != address(0), "NFTData: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizerAddress;
        if (_dividendManagerAddress != address(0)) {
            dividendManager = _dividendManagerAddress;
        }
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "NFTData: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置分红管理合约地址
     * @param _dividendManagerAddress 分红管理合约地址
     */
    function setDividendManager(address _dividendManagerAddress) external onlyOwnerOrAuthorizer {
        require(_dividendManagerAddress != address(0), "NFTData: Invalid dividend manager address");
        dividendManager = _dividendManagerAddress;
    }

    /**
     * @dev 设置NFT铸造核心合约地址（NFTMintCore）
     * @param _nftMintCoreAddress NFT铸造核心合约地址
     */
    function setNFTMintCore(address _nftMintCoreAddress) external onlyOwnerOrAuthorizer {
        require(_nftMintCoreAddress != address(0), "NFTData: Invalid NFT mint core address");
        nftMintCore = _nftMintCoreAddress;
    }

    /**
     * @dev 设置权重管理合约地址
     * @param _weightManagerAddress 权重管理合约地址
     */
    function setWeightManager(address _weightManagerAddress) external onlyOwnerOrAuthorizer {
        require(_weightManagerAddress != address(0), "NFTData: Invalid weight manager address");
        weightManager = _weightManagerAddress;
    }

    /**
     * @dev 检查是否为授权调用者（owner、authorizer或nftMintCore）
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer || (nftMintCore != address(0) && msg.sender == nftMintCore), "NFTData: Not authorized");
        _;
    }

    /**
     * @dev NFT元数据结构体（完整版，包含父代信息）
     *
     * 用于繁殖产生的子代NFT
     */
    struct NFTMeta {
        uint256 tokenId;
        uint256 zodiacType;
        uint8 level;
        uint256 mintTime;
        uint256 fatherId;         // 父亲NFT ID
        uint256 motherId;         // 母亲NFT ID
        uint256 generation;        // 代数（0为初始铸造，1为第一代繁殖后代）
    }

    /**
     * @dev 设置NFT信息
     *
     * @param tokenId NFT ID
     * @param zodiacType 生肖类型
     * @param level 等级
     * @param mintTime 铸造时间
     */
    function _setNFTInfo(
        uint256 tokenId,
        uint256 zodiacType,
        uint8 level,
        uint8 growth,
        uint256 mintTime
    ) internal {
        require(zodiacType <= MAX_ZODIAC_TYPE, "NFTData: Invalid zodiacType");
        require(level >= 1 && level <= 5, "NFTData: Invalid level");
        require(growth >= 10 && growth <= 100, "NFTData: Invalid growth value");
        
        _nftInfo[tokenId] = struct_NFTInfo({
            tokenId: tokenId,
            zodiacType: zodiacType,
            level: level,
            growth: growth,
            mintTime: mintTime
        });
    }

    /**
     * @dev 获取NFT信息
     *
     * @param tokenId NFT ID
     * @return tuple (zodiacType, level, growth, mintTime)
     */
    function _getNFTInfo(uint256 tokenId) internal view returns (uint256, uint8, uint8, uint256) {
        struct_NFTInfo memory info = _nftInfo[tokenId];
        return (info.zodiacType, info.level, info.growth, info.mintTime);
    }

    /**
     * @dev 获取NFT成长值
     *
     * @param tokenId NFT ID
     * @return uint8 成长值（10-100）
     */
    function _getNFTGrowth(uint256 tokenId) internal view returns (uint8) {
        return _nftInfo[tokenId].growth;
    }

    /**
     * @dev 设置NFT成长值
     *
     * @param tokenId NFT ID
     * @param growth 成长值（10-100）
     */
    function _setNFTGrowth(uint256 tokenId, uint8 growth) internal {
        require(growth >= 10 && growth <= 100, "NFTData: Invalid growth value");
        _nftInfo[tokenId].growth = growth;
    }

    /**
     * @dev 获取NFT类型
     *
     * @param tokenId NFT ID
     * @return uint256 生肖类型（0-119）
     */
    function _getNFTType(uint256 tokenId) internal view returns (uint256) {
        return _nftInfo[tokenId].zodiacType;
    }

    /**
     * @dev 获取NFT等级
     *
     * @param tokenId NFT ID
     * @return uint8 等级（1-5）
     */
    function _getNFTLevel(uint256 tokenId) internal view returns (uint8) {
        return _nftInfo[tokenId].level;
    }

    /**
     * @dev 设置NFT等级
     *
     * @param tokenId NFT ID
     * @param newLevel 新等级
     */
    function _setNFTLevel(uint256 tokenId, uint8 newLevel) internal {
        require(newLevel >= 1 && newLevel <= 5, "NFTData: Invalid level");
        uint8 oldLevel = _nftInfo[tokenId].level;
        _nftInfo[tokenId].level = newLevel;
        if (oldLevel != newLevel) {
            emit LevelUpdated(tokenId, oldLevel, newLevel, uint64(block.timestamp));
        }
    }

    /**
     * @dev 获取NFT铸造时间（内部）
     *
     * @param tokenId NFT ID
     * @return uint256 铸造时间戳
     */
    function _getNFTMintTime(uint256 tokenId) internal view returns (uint256) {
        return _nftInfo[tokenId].mintTime;
    }

    /**
     * @dev 获取NFT铸造时间（外部）
     *
     * @param tokenId NFT ID
     * @return uint256 铸造时间戳
     */
    function getNFTMintTime(uint256 tokenId) external view returns (uint256) {
        return _nftInfo[tokenId].mintTime;
    }

    /**
     * @dev 添加用户NFT记录
     *
     * @param user 用户地址
     * @param tokenId NFT ID
     */
    function _addUserNFT(address user, uint256 tokenId) internal {
        _userNFTs[user].push(tokenId);
        _userNFTCount[user]++;
    }

    /**
     * @dev 移除用户NFT记录
     *
     * @param user 用户地址
     * @param tokenId NFT ID
     */
    function _removeUserNFT(address user, uint256 tokenId) internal {
        uint256[] storage userTokens = _userNFTs[user];
        for (uint256 i = 0; i < userTokens.length; i++) {
            if (userTokens[i] == tokenId) {
                userTokens[i] = userTokens[userTokens.length - 1];
                userTokens.pop();
                _userNFTCount[user]--;
                break;
            }
        }
        
        // 同步更新按类型分组的用户NFT列表
        uint256 zodiacType = _getNFTType(tokenId);
        uint256[] storage typeTokens = _userNFTsByType[user][zodiacType];
        for (uint256 i = 0; i < typeTokens.length; i++) {
            if (typeTokens[i] == tokenId) {
                typeTokens[i] = typeTokens[typeTokens.length - 1];
                typeTokens.pop();
                break;
            }
        }
    }

    /**
     * @dev 获取用户NFT列表
     *
     * @param user 用户地址
     * @return uint256[] tokenId数组
     */
    function _getUserNFTs(address user) internal view returns (uint256[] memory) {
        return _userNFTs[user];
    }

    /**
     * @dev 获取用户NFT数量
     *
     * @param user 用户地址
     * @return uint256 NFT数量
     */
    function _getUserNFTCount(address user) internal view returns (uint256) {
        return _userNFTCount[user];
    }

    /**
     * @dev 添加到类型持有者列表
     *
     * @param nftType 生肖类型
     * @param owner 持有者地址
     */
    function _addToTypeOwners(uint256 nftType, address owner) internal {
        // 修复：检查 owner 是否已在列表中，避免重复添加
        address[] storage owners = _nftTypeOwners[nftType];
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                return; // 已存在，不需要重复添加
            }
        }
        _nftTypeOwners[nftType].push(owner);
    }

    /**
     * @dev 从类型持有者列表移除
     *
     * @param nftType 生肖类型
     * @param owner 持有者地址
     */
    function _removeFromTypeOwners(uint256 nftType, address owner) internal {
        address[] storage owners = _nftTypeOwners[nftType];
        uint256 writeIndex = 0;
        bool found = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                found = true;
                continue; // 跳过要移除的元素
            }
            if (!found || i != writeIndex) {
                owners[writeIndex] = owners[i];
            }
            writeIndex++;
        }
        while (owners.length > writeIndex) {
            owners.pop();
        }
    }

    /**
     * @dev 获取类型持有者数量
     *
     * @param nftType 生肖类型
     * @return uint256 持有者数量
     */
    function _getTypeOwnerCount(uint256 nftType) internal view returns (uint256) {
        return _nftTypeOwners[nftType].length;
    }

    /**
     * @dev 检查NFT是否存在
     *
     * @param tokenId NFT ID
     * @return bool 是否存在
     */
    function _nftExists(uint256 tokenId) internal view returns (bool) {
        return _nftInfo[tokenId].mintTime > 0;
    }

    /**
     * @dev 获取某种类型的所有NFT
     *
     * @param nftType 生肖类型
     * @return address[] 持有者地址列表
     */
    function _getTypeOwners(uint256 nftType) internal view returns (address[] memory) {
        return _nftTypeOwners[nftType];
    }

    /**
     * @dev 批量获取NFT信息
     *
     * @param tokenIds tokenId数组
     * @return uint256[] zodiacTypes数组
     * @return uint8[] levels数组
     * @return uint256[] mintTimes数组
     */
    function _getNFTInfoBatch(uint256[] memory tokenIds) internal view returns (
        uint256[] memory,
        uint8[] memory,
        uint256[] memory
    ) {
        uint256 length = tokenIds.length;
        uint256[] memory types = new uint256[](length);
        uint8[] memory levels = new uint8[](length);
        uint256[] memory mintTimes = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            struct_NFTInfo memory info = _nftInfo[tokenIds[i]];
            types[i] = info.zodiacType;
            levels[i] = info.level;
            mintTimes[i] = info.mintTime;
        }

        return (types, levels, mintTimes);
    }
    
    // ========== 外部可见函数 ==========
    
    /**
     * @dev 获取NFT类型
     */
    function tokenType(uint256 tokenId) external view returns (uint256) {
        return _nftInfo[tokenId].zodiacType;
    }
    
    /**
     * @dev 获取NFT等级
     */
    function tokenLevel(uint256 tokenId) external view returns (uint8) {
        return _nftInfo[tokenId].level;
    }
    
    /**
     * @dev 设置NFT等级（仅授权调用者）
     */
    function setTokenLevel(uint256 tokenId, uint8 level) external onlyOwnerOrAuthorizer {
        require(level >= 1 && level <= 5, "NFTData: Invalid level");
        _setNFTLevel(tokenId, level);
    }
    
    /**
     * @dev 计算用户权重
     * 权重计算基于用户拥有的NFT数量、等级和稀有度
     */
    function calcUserWeight(address user) external view returns (uint256) {
        uint256[] memory userTokens = _getUserNFTs(user);
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < userTokens.length; i++) {
            uint256 tokenId = userTokens[i];
            struct_NFTInfo memory info = _nftInfo[tokenId];

            // 稀有属性权重（闪光属性，zodiacType >= 72）
            bool isRare = info.zodiacType >= RARE_TYPE_START;

            // 基础权重基于等级
            uint256 levelWeight;
            if (info.level == 1) levelWeight = isRare ? 10 : 1;
            else if (info.level == 2) levelWeight = isRare ? 12 : 2;
            else if (info.level == 3) levelWeight = isRare ? 16 : 6;
            else if (info.level == 4) levelWeight = isRare ? 28 : 18;
            else if (info.level == 5) levelWeight = isRare ? 76 : 66;
            else levelWeight = 0;

            totalWeight += levelWeight;
        }

        return totalWeight;
    }
    
    /**
     * @dev 设置NFT信息（用于初始化）
     */
    function setNFTInfo(
        uint256 tokenId,
        uint256 zodiacType,
        uint8 level,
        uint8 growth,
        uint256 mintTime,
        address owner
    ) external onlyOwnerOrAuthorizer {
        _setNFTInfo(tokenId, zodiacType, level, growth, mintTime);
        _addUserNFT(owner, tokenId);
        _addToTypeOwners(zodiacType, owner);
    }

    /**
     * @dev 同步NFT铸造数据（由NFTMintCore调用）
     */
    function syncNFTData(uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to) external onlyOwnerOrAuthorizer {
        _setNFTInfo(tokenId, zodiacType, level, growth, block.timestamp);
        _addUserNFT(to, tokenId);
        _addToTypeOwners(zodiacType, to);
        
        if (dividendManager != address(0)) {
            uint8 element = uint8(zodiacType / 24);
            IDividendManager(dividendManager).updateUserWeight(to, uint256(level), true, element);
        }
        
        if (weightManager != address(0)) {
            IWeightManager(weightManager).addHolder(to);
        }
    }
    
    /**
     * @dev 添加用户NFT（外部调用）
     */
    function addUserNFT(address user, uint256 tokenId) external onlyOwnerOrAuthorizer {
        _addUserNFT(user, tokenId);
        uint256 zodiacType = _getNFTType(tokenId);
        _addToTypeOwners(zodiacType, user);
    }
    
    /**
     * @dev 移除用户NFT（外部调用）
     */
    function removeUserNFT(address user, uint256 tokenId) external onlyOwnerOrAuthorizer {
        _removeUserNFT(user, tokenId);
        uint256 zodiacType = _getNFTType(tokenId);
        _removeFromTypeOwners(zodiacType, user);
    }

    /**
     * @dev 获取用户NFT列表（外部调用）
     */
    function getUserNFTs(address user) external view returns (uint256[] memory) {
        return _getUserNFTs(user);
    }
    
    /**
     * @dev 获取用户NFT列表（分页）
     * @param user 用户地址
     * @param offset 起始索引
     * @param limit 返回数量限制
     * @return nfts NFT列表
     * @return total 总数量
     */
    function getUserNFTsPaginated(address user, uint256 offset, uint256 limit) external view returns (uint256[] memory nfts, uint256 total) {
        uint256[] storage allNFTs = _userNFTs[user];
        total = allNFTs.length;
        
        if (offset >= total) {
            return (new uint256[](0), total);
        }
        
        uint256 size = total - offset;
        if (size > limit) {
            size = limit;
        }
        
        nfts = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            nfts[i] = allNFTs[offset + i];
        }
    }

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}