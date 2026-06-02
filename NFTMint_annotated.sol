// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";

/**
 * @title NFTMint
 * @dev 十二生肖NFT铸造合约
 * 
 * 功能：
 * - 支持普通铸造（水/风/火属性）
 * - 支持稀有铸造（光/暗属性）
 * - 支持批量铸造（十连抽）
 * - 支持指定生肖铸造
 * - 与NFTData合约同步数据
 * 
 * NFT类型计算：
 * - 属性(5种) × 生肖(12种) × 性别(2种) = 120种NFT
 * - tokenType = element × 24 + zodiac × 2 + gender
 */
contract NFTMint is ERC721EnumerableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // ============ 状态变量 ============
    
    /**
     * @dev 元素概率分布 [水, 风, 火, 暗, 光]
     * 普通铸造：水/风/火各32%，暗/光各2%
     */
    uint256[5] public elementProbabilities = [32, 32, 32, 2, 2];
    
    /**
     * @dev 稀有元素概率分布 [暗, 光]
     * 稀有铸造：暗/光各50%
     */
    uint256[2] public rareElementProbabilities = [50, 50];

    /// @dev 铸造计数器，用于增加随机数熵
    uint256 public mintCounter;
    
    /// @dev 上次铸造区块号
    uint256 public lastMintBlock;
    
    /// @dev 下一个NFT ID
    uint256 public _nextCardId;

    /// @dev TokenBurner合约地址
    address public tokenBurnerContract;
    
    /// @dev 授权合约地址
    address public authorizer;
    
    /// @dev NFT数据合约地址
    address public nftDataContract;
    
    /// @dev 黑洞地址（用于销毁）
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    /// @dev 是否暂停
    bool public paused;
    
    /// @dev 暂停原因
    string public pauseReason;
    
    /// @dev 是否允许公开铸造
    bool public allowPublicMinting = false;
    
    /// @dev 稀有类型阈值（>=72为稀有）
    uint256 public rareTypeThreshold = 72;
    
    /// @dev NFT类型映射 tokenId => zodiacType (0-119)
    mapping(uint256 => uint256) public tokenType;
    
    /// @dev NFT等级映射 tokenId => level (1-5)
    mapping(uint256 => uint8) public tokenLevel;
    
    /// @dev NFT成长值映射 tokenId => growth (10-100)
    mapping(uint256 => uint8) public tokenGrowth;

    // ============ 事件 ============
    
    /**
     * @dev 铸造事件
     * @param to 接收地址
     * @param tokenId NFT ID
     * @param zodiacType 生肖类型 (0-119)
     * @param growth 成长值 (10-100)
     */
    event Mint(address indexed to, uint256 indexed tokenId, uint256 zodiacType, uint8 growth);
    
    /**
     * @dev NFT数据同步失败事件
     * @param tokenId NFT ID
     * @param zodiacType 生肖类型
     */
    event NFTDataSyncFailed(uint256 indexed tokenId, uint256 zodiacType);
    
    /**
     * @dev 批量铸造事件
     * @param to 接收地址
     * @param tokenIds NFT ID数组
     */
    event BatchMint(address indexed to, uint256[] tokenIds);
    
    /**
     * @dev 升级事件
     * @param owner NFT所有者
     * @param tokenId NFT ID
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     */
    event Upgrade(address indexed owner, uint256 indexed tokenId, uint8 oldLevel, uint8 newLevel);
    
    /**
     * @dev 暂停事件
     * @param account 操作账户
     * @param reason 暂停原因
     */
    event Paused(address account, string reason);
    
    /**
     * @dev 恢复事件
     * @param account 操作账户
     */
    event Unpaused(address account);
    
    /**
     * @dev 公开铸造开关事件
     * @param allowed 是否允许
     */
    event PublicMintingToggled(bool allowed);
    
    /**
     * @dev 同步重试事件
     * @param syncId 同步ID
     * @param tokenId NFT ID
     * @param success 是否成功
     */
    event SyncRetryAttempted(uint256 syncId, uint256 tokenId, bool success);

    // ============ 结构体 ============
    
    /**
     * @dev 同步失败记录结构体
     */
    struct FailedSync {
        uint256 tokenId;        // NFT ID
        uint256 zodiacType;     // 生肖类型
        uint8 level;            // 等级
        uint8 growth;           // 成长值
        address to;             // 目标地址
        uint256 timestamp;      // 时间戳
        uint8 syncType;         // 0: setNFTInfo, 1: setTokenLevel
    }
    
    /// @dev 同步失败记录映射
    mapping(uint256 => FailedSync) public failedSyncs;
    
    /// @dev 同步失败计数
    uint256 public failedSyncCount;

    // ============ 修饰符 ============
    
    /**
     * @dev 检查是否授权
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTMint: Not authorized");
        _;
    }
    
    /**
     * @dev 检查是否未暂停
     */
    modifier whenNotPaused() {
        require(!paused, "NFTMint: Paused");
        _;
    }
    
    /**
     * @dev 检查是否允许公开铸造
     */
    modifier whenPublicMintingAllowed() {
        require(allowPublicMinting || msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        _;
    }

    // ============ 初始化函数 ============
    
    /**
     * @dev 初始化合约
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __ERC721_init("Zodiac NFT", "ZNFT");
        __ERC721Enumerable_init();
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _nextCardId = 1;
        authorizer = _authorizer;
    }

    // ============ 升级授权 ============
    
    /**
     * @dev UUPS升级授权
     * @param newImplementation 新实现地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ 设置函数 ============
    
    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }
    
    /**
     * @dev 设置TokenBurner合约地址
     * @param _tokenBurner TokenBurner合约地址
     */
    function setTokenBurner(address _tokenBurner) external onlyAuthorized {
        require(_tokenBurner != address(0), "NFTMint: Invalid token burner address");
        tokenBurnerContract = _tokenBurner;
    }
    
    /**
     * @dev 设置NFT数据合约地址
     * @param _nftData NFT数据合约地址
     */
    function setNFTDataContract(address _nftData) external onlyAuthorized {
        nftDataContract = _nftData;
    }
    
    /**
     * @dev 设置公开铸造开关
     * @param allowed 是否允许
     */
    function setAllowPublicMinting(bool allowed) external onlyOwner {
        allowPublicMinting = allowed;
        emit PublicMintingToggled(allowed);
    }
    
    /**
     * @dev 设置稀有类型阈值
     * @param _threshold 阈值 (0-120)
     */
    function setRareTypeThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold <= 120, "NFTMint: Invalid threshold");
        rareTypeThreshold = _threshold;
    }

    // ============ 数据同步函数 ============
    
    /**
     * @dev 同步NFT数据到NFTData合约
     * @param to 接收地址
     * @param tokenId NFT ID
     * @param zodiacType 生肖类型
     * @param level 等级
     * @param growth 成长值
     */
    function _syncNFTData(address to, uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth) internal {
        if (nftDataContract != address(0)) {
            bool success = _trySyncNFTInfo(tokenId, zodiacType, level, growth, to);
            if (!success) {
                _queueFailedSync(tokenId, zodiacType, level, growth, to, 0);
                emit NFTDataSyncFailed(tokenId, zodiacType);
            }
        }
    }
    
    /**
     * @dev 更新NFT数据等级
     * @param tokenId NFT ID
     * @param newLevel 新等级
     */
    function _updateNFTDataLevel(uint256 tokenId, uint8 newLevel) internal {
        if (nftDataContract != address(0)) {
            bool success = _trySetTokenLevel(tokenId, newLevel);
            if (!success) {
                _queueFailedSync(tokenId, tokenType[tokenId], newLevel, 0, address(0), 1);
                emit NFTDataSyncFailed(tokenId, tokenType[tokenId]);
            }
        }
    }
    
    /**
     * @dev 尝试同步NFT信息（重试3次）
     * @param tokenId NFT ID
     * @param zodiacType 生肖类型
     * @param level 等级
     * @param growth 成长值
     * @param to 目标地址
     * @return success 是否成功
     */
    function _trySyncNFTInfo(uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to) internal returns (bool) {
        for (uint8 i = 0; i < 3; i++) {
            (bool success, ) = nftDataContract.call(
                abi.encodeWithSignature(
                    "setNFTInfo(uint256,uint256,uint8,uint8,uint256,address)",
                    tokenId, zodiacType, level, growth, block.timestamp, to
                )
            );
            if (success) return true;
        }
        return false;
    }
    
    /**
     * @dev 尝试设置Token等级（重试3次）
     * @param tokenId NFT ID
     * @param newLevel 新等级
     * @return success 是否成功
     */
    function _trySetTokenLevel(uint256 tokenId, uint8 newLevel) internal returns (bool) {
        for (uint8 i = 0; i < 3; i++) {
            (bool success, ) = nftDataContract.call(
                abi.encodeWithSignature("setTokenLevel(uint256,uint8)", tokenId, newLevel)
            );
            if (success) return true;
        }
        return false;
    }
    
    /**
     * @dev 将同步失败加入队列
     * @param tokenId NFT ID
     * @param zodiacType 生肖类型
     * @param level 等级
     * @param growth 成长值
     * @param to 目标地址
     * @param syncType 同步类型
     */
    function _queueFailedSync(uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to, uint8 syncType) internal {
        failedSyncCount++;
        failedSyncs[failedSyncCount] = FailedSync({
            tokenId: tokenId,
            zodiacType: zodiacType,
            level: level,
            growth: growth,
            to: to,
            timestamp: block.timestamp,
            syncType: syncType
        });
    }
    
    /**
     * @dev 重试失败的同步
     * @param syncId 同步ID
     */
    function retryFailedSync(uint256 syncId) external onlyAuthorized {
        FailedSync storage sync = failedSyncs[syncId];
        require(sync.tokenId != 0, "NFTMint: Invalid sync ID");
        
        bool success;
        if (sync.syncType == 0) {
            success = _trySyncNFTInfo(sync.tokenId, sync.zodiacType, sync.level, sync.growth, sync.to);
        } else {
            success = _trySetTokenLevel(sync.tokenId, sync.level);
        }
        
        if (success) {
            delete failedSyncs[syncId];
        }
        
        emit SyncRetryAttempted(syncId, sync.tokenId, success);
    }
    
    /**
     * @dev 重试所有失败的同步
     */
    function retryAllFailedSyncs() external onlyAuthorized {
        for (uint256 i = 1; i <= failedSyncCount; i++) {
            if (failedSyncs[i].tokenId != 0) {
                retryFailedSync(i);
            }
        }
    }

    // ============ 随机数生成 ============
    
    /**
     * @dev 生成安全随机数
     * @return 随机数
     */
    function _generateSecureRandom() internal returns (uint256) {
        lastMintBlock = block.number;
        mintCounter++;
        bytes32 entropy = keccak256(
            abi.encodePacked(
                blockhash(block.number > 1 ? block.number - 1 : block.number),
                msg.sender,
                block.timestamp,
                mintCounter,
                gasleft(),
                address(this),
                block.coinbase,
                block.prevrandao
            )
        );
        return uint256(entropy);
    }
    
    /**
     * @dev 生成成长值 (10-100)
     * @param randomSeed 随机种子
     * @return 成长值
     */
    function _generateGrowthValue(uint256 randomSeed) internal pure returns (uint8) {
        uint256 roll = randomSeed % 91;
        return uint8(roll + 10);
    }
    
    /**
     * @dev 选择元素
     * @param randomVal 随机值
     * @return 元素索引 (0-4)
     */
    function _chooseElement(uint256 randomVal) internal view returns (uint256) {
        uint256[5] memory cumulativeProbabilities;
        cumulativeProbabilities[0] = elementProbabilities[0];
        for (uint256 i = 1; i < 5; i++) {
            cumulativeProbabilities[i] = cumulativeProbabilities[i-1] + elementProbabilities[i];
        }
        uint256 roll = randomVal % 100;
        for (uint256 i = 0; i < 5; i++) {
            if (roll < cumulativeProbabilities[i]) {
                return i;
            }
        }
        return 0;
    }
    
    /**
     * @dev 选择稀有元素
     * @param randomVal 随机值
     * @return 元素索引 (3-4)
     */
    function _chooseRareElement(uint256 randomVal) internal view returns (uint256) {
        uint256 roll = randomVal % 100;
        if (roll < rareElementProbabilities[0]) {
            return 3;
        }
        return 4;
    }
    
    /**
     * @dev 计算生肖类型
     * @param element 元素 (0-4)
     * @param zodiac 生肖 (0-11)
     * @param gender 性别 (0-1)
     * @return tokenType 类型 (0-119)
     */
    function _calculateZodiacType(uint256 element, uint256 zodiac, uint256 gender) internal pure returns (uint256) {
        return element * 24 + zodiac * 2 + gender;
    }
    
    /**
     * @dev 普通铸造
     * @param randomSeed 随机种子
     * @return tokenType 类型
     */
    function _mintNormal(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return _calculateZodiacType(element, zodiac, gender);
    }
    
    /**
     * @dev 稀有铸造
     * @param randomSeed 随机种子
     * @return tokenType 类型
     */
    function _mintRare(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseRareElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return _calculateZodiacType(element, zodiac, gender);
    }

    // ============ 铸造函数 ============
    
    /**
     * @dev 铸造指定类型的NFT
     * @param to 接收地址
     * @param zodiacType 生肖类型 (0-119)
     * @return tokenId NFT ID
     */
    function mint(address to, uint256 zodiacType) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        require(zodiacType < 120, "NFTMint: Invalid zodiac type");
        uint256 tokenId = _nextCardId++;
        uint8 growth = _generateGrowthValue(_generateSecureRandom());
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 批量铸造指定类型的NFT
     * @param to 接收地址
     * @param zodiacTypes 生肖类型数组
     * @return tokenIds NFT ID数组
     */
    function mintBatch(address to, uint256[] calldata zodiacTypes) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        require(zodiacTypes.length > 0, "NFTMint: No zodiac types provided");
        require(zodiacTypes.length <= 100, "NFTMint: Too many tokens to mint");
        uint256[] memory tokenIds = new uint256[](zodiacTypes.length);
        uint256 baseSeed = _generateSecureRandom();
        for (uint256 i = 0; i < zodiacTypes.length; i++) {
            require(zodiacTypes[i] < 120, "NFTMint: Invalid zodiac type");
            uint256 tokenId = _nextCardId++;
            uint8 growth = _generateGrowthValue(baseSeed + i * 1000003);
            _safeMint(to, tokenId);
            tokenType[tokenId] = zodiacTypes[i];
            tokenLevel[tokenId] = 1;
            tokenGrowth[tokenId] = growth;
            _syncNFTData(to, tokenId, zodiacTypes[i], 1, growth);
            tokenIds[i] = tokenId;
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    /**
     * @dev 普通铸造（随机）
     * @param to 接收地址
     * @return tokenId NFT ID
     */
    function mintNormal(address to) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        uint256 randomSeed = _generateSecureRandom();
        uint256 zodiacType = _mintNormal(randomSeed);
        uint8 growth = _generateGrowthValue(randomSeed);
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 稀有铸造（随机，光/暗属性）
     * @param to 接收地址
     * @return tokenId NFT ID
     */
    function mintRare(address to) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        uint256 randomSeed = _generateSecureRandom();
        uint256 zodiacType = _mintRare(randomSeed);
        uint8 growth = _generateGrowthValue(randomSeed);
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 普通十连铸造
     * @param to 接收地址
     * @return tokenIds NFT ID数组
     */
    function mintNormalTen(address to) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = _generateSecureRandom();
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            uint256 zodiacType = _mintNormal(seed);
            uint8 growth = _generateGrowthValue(seed);
            uint256 tokenId = _nextCardId++;
            _safeMint(to, tokenId);
            tokenType[tokenId] = zodiacType;
            tokenLevel[tokenId] = 1;
            tokenGrowth[tokenId] = growth;
            _syncNFTData(to, tokenId, zodiacType, 1, growth);
            tokenIds[i] = tokenId;
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    /**
     * @dev 稀有十连铸造
     * @param to 接收地址
     * @return tokenIds NFT ID数组
     */
    function mintRareTen(address to) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = _generateSecureRandom();
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            uint256 zodiacType = _mintRare(seed);
            uint8 growth = _generateGrowthValue(seed);
            uint256 tokenId = _nextCardId++;
            _safeMint(to, tokenId);
            tokenType[tokenId] = zodiacType;
            tokenLevel[tokenId] = 1;
            tokenGrowth[tokenId] = growth;
            _syncNFTData(to, tokenId, zodiacType, 1, growth);
            tokenIds[i] = tokenId;
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }
    
    /**
     * @dev 指定生肖铸造（铸造该生肖所有10种组合）
     * @param to 接收地址
     * @param baseZodiac 基础生肖 (0-11)
     * @return tokenIds NFT ID数组
     */
    function mintTargeted(address to, uint8 baseZodiac) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        require(baseZodiac < 12, "NFTMint: Invalid zodiac");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 index = 0;
        uint256 baseSeed = _generateSecureRandom();
        for (uint256 element = 0; element < 5; element++) {
            for (uint256 gender = 0; gender < 2; gender++) {
                if (index < 10) {
                    uint256 zodiacType = _calculateZodiacType(element, baseZodiac, gender);
                    uint8 growth = _generateGrowthValue(baseSeed + index * 9973);
                    uint256 tokenId = _nextCardId++;
                    _safeMint(to, tokenId);
                    tokenType[tokenId] = zodiacType;
                    tokenLevel[tokenId] = 1;
                    tokenGrowth[tokenId] = growth;
                    _syncNFTData(to, tokenId, zodiacType, 1, growth);
                    tokenIds[index] = tokenId;
                    index++;
                }
            }
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }

    // ============ 查询函数 ============
    
    /**
     * @dev 获取NFT类型
     * @param tokenId NFT ID
     * @return 生肖类型 (0-119)
     */
    function getNFTType(uint256 tokenId) external view returns (uint256) {
        return tokenType[tokenId];
    }
    
    /**
     * @dev 获取NFT基本信息
     * @param tokenId NFT ID
     * @return tokenType_ 类型
     * @return level 等级
     * @return growth 成长值
     */
    function getNFTInfo(uint256 tokenId) external view returns (uint256, uint8, uint8) {
        return (tokenType[tokenId], tokenLevel[tokenId], tokenGrowth[tokenId]);
    }
    
    /**
     * @dev 获取NFT成长值
     * @param tokenId NFT ID
     * @return 成长值
     */
    function getNFTGrowth(uint256 tokenId) external view returns (uint8) {
        return tokenGrowth[tokenId];
    }
    
    /**
     * @dev 获取NFT完整数据
     * @param tokenId NFT ID
     * @return tokenType_ 类型
     * @return attack 攻击力
     * @return defense 防御力
     * @return health 生命值
     * @return speed 速度
     * @return level 等级
     * @return rank 排名
     * @return name 名称
     * @return imageUrl 图片URL
     */
    function getNFTData(uint256 tokenId) external view returns (
        uint256 tokenType_,
        uint256 attack,
        uint256 defense,
        uint256 health,
        uint256 speed,
        uint256 level,
        uint256 rank,
        string memory name,
        string memory imageUrl
    ) {
        uint256 t = tokenType[tokenId];
        uint8 l = tokenLevel[tokenId];
        uint8 g = tokenGrowth[tokenId];
        
        uint256 baseAttack = 10;
        uint256 baseDefense = 10;
        uint256 baseHealth = 100;
        uint256 baseSpeed = 60;
        
        uint256 attackIncrement = 0;
        uint256 defenseIncrement = 0;
        uint256 healthIncrement = 0;
        uint256 speedIncrement = 0;
        
        if (l > 1) {
            uint256 growthMultiplier = uint256(g);
            
            for (uint256 i = 2; i <= l; i++) {
                attackIncrement += (5 * growthMultiplier) / 100;
                defenseIncrement += (4 * growthMultiplier) / 100;
                healthIncrement += (20 * growthMultiplier) / 100;
                speedIncrement += (3 * growthMultiplier) / 100;
            }
        }
        
        uint256 zodiac = (t / 2) % 12;
        uint256[12] memory zodiacSpeedBase = [
            uint256(65), 45, 75, 85, 78, 82, 90, 40, 95, 55, 60, 38
        ];
        uint256 zodiacSpeedBonus = zodiacSpeedBase[zodiac] - 60;

        uint256 element = t / 24;
        uint8 gender = uint8(t % 2);

        string memory elementName;
        string memory zodiacName;
        if (element == 0) elementName = "水";
        else if (element == 1) elementName = "风";
        else if (element == 2) elementName = "火";
        else if (element == 3) elementName = "暗";
        else elementName = "光";

        string[12] memory zodiacNames = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"];
        zodiacName = zodiacNames[zodiac];

        string memory genderName = gender == 0 ? "公" : "母";
        name = string(abi.encodePacked(elementName, "·", zodiacName, "·", genderName));

        imageUrl = string(abi.encodePacked("ipfs://metadata/", Strings.toString(t), ".json"));

        return (
            t,
            baseAttack + attackIncrement,
            baseDefense + defenseIncrement,
            baseHealth + healthIncrement,
            baseSpeed + speedIncrement + zodiacSpeedBonus,
            uint256(l),
            l,
            name,
            imageUrl
        );
    }
    
    /**
     * @dev 判断NFT是否为稀有
     * @param tokenId NFT ID
     * @return 是否稀有
     */
    function isRare(uint256 tokenId) external view returns (bool) {
        uint256 t = tokenType[tokenId];
        return t >= rareTypeThreshold;
    }
    
    /**
     * @dev 判断NFT是否达到最大等级
     * @param tokenId NFT ID
     * @return 是否最大等级
     */
    function isMaxLevel(uint256 tokenId) external view returns (bool) {
        return tokenLevel[tokenId] >= 5;
    }
    
    /**
     * @dev 获取NFT等级
     * @param tokenId NFT ID
     * @return 等级
     */
    function getNFTLevel(uint256 tokenId) external view returns (uint8) {
        return tokenLevel[tokenId];
    }
    
    /**
     * @dev 管理员设置NFT等级
     * @param tokenId NFT ID
     * @param newLevel 新等级 (1-5)
     */
    function adminSetNFTLevel(uint256 tokenId, uint256 newLevel) external whenNotPaused onlyAuthorized {
        require(newLevel <= 5 && newLevel >= 1, "NFTMint: Invalid level");
        uint8 oldLevel = tokenLevel[tokenId];
        tokenLevel[tokenId] = uint8(newLevel);
        _updateNFTDataLevel(tokenId, uint8(newLevel));
        emit Upgrade(ownerOf(tokenId), tokenId, oldLevel, uint8(newLevel));
    }
    
    /**
     * @dev 获取NFT所有者
     * @param tokenId NFT ID
     * @return 所有者地址
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        return super.ownerOf(tokenId);
    }
    
    /**
     * @dev 安全转移NFT
     * @param from 发送地址
     * @param to 接收地址
     * @param tokenId NFT ID
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721Upgradeable) {
        super.safeTransferFrom(from, to, tokenId);
    }
    
    /**
     * @dev 转移NFT
     * @param from 发送地址
     * @param to 接收地址
     * @param tokenId NFT ID
     */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721Upgradeable) {
        super.transferFrom(from, to, tokenId);
    }
    
    /**
     * @dev 在代币转移前同步更新NFTData合约
     * @param from 发送地址
     * @param to 接收地址
     * @param firstTokenId 第一个NFT ID
     * @param batchSize 批量大小
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        if (nftDataContract != address(0)) {
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 tokenId = firstTokenId + i;
                if (from != address(0)) {
                    // 重试3次
                    bool success1 = false;
                    for (uint8 retry = 0; retry < 3 && !success1; retry++) {
                        (success1, ) = nftDataContract.call(
                            abi.encodeWithSignature("removeUserNFT(address,uint256)", from, tokenId)
                        );
                    }
                    if (!success1) {
                        emit NFTDataSyncFailed(tokenId, tokenType[tokenId]);
                    }
                }
                if (to != address(0)) {
                    // 重试3次
                    bool success2 = false;
                    for (uint8 retry = 0; retry < 3 && !success2; retry++) {
                        (success2, ) = nftDataContract.call(
                            abi.encodeWithSignature("addUserNFT(address,uint256)", to, tokenId)
                        );
                    }
                    if (!success2) {
                        emit NFTDataSyncFailed(tokenId, tokenType[tokenId]);
                    }
                }
            }
        }
    }
    
    /**
     * @dev 检查接口支持
     * @param interfaceId 接口ID
     * @return 是否支持
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev 批量获取NFT类型
     * @param tokenIds NFT ID数组
     * @return 类型数组
     */
    function getNFTInfoBatch(uint256[] calldata tokenIds) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            result[i] = tokenType[tokenIds[i]];
        }
        return result;
    }
    
    /**
     * @dev 获取NFT名称
     * @return 名称
     */
    function name() public view override returns (string memory) {
        return "Zodiac NFT";
    }
    
    /**
     * @dev 获取NFT符号
     * @return 符号
     */
    function symbol() public view override returns (string memory) {
        return "ZNFT";
    }
    
    /**
     * @dev 获取下一个NFT ID
     * @return NFT ID
     */
    function nextCardId() external view returns (uint256) {
        return _nextCardId;
    }
    
    /**
     * @dev 获取用户所有NFT ID
     * @param owner 用户地址
     * @return NFT ID数组
     */
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    // ============ 暂停控制 ============
    
    /**
     * @dev 暂停合约
     * @param reason 暂停原因
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }
    
    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }
    
    /**
     * @dev 升级合约
     * @param newImplementation 新实现地址
     */
    function upgradeTo(address newImplementation) external override onlyOwner {
        _upgradeToAndCall(newImplementation, "", true);
    }
    
    /**
     * @dev 升级合约并调用
     * @param newImplementation 新实现地址
     * @param data 调用数据
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable override onlyOwner {
        _upgradeToAndCall(newImplementation, data, true);
    }
}
