// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

contract NFTMint is ERC721, Ownable2StepUpgradeable, UUPSUpgradeable {
    uint256 public constant MINT_COST = 8888 * 10**18;
    uint256 public constant RARE_MINT_COST = 88888 * 10**18;
    uint256 public constant BATCH_MINT_COST = 88880 * 10**18;
    uint256 public constant RARE_BATCH_MINT_COST = 888880 * 10**18;
    uint256 public constant ZODIAC_MINT_COST = 88880 * 10**18;

    uint256[5] public elementProbabilities = [32, 32, 32, 2, 2];
    uint256[2] public rareElementProbabilities = [50, 50];

    uint256 public mintCounter;
    uint256 public lastMintBlock;
    uint256 public _nextCardId;

    address public tokenBurnerContract;
    address public authorizer;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    mapping(uint256 => uint256) public tokenType;
    mapping(uint256 => uint8) public tokenLevel;

    event Mint(address indexed to, uint256 indexed tokenId, uint256 zodiacType);
    event BatchMint(address indexed to, uint256[] tokenIds);
    event Upgrade(address indexed owner, uint256 indexed tokenId, uint8 oldLevel, uint8 newLevel);

    function initialize(address _authorizer) external initializer {
        __ERC721_init("Zodiac NFT", "ZNFT");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
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
                tx.origin,
                block.coinbase,
                block.prevrandao
            )
        );
        return uint256(entropy);
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

    function mint(address to, uint256 zodiacType) external returns (uint256) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        emit Mint(to, tokenId, zodiacType);
        return tokenId;
    }

    function mintBatch(address to, uint256[] calldata zodiacTypes) external returns (uint256[] memory) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        uint256[] memory tokenIds = new uint256[](zodiacTypes.length);
        for (uint256 i = 0; i < zodiacTypes.length; i++) {
            uint256 tokenId = _nextCardId++;
            _safeMint(to, tokenId);
            tokenType[tokenId] = zodiacTypes[i];
            tokenLevel[tokenId] = 1;
            tokenIds[i] = tokenId;
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }

    function mintNormal(address to) external returns (uint256) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        uint256 randomSeed = _generateSecureRandom();
        uint256 zodiacType = _mintNormal(randomSeed);
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        emit Mint(to, tokenId, zodiacType);
        return tokenId;
    }

    function mintRare(address to) external returns (uint256) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        uint256 randomSeed = _generateSecureRandom();
        uint256 zodiacType = _mintRare(randomSeed);
        uint256 tokenId = _nextCardId++;
        _safeMint(to, tokenId);
        tokenType[tokenId] = zodiacType;
        tokenLevel[tokenId] = 1;
        emit Mint(to, tokenId, zodiacType);
        return tokenId;
    }

    function mintNormalTen(address to) external returns (uint256[] memory) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = _generateSecureRandom();
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            uint256 zodiacType = _mintNormal(seed);
            uint256 tokenId = _nextCardId++;
            _safeMint(to, tokenId);
            tokenType[tokenId] = zodiacType;
            tokenLevel[tokenId] = 1;
            tokenIds[i] = tokenId;
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }

    function mintRareTen(address to) external returns (uint256[] memory) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 baseSeed = _generateSecureRandom();
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            uint256 zodiacType = _mintRare(seed);
            uint256 tokenId = _nextCardId++;
            _safeMint(to, tokenId);
            tokenType[tokenId] = zodiacType;
            tokenLevel[tokenId] = 1;
            tokenIds[i] = tokenId;
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }

    function mintTargeted(address to, uint8 baseZodiac) external returns (uint256[] memory) {
        require(msg.sender == tokenBurnerContract || msg.sender == owner(), "NFTMint: Unauthorized");
        require(baseZodiac < 12, "NFTMint: Invalid zodiac");
        uint256[] memory tokenIds = new uint256[](10);
        uint256 index = 0;
        for (uint256 element = 0; element < 5; element++) {
            for (uint256 gender = 0; gender < 2; gender++) {
                if (index < 10) {
                    uint256 zodiacType = _calculateZodiacType(element, baseZodiac, gender);
                    uint256 tokenId = _nextCardId++;
                    _safeMint(to, tokenId);
                    tokenType[tokenId] = zodiacType;
                    tokenLevel[tokenId] = 1;
                    tokenIds[index] = tokenId;
                    index++;
                }
            }
        }
        emit BatchMint(to, tokenIds);
        return tokenIds;
    }

    function getNFTType(uint256 tokenId) external view returns (uint256) {
        return tokenType[tokenId];
    }

    function getNFTInfo(uint256 tokenId) external view returns (uint256, uint8, uint256) {
        return (tokenType[tokenId], tokenLevel[tokenId], 0);
    }

    function isRare(uint256 tokenId) external view returns (bool) {
        uint256 t = tokenType[tokenId];
        return t >= 72;
    }

    function isMaxLevel(uint256 tokenId) external view returns (bool) {
        return tokenLevel[tokenId] >= 5;
    }

    function getNFTLevel(uint256 tokenId) external view returns (uint8) {
        return tokenLevel[tokenId];
    }

    function setNFTLevel(uint256 tokenId, uint256 newLevel) external {
        require(ownerOf(tokenId) == msg.sender || msg.sender == owner(), "NFTMint: Not owner");
        require(newLevel <= 5 && newLevel >= tokenLevel[tokenId], "NFTMint: Invalid level");
        uint8 oldLevel = tokenLevel[tokenId];
        tokenLevel[tokenId] = uint8(newLevel);
        emit Upgrade(ownerOf(tokenId), tokenId, oldLevel, uint8(newLevel));
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        return super.ownerOf(tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        super.safeTransferFrom(from, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        super.transferFrom(from, to, tokenId);
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

    function totalSupply() external view returns (uint256) {
        return _nextCardId - 1;
    }

    function pause(string memory reason) external onlyOwner {
    }

    function unpause() external onlyOwner {
    }

    function upgradeTo(address newImplementation) external override onlyOwner {
        _upgradeToAndCall(newImplementation, "", true);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable override onlyOwner {
        _upgradeToAndCall(newImplementation, data, true);
    }
}