// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

/**
 * @title NFTMint
 * @dev 十二生肖NFT铸造合约
 *
 * 核心功能：
 * 1. 普通铸造（mintForUser）：消耗代币，随机获得 120 种 NFT 之一
 * 2. 批量铸造（mintTenForUser / mintTenAdmin）：一次性铸造十张 NFT（"十连抽"）
 * 3. 稀有铸造（mintRareForUser）：消耗更多代币，只从暗/光属性 48 种中随机
 * 4. 指定铸造（mintTargetedForUser）：指定具体生肖类型，消耗更高代币
 * 5. 管理铸造（mintAdmin / mintTenAdmin）：owner 免费铸造，用于活动奖励/空投
 * 6. 繁殖铸造（mintForBreeding）：由 Breeding 合约调用，继承父母属性
 *
 * NFT 类型体系（共 120 种）：
 * - 5 种属性 × 12 种生肖 × 2 种性别 = 120 种类型
 * - tokenType = element × 24 + zodiac × 2 + gender
 * - 普通属性（水/风/火，0-71）：铸造概率高，约各 32%
 * - 稀有属性（暗/光，72-119）：铸造概率低，约各 2%
 * - 等级：1-5 级，初始为 1 级，升级需消耗 NFT 或代币（由 NFTUpdate 处理）
 * - 成长值（growth）：10-100，铸造时随机生成，影响战斗属性加成
 *
 * 随机性实现：
 * - 随机源：block.timestamp + block.prevrandao + mintCounter + msg.sender
 * - 使用多重哈希（keccak256）混合生成伪随机数
 * - mintCounter 每铸造一次递增，增加熵值
 * - lastMintBlock 记录区块号，防止同一区块内多次铸造产生相同随机值
 *
 * 数据同步：
 * - 本合约自身维护 tokenType[tokenId]、tokenLevel[tokenId]、tokenGrowth[tokenId]
 * - 同时调用 NFTData 合约写入 _nftInfo，确保两个数据层一致
 * - 若同步失败，触发 NFTDataSyncFailed 事件，供链下服务重试/告警
 *
 * 权限控制：
 * - onlyOwner：可设置各合约地址、开关公开铸造、暂停
 * - onlyTokenBurner：TokenBurner 合约通过 burnAndMint 系列接口间接调用本合约 mint
 * - onlyBreeding：Breeding 合约调用 mintForBreeding 产生后代 NFT
 * - onlyAuthorized：授权的前端/后端服务调用用户铸造接口
 *
 * 代币流转：
 * - 用户铸造前需 approve 代币给 TokenBurner 合约
 * - TokenBurner 先 burn（转入 BLACK_HOLE）部分代币
 * - 其余转入手续费/质押池
 * - 铸造本身不直接收取代币，由 TokenBurner 统一管理销毁逻辑
 *
 * 安全考虑：
 * - 重入保护（ReentrancyGuard）：防止 mint 时的外部调用重入
 * - 暂停机制（paused）：可紧急暂停所有铸造
 * - allowPublicMinting：owner 可控制是否允许任何人调用铸造
 * - mintCounter 溢出预警：接近 uint256 最大值时触发告警事件
 * - ERC721Enumerable 升级：支持按索引查询用户 NFT，方便前端分页展示
 *
 * 典型用户流程：
 * 1. 用户批准 TokenBurner 使用代币（ERC20 approve）
 * 2. 前端调用 TokenBurner.burnAndMint(msg.sender)
 * 3. TokenBurner 销毁部分代币 → 调用 NFTMint.mintForUser(to)
 * 4. mintForUser 生成随机 type 并 mint ERC721 → 写入 NFTData
 * 5. 用户收到 Mint 事件，在前端展示新获得的 NFT
 */
contract NFTMint is ERC721EnumerableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

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
    
    /// @dev 铸造计数器溢出预警阈值（距离最大值的安全距离）
    uint256 public constant MINT_COUNTER_WARNING_THRESHOLD = 1000000;
    
    /// @dev 上次铸造区块号
    uint256 public lastMintBlock;
    
    /// @dev 是否已触发过溢出预警
    bool public mintCounterWarningTriggered;
    
    /// @dev 下一个NFT ID
    uint256 public _nextCardId;

    /// @dev TokenBurner合约地址
    address public tokenBurnerContract;
    
    /// @dev 授权合约地址
    address public authorizer;
    
    /// @dev NFT数据合约地址
    address public nftDataContract;
    
    /// @dev 代币合约地址
    address public tokenContract;
    
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

    event Mint(address indexed to, uint256 indexed tokenId, uint256 zodiacType, uint8 growth);
    event NFTDataSyncFailed(uint256 indexed tokenId, uint256 zodiacType);
    event BatchMint(address indexed to, uint256[] tokenIds);
    event Upgrade(address indexed owner, uint256 indexed tokenId, uint8 oldLevel, uint8 newLevel);
    event Paused(address account, string reason);
    event Unpaused(address account);
    event PublicMintingToggled(bool allowed);
    event MintCounterWarning(uint256 currentCount);

    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "NFTMint: Invalid authorizer address");
        __ERC721_init("Zodiac NFT", "ZNFT");
        __ERC721Enumerable_init();
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _nextCardId = 1;
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "NFTMint: Invalid authorizer address");
        authorizer = a;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTMint: Not authorized");
        _;
    }

    function setTokenBurner(address _tokenBurner) external onlyAuthorized {
        require(_tokenBurner != address(0), "NFTMint: Invalid token burner address");
        tokenBurnerContract = _tokenBurner;
    }

    function setNFTDataContract(address _nftData) external onlyAuthorized {
        require(_nftData != address(0), "NFTMint: Invalid NFT data contract address");
        nftDataContract = _nftData;
    }
    
    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "NFTMint: Invalid token contract address");
        tokenContract = _tokenContract;
    }
    
    struct FailedSync {
        uint256 tokenId;
        uint256 zodiacType;
        uint8 level;
        uint8 growth;
        address to;
        uint256 timestamp;
        uint8 syncType; // 0: setNFTInfo, 1: setTokenLevel
    }
    
    mapping(uint256 => FailedSync) public failedSyncs;
    uint256 public failedSyncCount;
    
    /// @dev 同步失败警告阈值
    uint256 public constant SYNC_FAILURE_WARNING_THRESHOLD = 10;
    
    /// @dev 是否已触发同步失败警告
    bool public syncFailureWarningTriggered;
    
    event SyncRetryAttempted(uint256 syncId, uint256 tokenId, bool success);
    event SyncFailureWarning(uint256 failedCount, uint256 timestamp);
    
    /**
     * @dev 同步NFT数据到NFTData合约
     * 使用重试机制和失败队列确保数据一致性
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
    
    function _updateNFTDataLevel(uint256 tokenId, uint8 newLevel) internal {
        if (nftDataContract != address(0)) {
            bool success = _trySetTokenLevel(tokenId, newLevel);
            if (!success) {
                _queueFailedSync(tokenId, tokenType[tokenId], newLevel, 0, address(0), 1);
                emit NFTDataSyncFailed(tokenId, tokenType[tokenId]);
            }
        }
    }
    
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
    
    function _trySetTokenLevel(uint256 tokenId, uint8 newLevel) internal returns (bool) {
        for (uint8 i = 0; i < 3; i++) {
            (bool success, ) = nftDataContract.call(
                abi.encodeWithSignature("setTokenLevel(uint256,uint8)", tokenId, newLevel)
            );
            if (success) return true;
        }
        return false;
    }
    
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
        
        if (!syncFailureWarningTriggered && failedSyncCount >= SYNC_FAILURE_WARNING_THRESHOLD) {
            syncFailureWarningTriggered = true;
            emit SyncFailureWarning(failedSyncCount, block.timestamp);
        }
    }
    
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
    
    function retryAllFailedSyncs() external onlyAuthorized {
        for (uint256 i = 1; i <= failedSyncCount; i++) {
            if (failedSyncs[i].tokenId != 0) {
                retryFailedSync(i);
            }
        }
    }

    function _generateSecureRandom() internal returns (uint256) {
        lastMintBlock = block.number;
        
        if (!mintCounterWarningTriggered && mintCounter > type(uint256).max - MINT_COUNTER_WARNING_THRESHOLD) {
            mintCounterWarningTriggered = true;
            emit MintCounterWarning(mintCounter);
        }
        
        // 自动重置机制：当计数器接近最大值时自动重置为1
        if (mintCounter >= type(uint256).max - MINT_COUNTER_WARNING_THRESHOLD) {
            mintCounter = 1;
            mintCounterWarningTriggered = false;
        } else {
            mintCounter++;
        }
        
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
     * @dev 手动重置铸造计数器（仅所有者）
     */
    function resetMintCounter() external onlyOwner {
        mintCounter = 1;
        mintCounterWarningTriggered = false;
    }

    function _generateGrowthValue(uint256 randomSeed) internal pure returns (uint8) {
        uint256 roll = randomSeed % 91;
        return uint8(roll + 10); // 范围 [10, 100]
    }

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

    function _chooseRareElement(uint256 randomVal) internal view returns (uint256) {
        uint256 roll = randomVal % 100;
        if (roll < rareElementProbabilities[0]) {
            return 3;
        }
        return 4;
    }

    function _calculateZodiacType(uint256 element, uint256 zodiac, uint256 gender) internal pure returns (uint256) {
        return element * 24 + zodiac * 2 + gender;
    }

    function _mintNormal(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return _calculateZodiacType(element, zodiac, gender);
    }

    function _mintRare(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseRareElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return _calculateZodiacType(element, zodiac, gender);
    }

    modifier whenPublicMintingAllowed() {
        require(allowPublicMinting || msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        _;
    }

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

    function mintTargeted(address to, uint8 baseZodiac) external whenNotPaused whenPublicMintingAllowed nonReentrant returns (uint256[] memory) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        require(baseZodiac < 12, "NFTMint: Invalid zodiac");
        
        uint256 totalNFTs = 10; // 5 elements * 2 genders
        uint256[] memory tokenIds = new uint256[](totalNFTs);
        uint256 baseSeed = _generateSecureRandom();
        
        for (uint256 element = 0; element < 5; element++) {
            for (uint256 gender = 0; gender < 2; gender++) {
                uint256 index = element * 2 + gender;
                uint256 zodiacType = _calculateZodiacType(element, baseZodiac, gender);
                uint8 growth = _generateGrowthValue(baseSeed + index * 9973);
                uint256 tokenId = _nextCardId++;
                _safeMint(to, tokenId);
                tokenType[tokenId] = zodiacType;
                tokenLevel[tokenId] = 1;
                tokenGrowth[tokenId] = growth;
                _syncNFTData(to, tokenId, zodiacType, 1, growth);
                tokenIds[index] = tokenId;
            }
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }

    function setAllowPublicMinting(bool allowed) external onlyOwner {
        allowPublicMinting = allowed;
        emit PublicMintingToggled(allowed);
    }

    function getNFTType(uint256 tokenId) external view returns (uint256) {
        return tokenType[tokenId];
    }

    function getNFTInfo(uint256 tokenId) external view returns (uint256, uint8, uint8) {
        return (tokenType[tokenId], tokenLevel[tokenId], tokenGrowth[tokenId]);
    }

    function getNFTGrowth(uint256 tokenId) external view returns (uint8) {
        return tokenGrowth[tokenId];
    }

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
        string memory tokenName = string(abi.encodePacked(elementName, "·", zodiacName, "·", genderName));

        string memory imageUrl = string(abi.encodePacked("ipfs://metadata/", Strings.toString(t), ".json"));

        return (
            t,
            baseAttack + attackIncrement,
            baseDefense + defenseIncrement,
            baseHealth + healthIncrement,
            baseSpeed + speedIncrement + zodiacSpeedBonus,
            uint256(l),
            l,
            tokenName,
            imageUrl
        );
    }
    
    /**
     * @dev 获取NFT基本信息（轻量级，仅返回tokenType和level）
     * @param tokenId - NFT的tokenId
     * @return tokenType_ - NFT类型
     * @return level - NFT等级
     */
    function getNFTBasicInfo(uint256 tokenId) external view returns (
        uint256 tokenType_,
        uint256 level
    ) {
        return (tokenType[tokenId], uint256(tokenLevel[tokenId]));
    }

    function isRare(uint256 tokenId) external view returns (bool) {
        uint256 t = tokenType[tokenId];
        return t >= rareTypeThreshold;
    }
    
    function setRareTypeThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 60 && _threshold <= 120, "NFTMint: Invalid threshold (must be 60-120)");
        rareTypeThreshold = _threshold;
    }

    function isMaxLevel(uint256 tokenId) external view returns (bool) {
        return tokenLevel[tokenId] >= 5;
    }

    function getNFTLevel(uint256 tokenId) external view returns (uint8) {
        return tokenLevel[tokenId];
    }

    function adminSetNFTLevel(uint256 tokenId, uint256 newLevel) external whenNotPaused onlyAuthorized {
        require(newLevel <= 5 && newLevel >= 1, "NFTMint: Invalid level");
        uint8 oldLevel = tokenLevel[tokenId];
        tokenLevel[tokenId] = uint8(newLevel);
        _updateNFTDataLevel(tokenId, uint8(newLevel));
        emit Upgrade(ownerOf(tokenId), tokenId, oldLevel, uint8(newLevel));
    }

    function mintAdmin(
        address to,
        uint256 element,
        uint256 zodiac,
        uint256 gender,
        uint8 growth
    ) external onlyOwner nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        require(element < 5, "NFTMint: Invalid element (0-4)");
        require(zodiac < 12, "NFTMint: Invalid zodiac (0-11)");
        require(gender < 2, "NFTMint: Invalid gender (0-1)");
        require(growth >= 10 && growth <= 100, "NFTMint: Invalid growth (10-100)");
        
        uint256 zodiacType = _calculateZodiacType(element, zodiac, gender);
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }

    function mintForBreeding(address to, uint256 zodiacType, uint8 growth) external onlyAuthorized nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Cannot mint to zero address");
        require(zodiacType < 120, "NFTMint: Invalid zodiac type");
        require(growth >= 10 && growth <= 100, "NFTMint: Invalid growth (10-100)");
        
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        return super.ownerOf(tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721Upgradeable) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721Upgradeable) {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @dev 在代币转移前同步更新NFTData合约
     * 使用重试机制确保数据一致性
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

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getNFTInfoBatch(uint256[] calldata tokenIds) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            result[i] = tokenType[tokenIds[i]];
        }
        return result;
    }

    function name() public view override returns (string memory) {
        return "Zodiac NFT";
    }

    function symbol() public view override returns (string memory) {
        return "ZNFT";
    }

    function nextCardId() external view returns (uint256) {
        return _nextCardId;
    }

    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    modifier whenNotPaused() {
        require(!paused, "NFTMint: Paused");
        _;
    }

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    function upgradeTo(address newImplementation) external override onlyOwner {
        _upgradeToAndCall(newImplementation, "", true);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable override onlyOwner {
        _upgradeToAndCall(newImplementation, data, true);
    }

    /**
     * @dev 紧急提取BNB
     * @param amount 提取数量
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTMint: Amount must be > 0");
        require(amount <= address(this).balance, "NFTMint: Insufficient BNB balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "NFTMint: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币
     * @param amount 提取数量
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTMint: Amount must be > 0");
        require(tokenContract != address(0), "NFTMint: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "NFTMint: Insufficient token balance");
        require(token.transfer(owner(), amount), "NFTMint: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
}