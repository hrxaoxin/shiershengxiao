// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title NFTData
 * @dev NFT数据存储合约，用于存储和管理NFT的类型、等级、用户持有信息等数据
 * 基于OpenZeppelin UUPS可升级合约实现
 */
contract NFTData is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, INFTDataInterface {
    using NFTDataTypes for NFTDataTypes.ZodiacType;

    /** @dev 属性名称数组（中文） */
    string[] private _elementNames = [unicode"水", unicode"风", unicode"火", unicode"暗", unicode"光"];
    /** @dev 生肖名称数组（中文） */
    string[] private _zodiacNames = [unicode"鼠", unicode"牛", unicode"虎", unicode"兔", unicode"龙", unicode"蛇", unicode"马", unicode"羊", unicode"猴", unicode"鸡", unicode"狗", unicode"猪"];
    /** @dev 性别名称数组（中文） */
    string[] private _genderNames = [unicode"母", unicode"公"];
    /** @dev 属性拼音前缀数组，用于生成图片URL */
    string[] private _elementPrefixes = ["shui", "feng", "huo", "an", "guang"];
    /** @dev 生肖拼音前缀数组，用于生成图片URL */
    string[] private _zodiacPrefixes = ["shu", "niu", "hu", "tu", "long", "she", "ma", "yang", "hou", "ji", "gou", "zhu"];
    /** @dev 普通属性IPFS基础URL */
    string private constant IPFS_BASE_COMMON = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/";
    /** @dev 稀有属性（暗/光）IPFS基础URL */
    string private constant IPFS_BASE_RARE = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/";

    /** @dev NFT信息映射：tokenId -> NFTInfo结构体 */
    mapping(uint256 => NFTDataTypes.NFTInfo) private _nftInfos;
    /** @dev NFT类型映射：tokenId -> ZodiacType */
    mapping(uint256 => NFTDataTypes.ZodiacType) public override tokenType;
    /** @dev NFT等级映射：tokenId -> level(1-5) */
    mapping(uint256 => uint8) public override tokenLevel;
    /** @dev 用户持有的NFT列表：user -> tokenId数组 */
    mapping(address => uint256[]) public _userTokens;
    /** @dev 用户NFT存在性检查：user -> tokenId -> bool */
    mapping(address => mapping(uint256 => bool)) public userTokenExists;
    /** @dev 用户持有的指定类型NFT数量：user -> ZodiacType -> count */
    mapping(address => mapping(NFTDataTypes.ZodiacType => uint256)) public userTokenCount;
    /** @dev 用户权重缓存：user -> weight */
    mapping(address => uint256) public override userWeightCache;

    /** @dev 授权的NFT合约地址（用于调用者验证） */
    address public authorizedNFTContract;
    /** @dev 授权NFT合约设置事件 */
    event AuthorizedNFTContractSet(address indexed nftContract, uint256 timestamp);
    /** @dev 授权合约地址 */
    address public authorizer;
    
    /** @dev 普通属性（风、水、火）各等级权重：1阶=1, 2阶=2, 3阶=6, 4阶=18, 5阶=66 */
    uint256[6] public commonWeights;
    /** @dev 稀有属性（光、暗）各等级权重：1阶=10, 2阶=12, 3阶=16, 4阶=28, 5阶=76 */
    uint256[6] public rareWeights;
    /** @dev 权重规则更新事件 */
    event WeightRulesUpdated(uint256[6] commonWeights, uint256[6] rareWeights, uint256 timestamp);
    
    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[48] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者地址
     */
    function initialize(address initialOwner) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        transferOwnership(initialOwner);
        
        // 设置默认权重规则
        // 普通属性（风、水、火）: 1阶=1, 2阶=2, 3阶=6, 4阶=18, 5阶=66
        commonWeights[0] = 0;  // 索引0未使用
        commonWeights[1] = 1;
        commonWeights[2] = 2;
        commonWeights[3] = 6;
        commonWeights[4] = 18;
        commonWeights[5] = 66;
        
        // 稀有属性（光、暗）: 1阶=10, 2阶=12, 3阶=16, 4阶=28, 5阶=76
        // 光暗为稀有属性，铸造消耗更高，权重适当提升
        rareWeights[0] = 0;     // 索引0未使用
        rareWeights[1] = 10;
        rareWeights[2] = 12;
        rareWeights[3] = 16;
        rareWeights[4] = 28;
        rareWeights[5] = 76;
    }

    

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 仅授权地址可调用修饰器
     * 允许合约所有者或授权的NFT合约调用
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizedNFTContract, "NFTData: Unauthorized");
        _;
    }

    /**
     * @dev 获取NFT信息
     * @param tokenId NFT ID
     * @return NFTDataTypes.NFTInfo NFT信息结构体
     */
    function getNFTInfo(uint256 tokenId) external view override returns (NFTDataTypes.NFTInfo memory) {
        return _nftInfos[tokenId];
    }

    /**
     * @dev 设置NFT信息
     * @param tokenId NFT ID
     * @param info NFT信息结构体
     */
    function setNFTInfo(uint256 tokenId, NFTDataTypes.NFTInfo memory info) external onlyAuthorized {
        _nftInfos[tokenId] = info;
    }
    
    /**
     * @dev 清除NFT信息
     * @param tokenId NFT ID
     */
    function clearNFTInfo(uint256 tokenId) external onlyAuthorized {
        delete _nftInfos[tokenId];
    }

    /**
     * @dev 设置NFT类型
     * @param tokenId NFT ID
     * @param type_ 生肖类型
     */
    function setTokenType(uint256 tokenId, NFTDataTypes.ZodiacType type_) external override onlyAuthorized {
        tokenType[tokenId] = type_;
    }

    /**
     * @dev 设置NFT等级
     * @param tokenId NFT ID
     * @param level 等级（1-5）
     */
    function setTokenLevel(uint256 tokenId, uint8 level) external override onlyAuthorized {
        tokenLevel[tokenId] = level;
    }

    /**
     * @dev 添加用户NFT
     * @param user 用户地址
     * @param type_ 生肖类型
     * @param tokenId NFT ID
     */
    function addUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external override onlyAuthorized {
        if (!userTokenExists[user][tokenId]) {
            _userTokens[user].push(tokenId);
            userTokenExists[user][tokenId] = true;
        }
        tokenType[tokenId] = type_;
        userTokenCount[user][type_]++;
    }

    /**
     * @dev 移除用户NFT
     * @param user 用户地址
     * @param type_ 生肖类型
     * @param tokenId NFT ID
     */
    function removeUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external override onlyAuthorized {
        uint256[] storage arr = _userTokens[user];
        uint256 length = arr.length;
        for (uint i = 0; i < length; i++) {
            if (arr[i] == tokenId) {
                if (length > 1) {
                    arr[i] = arr[length - 1];
                }
                arr.pop();
                break;
            }
        }
        delete userTokenExists[user][tokenId];
        delete _nftInfos[tokenId];
        if (userTokenCount[user][type_] > 0) userTokenCount[user][type_]--;
    }

    /**
     * @dev 更新用户权重缓存
     * @param user 用户地址
     * @param weight 权重值
     */
    function updateUserWeightCache(address user, uint256 weight) external override onlyAuthorized {
        userWeightCache[user] = weight;
    }

    /**
     * @dev 根据等级和属性类型获取权重值（内部函数）
     * 普通属性（风、水、火）权重规则：1阶=1, 2阶=2, 3阶=4, 4阶=12, 5阶=48
     * 稀有属性（光、暗）权重规则：1阶=10, 2阶=20, 3阶=40, 4阶=120, 5阶=480
     * @param level NFT等级
     * @param isRare 是否稀有属性
     * @return uint256 权重值
     */
    function _getLevelWeight(uint8 level, bool isRare) internal view returns (uint256) {
        if (level < 1 || level > 5) return 0;
        return isRare ? rareWeights[level] : commonWeights[level];
    }

    /**
     * @dev 检查属性是否为稀有属性（光、暗）
     * @param element 属性类型
     * @return bool 是否为稀有属性
     */
    function _isRareElement(NFTDataTypes.ElementType element) internal pure returns (bool) {
        return element == NFTDataTypes.ElementType.DARK || element == NFTDataTypes.ElementType.LIGHT;
    }

    /**
     * @dev 统一的权重更新函数（由NFTMint、NFTUpdate等调用）
     * @param user 用户地址
     * @param level NFT等级
     * @param add 是否增加（true增加，false减少）
     * @param element 属性类型
     */
    function updateUserWeight(address user, uint8 level, bool add, NFTDataTypes.ElementType element) external override onlyAuthorized {
        uint256 currentWeight = userWeightCache[user];
        uint256 weightDelta = _getLevelWeight(level, _isRareElement(element));
        if (add) {
            userWeightCache[user] = currentWeight + weightDelta;
        } else {
            userWeightCache[user] = currentWeight >= weightDelta ? currentWeight - weightDelta : 0;
        }
    }

    /**
     * @dev 直接计算用户权重（遍历所有NFT）
     * 用于精确计算用户权重，解决缓存不一致问题
     * @param user 用户地址
     * @return uint256 用户权重
     */
    function calcUserWeight(address user) external view override returns (uint256) {
        uint256[] memory tokens = _userTokens[user];
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenId = tokens[i];
            uint8 level = tokenLevel[tokenId];
            NFTDataTypes.ZodiacType t = tokenType[tokenId];
            bool isRare = _isRareElement(t.getElement());
            totalWeight += _getLevelWeight(level, isRare);
        }
        return totalWeight;
    }

    /**
     * @dev 设置权重规则（仅合约所有者可调用）
     * @param _commonWeights 普通属性各等级权重（索引0未使用，1-5对应等级1-5）
     * @param _rareWeights 稀有属性各等级权重（索引0未使用，1-5对应等级1-5）
     */
    function setWeightRules(uint256[6] calldata _commonWeights, uint256[6] calldata _rareWeights) external onlyOwner {
        require(_commonWeights[1] > 0, "NFTData: Common weight level 1 must be > 0");
        require(_rareWeights[1] > 0, "NFTData: Rare weight level 1 must be > 0");
        
        for (uint i = 1; i <= 5; i++) {
            require(_commonWeights[i] >= _commonWeights[i-1], "NFTData: Common weights must be non-decreasing");
            require(_rareWeights[i] >= _rareWeights[i-1], "NFTData: Rare weights must be non-decreasing");
        }
        
        commonWeights = _commonWeights;
        rareWeights = _rareWeights;
        
        emit WeightRulesUpdated(_commonWeights, _rareWeights, block.timestamp);
    }

    /**
     * @dev 获取权重规则信息
     * @return (uint256[6], uint256[6]) 普通属性权重数组和稀有属性权重数组
     */
    function getWeightRules() external view returns (uint256[6] memory, uint256[6] memory) {
        return (commonWeights, rareWeights);
    }

    /**
     * @dev 获取用户持有的指定类型NFT数量
     * @param user 用户地址
     * @param type_ 生肖类型
     * @return uint256 数量
     */
    function getUserTokenCount(address user, NFTDataTypes.ZodiacType type_) external view override returns (uint256) {
        return userTokenCount[user][type_];
    }

    /**
     * @dev 获取用户持有的NFT总数
     * @param user 用户地址
     * @return uint256 总数
     */
    function getUserTotalTokenCount(address user) external view override returns (uint256) {
        return _userTokens[user].length;
    }

    /**
     * @dev 获取用户持有的指定类型NFT列表
     * @param user 用户地址
     * @param type_ 生肖类型
     * @return uint256[] NFT ID列表
     */
    function userTokens(address user, NFTDataTypes.ZodiacType type_) external view override returns (uint256[] memory) {
        uint256[] memory all = _userTokens[user];
        uint cnt;
        for (uint i = 0; i < all.length; i++) if (tokenType[all[i]] == type_) cnt++;
        uint256[] memory res = new uint256[](cnt);
        uint idx;
        for (uint i = 0; i < all.length; i++) if (tokenType[all[i]] == type_) res[idx++] = all[i];
        return res;
    }

    /**
     * @dev 获取用户持有的所有NFT列表
     * @param user 用户地址
     * @return uint256[] NFT ID列表
     */
    function userAllTokens(address user) external view override returns (uint256[] memory) {
        return _userTokens[user];
    }

    /**
     * @dev 设置授权的NFT合约地址
     * @param nftContract NFT合约地址
     */
    function setAuthorizedNFTContract(address nftContract) external onlyOwner {
        require(nftContract != address(0), "Zero address");
        authorizedNFTContract = nftContract;
        emit AuthorizedNFTContractSet(nftContract, block.timestamp);
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 获取属性名称
     * @param e 属性类型
     * @return string memory 属性名称（中文）
     */
    function getElementName(NFTDataTypes.ElementType e) external view override returns (string memory) { return _elementNames[uint256(e)]; }

    /**
     * @dev 获取生肖名称
     * @param z 生肖类型
     * @return string memory 生肖名称（中文）
     */
    function getZodiacName(NFTDataTypes.BaseZodiac z) external view override returns (string memory) { return _zodiacNames[uint256(z)]; }

    /**
     * @dev 获取性别名称
     * @param g 性别类型
     * @return string memory 性别名称（中文）
     */
    function getGenderName(NFTDataTypes.GenderType g) external view override returns (string memory) { return _genderNames[uint256(g)]; }

    /**
     * @dev 获取完整类型名称（内部函数）
     * @param t 生肖类型
     * @return string memory 完整名称（如：水鼠（公））
     */
    function _getFullTypeName(NFTDataTypes.ZodiacType t) internal view returns (string memory) {
        return string(abi.encodePacked(
            _elementNames[uint256(t.getElement())],
            _zodiacNames[uint256(t.getBaseZodiac())],
            unicode"（", _genderNames[uint256(t.getGender())], unicode"）"
        ));
    }

    /**
     * @dev 获取完整类型名称
     * @param t 生肖类型
     * @return string memory 完整名称（如：水鼠（公））
     */
    function getFullTypeName(NFTDataTypes.ZodiacType t) external view override returns (string memory) {
        return _getFullTypeName(t);
    }

    /**
     * @dev 获取集合名称
     * @return string memory 集合名称
     */
    function collName() external pure override returns (string memory) { return "Twelve Zodiacs"; }

    /**
     * @dev 获取集合描述
     * @return string memory 集合描述
     */
    function collDesc() external pure override returns (string memory) { return unicode"十二生肖NFT系列 - 120种独特卡牌"; }

    /**
     * @dev 获取集合图片URL
     * @return string memory 图片URL
     */
    function collImage() external pure override returns (string memory) { return "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/logo.png"; }

    /**
     * @dev 获取卖家费用比例（千分比）
     * @return uint256 费用比例（500 = 5%）
     */
    function sellerFeeBasisPoints() external pure override returns (uint256) { return 500; }

    /**
     * @dev 获取卡牌名称
     * @param t 生肖类型
     * @return string memory 卡牌名称
     */
    function getCardName(NFTDataTypes.ZodiacType t) external view override returns (string memory) { return _getFullTypeName(t); }

    /**
     * @dev 获取卡牌描述
     * @param t 生肖类型
     * @return string memory 卡牌描述
     */
    function getCardDesc(NFTDataTypes.ZodiacType t) external view override returns (string memory) { return string(abi.encodePacked(unicode"十二生肖NFT - ", _getFullTypeName(t))); }

    /**
     * @dev 获取卡牌图片URL
     * 暗/光属性使用不同的IPFS CID
     * @param t 生肖类型
     * @return string memory 图片URL
     */
    function getCardImage(NFTDataTypes.ZodiacType t) external view override returns (string memory) {
        string memory baseUrl = t.getElement() == NFTDataTypes.ElementType.DARK || t.getElement() == NFTDataTypes.ElementType.LIGHT 
            ? IPFS_BASE_RARE 
            : IPFS_BASE_COMMON;
        
        return string(abi.encodePacked(
            baseUrl,
            _elementPrefixes[uint256(t.getElement())],
            _zodiacPrefixes[uint256(t.getBaseZodiac())],
            t.getGender() == NFTDataTypes.GenderType.MALE ? "_1" : "_0",
            ".png"
        ));
    }

    /**
     * @dev 检查用户是否有资格（持有NFT）
     * @param user 用户地址
     * @return bool 是否有资格
     */
    function hasEligibility(address user) external view override returns (bool) {
        return _userTokens[user].length > 0;
    }

    /**
     * @dev 获取用户持有的NFT类型列表
     * @param user 用户地址
     * @return NFTDataTypes.ZodiacType[] 类型列表
     */
    function getUserTokenTypes(address user) external view override returns (NFTDataTypes.ZodiacType[] memory) {
        uint256[] memory tokens = _userTokens[user];
        NFTDataTypes.ZodiacType[] memory types = new NFTDataTypes.ZodiacType[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            types[i] = tokenType[tokens[i]];
        }
        return types;
    }

    /**
     * @dev 分页获取用户持有的NFT类型列表
     * @param user 用户地址
     * @param offset 偏移量
     * @param limit 每页大小
     * @return NFTDataTypes.ZodiacType[] 类型列表
     * @return uint256 总数
     */
    function getUserTokenTypesByPage(address user, uint256 offset, uint256 limit) external view returns (NFTDataTypes.ZodiacType[] memory, uint256) {
        uint256[] memory tokens = _userTokens[user];
        uint256 total = tokens.length;
        if (offset >= total) {
            return (new NFTDataTypes.ZodiacType[](0), 0);
        }
        uint256 size = offset + limit > total ? total - offset : limit;
        NFTDataTypes.ZodiacType[] memory types = new NFTDataTypes.ZodiacType[](size);
        for (uint i = 0; i < size; i++) {
            types[i] = tokenType[tokens[offset + i]];
        }
        return (types, total);
    }
}
