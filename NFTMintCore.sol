// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title NFTMintCore
 * @dev NFT核心铸造合约，负责NFT的创建和管理
 * 
 * 核心职责：
 * 1. NFT铸造：支持多种铸造方式（普通、稀有、指定类型）
 * 2. NFT数据管理：存储NFT的类型、等级、成长值
 * 3. 数据同步：与NFTData合约保持数据同步
 * 4. 权限控制：限制铸造权限，仅授权合约可调用
 * 
 * NFT类型体系：
 * - 12个生肖 × 5个属性 × 2个性别 = 120种类型
 * - 属性：水(0)、风(1)、火(2)、暗(3)、光(4)
 * - 稀有度：普通属性(0-2)占96%，稀有属性(3-4)占4%
 * 
 * 铸造方式：
 * 1. mint(): 指定类型铸造（由TokenBurner调用）
 * 2. mintNormal(): 随机普通属性铸造
 * 3. mintRare(): 随机稀有属性铸造
 * 4. mintAdmin(): 管理员指定类型和成长值铸造
 * 5. mintForBreeding(): 繁殖产生的子代铸造
 * 
 * 成长值系统：
 * - 范围：10-100
 * - 影响NFT属性成长潜力
 * - 由NFTLib.generateGrowthValue()生成
 * 
 * 属性概率分布：
 * - elementProbabilities = [32, 32, 32, 2, 2]
 *   - 水/风/火各32%，暗/光各2%
 * - rareElementProbabilities = [50, 50]
 *   - 稀有属性中暗/光各50%
 * 
 * 安全机制：
 * - ReentrancyGuard: 防止重入攻击
 * - Pausable: 可暂停铸造
 * - 权限控制：仅授权合约可铸造
 * 
 * 数据存储双轨制：
 * - 本合约：tokenType[], tokenLevel[], tokenGrowth[]（ERC721标准存储）
 * - NFTData合约：详细的ZodiacType、用户代币列表等
 */
contract NFTMintCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, INFTMint {
    using NFTLib for uint256;
    
    /**
     * @dev 属性概率分布（水、风、火、暗、光）
     */
    uint256[5] public elementProbabilities;
    /**
     * @dev 稀有属性概率分布（暗、光）
     */
    uint256[2] public rareElementProbabilities;
    
    /**
     * @dev 铸造计数器
     */
    uint256 public mintCounter;
    /**
     * @dev 铸造计数器警告阈值
     */
    uint256 public constant MINT_COUNTER_WARNING_THRESHOLD = 1000000;
    /**
     * @dev 上次铸造区块
     */
    uint256 public lastMintBlock;
    /**
     * @dev 是否触发过计数器警告
     */
    bool public mintCounterWarningTriggered;
    
    /**
     * @dev 下一个NFT ID
     */
    uint256 public _nextCardId;
    /**
     * @dev NFT类型映射（tokenId -> zodiacType）
     */
    mapping(uint256 => uint256) public tokenType;
    /**
     * @dev NFT等级映射（tokenId -> level）
     */
    mapping(uint256 => uint8) public tokenLevel;
    /**
     * @dev NFT成长值映射（tokenId -> growth）
     */
    mapping(uint256 => uint8) public tokenGrowth;
    
    /**
     * @dev NFT数据合约地址
     */
    address public nftDataContract;
    /**
     * @dev 代币销毁合约地址
     */
    address public tokenBurnerContract;
    /**
     * @dev 繁殖合约地址
     */
    address public breedingContract;
    /**
     * @dev 授权器合约地址（Authorizer）
     */
    address public authorizer;
    
    /**
     * @dev 是否暂停铸造
     */
    bool public paused;
    /**
     * @dev 是否允许公开铸造
     */
    bool public allowPublicMinting;
    
    /**
     * @dev NFT铸造事件
     */
    event Mint(address indexed to, uint256 indexed tokenId, uint256 zodiacType, uint8 growth);
    /**
     * @dev 批量铸造事件
     */
    event BatchMint(address indexed to, uint256[] tokenIds);
    /**
     * @dev NFT数据同步失败事件
     */
    event NFTDataSyncFailed(uint256 indexed tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to);
    
    /**
     * @dev 修饰器：确保合约未暂停
     */
    modifier whenNotPaused() {
        require(!paused, "NFTMint: Contract paused");
        _;
    }
    
    /**
     * @dev 修饰器：仅TokenBurner合约可调用
     */
    modifier onlyTokenBurner() {
        require(tokenBurnerContract != address(0), "NFTMint: tokenBurnerContract not set");
        require(msg.sender == tokenBurnerContract, "NFTMint: Only TokenBurner");
        _;
    }
    
    /**
     * @dev 修饰器：仅繁殖合约可调用
     */
    modifier onlyBreeding() {
        require(breedingContract != address(0), "NFTMint: breedingContract not set");
        require(msg.sender == breedingContract, "NFTMint: Only Breeding");
        _;
    }
    
    /**
     * @dev 修饰器：仅授权合约可调用（TokenBurner或Breeding）
     */
    modifier onlyAuthorized() {
        require(tokenBurnerContract != address(0), "NFTMint: tokenBurnerContract not set");
        require(breedingContract != address(0), "NFTMint: breedingContract not set");
        require(msg.sender == tokenBurnerContract || msg.sender == breedingContract, "NFTMint: Unauthorized");
        _;
    }
    
    /**
     * @dev 修饰器：仅所有者或授权器可调用
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTMint: Only owner or authorizer");
        _;
    }
    
    /**
     * @dev 初始化函数
     * @param _nftDataContractAddress NFT数据合约地址
     * @param _tokenBurnerContractAddress 代币销毁合约地址
     * @param _authorizerAddress 授权合约地址
     * @param _breedingContractAddress 繁殖合约地址
     */
    function initialize(address _nftDataContractAddress, address _tokenBurnerContractAddress, address _authorizerAddress, address _breedingContractAddress) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        elementProbabilities = [32, 32, 32, 2, 2];
        rareElementProbabilities = [50, 50];
        nftDataContract = _nftDataContractAddress;
        tokenBurnerContract = _tokenBurnerContractAddress;
        authorizer = _authorizerAddress;
        breedingContract = _breedingContractAddress;
        _nextCardId = 1;
    }
    
    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev 指定类型铸造NFT
     * @param to 接收地址
     * @param zodiacType NFT类型
     * @return tokenId 铸造的NFT ID
     */
    function mint(address to, uint256 zodiacType) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Zero address");
        require(zodiacType < 120, "NFTMint: Invalid type");
        
        uint256 tokenId = _nextCardId++;
        uint8 growth = NFTLib.generateGrowthValue(_generateSecureRandom());
        
        _mint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 铸造普通NFT（随机属性）
     * @param to 接收地址
     * @return tokenId 铸造的NFT ID
     */
    function mintNormal(address to) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Zero address");
        
        uint256 randomSeed = _generateSecureRandom();
        uint256 zodiacType = _mintNormalType(randomSeed);
        uint8 growth = NFTLib.generateGrowthValue(randomSeed);
        
        uint256 tokenId = _nextCardId++;
        _mint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 铸造稀有NFT（暗/光属性）
     * @param to 接收地址
     * @return tokenId 铸造的NFT ID
     */
    function mintRare(address to) external whenNotPaused onlyTokenBurner nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Zero address");
        
        uint256 randomSeed = _generateSecureRandom();
        uint256 zodiacType = _mintRareType(randomSeed);
        uint8 growth = NFTLib.generateGrowthValue(randomSeed);
        
        uint256 tokenId = _nextCardId++;
        _mint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 管理员铸造NFT（可指定类型和成长值）
     * @param to 接收地址
     * @param zodiacType NFT类型
     * @param growth 成长值
     * @return tokenId 铸造的NFT ID
     */
    function mintAdmin(address to, uint256 zodiacType, uint8 growth) external onlyOwner nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Zero address");
        require(zodiacType < 120, "NFTMint: Invalid type");
        require(growth >= 10 && growth <= 100, "NFTMint: Invalid growth");
        
        uint256 tokenId = _nextCardId++;
        _mint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    /**
     * @dev 繁殖铸造NFT（由Breeding合约调用）
     * @param to 接收地址
     * @param zodiacType NFT类型
     * @param growth 成长值
     * @return tokenId 铸造的NFT ID
     */
    function mintForBreeding(address to, uint256 zodiacType, uint8 growth) external onlyBreeding nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Zero address");
        require(zodiacType < 120, "NFTMint: Invalid type");
        require(growth >= 10 && growth <= 100, "NFTMint: Invalid growth");
        
        uint256 tokenId = _nextCardId++;
        _mint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    function mintWithGrowth(address to, uint256 zodiacType, uint8 growth) external onlyTokenBurner nonReentrant returns (uint256) {
        require(to != address(0), "NFTMint: Zero address");
        require(zodiacType < 120, "NFTMint: Invalid type");
        require(growth >= 10 && growth <= 100, "NFTMint: Invalid growth");
        
        uint256 tokenId = _nextCardId++;
        _mint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        tokenGrowth[tokenId] = growth;
        
        _syncNFTData(to, tokenId, zodiacType, 1, growth);
        emit Mint(to, tokenId, zodiacType, growth);
        return tokenId;
    }
    
    function generateSecureRandom() external onlyTokenBurner returns (uint256) {
        return _generateSecureRandom();
    }
    
    function _mintNormalType(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return NFTLib.calculateZodiacType(element, zodiac, gender);
    }
    
    function _mintRareType(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseRareElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return NFTLib.calculateZodiacType(element, zodiac, gender);
    }
    
    function _chooseElement(uint256 randomVal) internal view returns (uint256) {
        uint256[5] memory cumulative;
        cumulative[0] = elementProbabilities[0];
        for (uint256 i = 1; i < 5; i++) {
            cumulative[i] = cumulative[i-1] + elementProbabilities[i];
        }
        uint256 roll = randomVal % 100;
        for (uint256 i = 0; i < 5; i++) {
            if (roll < cumulative[i]) return i;
        }
        return 0;
    }
    
    function _chooseRareElement(uint256 randomVal) internal view returns (uint256) {
        uint256 roll = randomVal % 100;
        return roll < rareElementProbabilities[0] ? 3 : 4;
    }
    
    function _generateSecureRandom() internal returns (uint256) {
        mintCounter++;
        if (mintCounter > type(uint256).max - MINT_COUNTER_WARNING_THRESHOLD && !mintCounterWarningTriggered) {
            mintCounterWarningTriggered = true;
        }
        lastMintBlock = block.number;
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, mintCounter, msg.sender)));
    }

    struct FailedSync {
        uint256 tokenId;
        uint256 zodiacType;
        uint8 level;
        uint8 growth;
        address to;
        uint256 timestamp;
        uint8 retryCount;
    }

    mapping(uint256 => FailedSync) public failedSyncs;
    uint256 public failedSyncCount;
    uint256 public syncFailureWarningTriggered;
    uint256 public constant MAX_RETRY_COUNT = 5;
    uint256 public constant SYNC_FAILURE_WARNING_THRESHOLD = 10;

    function _syncNFTData(address to, uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth) internal {
        require(nftDataContract != address(0), "NFTMint: nftDataContract not set");
        
        try INFTDataInterface(nftDataContract).syncNFTData(tokenId, zodiacType, level, growth, to) {
        } catch (bytes memory reason) {
            emit NFTDataSyncFailed(tokenId, zodiacType, level, growth, to);
            _queueFailedSync(tokenId, zodiacType, level, growth, to);
            
            if (bytes(reason).length > 0) {
                revert(string(abi.encodePacked("NFTMint: Sync failed - ", reason)));
            } else {
                revert("NFTMint: Sync failed");
            }
        }
    }

    function _queueFailedSync(uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to) internal {
        failedSyncs[failedSyncCount] = FailedSync({
            tokenId: tokenId,
            zodiacType: zodiacType,
            level: level,
            growth: growth,
            to: to,
            timestamp: block.timestamp,
            retryCount: 0
        });
        failedSyncCount++;

        if (failedSyncCount >= SYNC_FAILURE_WARNING_THRESHOLD && syncFailureWarningTriggered == 0) {
            syncFailureWarningTriggered = block.timestamp;
        }
    }

    function retryFailedSync(uint256 syncId) external onlyOwner {
        require(syncId < failedSyncCount, "NFTMint: Invalid syncId");
        
        FailedSync storage sync = failedSyncs[syncId];
        require(sync.retryCount < MAX_RETRY_COUNT, "NFTMint: Max retry count exceeded");
        
        try INFTDataInterface(nftDataContract).syncNFTData(sync.tokenId, sync.zodiacType, sync.level, sync.growth, sync.to) {
            _removeFailedSync(syncId);
        } catch {
            sync.retryCount++;
            if (sync.retryCount >= MAX_RETRY_COUNT) {
                _removeFailedSync(syncId);
            }
        }
    }

    function retryAllFailedSyncs() external onlyOwner {
        for (uint256 i = 0; i < failedSyncCount; ) {
            FailedSync storage sync = failedSyncs[i];
            if (sync.retryCount >= MAX_RETRY_COUNT) {
                _removeFailedSync(i);
                continue;
            }

            try INFTDataInterface(nftDataContract).syncNFTData(sync.tokenId, sync.zodiacType, sync.level, sync.growth, sync.to) {
                _removeFailedSync(i);
            } catch {
                sync.retryCount++;
                i++;
            }
        }
    }

    function _removeFailedSync(uint256 syncId) internal {
        if (syncId < failedSyncCount - 1) {
            failedSyncs[syncId] = failedSyncs[failedSyncCount - 1];
        }
        delete failedSyncs[failedSyncCount - 1];
        failedSyncCount--;
    }
    
    function setNftDataContract(address _nftDataContractAddress) external onlyOwnerOrAuthorizer {
        // 修复：零地址检查，防止错误配置导致所有 mint 失败
        require(_nftDataContractAddress != address(0), "NFTMint: nftDataContract cannot be zero address");
        nftDataContract = _nftDataContractAddress;
    }
    
    function setTokenBurnerContract(address _tokenBurnerContractAddress) external onlyOwnerOrAuthorizer {
        // 修复：零地址检查，防止错误配置导致 burner mint 失败
        require(_tokenBurnerContractAddress != address(0), "NFTMint: tokenBurnerContract cannot be zero address");
        tokenBurnerContract = _tokenBurnerContractAddress;
    }
    
    function setBreedingContract(address _breedingContractAddress) external onlyOwnerOrAuthorizer {
        // 修复：零地址检查，防止错误配置导致 breeding mint 失败
        require(_breedingContractAddress != address(0), "NFTMint: breedingContract cannot be zero address");
        breedingContract = _breedingContractAddress;
    }
    
    /**
     * @dev 设置授权器合约地址
     * @param _authorizerAddress 授权器合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "NFTMint: authorizer cannot be zero address");
        authorizer = _authorizerAddress;
    }
    
    function pause() external onlyOwner {
        paused = true;
    }
    
    function unpause() external onlyOwner {
        paused = false;
    }
    
    function setAllowPublicMinting(bool _allow) external onlyOwner {
        allowPublicMinting = _allow;
    }
    
    function resetMintCounter() external onlyOwner {
        mintCounter = 1;
        mintCounterWarningTriggered = false;
    }
    
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");
        
        _beforeTokenTransfer(address(0), to, tokenId, 1);
        
        _ownerOf[tokenId] = to;
        _balanceOf[to]++;
        
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
        
        emit Transfer(address(0), to, tokenId);
        
        _afterTokenTransfer(address(0), to, tokenId, 1);
    }
    
    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
    mapping(address => uint256[]) internal _ownedTokens;
    mapping(uint256 => uint256) internal _ownedTokensIndex;
    
    function _exists(uint256 tokenId) public view returns (bool) {
        return _ownerOf[tokenId] != address(0);
    }
    
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _ownerOf[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }
    
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balanceOf[owner];
    }
    
    function isRare(uint256 tokenId) external view returns (bool) {
        return tokenType[tokenId] >= 72;
    }
    
    function transferFrom(address from, address to, uint256 tokenId) public {
        // 修复：添加 msg.sender 授权检查，确保只有所有者或授权方可以转移
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: caller is not owner nor approved");
        require(_ownerOf[tokenId] == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");
        
        _beforeTokenTransfer(from, to, tokenId, 1);
        
        _ownerOf[tokenId] = to;
        _balanceOf[from]--;
        _balanceOf[to]++;
        
        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);
        
        emit Transfer(from, to, tokenId);
        
        _afterTokenTransfer(from, to, tokenId, 1);
    }
    
    /**
     * @dev 检查调用者是否是 NFT 所有者或被授权者
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _ownerOf[tokenId];
        return (spender == owner || _operatorApprovals[owner][spender]);
    }
    
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastTokenIndex = _ownedTokens[from].length - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];
        
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }
        
        delete _ownedTokensIndex[tokenId];
        _ownedTokens[from].pop();
    }
    
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
    }
    
    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }
    
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        require(index < _ownedTokens[owner].length, "ERC721: owner index out of bounds");
        return _ownedTokens[owner][index];
    }
    
    function nextCardId() external view returns (uint256) {
        return _nextCardId;
    }
    
    function totalSupply() external view returns (uint256) {
        if (_nextCardId == 0) return 0;
        return _nextCardId - 1;
    }
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal virtual {}
    function _afterTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal virtual {}
    
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
        // 修复：检查 to 是合约时是否实现了 IERC721Receiver 接口，避免 NFT 被锁定在不识别 ERC721 的合约中
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, "") returns (bytes4 retval) {
                require(retval == IERC721Receiver.onERC721Received.selector, "ERC721: invalid receiver");
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }
    
    function adminSetNFTLevel(uint256 tokenId, uint256 newLevel) external onlyOwner {
        require(_exists(tokenId), "NFTMint: Token not exists");
        require(newLevel >= 1 && newLevel <= 5, "NFTMint: Invalid level");
        tokenLevel[tokenId] = uint8(newLevel);
    }
    
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = _balanceOf[owner];
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = _ownedTokens[owner][i];
        }
        return tokenIds;
    }
}