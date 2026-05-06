// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/ERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/Counters.sol";

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

// ====================== 工具库（大幅减小合约尺寸）======================
library NFTLib {
    function uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 len;
        while (temp != 0) { len++; temp /= 10; }
        bytes memory buf = new bytes(len);
        while (n != 0) { len--; buf[len] = bytes1(uint8(48 + n % 10)); n /= 10; }
        return string(buf);
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0'; str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i+12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i+12] & 0x0f)];
        }
        return string(str);
    }

    function base64Encode(bytes memory data) internal pure returns (string memory) {
        bytes memory base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        bytes memory result = new bytes((data.length + 2) / 3 * 4);
        uint cursor = 0;
        for (uint i = 0; i < data.length; i += 3) {
            uint b0 = uint8(data[i]);
            uint b1 = i+1 < data.length ? uint8(data[i+1]) : 0;
            uint b2 = i+2 < data.length ? uint8(data[i+2]) : 0;
            uint chunk = (b0 << 16) | (b1 << 8) | b2;
            result[cursor++] = base64[(chunk >> 18) & 0x3F];
            result[cursor++] = base64[(chunk >> 12) & 0x3F];
            result[cursor++] = base64[(chunk >> 6) & 0x3F];
            result[cursor++] = base64[chunk & 0x3F];
        }
        if (data.length % 3 == 1) { result[cursor-2] = '='; result[cursor-1] = '='; }
        else if (data.length % 3 == 2) { result[cursor-1] = '='; }
        return string(result);
    }

    function escapeString(string memory input) internal pure returns (string memory) {
        bytes memory b = bytes(input);
        uint esc;
        for (uint i; i<b.length; i++) { if (b[i] == '"' || b[i] == '\\') esc++; }
        if (esc == 0) return input;
        bytes memory o = new bytes(b.length + esc);
        uint j;
        for (uint i; i<b.length; i++) {
            if (b[i] == '"' || b[i] == '\\') o[j++] = '\\';
            o[j++] = b[i];
        }
        return string(o);
    }
}

contract FiveBlessingsNFT is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, ERC721HolderUpgradeable {
    using Counters for Counters.Counter;
    using NFTLib for uint256;
    using NFTLib for address;
    using NFTLib for bytes;
    using NFTLib for string;

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
    address public breedingContract;

    mapping(address => bool) public authorizedMinter;
    mapping(uint256 => ZodiacType) public tokenType;
    mapping(uint256 => uint8) public tokenLevel;
    mapping(address => mapping(ZodiacType => uint256[])) public userTokens;
    mapping(address => mapping(ZodiacType => uint256)) public userLatestToken;
    mapping(address => mapping(ZodiacType => mapping(uint8 => uint256[]))) public userTokensByLevel;
    mapping(address => mapping(ZodiacType => mapping(uint8 => uint256))) public userLatestTokenByLevel;

    uint256[50] private __gap;

    constructor() { _disableInitializers(); }

    function initialize(address initialOwner, address _metadataContract, address _authorizer) external initializer {
        __ERC721_init("Twelve Zodiacs", "12ZODIAC");
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC721Holder_init();
        nextCardId = 1;
        authorizedMinter[initialOwner] = true;
        metadataContract = _metadataContract;
        authorizer = _authorizer;
        _nonce.increment();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ====================== 随机类型 ======================
    function _getRandomType(uint256 salt) internal returns (ZodiacType) {
        _nonce.increment();
        uint rand = uint(keccak256(abi.encodePacked(blockhash(block.number-1), msg.sender, salt, block.timestamp, _nonce.current(), gasleft())));
        uint r = rand % 100;
        if (r < 2) return ZodiacType(72 + (rand % 24));
        else if (r < 4) return ZodiacType(96 + (rand % 24));
        else return ZodiacType(rand % 48);
    }

    // ====================== URI ======================
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "E0");
        IFiveBlessingsMetadata m = IFiveBlessingsMetadata(metadataContract);
        ZodiacType t = tokenType[tokenId];
        string memory json = string(abi.encodePacked(
            '{"name":"', m.getCardName(t), " #", tokenId.uint2str(), '",',
            '"description":"', m.getCardDesc(t).escapeString(), '",',
            '"image":"', m.getCardImage(t).escapeString(), '"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", bytes(json).base64Encode()));
    }

    function contractURI() public view returns (string memory) {
        require(metadataContract != address(0), "E1");
        IFiveBlessingsMetadata m = IFiveBlessingsMetadata(metadataContract);
        IRewardManager rm = IRewardManager(rewardManager);
        string memory json = string(abi.encodePacked(
            '{"name":"', m.collName().escapeString(), '",',
            '"description":"', m.collDesc().escapeString(), '",',
            '"image":"', m.collImage().escapeString(), '",',
            '"seller_fee_basis_points":', m.sellerFeeBasisPoints().uint2str(), ',',
            '"fee_recipient":"', rm.royaltyWallet().addressToString(), '"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", bytes(json).base64Encode()));
    }

    // ====================== 核心MINT ======================
    function mint() external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(nextCardId < MAX_SUPPLY, "E3");
        ITokenBurner tb = ITokenBurner(tokenBurner);
        require(tb.hasBurnedToken(msg.sender) && tb.getBurnCount(msg.sender) > 0, "E4");
        require(tb.decreaseBurnCount(msg.sender), "E5");
        return _mintTo(msg.sender, _getRandomType(nextCardId));
    }

    function mintOneStep() external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(nextCardId < MAX_SUPPLY, "E3");
        require(ITokenBurner(tokenBurner).burnAndMint(msg.sender), "E6");
        return _mintTo(msg.sender, _getRandomType(nextCardId));
    }

    uint256 public constant LIGHT_DARK_COST = 88888;
    function mintLightDark() external nonReentrant returns (uint256) {
        require(tokenContract != address(0) && rewardManager != address(0), "E7");
        require(nextCardId < MAX_SUPPLY, "E3");
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= LIGHT_DARK_COST, "E8");
        require(t.transferFrom(msg.sender, BLACK_HOLE, LIGHT_DARK_COST), "E9");
        _nonce.increment();
        uint rand = uint(keccak256(abi.encodePacked(blockhash(block.number-1), msg.sender, nextCardId, block.timestamp, _nonce.current(), gasleft())));
        ZodiacType z = rand % 2 == 0 ? ZodiacType(72 + rand % 24) : ZodiacType(96 + rand % 24);
        return _mintTo(msg.sender, z);
    }

    function mintSpecificType(address to, ZodiacType t) external nonReentrant returns (uint256) {
        require(authorizedMinter[msg.sender] || msg.sender == owner(), "E10");
        require(to != address(0) && nextCardId < MAX_SUPPLY, "E11");
        return _mintTo(to, t);
    }

    function mintBreedResult(address to, ZodiacType t) external returns (uint256) {
        require(msg.sender == breedingContract, "E12");
        require(nextCardId < MAX_SUPPLY, "E3");
        return _mintTo(to, t);
    }

    // 统一Mint逻辑（大幅减码）
    function _mintTo(address to, ZodiacType t) internal returns (uint256) {
        uint id = nextCardId++;
        tokenType[id] = t;
        tokenLevel[id] = 1;
        _safeMint(to, id);
        userTokens[to][t].push(id);
        userLatestToken[to][t] = id;
        userTokensByLevel[to][t][1].push(id);
        userLatestTokenByLevel[to][t][1] = id;
        emit CardMinted(id, t, to, uint64(block.timestamp));
        return id;
    }

    // ====================== 转账钩子 ======================
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        ZodiacType t = tokenType[tokenId];
        uint8 lv = tokenLevel[tokenId];
        if (from != address(0) && from != BLACK_HOLE) {
            _removeToken(from, t, tokenId);
            _removeTokenByLevel(from, t, lv, tokenId);
            _updateReward(from, t, false);
        }
        if (to != address(0) && to != BLACK_HOLE) {
            userTokens[to][t].push(tokenId);
            userLatestToken[to][t] = tokenId;
            userTokensByLevel[to][t][lv].push(tokenId);
            userLatestTokenByLevel[to][t][lv] = tokenId;
            _updateReward(to, t, true);
        }
    }

    // ====================== 工具 ======================
    function _removeToken(address u, ZodiacType t, uint id) internal {
        uint256[] storage arr = userTokens[u][t];
        for (uint i; i<arr.length; i++) { if (arr[i] == id) { arr[i] = arr[arr.length-1]; arr.pop(); break; } }
    }

    function _removeTokenByLevel(address u, ZodiacType t, uint8 lv, uint id) internal {
        uint256[] storage arr = userTokensByLevel[u][t][lv];
        for (uint i; i<arr.length; i++) { if (arr[i] == id) { arr[i] = arr[arr.length-1]; arr.pop(); break; } }
        userLatestTokenByLevel[u][t][lv] = arr.length > 0 ? arr[arr.length-1] : 0;
    }

    function _updateReward(address u, ZodiacType t, bool add) internal {
        if (rewardManager == address(0)) return;
        IRewardManager rm = IRewardManager(rewardManager);
        uint cnt = rm.cardCount(u, t);
        uint n = add ? cnt+1 : (cnt>0 ? cnt-1 : 0);
        require(rm.updateCardExternal(u, t, n), add ? "E13" : "E14");
    }

    // ====================== 升级 ======================
    function upgradeWithNFT(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "E15");
        ZodiacType t = tokenType[tokenId];
        uint8 lv = tokenLevel[tokenId];
        require(lv < 6, "E16");
        uint req = lv;
        uint256[] storage arr = userTokensByLevel[msg.sender][t][lv];
        require(arr.length >= req+1, "E17");
        for (uint i; i<req; i++) {
            uint burnId = arr[i];
            if (burnId != tokenId) {
                _transfer(msg.sender, BLACK_HOLE, burnId);
                _removeToken(msg.sender, t, burnId);
                _removeTokenByLevel(msg.sender, t, lv, burnId);
                emit CardBurned(burnId, t, msg.sender);
            }
        }
        uint8 newLv = lv+1;
        tokenLevel[tokenId] = newLv;
        _removeTokenByLevel(msg.sender, t, lv, tokenId);
        userTokensByLevel[msg.sender][t][newLv].push(tokenId);
        userLatestTokenByLevel[msg.sender][t][newLv] = tokenId;
        emit CardUpgraded(tokenId, t, lv, newLv, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    function upgradeWithToken(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "E15");
        require(tokenContract != address(0), "E7");
        uint8 lv = tokenLevel[tokenId];
        require(lv < 6, "E16");
        uint cost;
        if (lv == 1) cost = 10000;
        else if (lv == 2) cost = 40000;
        else if (lv == 3) cost = 120000;
        else if (lv == 4) cost = 480000;
        else if (lv == 5) cost = 2400000;
        else revert("E18");
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8");
        require(t.transferFrom(msg.sender, BLACK_HOLE, cost), "E9");
        return _upgradeLevel(tokenId, lv);
    }

    function upgradeWithUSDValue(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "E15");
        require(tokenContract != address(0) && priceOracle != address(0), "E19");
        uint8 lv = tokenLevel[tokenId];
        require(lv < 6, "E16");
        uint usd;
        if (lv == 1) usd = 1 ether;
        else if (lv == 2) usd = 4 ether;
        else if (lv == 3) usd = 12 ether;
        else if (lv == 4) usd = 48 ether;
        else if (lv == 5) usd = 240 ether;
        else revert("E18");
        uint price = IPriceOracle(priceOracle).getTokenPriceInUSD();
        require(price > 0, "E20");
        uint cost = (usd * 1e18) / price;
        require(cost > 0, "E21");
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8");
        require(t.transferFrom(msg.sender, BLACK_HOLE, cost), "E9");
        return _upgradeLevel(tokenId, lv);
    }

    function _upgradeLevel(uint id, uint8 oldLv) internal returns (uint8) {
        ZodiacType t = tokenType[id];
        uint8 newLv = oldLv+1;
        tokenLevel[id] = newLv;
        _removeTokenByLevel(msg.sender, t, oldLv, id);
        userTokensByLevel[msg.sender][t][newLv].push(id);
        userLatestTokenByLevel[msg.sender][t][newLv] = id;
        emit CardUpgraded(id, t, oldLv, newLv, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    // ====================== 配置 ======================
    function setAddresses(address tb, address rm) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenBurner = tb; rewardManager = rm;
        IRewardManager(rm).setAuthorizedNFTContract(address(this), true);
    }

    function setMetadataContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        metadataContract = a;
    }

    function setTokenContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenContract = a;
    }

    function setPriceOracle(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        priceOracle = a;
    }

    function authorizeMinter(address a) external onlyOwner { authorizedMinter[a] = true; }
    function unauthorizedMinter(address a) external onlyOwner { authorizedMinter[a] = false; }
    function setAuthorizer(address a) external onlyOwner { authorizer = a; }
    function setBreedingContract(address a) external onlyOwner { breedingContract = a; }

    // ====================== 查询 ======================
    function getCardCount(address u, ZodiacType t) external view returns (uint) {
        return IRewardManager(rewardManager).cardCount(u, t);
    }

    function calcUserWeight(address user) external view returns (uint256) {
        uint w;
        for (uint i; i<120; i++) {
            ZodiacType t = ZodiacType(i);
            uint256[] memory arr = userTokens[user][t];
            for (uint j; j<arr.length; j++) { w += tokenLevel[arr[j]] + 2; }
        }
        return w;
    }

    // ====================== 事件 ======================
    event CardMinted(uint256 indexed cardId, ZodiacType indexed cardType, address indexed owner, uint64 timestamp);
    event CardBurned(uint256 indexed cardId, ZodiacType indexed cardType, address indexed owner);
    event WuFuSynthesized(address indexed user, uint64 timestamp, uint256 wanNengUsed);
    event CardUpgraded(uint256 indexed cardId, ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);
}