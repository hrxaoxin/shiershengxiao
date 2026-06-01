// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";

contract NFTMint is ERC721EnumerableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    uint256[5] public elementProbabilities = [32, 32, 32, 2, 2];
    uint256[2] public rareElementProbabilities = [50, 50];

    uint256 public mintCounter;
    uint256 public lastMintBlock;
    uint256 public _nextCardId;

    address public tokenBurnerContract;
    address public authorizer;
    address public nftDataContract;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    bool public paused;
    string public pauseReason;
    bool public allowPublicMinting = false;
    uint256 public rareTypeThreshold = 72;
    
    mapping(uint256 => uint256) public tokenType;
    mapping(uint256 => uint8) public tokenLevel;
    mapping(uint256 => uint8) public tokenGrowth;

    event Mint(address indexed to, uint256 indexed tokenId, uint256 zodiacType, uint8 growth);
    event NFTDataSyncFailed(uint256 indexed tokenId, uint256 zodiacType);
    event BatchMint(address indexed to, uint256[] tokenIds);
    event Upgrade(address indexed owner, uint256 indexed tokenId, uint8 oldLevel, uint8 newLevel);
    event Paused(address account, string reason);
    event Unpaused(address account);
    event PublicMintingToggled(bool allowed);

    function initialize(address _authorizer) external initializer {
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
        nftDataContract = _nftData;
    }
    
    function _syncNFTData(address to, uint256 tokenId, uint256 zodiacType, uint8 level, uint8 growth) internal {
        if (nftDataContract != address(0)) {
            (bool success, ) = nftDataContract.call(
                abi.encodeWithSignature(
                    "setNFTInfo(uint256,uint256,uint8,uint8,uint256,address)",
                    tokenId, zodiacType, level, growth, block.timestamp, to
                )
            );
            if (!success) {
                emit NFTDataSyncFailed(tokenId, zodiacType);
            }
        }
    }
    
    function _updateNFTDataLevel(uint256 tokenId, uint8 newLevel) internal {
        if (nftDataContract != address(0)) {
            (bool success, ) = nftDataContract.call(
                abi.encodeWithSignature("setTokenLevel(uint256,uint8)", tokenId, newLevel)
            );
            if (!success) {
                emit NFTDataSyncFailed(tokenId, tokenType[tokenId]);
            }
        }
    }

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

    function _generateGrowthValue(uint256 randomSeed) internal pure returns (uint8) {
        uint256 roll = randomSeed % 91;
        return uint8(roll + 10);
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

        string[12] memory zodiacNames = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"};
        zodiacName = zodiacNames[zodiac];

        string memory genderName = gender == 0 ? "公" : "母";
        string memory name = string(abi.encodePacked(elementName, "·", zodiacName, "·", genderName));

        string memory imageUrl = string(abi.encodePacked("ipfs://metadata/", Strings.toString(t), ".json"));

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

    function isRare(uint256 tokenId) external view returns (bool) {
        uint256 t = tokenType[tokenId];
        return t >= rareTypeThreshold;
    }
    
    function setRareTypeThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold <= 120, "NFTMint: Invalid threshold");
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

    function ownerOf(uint256 tokenId) public view override returns (address) {
        return super.ownerOf(tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721Upgradeable) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721Upgradeable) {
        super.transferFrom(from, to, tokenId);
    }

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
                    (bool success1, ) = nftDataContract.call(
                        abi.encodeWithSignature("removeUserNFT(address,uint256)", from, tokenId)
                    );
                    if (!success1) {
                        emit NFTDataSyncFailed(tokenId, tokenType[tokenId]);
                    }
                }
                if (to != address(0)) {
                    (bool success2, ) = nftDataContract.call(
                        abi.encodeWithSignature("addUserNFT(address,uint256)", to, tokenId)
                    );
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
}