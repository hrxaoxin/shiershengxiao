// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

enum ZodiacType {
    ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1, ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
    ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0, ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,
    FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1, FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
    FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0, FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,
    HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1, HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
    HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0, HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,
    AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1, AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
    AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0, AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,
    GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1, GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
    GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0, GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
}

interface ITokenBurner {
    function hasBurnedToken(address user) external view returns (bool);
    function decreaseBurnCount(address user) external returns (bool);
    function getBurnCount(address user) external view returns (uint256);
    function burnAndMint(address user) external returns (bool);
}

interface IToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracle {
    function getTokenPriceInUSD() external view returns (uint256);
}

interface IRewardManager {
    function updateCardExternal(address user, ZodiacType t, uint256 cnt) external returns (bool);
    function addWuFu(address user) external returns (bool);
    function _hasAllBasic(address user) external view returns (bool);
    function isWuFuHolder(address user) external view returns (bool);
    function cardCount(address user, ZodiacType t) external view returns (uint256);
    function resetWuFuHolder(address user) external returns (bool);
    function setAuthorizedNFTContract(address nft, bool ok) external;
    function royaltyWallet() external view returns (address);
}

interface IFiveBlessingsMetadata {
    function getCardImage(ZodiacType t) external view returns (string memory);
    function getCardName(ZodiacType t) external view returns (string memory);
    function getCardDesc(ZodiacType t) external view returns (string memory);
    function getNFTName(ZodiacType t, uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
    function collName() external view returns (string memory);
    function collDesc() external view returns (string memory);
    function collImage() external view returns (string memory);
    function sellerFeeBasisPoints() external view returns (uint256);
}

interface IFiveBlessingsNFTWeight {
    function calcUserWeight(address user) external view returns (uint256);
}

interface FiveBlessingsMetadata is IFiveBlessingsMetadata {}

contract FiveBlessingsNFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable
{
    using Counters for Counters.Counter;
    Counters.Counter private _nonce;

    uint256 public constant MAX_SUPPLY = 1000000;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    uint256 public nextCardId;
    address public tokenBurner;
    address public rewardManager;
    address public metadataContract;
    address public authorizer;
    address public tokenContract;
    address public priceOracle;

    mapping(address => bool) public authorizedMinter;
    mapping(uint256 => ZodiacType) public tokenType;
    mapping(uint256 => uint8) public tokenLevel;

    mapping(address => mapping(ZodiacType => mapping(uint8 => uint256[]))) public userTokensByLevel;
    mapping(address => mapping(ZodiacType => mapping(uint8 => uint256))) public userLatestTokenByLevel;
    mapping(address => mapping(ZodiacType => uint256[])) public userTokens;
    mapping(address => mapping(ZodiacType => uint256)) public userLatestToken;

    address public breedingContract;

    uint256[60] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _metadataContract, address _authorizer) external initializer {
        __ERC721_init("Twelve Zodiacs", "12ZODIAC");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC721Holder_init();

        nextCardId = 1;
        authorizedMinter[initialOwner] = true;
        metadataContract = _metadataContract;
        authorizer = _authorizer;
        _nonce.increment();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _getRandomType(uint256 salt) internal returns (ZodiacType) {
        _nonce.increment();
        uint256 rand = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            salt,
            block.timestamp,
            _nonce.current(),
            gasleft()
        )));

        uint256 r = rand % 100;
        
        if (r < 2) {
            return ZodiacType(72 + (rand % 24));
        } else if (r < 4) {
            return ZodiacType(96 + (rand % 24));
        } else {
            return ZodiacType((rand % 48));
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Invalid token ID");

        IFiveBlessingsMetadata metadata = IFiveBlessingsMetadata(metadataContract);
        ZodiacType t = tokenType[tokenId];

        string memory baseCardName = metadata.getCardName(t);
        string memory cardDesc = metadata.getCardDesc(t);
        string memory cardImage = metadata.getCardImage(t);

        string memory nftName = string(abi.encodePacked(baseCardName, " #", _uint2str(tokenId)));

        string memory json = string(abi.encodePacked(
            '{"name":"', nftName, '",',
            '"description":"', cardDesc, '",',
            '"image":"', cardImage, '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            _base64Encode(bytes(json))
        ));
    }

    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        bytes memory base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        bytes memory result = new bytes((data.length + 2) / 3 * 4);
        uint256 cursor = 0;

        for (uint256 i = 0; i < data.length; i += 3) {
            uint256 b0 = uint8(data[i]);
            uint256 b1 = i + 1 < data.length ? uint8(data[i + 1]) : 0;
            uint256 b2 = i + 2 < data.length ? uint8(data[i + 2]) : 0;

            uint256 chunk = (b0 << 16) | (b1 << 8) | b2;

            result[cursor++] = base64[(chunk >> 18) & 0x3F];
            result[cursor++] = base64[(chunk >> 12) & 0x3F];
            result[cursor++] = base64[(chunk >> 6) & 0x3F];
            result[cursor++] = base64[chunk & 0x3F];
        }

        if (data.length % 3 == 1) {
            result[cursor - 2] = '=';
            result[cursor - 1] = '=';
        } else if (data.length % 3 == 2) {
            result[cursor - 1] = '=';
        }

        return string(result);
    }

    function contractURI() public view returns (string memory) {
        require(metadataContract != address(0), "Metadata contract not set");

        FiveBlessingsMetadata metaContract = FiveBlessingsMetadata(metadataContract);
        IRewardManager rm = IRewardManager(rewardManager);

        string memory collName = metaContract.collName();
        string memory collDesc = metaContract.collDesc();
        string memory collImage = metaContract.collImage();

        string memory escapedName = _escapeString(collName);
        string memory escapedDesc = _escapeString(collDesc);
        string memory escapedImage = _escapeString(collImage);

        string memory json = string(abi.encodePacked(
            '{"name":"', escapedName, '",',
            '"description":"', escapedDesc, '",',
            '"image":"', escapedImage, '",',
            '"seller_fee_basis_points":', _uint2str(metaContract.sellerFeeBasisPoints()), ',',
            '"fee_recipient":"', _addressToString(rm.royaltyWallet()), '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            _base64Encode(bytes(json))
        ));
    }

    function mint() external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "Dependencies not set");
        require(nextCardId < MAX_SUPPLY, "Max supply reached");

        ITokenBurner tb = ITokenBurner(tokenBurner);
        require(tb.hasBurnedToken(msg.sender) && tb.getBurnCount(msg.sender) > 0, "No permission");
        require(tb.decreaseBurnCount(msg.sender), "Burn count decrease failed");

        uint256 tokenId = nextCardId++;
        ZodiacType t = _getRandomType(tokenId);
        tokenType[tokenId] = t;
        tokenLevel[tokenId] = 1;

        _safeMint(msg.sender, tokenId);
        userTokens[msg.sender][t].push(tokenId);
        userLatestToken[msg.sender][t] = tokenId;
        userTokensByLevel[msg.sender][t][1].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][1] = tokenId;

        emit CardMinted(tokenId, t, msg.sender, uint64(block.timestamp));
        return tokenId;
    }

    function mintOneStep() external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "Dependencies not set");
        require(nextCardId < MAX_SUPPLY, "Max supply reached");

        ITokenBurner tb = ITokenBurner(tokenBurner);
        require(tb.burnAndMint(msg.sender), "Token burn failed");

        uint256 tokenId = nextCardId++;
        ZodiacType t = _getRandomType(tokenId);
        tokenType[tokenId] = t;
        tokenLevel[tokenId] = 1;

        _safeMint(msg.sender, tokenId);
        userTokens[msg.sender][t].push(tokenId);
        userLatestToken[msg.sender][t] = tokenId;
        userTokensByLevel[msg.sender][t][1].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][1] = tokenId;

        emit CardMinted(tokenId, t, msg.sender, uint64(block.timestamp));
        return tokenId;
    }

    uint256 public constant LIGHT_DARK_COST = 88888;

    function mintLightDark() external nonReentrant returns (uint256) {
        require(tokenContract != address(0), "Token contract not set");
        require(rewardManager != address(0), "RewardManager not set");
        require(nextCardId < MAX_SUPPLY, "Max supply reached");

        IToken token = IToken(tokenContract);
        require(token.balanceOf(msg.sender) >= LIGHT_DARK_COST, "Insufficient tokens");
        require(token.transferFrom(msg.sender, BLACK_HOLE, LIGHT_DARK_COST), "Token transfer failed");

        _nonce.increment();
        uint256 rand = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            nextCardId,
            block.timestamp,
            _nonce.current(),
            gasleft()
        )));

        ZodiacType t;
        if (rand % 2 == 0) {
            t = ZodiacType(72 + (rand % 24));
        } else {
            t = ZodiacType(96 + (rand % 24));
        }

        uint256 tokenId = nextCardId++;
        tokenType[tokenId] = t;
        tokenLevel[tokenId] = 1;

        _safeMint(msg.sender, tokenId);
        userTokens[msg.sender][t].push(tokenId);
        userLatestToken[msg.sender][t] = tokenId;
        userTokensByLevel[msg.sender][t][1].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][1] = tokenId;

        emit CardMinted(tokenId, t, msg.sender, uint64(block.timestamp));
        return tokenId;
    }

    function mintSpecificType(address to, ZodiacType t) external nonReentrant returns (uint256) {
        require(authorizedMinter[msg.sender] || msg.sender == owner(), "Not authorized");
        require(to != address(0) && nextCardId < MAX_SUPPLY, "Invalid params");

        uint256 tokenId = nextCardId++;
        tokenType[tokenId] = t;
        tokenLevel[tokenId] = 1;
        _safeMint(to, tokenId);

        userTokens[to][t].push(tokenId);
        userLatestToken[to][t] = tokenId;
        userTokensByLevel[to][t][1].push(tokenId);
        userLatestTokenByLevel[to][t][1] = tokenId;

        emit CardMinted(tokenId, t, to, uint64(block.timestamp));
        return tokenId;
    }

    function _burnCard(address user, ZodiacType t) internal {
        uint256 tokenId = userLatestToken[user][t];
        require(tokenId != 0 && _ownerOf(tokenId) == user, "Not owner of token");

        _transfer(user, BLACK_HOLE, tokenId);

        uint256[] storage tokens = userTokens[user][t];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        userLatestToken[user][t] = tokens.length > 0 ? tokens[tokens.length - 1] : 0;
        emit CardBurned(tokenId, t, user);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        address prevOwner = super._update(to, tokenId, auth);

        if (from != address(0) && from != BLACK_HOLE) {
            ZodiacType t = tokenType[tokenId];
            uint8 level = tokenLevel[tokenId];
            _removeToken(from, t, tokenId);
            _removeTokenByLevel(from, t, level, tokenId);
            _updateReward(from, t, false);
        }

        if (to != address(0) && to != BLACK_HOLE) {
            ZodiacType t = tokenType[tokenId];
            uint8 level = tokenLevel[tokenId];
            userTokens[to][t].push(tokenId);
            userLatestToken[to][t] = tokenId;
            userTokensByLevel[to][t][level].push(tokenId);
            userLatestTokenByLevel[to][t][level] = tokenId;
            _updateReward(to, t, true);
        }

        return prevOwner;
    }

    function _removeToken(address user, ZodiacType t, uint256 tokenId) internal {
        uint256[] storage tokens = userTokens[user][t];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }

    function _removeTokenByLevel(address user, ZodiacType t, uint8 level, uint256 tokenId) internal {
        uint256[] storage tokens = userTokensByLevel[user][t][level];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
        userLatestTokenByLevel[user][t][level] = tokens.length > 0 ? tokens[tokens.length - 1] : 0;
    }

    function _updateReward(address user, ZodiacType t, bool isAdd) internal {
        if (rewardManager == address(0)) return;

        IRewardManager rm = IRewardManager(rewardManager);
        uint256 cnt = rm.cardCount(user, t);

        uint256 newCount = isAdd ? cnt + 1 : (cnt > 0 ? cnt - 1 : 0);
        require(rm.updateCardExternal(user, t, newCount), isAdd ? "Update add failed" : "Update sub failed");
        rm.refreshUserWeight(user);
    }

    function _escapeString(string memory input) internal pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        uint256 escapeCount = 0;

        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == "\"" || inputBytes[i] == "\\") {
                escapeCount++;
            }
        }

        if (escapeCount == 0) return input;

        bytes memory outputBytes = new bytes(inputBytes.length + escapeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == "\"" || inputBytes[i] == "\\") {
                outputBytes[j++] = "\\";
            }
            outputBytes[j++] = inputBytes[i];
        }

        return string(outputBytes);
    }

    function _zodiacTypeToString(ZodiacType t) internal pure returns (string memory) {
        return _uint2str(uint(t));
    }

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function _uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 len;
        while (temp != 0) {
            len++;
            temp /= 10;
        }
        bytes memory buf = new bytes(len);
        while (n != 0) {
            len--;
            buf[len] = bytes1(uint8(48 + n % 10));
            n /= 10;
        }
        return string(buf);
    }

    function setAddresses(address tb, address rm) external {
        require(msg.sender == owner() || msg.sender == authorizer, "FiveBlessingsNFT: Unauthorized");
        require(tb != address(0) && rm != address(0), "Invalid zero address");
        tokenBurner = tb;
        rewardManager = rm;
        IRewardManager(rm).setAuthorizedNFTContract(address(this), true);
    }

    function setMetadataContract(address _metadataContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "FiveBlessingsNFT: Unauthorized");
        require(_metadataContract != address(0), "Invalid zero address");
        metadataContract = _metadataContract;
    }

    function authorizeMinter(address minter) external onlyOwner {
        require(minter != address(0), "Invalid zero address");
        authorizedMinter[minter] = true;
    }

    function unauthorizedMinter(address minter) external onlyOwner {
        authorizedMinter[minter] = false;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "Invalid zero address");
        authorizer = _authorizer;
    }

    function setTokenContract(address _tokenContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "FiveBlessingsNFT: Unauthorized");
        require(_tokenContract != address(0), "Invalid zero address");
        tokenContract = _tokenContract;
    }

    function setPriceOracle(address _priceOracle) external {
        require(msg.sender == owner() || msg.sender == authorizer, "FiveBlessingsNFT: Unauthorized");
        require(_priceOracle != address(0), "Invalid zero address");
        priceOracle = _priceOracle;
    }

    function getCardCount(address user, ZodiacType t) external view returns (uint256) {
        require(rewardManager != address(0), "RewardManager not set");
        return IRewardManager(rewardManager).cardCount(user, t);
    }

    function getUserTokens(address user, ZodiacType t) external view returns (uint256[] memory) {
        return userTokens[user][t];
    }

    function getUserTokensByLevel(address user, ZodiacType t, uint8 level) external view returns (uint256[] memory) {
        return userTokensByLevel[user][t][level];
    }

    function upgradeWithNFT(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "Not owner of token");
        ZodiacType t = tokenType[tokenId];
        uint8 currentLevel = tokenLevel[tokenId];
        require(currentLevel < 6, "Already max level");

        uint8 requiredCount = currentLevel;
        uint256[] storage tokens = userTokensByLevel[msg.sender][t][currentLevel];
        require(tokens.length >= requiredCount + 1, "Not enough NFTs to upgrade");

        for (uint i = 0; i < requiredCount; i++) {
            if (tokens[i] != tokenId) {
                _transfer(msg.sender, BLACK_HOLE, tokens[i]);
                _removeToken(msg.sender, t, tokens[i]);
                _removeTokenByLevel(msg.sender, t, currentLevel, tokens[i]);
                emit CardBurned(tokens[i], t, msg.sender);
            }
        }

        uint8 newLevel = currentLevel + 1;
        tokenLevel[tokenId] = newLevel;
        _removeTokenByLevel(msg.sender, t, currentLevel, tokenId);
        userTokensByLevel[msg.sender][t][newLevel].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][newLevel] = tokenId;

        emit CardUpgraded(tokenId, t, currentLevel, newLevel, msg.sender, uint64(block.timestamp));
        IRewardManager(rewardManager).refreshUserWeight(msg.sender);
        return newLevel;
    }

    function upgradeWithToken(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "Not owner of token");
        require(tokenContract != address(0), "Token contract not set");
        
        ZodiacType t = tokenType[tokenId];
        uint8 currentLevel = tokenLevel[tokenId];
        require(currentLevel < 6, "Already max level");

        uint256 requiredTokens;
        if (currentLevel == 1) requiredTokens = 10000;
        else if (currentLevel == 2) requiredTokens = 40000;
        else if (currentLevel == 3) requiredTokens = 120000;
        else if (currentLevel == 4) requiredTokens = 480000;
        else if (currentLevel == 5) requiredTokens = 2400000;
        else revert("Invalid level");

        IToken token = IToken(tokenContract);
        require(token.balanceOf(msg.sender) >= requiredTokens, "Insufficient token balance");
        require(token.transferFrom(msg.sender, BLACK_HOLE, requiredTokens), "Token transfer failed");

        uint8 newLevel = currentLevel + 1;
        tokenLevel[tokenId] = newLevel;
        _removeTokenByLevel(msg.sender, t, currentLevel, tokenId);
        userTokensByLevel[msg.sender][t][newLevel].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][newLevel] = tokenId;

        emit CardUpgraded(tokenId, t, currentLevel, newLevel, msg.sender, uint64(block.timestamp));
        IRewardManager(rewardManager).refreshUserWeight(msg.sender);
        return newLevel;
    }

    function upgradeWithUSDValue(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "Not owner of token");
        require(tokenContract != address(0), "Token contract not set");
        require(priceOracle != address(0), "Price oracle not set");
        
        ZodiacType t = tokenType[tokenId];
        uint8 currentLevel = tokenLevel[tokenId];
        require(currentLevel < 6, "Already max level");

        uint256 requiredUSDValue;
        if (currentLevel == 1) requiredUSDValue = 1 ether; // 1 USDT
        else if (currentLevel == 2) requiredUSDValue = 4 ether; // 4 USDT
        else if (currentLevel == 3) requiredUSDValue = 12 ether; // 12 USDT
        else if (currentLevel == 4) requiredUSDValue = 48 ether; // 48 USDT
        else if (currentLevel == 5) requiredUSDValue = 240 ether; // 240 USDT
        else revert("Invalid level");

        IPriceOracle oracle = IPriceOracle(priceOracle);
        uint256 tokenPriceInUSD = oracle.getTokenPriceInUSD();
        require(tokenPriceInUSD > 0, "Invalid token price");

        uint256 requiredTokens = (requiredUSDValue * 10**18) / tokenPriceInUSD;
        require(requiredTokens > 0, "Required tokens must be greater than 0");

        IToken token = IToken(tokenContract);
        require(token.balanceOf(msg.sender) >= requiredTokens, "Insufficient token balance");
        require(token.transferFrom(msg.sender, BLACK_HOLE, requiredTokens), "Token transfer failed");

        uint8 newLevel = currentLevel + 1;
        tokenLevel[tokenId] = newLevel;
        _removeTokenByLevel(msg.sender, t, currentLevel, tokenId);
        userTokensByLevel[msg.sender][t][newLevel].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][newLevel] = tokenId;

        emit CardUpgraded(tokenId, t, currentLevel, newLevel, msg.sender, uint64(block.timestamp));
        IRewardManager(rewardManager).refreshUserWeight(msg.sender);
        return newLevel;
    }

    function setBreedingContract(address _breedingContract) external onlyOwner {
        require(_breedingContract != address(0), "Invalid address");
        breedingContract = _breedingContract;
    }

    function mintBreedResult(address to, ZodiacType t) external returns (uint256) {
        require(msg.sender == breedingContract, "Not authorized");
        require(nextCardId < MAX_SUPPLY, "Max supply reached");

        uint256 tokenId = nextCardId++;
        tokenType[tokenId] = t;
        tokenLevel[tokenId] = 1;
        _safeMint(to, tokenId);
        userTokens[to][t].push(tokenId);
        userLatestToken[to][t] = tokenId;
        userTokensByLevel[to][t][1].push(tokenId);
        userLatestTokenByLevel[to][t][1] = tokenId;

        emit CardMinted(tokenId, t, to, uint64(block.timestamp));
        return tokenId;
    }

    event CardMinted(uint256 indexed cardId, ZodiacType indexed cardType, address indexed owner, uint64 timestamp);
    event CardBurned(uint256 indexed cardId, ZodiacType indexed cardType, address indexed owner);
    event WuFuSynthesized(address indexed user, uint256 timestamp, uint256 wanNengUsed);
    event CardUpgraded(uint256 indexed cardId, ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);

    function calcUserWeight(address user) external view returns (uint256) {
        uint256 totalWeight = 0;
        for (uint i = 0; i < 120; i++) {
            ZodiacType t = ZodiacType(i);
            uint256[] memory tokens = userTokens[user][t];
            for (uint j = 0; j < tokens.length; j++) {
                uint256 tokenId = tokens[j];
                uint8 level = tokenLevel[tokenId];
                totalWeight += level + 2;
            }
        }
        return totalWeight;
    }
}
