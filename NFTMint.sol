// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTMint
 * @dev 十二生肖NFT合约，支持铸造、升级、繁殖等功能
 * 实现120种生肖NFT类型（5属性x12生肖x2性别）
 * 基于OpenZeppelin UUPS可升级合约实现
 */
import "./NFTData.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/ERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/Counters.sol";

/**
 * @dev ITokenBurner接口：代币销毁合约接口
 */
interface ITokenBurner {
    /**
     * @dev 销毁代币用于铸造
     * @return bool 是否成功
     */
    function burnTokenForMint() external returns (bool);
    /**
     * @dev 销毁代币并铸造
     * @param user 用户地址
     * @return bool 是否成功
     */
    function burnAndMint(address user) external returns (bool);
}

/**
 * @dev IToken接口：ERC20代币接口
 */
interface IToken {
    /**
     * @dev 转账
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 数量
     * @return bool 是否成功
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    /**
     * @dev 获取余额
     * @param account 账户地址
     * @return uint256 余额
     */
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @dev IPriceOracle接口：价格预言机接口
 */
interface IPriceOracle {
    /**
     * @dev 获取代币的USD价格
     * @return uint256 代币价格（精度8位）
     */
    function getTokenPriceInUSD() external view returns (uint256);
}

/**
 * @dev NFTLib工具库：用于NFT合约的辅助函数
 */
library NFTLib {
    /**
     * @dev 整数转字符串
     * @param n 整数
     * @return string 字符串
     */
    function uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 len;
        while (temp != 0) { len++; temp /= 10; }
        bytes memory buf = new bytes(len);
        while (n != 0) { len--; buf[len] = bytes1(uint8(48 + n % 10)); n /= 10; }
        return string(buf);
    }

    /**
     * @dev 地址转字符串
     * @param _addr 地址
     * @return string 十六进制字符串
     */
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

    /**
     * @dev Base64编码
     * @param data 原始数据
     * @return string Base64编码字符串
     */
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

    /**
     * @dev 转义字符串（处理特殊字符）
     * @param input 输入字符串
     * @return string 转义后的字符串
     */
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

/**
 * @title NFTMint
 * @dev 十二生肖NFT合约
 */
contract NFTMint is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, ERC721HolderUpgradeable {
    using Counters for Counters.Counter;
    using NFTLib for uint256;
    using NFTLib for address;
    using NFTLib for bytes;
    using NFTLib for string;

    /** @dev 用于生成随机数的计数器 */
    Counters.Counter private _nonce;
    /** @dev 黑洞地址，用于永久销毁NFT */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    /** @dev 下一个可铸造的NFT ID */
    uint256 public nextCardId;
    /** @dev TokenBurner代币销毁合约地址 */
    address public tokenBurner;
    /** @dev RewardManager奖励管理器地址 */
    address public rewardManager;
    /** @dev 元数据合约地址 */
    address public metadataContract;
    /** @dev 授权合约地址 */
    address public authorizer;
    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 价格预言机地址 */
    address public priceOracle;
    /** @dev 繁殖合约地址 */
    address public breedingContract;

    /** @dev 授权铸造者映射 */
    mapping(address => bool) public authorizedMinter;
    /** @dev NFT类型映射（tokenId => 类型） */
    mapping(uint256 => NFTDataTypes.ZodiacType) public tokenType;
    /** @dev NFT等级映射（tokenId => 等级） */
    mapping(uint256 => uint8) public tokenLevel;
    /** @dev 用户NFT列表（用户地址 => 类型 => ID数组） */
    mapping(address => mapping(NFTDataTypes.ZodiacType => uint256[])) public userTokens;
    /** @dev 用户最新NFT（用户地址 => 类型 => 最新ID） */
    mapping(address => mapping(NFTDataTypes.ZodiacType => uint256)) public userLatestToken;
    /** @dev 用户NFT按等级分类（用户地址 => 类型 => 等级 => ID数组） */
    mapping(address => mapping(NFTDataTypes.ZodiacType => mapping(uint8 => uint256[]))) public userTokensByLevel;
    /** @dev 用户最新NFT按等级（用户地址 => 类型 => 等级 => 最新ID） */
    mapping(address => mapping(NFTDataTypes.ZodiacType => mapping(uint8 => uint256))) public userLatestTokenByLevel;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _metadataContract 元数据合约地址
     * @param _authorizer 授权合约地址
     */
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

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ====================== 随机类型 ======================

    /**
     * @dev 生成随机生肖类型
     * 概率分布：水/风属性各48%，光/暗属性各2%
     * @param salt 随机种子
     * @return NFTDataTypes.ZodiacType 随机生成的生肖类型
     */
    function _getRandomType(uint256 salt) internal returns (NFTDataTypes.ZodiacType) {
        _nonce.increment();
        uint rand = uint(keccak256(abi.encodePacked(blockhash(block.number-1), msg.sender, salt, block.timestamp, _nonce.current(), gasleft())));
        uint r = rand % 100;
        if (r < 2) return NFTDataTypes.ZodiacType(72 + (rand % 24));      // 光属性(2%)
        else if (r < 4) return NFTDataTypes.ZodiacType(96 + (rand % 24));  // 暗属性(2%)
        else return NFTDataTypes.ZodiacType(rand % 48);                     // 水/风属性(96%)
    }

    // ====================== URI ======================

    /**
     * @dev 获取NFT的元数据URI
     * @param tokenId NFT ID
     * @return string JSON格式的元数据URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "E0");
        INFTData m = INFTData(metadataContract);
        NFTDataTypes.ZodiacType t = tokenType[tokenId];
        string memory json = string(abi.encodePacked(
            '{"name":"', m.getCardName(t), " #", tokenId.uint2str(), '",',
            '"description":"', m.getCardDesc(t).escapeString(), '",',
            '"image":"', m.getCardImage(t).escapeString(), '"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", bytes(json).base64Encode()));
    }

    /**
     * @dev 获取合约级别的元数据URI（用于OpenSea等平台）
     * @return string JSON格式的合约元数据URI
     */
    function contractURI() public view returns (string memory) {
        require(metadataContract != address(0), "E1");
        INFTData m = INFTData(metadataContract);
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

    /**
     * @dev 铸造NFT（通过销毁代币）
     * 用户需先授权并销毁代币，然后调用此函数铸造NFT
     * @param to 接收NFT的地址
     * @return uint256 新铸造的NFT ID
     */
    function mint(address to) external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMint(to), "E6");
        return _mintTo(to, _getRandomType(nextCardId));
    }

    /** @dev 铸造光/暗属性NFT所需的代币数量 */
    uint256 public constant LIGHT_DARK_COST = 88888;

    /**
     * @dev 铸造光/暗属性NFT
     * 需要燃烧88888个代币，只能铸造光或暗属性的NFT
     * @param to 接收NFT的地址
     * @param isLight 是否铸造光属性（true=光，false=暗）
     * @return uint256 新铸造的NFT ID
     */
    function mintLightDark(address to, bool isLight) external nonReentrant returns (uint256) {
        require(tokenContract != address(0) && rewardManager != address(0), "E7");
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= LIGHT_DARK_COST, "E8");
        require(t.transferFrom(msg.sender, BLACK_HOLE, LIGHT_DARK_COST), "E9");
        _nonce.increment();
        uint rand = uint(keccak256(abi.encodePacked(blockhash(block.number-1), msg.sender, nextCardId, block.timestamp, _nonce.current(), gasleft())));
        NFTDataTypes.ZodiacType z = isLight ? NFTDataTypes.ZodiacType(96 + rand % 24) : NFTDataTypes.ZodiacType(72 + rand % 24);
        return _mintTo(to, z);
    }

    /**
     * @dev 铸造指定类型的NFT（仅限授权地址）
     * 用于白名单铸造或特殊活动铸造
     * @param to 接收NFT的地址
     * @param t NFT的类型
     * @return uint256 新铸造的NFT ID
     */
    function mintSpecificType(address to, NFTDataTypes.ZodiacType t) external nonReentrant returns (uint256) {
        require(authorizedMinter[msg.sender] || msg.sender == owner(), "E10");
        require(to != address(0), "E11");
        return _mintTo(to, t);
    }

    /**
     * @dev 铸造繁殖结果NFT（仅限繁殖合约调用）
     * 繁殖完成后调用此函数铸造新的NFT
     * @param to 接收NFT的地址
     * @param t NFT的类型
     * @return uint256 新铸造的NFT ID
     */
    function mintBreedResult(address to, NFTDataTypes.ZodiacType t) external returns (uint256) {
        require(msg.sender == breedingContract, "E12");
        return _mintTo(to, t);
    }

    /**
     * @dev 统一铸造逻辑（内部函数）
     * @param to 接收NFT的地址
     * @param t NFT的类型
     * @return uint256 新铸造的NFT ID
     */
    function _mintTo(address to, NFTDataTypes.ZodiacType t) internal returns (uint256) {
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

    /**
     * @dev 转账前的钩子函数
     * 在转账时自动更新用户的NFT列表和奖励管理器
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     * @param batchSize 批量转账数量
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        NFTDataTypes.ZodiacType t = tokenType[tokenId];
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

    /**
     * @dev 从用户的NFT列表中移除指定NFT（内部函数）
     * @param u 用户地址
     * @param t NFT类型
     * @param id NFT ID
     */
    function _removeToken(address u, NFTDataTypes.ZodiacType t, uint id) internal {
        uint256[] storage arr = userTokens[u][t];
        for (uint i; i<arr.length; i++) { if (arr[i] == id) { arr[i] = arr[arr.length-1]; arr.pop(); break; } }
    }

    /**
     * @dev 从用户的NFT等级列表中移除指定NFT（内部函数）
     * @param u 用户地址
     * @param t NFT类型
     * @param lv NFT等级
     * @param id NFT ID
     */
    function _removeTokenByLevel(address u, NFTDataTypes.ZodiacType t, uint8 lv, uint id) internal {
        uint256[] storage arr = userTokensByLevel[u][t][lv];
        for (uint i; i<arr.length; i++) { if (arr[i] == id) { arr[i] = arr[arr.length-1]; arr.pop(); break; } }
        userLatestTokenByLevel[u][t][lv] = arr.length > 0 ? arr[arr.length-1] : 0;
    }

    /**
     * @dev 更新奖励管理器中的用户卡牌计数（内部函数）
     * @param u 用户地址
     * @param t NFT类型
     * @param add 是否增加计数（true增加，false减少）
     */
    function _updateReward(address u, NFTDataTypes.ZodiacType t, bool add) internal {
        if (rewardManager == address(0)) return;
        IRewardManager rm = IRewardManager(rewardManager);
        uint cnt = rm.cardCount(u, t);
        uint n = add ? cnt+1 : (cnt>0 ? cnt-1 : 0);
        require(rm.updateCardExternal(u, t, n), add ? "E13" : "E14");
    }

    /**
     * @dev 使用NFT升级（消耗同类型同等级的其他NFT）
     * 升级需要消耗lv个同类型同等级的NFT
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
    function upgradeWithNFT(uint256 tokenId) external nonReentrant returns (uint8) {
        require(_ownerOf(tokenId) == msg.sender, "E15");
        NFTDataTypes.ZodiacType t = tokenType[tokenId];
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

    /**
     * @dev 使用代币升级
     * 各级别所需代币数量：1->2需10000, 2->3需40000, 3->4需120000, 4->5需480000, 5->6需2400000
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
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

    /**
     * @dev 使用USD价值升级（通过价格预言机计算所需代币数量）
     * 各级别所需USD价值：1->2需1USD, 2->3需4USD, 3->4需12USD, 4->5需48USD, 5->6需240USD
     * @param tokenId 要升级的NFT ID
     * @return uint8 新等级
     */
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

    /**
     * @dev 升级等级的内部函数
     * @param id NFT ID
     * @param oldLv 旧等级
     * @return uint8 新等级
     */
    function _upgradeLevel(uint id, uint8 oldLv) internal returns (uint8) {
        NFTDataTypes.ZodiacType t = tokenType[id];
        uint8 newLv = oldLv+1;
        tokenLevel[id] = newLv;
        _removeTokenByLevel(msg.sender, t, oldLv, id);
        userTokensByLevel[msg.sender][t][newLv].push(id);
        userLatestTokenByLevel[msg.sender][t][newLv] = id;
        emit CardUpgraded(id, t, oldLv, newLv, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    /**
     * @dev 设置TokenBurner和RewardManager地址
     * @param tb TokenBurner合约地址
     * @param rm RewardManager合约地址
     */
    function setAddresses(address tb, address rm) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenBurner = tb; rewardManager = rm;
        IRewardManager(rm).setAuthorizedNFTContract(address(this), true);
    }

    /**
     * @dev 设置元数据合约地址
     * @param a 元数据合约地址
     */
    function setMetadataContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        metadataContract = a;
    }

    /**
     * @dev 设置代币合约地址
     * @param a 代币合约地址
     */
    function setTokenContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenContract = a;
    }

    /**
     * @dev 设置价格预言机地址
     * @param a 价格预言机地址
     */
    function setPriceOracle(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        priceOracle = a;
    }

    /**
     * @dev 授权铸造者
     * @param a 铸造者地址
     */
    function authorizeMinter(address a) external onlyOwner { authorizedMinter[a] = true; }

    /**
     * @dev 取消铸造者授权
     * @param a 铸造者地址
     */
    function unauthorizedMinter(address a) external onlyOwner { authorizedMinter[a] = false; }

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner { authorizer = a; }

    /**
     * @dev 设置繁殖合约地址
     * @param a 繁殖合约地址
     */
    function setBreedingContract(address a) external onlyOwner { breedingContract = a; }

    /**
     * @dev 获取用户拥有的指定类型NFT数量
     * @param u 用户地址
     * @param t NFT类型
     * @return uint NFT数量
     */
    function getCardCount(address u, NFTDataTypes.ZodiacType t) external view returns (uint) {
        return IRewardManager(rewardManager).cardCount(u, t);
    }

    /**
     * @dev 计算用户权重（用于分红计算）
     * 权重 = 每个NFT的等级+ 2 的总和
     * @param user 用户地址
     * @return uint256 用户权重
     */
    function calcUserWeight(address user) external view returns (uint256) {
        uint w;
        for (uint i; i<120; i++) {
            NFTDataTypes.ZodiacType t = NFTDataTypes.ZodiacType(i);
            uint256[] memory arr = userTokens[user][t];
            for (uint j; j<arr.length; j++) { w += tokenLevel[arr[j]] + 2; }
        }
        return w;
    }

    /**
     * @dev 获取总供应量
     * @return uint256 总NFT数量
     */
    function totalSupply() external view returns (uint256) {
        return nextCardId - 1;
    }

    /**
     * @dev 获取用户持有的NFT列表（按索引）
     * @param owner 持有者地址
     * @param index 索引
     * @return uint256 NFT ID
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        uint256 count = 0;
        for (uint i = 0; i < 120; i++) {
            NFTDataTypes.ZodiacType t = NFTDataTypes.ZodiacType(i);
            uint256[] storage arr = userTokens[owner][t];
            if (index < count + arr.length) {
                return arr[index - count];
            }
            count += arr.length;
        }
        revert("NFTMint: index out of bounds");
    }

    /**
     * @dev 铸造事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param owner 持有者地址
     * @param timestamp 时间戳
     */
    event CardMinted(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner, uint64 timestamp);

    /**
     * @dev 销毁事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param owner 持有者地址
     */
    event CardBurned(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner);


    /**
     * @dev 升级事件
     * @param cardId NFT ID
     * @param cardType NFT类型
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     * @param owner 持有者地址
     * @param timestamp 时间戳
     */
    event CardUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);
}