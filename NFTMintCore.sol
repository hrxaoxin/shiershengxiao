// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract NFTMintCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, INFTMint {
    using NFTLib for uint256;
    
    uint256[5] public elementProbabilities;
    uint256[2] public rareElementProbabilities;
    
    uint256 public mintCounter;
    uint256 public constant MINT_COUNTER_WARNING_THRESHOLD = 1000000;
    uint256 public lastMintBlock;
    bool public mintCounterWarningTriggered;
    
    uint256 public _nextCardId;
    mapping(uint256 => uint256) public tokenType;
    mapping(uint256 => uint8) public tokenLevel;
    mapping(uint256 => uint8) public tokenGrowth;
    
    address public nftDataContract;
    address public tokenBurnerContract;
    address public breedingContract;
    
    bool public paused;
    bool public allowPublicMinting;
    
    event Mint(address indexed to, uint256 indexed tokenId, uint256 zodiacType, uint8 growth);
    event BatchMint(address indexed to, uint256[] tokenIds);
    event NFTDataSyncFailed(uint256 indexed tokenId, uint256 zodiacType, uint8 level, uint8 growth, address to);
    
    modifier whenNotPaused() {
        require(!paused, "NFTMint: Contract paused");
        _;
    }
    
    modifier onlyTokenBurner() {
        require(tokenBurnerContract != address(0), "NFTMint: tokenBurnerContract not set");
        require(msg.sender == tokenBurnerContract, "NFTMint: Only TokenBurner");
        _;
    }
    
    modifier onlyBreeding() {
        require(breedingContract != address(0), "NFTMint: breedingContract not set");
        require(msg.sender == breedingContract, "NFTMint: Only Breeding");
        _;
    }
    
    modifier onlyAuthorized() {
        require(tokenBurnerContract != address(0), "NFTMint: tokenBurnerContract not set");
        require(breedingContract != address(0), "NFTMint: breedingContract not set");
        require(msg.sender == tokenBurnerContract || msg.sender == breedingContract, "NFTMint: Unauthorized");
        _;
    }
    
    function initialize(address _nftDataContract, address _tokenBurnerContract) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        elementProbabilities = [32, 32, 32, 2, 2];
        rareElementProbabilities = [50, 50];
        nftDataContract = _nftDataContract;
        tokenBurnerContract = _tokenBurnerContract;
        _nextCardId = 1;
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
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
        } catch {
            emit NFTDataSyncFailed(tokenId, zodiacType, level, growth, to);
            _queueFailedSync(tokenId, zodiacType, level, growth, to);
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
    
    function setNftDataContract(address _nftDataContract) external onlyOwner {
        // 修复：零地址检查，防止错误配置导致所有 mint 失败
        require(_nftDataContract != address(0), "NFTMint: nftDataContract cannot be zero address");
        nftDataContract = _nftDataContract;
    }
    
    function setTokenBurnerContract(address _tokenBurnerContract) external onlyOwner {
        // 修复：零地址检查，防止错误配置导致 burner mint 失败
        require(_tokenBurnerContract != address(0), "NFTMint: tokenBurnerContract cannot be zero address");
        tokenBurnerContract = _tokenBurnerContract;
    }
    
    function setBreedingContract(address _breedingContract) external onlyOwner {
        // 修复：零地址检查，防止错误配置导致 breeding mint 失败
        require(_breedingContract != address(0), "NFTMint: breedingContract cannot be zero address");
        breedingContract = _breedingContract;
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