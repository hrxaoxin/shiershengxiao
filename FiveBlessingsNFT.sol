// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 确保导入路径正确，使用最新的OpenZeppelin升级合约版本
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

enum ZodiacType { Rat, Ox, Tiger, Rabbit, Dragon, Snake, Horse, Goat, Monkey, Rooster, Dog, Pig }

interface ITokenBurner {
    function hasBurnedToken(address user) external view returns (bool);
    function decreaseBurnCount(address user) external returns (bool);
    function getBurnCount(address user) external view returns (uint256);
}

interface IRewardManager {
    function updateCardExternal(address user, ZodiacType t, uint256 cnt) external returns (bool);
    function cardCount(address user, ZodiacType t) external view returns (uint256);
    function setAuthorizedNFTContract(address nft, bool ok) external;
    function royaltyWallet() external view returns (address);
}

interface IZodiacMetadata {
    function getCardImage(ZodiacType t, uint8 starLevel) external view returns (string memory);
    function getCardName(ZodiacType t) external view returns (string memory);
    function getCardDesc(ZodiacType t) external view returns (string memory);
    function getNFTName(ZodiacType t, uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
    
    // 补充缺失的接口方法定义
    function collName() external view returns (string memory);
    function collDesc() external view returns (string memory);
    function collImage() external view returns (string memory);
    function sellerFeeBasisPoints() external view returns (uint256);
}

// 补充ZodiacMetadata接口别名定义
interface ZodiacMetadata is IZodiacMetadata {}

struct BatchBurnInfo {
    ZodiacType cardType;
    uint256 burnCount;
}

struct NFTAttributes {
    uint256 life;
    uint256 attack;
    uint256 defense;
    uint256 speed;
    uint256 level;
    uint8 starLevel;
}

contract ZodiacNFT is 
    Initializable, 
    ERC721Upgradeable, 
    OwnableUpgradeable, 
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable
{
    using Counters for Counters.Counter;
    Counters.Counter private _nonce;

    // 核心常量
    uint256 public constant MAX_SUPPLY = 1000000;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    uint8 public constant MAX_STAR_LEVEL = 6;
    uint256 public constant ATTRIBUTE_INCREMENT = 10;

    // 核心状态变量
    uint256 public nextCardId;
    address public tokenBurner;
    address public rewardManager;
    address public metadataContract;
    address public authorizer;
    
    mapping(address => bool) public authorizedMinter;
    mapping(uint256 => ZodiacType) public tokenType;
    mapping(uint256 => NFTAttributes) public tokenAttributes;

    // 用户NFT存储
    mapping(address => mapping(ZodiacType => uint256[])) public userTokens;
    mapping(address => mapping(ZodiacType => uint256)) public userLatestToken;

    // 存储间隙
    uint256[60] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // 初始化函数
    function initialize(address initialOwner, address _metadataContract, address _authorizer) external initializer {
        __ERC721_init("Zodiac NFT", "ZODIAC");
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

    // UUPS升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // 安全的随机卡片类型生成
    function _getRandomType(uint256 salt) internal returns (ZodiacType) {
        _nonce.increment();
        uint256 r = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            salt,
            block.timestamp,
            _nonce.current(),
            gasleft()
        ))) % 12;

        return ZodiacType(r);
    }

    // 生成随机属性
    function _generateRandomAttributes(uint8 starLevel) internal returns (NFTAttributes memory) {
        _nonce.increment();
        uint256 baseValue = 100 + (starLevel - 1) * 50;
        uint256 totalIncrement = ATTRIBUTE_INCREMENT;
        
        NFTAttributes memory attributes;
        attributes.life = baseValue + _randomValue(totalIncrement, 0);
        attributes.attack = baseValue + _randomValue(totalIncrement, 1);
        attributes.defense = baseValue + _randomValue(totalIncrement, 2);
        attributes.speed = baseValue + _randomValue(totalIncrement, 3);
        attributes.level = 1;
        attributes.starLevel = starLevel;
        
        return attributes;
    }

    // 随机值生成
    function _randomValue(uint256 max, uint256 offset) internal returns (uint256) {
        _nonce.increment();
        uint256 r = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            offset,
            block.timestamp,
            _nonce.current(),
            gasleft()
        )));
        return r % (max + 1);
    }

    // ========== 核心修改：Base64编码的tokenURI ==========
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_ownerOf(tokenId) != address(0), "Invalid token ID");
    
    IZodiacMetadata metadata = IZodiacMetadata(metadataContract);
    ZodiacType t = tokenType[tokenId];
    NFTAttributes memory attrs = tokenAttributes[tokenId];
    
    // 直接获取基础信息
    string memory baseCardName = metadata.getCardName(t);
    string memory cardDesc = metadata.getCardDesc(t);
    string memory cardImage = metadata.getCardImage(t, attrs.starLevel);
    
    // 构造NFT名称
    string memory nftName = string(abi.encodePacked(baseCardName, " #", _uint2str(tokenId)));
    
    // 构造符合标准的JSON格式
    string memory json = string(abi.encodePacked(
        '{"name":"', nftName, '",',
        '"description":"', cardDesc, '",',
        '"image":"', cardImage, '",',
        '"attributes":[',
        '{"trait_type":"生命","value":', _uint2str(attrs.life), '},',
        '{"trait_type":"攻击","value":', _uint2str(attrs.attack), '},',
        '{"trait_type":"防御","value":', _uint2str(attrs.defense), '},',
        '{"trait_type":"速度","value":', _uint2str(attrs.speed), '},',
        '{"trait_type":"等级","value":', _uint2str(attrs.level), '},',
        '{"trait_type":"星阶","value":', _uint2str(attrs.starLevel), '}',
        ']}'
    ));
    
    // 使用标准的Base64编码格式
    return string(abi.encodePacked(
        "data:application/json;base64,",
        _base64Encode(bytes(json))
    ));
}

// 辅助函数：将ipfs://协议转换为HTTP格式
function _convertIpfsToHttp(string memory ipfsUrl) internal pure returns (string memory) {
    bytes memory ipfsBytes = bytes(ipfsUrl);
    if (ipfsBytes.length < 7) return ipfsUrl;
    
    // 检查是否以ipfs://开头
    bool isIpfs = true;
    bytes memory ipfsPrefix = bytes("ipfs://");
    for (uint i = 0; i < 7; i++) {
        if (ipfsBytes[i] != ipfsPrefix[i]) {
            isIpfs = false;
            break;
        }
    }
    
    if (!isIpfs) return ipfsUrl;
    
    // 提取CID并转换为HTTP格式
    bytes memory cidBytes = new bytes(ipfsBytes.length - 7);
    for (uint i = 0; i < cidBytes.length; i++) {
        cidBytes[i] = ipfsBytes[i + 7];
    }
    string memory cid = string(cidBytes);
    return string(abi.encodePacked("https://ipfs.io/ipfs/", cid));
}

// 测试函数：生成tokenURI用于调试
function testTokenURI(uint256 tokenId) external view returns (string memory) {
    return tokenURI(tokenId);
}

    // Base64编码实现
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
        
        // 处理填充
        if (data.length % 3 == 1) {
            result[cursor - 2] = '=';
            result[cursor - 1] = '=';
        } else if (data.length % 3 == 2) {
            result[cursor - 1] = '=';
        }
        
        return string(result);
    }

    // 合约元数据URI（也改为Base64格式）
    function contractURI() public view returns (string memory) {
        require(metadataContract != address(0), "Metadata contract not set");
        
        ZodiacMetadata metaContract = ZodiacMetadata(metadataContract);
        IRewardManager rm = IRewardManager(rewardManager);
        
        // 获取元数据信息并进行转义处理
        string memory collName = metaContract.collName();
        string memory collDesc = metaContract.collDesc();
        string memory collImage = metaContract.collImage();
        
        string memory escapedName = _escapeString(collName);
        string memory escapedDesc = _escapeString(collDesc);
        string memory escapedImage = _escapeString(collImage);
        
        // 构造合约级别的元数据JSON
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

    // 普通铸造
    function mint() external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "Dependencies not set");
        require(nextCardId < MAX_SUPPLY, "Max supply reached");

        ITokenBurner tb = ITokenBurner(tokenBurner);
        require(tb.hasBurnedToken(msg.sender) && tb.getBurnCount(msg.sender) > 0, "No permission");
        require(tb.decreaseBurnCount(msg.sender), "Burn count decrease failed");

        uint256 tokenId = nextCardId++;
        ZodiacType t = _getRandomType(tokenId);
        tokenType[tokenId] = t;
        tokenAttributes[tokenId] = _generateRandomAttributes(1);
        
        _safeMint(msg.sender, tokenId);
        userTokens[msg.sender][t].push(tokenId);
        userLatestToken[msg.sender][t] = tokenId;

        emit CardMinted(tokenId, t, msg.sender, uint64(block.timestamp), 1);
        return tokenId;
    }

    // 指定类型铸造
    function mintSpecificType(address to, ZodiacType t, uint8 starLevel) external nonReentrant returns (uint256) {
        require(authorizedMinter[msg.sender] || msg.sender == owner(), "Not authorized");
        require(to != address(0) && nextCardId < MAX_SUPPLY, "Invalid params");
        require(starLevel >= 1 && starLevel <= MAX_STAR_LEVEL, "Invalid star level");

        uint256 tokenId = nextCardId++;
        tokenType[tokenId] = t;
        tokenAttributes[tokenId] = _generateRandomAttributes(starLevel);
        _safeMint(to, tokenId);
        
        userTokens[to][t].push(tokenId);
        userLatestToken[to][t] = tokenId;

        emit CardMinted(tokenId, t, to, uint64(block.timestamp), starLevel);
        return tokenId;
    }

    // 升级NFT等级
    function upgradeNFT(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) == msg.sender, "Not owner");
        require(tokenBurner != address(0), "TokenBurner not set");
        
        ITokenBurner tb = ITokenBurner(tokenBurner);
        require(tb.hasBurnedToken(msg.sender) && tb.getBurnCount(msg.sender) > 0, "No permission");
        require(tb.decreaseBurnCount(msg.sender), "Burn count decrease failed");
        
        NFTAttributes memory attrs = tokenAttributes[tokenId];
        attrs.level += 1;
        
        // 随机增加属性
        uint256 totalIncrement = ATTRIBUTE_INCREMENT;
        attrs.life += _randomValue(totalIncrement, 0);
        attrs.attack += _randomValue(totalIncrement, 1);
        attrs.defense += _randomValue(totalIncrement, 2);
        attrs.speed += _randomValue(totalIncrement, 3);
        
        tokenAttributes[tokenId] = attrs;
        
        emit NFTUpgraded(tokenId, attrs.level, attrs.life, attrs.attack, attrs.defense, attrs.speed);
    }

    // 合成NFT
    function synthesizeNFT(uint256 tokenId1, uint256 tokenId2) external nonReentrant {
        require(_ownerOf(tokenId1) == msg.sender, "Not owner of token1");
        require(_ownerOf(tokenId2) == msg.sender, "Not owner of token2");
        
        ZodiacType t1 = tokenType[tokenId1];
        ZodiacType t2 = tokenType[tokenId2];
        require(t1 == t2, "Different zodiac types");
        
        NFTAttributes memory attrs1 = tokenAttributes[tokenId1];
        NFTAttributes memory attrs2 = tokenAttributes[tokenId2];
        require(attrs1.starLevel == attrs2.starLevel, "Different star levels");
        require(attrs1.starLevel < MAX_STAR_LEVEL, "Max star level reached");
        
        // 销毁两个NFT
        _burn(tokenId1);
        _burn(tokenId2);
        
        // 从用户记录中移除
        _removeToken(msg.sender, t1, tokenId1);
        _removeToken(msg.sender, t1, tokenId2);
        
        // 铸造新的高阶NFT
        uint256 newTokenId = nextCardId++;
        require(newTokenId < MAX_SUPPLY, "Max supply reached");
        
        tokenType[newTokenId] = t1;
        tokenAttributes[newTokenId] = _generateRandomAttributes(uint8(attrs1.starLevel + 1));
        
        _safeMint(msg.sender, newTokenId);
        userTokens[msg.sender][t1].push(newTokenId);
        userLatestToken[msg.sender][t1] = newTokenId;
        
        emit NFTSynthesized(newTokenId, t1, attrs1.starLevel + 1, tokenId1, tokenId2, msg.sender);
    }

    // 销毁卡片
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

    // 重写_update函数
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        address prevOwner = super._update(to, tokenId, auth);

        if (from != address(0) && from != BLACK_HOLE) {
            ZodiacType t = tokenType[tokenId];
            _removeToken(from, t, tokenId);
            _updateReward(from, t, false);
        }
        
        if (to != address(0) && to != BLACK_HOLE) {
            ZodiacType t = tokenType[tokenId];
            userTokens[to][t].push(tokenId);
            userLatestToken[to][t] = tokenId;
            _updateReward(to, t, true);
        }

        return prevOwner;
    }

    // 移除用户NFT记录
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

    // 同步更新RewardManager的卡片计数
    function _updateReward(address user, ZodiacType t, bool isAdd) internal {
        if (rewardManager == address(0)) return;
        
        IRewardManager rm = IRewardManager(rewardManager);
        uint256 cnt = rm.cardCount(user, t);
        
        uint256 newCount = isAdd ? cnt + 1 : (cnt > 0 ? cnt - 1 : 0);
        require(rm.updateCardExternal(user, t, newCount), isAdd ? "Update add failed" : "Update sub failed");
    }

    // ========== 工具函数 ==========
    function _escapeString(string memory input) internal pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        uint256 escapeCount = 0;
        
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == """ || inputBytes[i] == "\\") {
                escapeCount++;
            }
        }
        
        if (escapeCount == 0) return input;
        
        bytes memory outputBytes = new bytes(inputBytes.length + escapeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == """ || inputBytes[i] == "\\") {
                outputBytes[j++] = "\\";
            }
            outputBytes[j++] = inputBytes[i];
        }
        
        return string(outputBytes);
    }

    function _zodiacTypeToString(ZodiacType t) internal pure returns (string memory) {
        if (t == ZodiacType.Rat) return "Rat";
        if (t == ZodiacType.Ox) return "Ox";
        if (t == ZodiacType.Tiger) return "Tiger";
        if (t == ZodiacType.Rabbit) return "Rabbit";
        if (t == ZodiacType.Dragon) return "Dragon";
        if (t == ZodiacType.Snake) return "Snake";
        if (t == ZodiacType.Horse) return "Horse";
        if (t == ZodiacType.Goat) return "Goat";
        if (t == ZodiacType.Monkey) return "Monkey";
        if (t == ZodiacType.Rooster) return "Rooster";
        if (t == ZodiacType.Dog) return "Dog";
        if (t == ZodiacType.Pig) return "Pig";
        return "unknown";
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

    // ========== 管理员接口 ==========
    function setAddresses(address tb, address rm) external {
        require(msg.sender == owner() || msg.sender == authorizer, "ZodiacNFT: Unauthorized");
        require(tb != address(0) && rm != address(0), "Invalid zero address");
        tokenBurner = tb;
        rewardManager = rm;
        IRewardManager(rm).setAuthorizedNFTContract(address(this), true);
    }

    function setMetadataContract(address _metadataContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "ZodiacNFT: Unauthorized");
        require(_metadataContract != address(0), "Invalid zero address");
        metadataContract = _metadataContract;
    }

    function authorizeMinter(address minter) external onlyOwner {
        require(minter != address(0), "Invalid zero address");
        authorizedMinter[minter] = true;
    }

    function unauthorizeMinter(address minter) external onlyOwner {
        authorizedMinter[minter] = false;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "Invalid zero address");
        authorizer = _authorizer;
    }

    function getCardCount(address user, ZodiacType t) external view returns (uint256) {
        require(rewardManager != address(0), "RewardManager not set");
        return IRewardManager(rewardManager).cardCount(user, t);
    }

    function getUserTokens(address user, ZodiacType t) external view returns (uint256[] memory) {
        return userTokens[user][t];
    }

    function getNFTAttributes(uint256 tokenId) external view returns (NFTAttributes memory) {
        require(_ownerOf(tokenId) != address(0), "Invalid token ID");
        return tokenAttributes[tokenId];
    }

    // 事件定义
    event CardMinted(uint256 indexed cardId, ZodiacType indexed cardType, address indexed owner, uint64 timestamp, uint8 starLevel);
    event CardBurned(uint256 indexed cardId, ZodiacType indexed cardType, address indexed owner);
    event NFTUpgraded(uint256 indexed tokenId, uint256 newLevel, uint256 life, uint256 attack, uint256 defense, uint256 speed);
    event NFTSynthesized(uint256 indexed newTokenId, ZodiacType indexed zodiacType, uint8 newStarLevel, uint256 tokenId1, uint256 tokenId2, address indexed owner);
}