// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTMint
 * @dev 十二生肖NFT合约，支持铸造、升级、繁殖等功能
 * 实现120种生肖NFT类型（5属性x12生肖x2性别）
 * 基于OpenZeppelin UUPS可升级合约实现
 */
import "./NFTDataType.sol";
import "./NFTInterface.sol";
import "./NFTLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/ERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/Counters.sol";

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
    /** @dev 繁殖合约地址 */
    address public breedingContract;
    /** @dev NFTUpdate合约地址 */
    address public nftUpdateContract;

    /** @dev 授权铸造者映射 */
    mapping(address => bool) public authorizedMinter;

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
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __ERC721_init("Twelve Zodiacs", "12ZODIAC");
        __ERC721Holder_init();
        nextCardId = 1;
        authorizedMinter[initialOwner] = true;
        metadataContract = _metadataContract;
        authorizer = _authorizer;
        _nonce.increment();
    }

    /**
     * @dev 升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ====================== 随机类型 ======================

    /**
     * @dev 安全随机数生成器
     * 使用链上数据源生成不可预测的随机数
     * 注意：对于生产环境，建议使用Chainlink VRF或其他去中心化随机数服务
     */
    function _generateSecureRandom() internal returns (uint256) {
        _nonce.increment();
        bytes32 entropy = keccak256(
            abi.encodePacked(
                blockhash(block.number > 1 ? block.number - 1 : block.number),
                msg.sender,
                nextCardId,
                block.timestamp,
                _nonce.current(),
                gasleft(),
                tx.origin,
                block.coinbase,
                block.prevrandao,
                address(this).balance,
                block.difficulty
            )
        );
        return uint256(entropy);
    }

    /**
     * @dev 普通铸造随机类型生成：五种属性随机
     * 概率分布：水(32%)、火(32%)、风(32%)、光(2%)、暗(2%)
     * @return NFTDataTypes.ZodiacType 随机生成的生肖类型
     */
    function _getRandomNormalType() internal returns (NFTDataTypes.ZodiacType) {
        uint rand = _generateSecureRandom();
        uint r = rand % 100;
        if (r < 2) return NFTDataTypes.ZodiacType(72 + (rand % 24));      // 暗属性(2%)
        else if (r < 4) return NFTDataTypes.ZodiacType(96 + (rand % 24));  // 光属性(2%)
        else if (r < 36) return NFTDataTypes.ZodiacType(rand % 24);        // 水属性(32%)
        else if (r < 68) return NFTDataTypes.ZodiacType(24 + (rand % 24)); // 风属性(32%)
        else return NFTDataTypes.ZodiacType(48 + (rand % 24));              // 火属性(32%)
    }

    /**
     * @dev 稀有铸造随机类型生成：仅光/暗属性随机
     * 概率分布：光(50%)、暗(50%)
     * @return NFTDataTypes.ZodiacType 随机生成的生肖类型
     */
    function _getRandomRareType() internal returns (NFTDataTypes.ZodiacType) {
        uint rand = _generateSecureRandom();
        // 50%概率光属性，50%概率暗属性
        if (rand % 2 == 0) {
            return NFTDataTypes.ZodiacType(96 + (rand % 24));  // 光属性(50%)
        } else {
            return NFTDataTypes.ZodiacType(72 + (rand % 24));  // 暗属性(50%)
        }
    }

    // ====================== URI ======================

    /**
     * @dev 获取NFT的元数据URI
     * @param tokenId NFT ID
     * @return string JSON格式的元数据URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "E0");
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
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
        INFTDataInterface m = INFTDataInterface(metadataContract);
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
     * @dev 普通铸造：销毁代币，随机铸造五种属性中的任意一个生肖
     * 概率分布：水(32%)、火(32%)、风(32%)、光(2%)、暗(2%)
     * @param to 接收NFT的地址
     * @return uint256 新铸造的NFT ID
     */
    function mintNormal(address to) external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMint(to, false), "E6");
        return _mintTo(to, _getRandomNormalType());
    }

    /**
     * @dev 稀有铸造：销毁代币，随机铸造光或暗属性的生肖
     * 概率分布：光(50%)、暗(50%)
     * @param to 接收NFT的地址
     * @return uint256 新铸造的NFT ID
     */
    function mintRare(address to) external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMint(to, true), "E6");
        return _mintTo(to, _getRandomRareType());
    }

    /**
     * @dev 指定类型铸造：直接铸造指定类型的生肖（无需销毁代币）
     * 仅限合约拥有者调用，用于特殊活动或白名单铸造
     * @param to 接收NFT的地址
     * @param zodiacType 指定的生肖类型
     * @return uint256 新铸造的NFT ID
     */
    function mintCustom(address to, NFTDataTypes.ZodiacType zodiacType) external nonReentrant onlyOwner returns (uint256) {
        require(to != address(0), "E11");
        return _mintTo(to, zodiacType);
    }

    /**
     * @dev 铸造繁殖结果NFT（仅限繁殖合约调用）
     * 繁殖完成后调用此函数铸造新的NFT
     * @param to 接收NFT的地址
     * @param t NFT的类型
     * @return uint256 新铸造的NFT ID
     */
    function mintBreedResult(address to, NFTDataTypes.ZodiacType t) external returns (uint256) {
        require(breedingContract != address(0), "E29: Breeding contract not set");
        require(msg.sender == breedingContract, "E12: Not breeding contract");
        require(to != address(0), "E11: Zero address");
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
        INFTDataInterface m = INFTDataInterface(metadataContract);
        m.setTokenType(id, t);
        m.setTokenLevel(id, 1);
        m.addUserToken(to, t, id);
        _safeMint(to, id);
        // 更新权重缓存
        m.updateUserWeight(to, 1, true);
        emit CardMinted(id, t, to, uint64(block.timestamp));
        return id;
    }

    /**
     * @dev 转账前的钩子函数
     * 在转账时自动更新用户的NFT列表、奖励管理器和权重缓存
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     * @param batchSize 批量转账数量
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        uint8 lv = m.tokenLevel(tokenId);
        if (from != address(0) && from != BLACK_HOLE) {
            m.removeUserToken(from, t, tokenId);
            _updateReward(from, t, false);
            // 更新权重缓存：减少转出方权重
            m.updateUserWeight(from, lv, false);
        }
        if (to != address(0) && to != BLACK_HOLE) {
            m.addUserToken(to, t, tokenId);
            _updateReward(to, t, true);
            // 更新权重缓存：增加转入方权重
            m.updateUserWeight(to, lv, true);
        }
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
        try rm.updateCardExternal(u, t, n) returns (bool success) {
            if (!success) {
                emit RewardUpdateFailed(u, t, n, add);
            }
        } catch {
            emit RewardUpdateFailed(u, t, n, add);
        }
    }
    
    event RewardUpdateFailed(address indexed user, NFTDataTypes.ZodiacType indexed zodiacType, uint256 count, bool add);

    

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
     * @dev 设置NFTUpdate合约地址
     * @param a NFTUpdate合约地址
     */
    function setNFTUpdateContract(address a) external onlyOwner { nftUpdateContract = a; }

    function upgradeWithNFT(uint256 tokenId) external returns (uint8) {
        require(nftUpdateContract != address(0), "E31: NFTUpdate contract not set");
        return INFTUpdate(nftUpdateContract).upgradeWithNFT(tokenId);
    }

    function upgradeWithToken(uint256 tokenId) external returns (uint8) {
        require(nftUpdateContract != address(0), "E31: NFTUpdate contract not set");
        return INFTUpdate(nftUpdateContract).upgradeWithToken(tokenId);
    }

    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8) {
        require(nftUpdateContract != address(0), "E31: NFTUpdate contract not set");
        return INFTUpdate(nftUpdateContract).upgradeWithUSDValue(tokenId);
    }

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
     * 权重 = 每个NFT的等级+ 3 的总和（1级权重为4，每级+1，最高5级权重为8）
     * 使用缓存机制减少Gas消耗
     * @param user 用户地址
     * @return uint256 用户权重
     */
    function calcUserWeight(address user) external view returns (uint256) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.userWeightCache(user);
    }

    /**
     * @dev 更新用户权重缓存（内部函数）
     * @param user 用户地址
     * @param level NFT等级
     * @param add 是否增加权重（true增加，false减少）
     * @dev 注意：权重更新已统一到NFTData.updateUserWeight函数
     */

    /**
     * @dev 获取总供应量
     * @return uint256 总NFT数量
     */
    function totalSupply() external view returns (uint256) {
        return nextCardId - 1;
    }

    function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.tokenType(tokenId);
    }

    function tokenLevel(uint256 tokenId) external view returns (uint8) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.tokenLevel(tokenId);
    }

    /**
     * @dev 获取用户持有的NFT列表（按索引）
     * @param owner 持有者地址
     * @param index 索引
     * @return uint256 NFT ID
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        require(index < arr.length, "NFTMint: index out of bounds");
        return arr[index];
    }

    /**
     * @dev 获取用户持有的NFT总数
     * @param owner 持有者地址
     * @return uint256 NFT数量
     */
    function balanceOf(address owner) public view override returns (uint256) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.userAllTokens(owner).length;
    }

    /**
     * @dev 分页获取用户持有的NFT列表
     * @param owner 持有者地址
     * @param page 页码（从0开始）
     * @param pageSize 每页大小
     * @return uint256[] NFT ID列表
     * @return bool 是否还有更多
     */
    function getTokensByPage(address owner, uint256 page, uint256 pageSize) external view returns (uint256[] memory, bool) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        uint256 total = arr.length;
        uint256 start = page * pageSize;
        
        if (start >= total) {
            return (new uint256[](0), false);
        }
        
        uint256 end = start + pageSize;
        if (end > total) {
            end = total;
        }
        
        uint256 count = end - start;
        uint256[] memory result = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            result[i] = arr[start + i];
        }
        
        return (result, end < total);
    }

    /**
     * @dev 分页获取用户持有的NFT详情列表
     * @param owner 持有者地址
     * @param page 页码（从0开始）
     * @param pageSize 每页大小
     * @return uint256[] NFT ID列表
     * @return NFTDataTypes.ZodiacType[] NFT类型列表
     * @return uint8[] NFT等级列表
     * @return bool 是否还有更多
     */
    function getTokenDetailsByPage(address owner, uint256 page, uint256 pageSize) external view returns (
        uint256[] memory, 
        NFTDataTypes.ZodiacType[] memory, 
        uint8[] memory,
        bool
    ) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint256[] memory arr = m.userAllTokens(owner);
        uint256 total = arr.length;
        uint256 start = page * pageSize;
        
        if (start >= total) {
            return (new uint256[](0), new NFTDataTypes.ZodiacType[](0), new uint8[](0), false);
        }
        
        uint256 end = start + pageSize;
        if (end > total) {
            end = total;
        }
        
        uint256 count = end - start;
        uint256[] memory tokenIds = new uint256[](count);
        NFTDataTypes.ZodiacType[] memory types = new NFTDataTypes.ZodiacType[](count);
        uint8[] memory levels = new uint8[](count);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = arr[start + i];
            tokenIds[i] = tokenId;
            types[i] = m.tokenType(tokenId);
            levels[i] = m.tokenLevel(tokenId);
        }
        
        return (tokenIds, types, levels, end < total);
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