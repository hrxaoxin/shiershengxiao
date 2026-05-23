// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTMint
 * @dev 十二生肖NFT合约，支持铸造、升级、繁殖等功能
 * 实现120种生肖NFT类型（5属性x12生肖x2性别）
 * 基于OpenZeppelin UUPS可升级合约实现
 *
 * 模块拆分说明：
 * - MintModule: 随机类型生成、成长值计算
 * - UpgradeModule: 升级费用计算、燃烧候选查找
 * - PriceOracle: PancakeSwap代币USD价格查询
 */
import "./NFTData.sol";
import "./NFTLib.sol";
import "./NFTInterface.sol";
import "./NFTQueryLib.sol";
import "./NFTMintDelegator.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/ERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/Counters.sol";

/**
 * @title NFTMint
 * @dev 十二生肖NFT主合约（ERC721核心 + 模块协调）
 */
contract NFTMint is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, ERC721HolderUpgradeable, PausableUpgradeable, INFTMint {
    using Counters for Counters.Counter;

    /** @dev 存储间隙计数器（保留用于存储兼容性） */
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
    /** @dev @deprecated PancakeSwap流动性池地址（已迁移至PriceOracle） */
    address public pancakeSwapPair;
    /** @dev @deprecated WBNB合约地址（已迁移至PriceOracle） */
    address public wbnbAddress;
    /** @dev @deprecated 稳定币合约地址（已迁移至PriceOracle） */
    address public stablecoinAddress;
    /** @dev 繁殖合约地址 */
    address public breedingContract;
    /** @dev NFT升级合约地址（旧版兼容） */
    address public nftUpdateContract;
    /** @dev @deprecated 价格过期时间（已迁移至PriceOracle） */
    uint256 public priceExpirySeconds;
    /** @dev @deprecated 价格波动保护阈值（已迁移至PriceOracle） */
    uint256 public priceDeviationThreshold;
    /** @dev @deprecated 上次价格（已迁移至PriceOracle） */
    uint256 public lastPrice;
    /** @dev @deprecated 上次价格更新时间（已迁移至PriceOracle） */
    uint256 public lastPriceUpdateTime;
    /** @dev @deprecated 升级费用变量（已迁移至UpgradeModule） */
    uint256 public level1UpgradeCost;
    uint256 public level2UpgradeCost;
    uint256 public level3UpgradeCost;
    uint256 public level4UpgradeCost;
    /** @dev 授权铸造者映射 */
    mapping(address => bool) public authorizedMinter;

    // ---- 新增：模块地址 ----
    /** @dev 铸造模块合约地址 */
    address public mintModule;
    /** @dev 升级模块合约地址 */
    address public upgradeModule;
    /** @dev 价格预言机合约地址 */
    address public priceOracle;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[47] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    // ====================== Init ======================

    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _metadataContract 元数据合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address initialOwner, address _metadataContract, address _authorizer) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC721_init("Twelve Zodiacs", "12ZODIAC");
        __ERC721Holder_init();
        __Pausable_init();
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

    // ====================== URI ======================

    /**
     * @dev 获取NFT的元数据URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "E0");
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        string memory json = string(abi.encodePacked(
            '{"name":"', m.getCardName(t), " #", NFTLib.uint2str(tokenId), '",',
            '"description":"', NFTLib.escapeString(m.getCardDesc(t)), '",',
            '"image":"', NFTLib.escapeString(m.getCardImage(t)), '"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", NFTLib.base64Encode(bytes(json))));
    }

    /**
     * @dev 获取合约级别的元数据URI（用于OpenSea等平台）
     */
    function contractURI() public view returns (string memory) {
        require(metadataContract != address(0), "E1");
        INFTDataInterface m = INFTDataInterface(metadataContract);
        IRewardManager rm = IRewardManager(rewardManager);
        string memory json = string(abi.encodePacked(
            '{"name":"', NFTLib.escapeString(m.collName()), '",',
            '"description":"', NFTLib.escapeString(m.collDesc()), '",',
            '"image":"', NFTLib.escapeString(m.collImage()), '",',
            '"seller_fee_basis_points":', NFTLib.uint2str(m.sellerFeeBasisPoints()), ',',
            '"fee_recipient":"', NFTLib.addressToString(rm.royaltyWallet()), '"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", NFTLib.base64Encode(bytes(json))));
    }

    // ====================== Mint (主逻辑 + 模块调用) ======================

    /**
     * @dev 内部统一铸造逻辑
     */
    function _mintRaw(address to, NFTDataTypes.ZodiacType t, uint256 growthValue) internal returns (uint256) {
        (uint256 id, uint256 newId) = NFTMintDelegator.mintRaw(address(this), metadataContract, nextCardId, to, t, growthValue);
        nextCardId = newId;
        return id;
    }

    /**
     * @dev 普通铸造：销毁代币，随机铸造五种属性中的任意一个生肖
     */
    function mintNormal(address to) external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMint(to, false), "E6");
        require(mintModule != address(0), "Module not set");
        (NFTDataTypes.ZodiacType t, uint256 growth) = IMintModule(mintModule).generateNormalType();
        return _mintRaw(to, t, growth);
    }

    /**
     * @dev 稀有铸造：销毁代币，随机铸造光或暗属性的生肖
     */
    function mintRare(address to) external nonReentrant returns (uint256) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMint(to, true), "E6");
        require(mintModule != address(0), "Module not set");
        (NFTDataTypes.ZodiacType t, uint256 growth) = IMintModule(mintModule).generateRareType();
        return _mintRaw(to, t, growth);
    }

    /**
     * @dev 指定类型铸造（仅Owner）
     */
    function mintCustom(address to, NFTDataTypes.ZodiacType zodiacType) external nonReentrant onlyOwner returns (uint256) {
        require(to != address(0), "E11");
        require(mintModule != address(0), "Module not set");
        uint256 growth = IMintModule(mintModule).generateGrowth();
        return _mintRaw(to, zodiacType, growth);
    }

    /**
     * @dev 铸造繁殖结果NFT（仅限繁殖合约调用）
     */
    function mintBreedResult(address to, NFTDataTypes.ZodiacType t) external nonReentrant returns (uint256) {
        require(msg.sender == breedingContract, "E12");
        require(mintModule != address(0), "Module not set");
        uint256 growth = IMintModule(mintModule).generateGrowth();
        return _mintRaw(to, t, growth);
    }

    /**
     * @dev 批量铸造内部逻辑（十连铸造复用）
     */
    function _mintBatchRaw(
        address to,
        NFTDataTypes.ZodiacType[] memory types,
        uint256[] memory growthValues,
        bool isNormal
    ) internal returns (uint256[] memory) {
        (uint256[] memory tokenIds, uint256 newId) = NFTMintDelegator.mintBatchRaw(address(this), metadataContract, nextCardId, to, types, growthValues, isNormal);
        nextCardId = newId;
        return tokenIds;
    }

    /**
     * @dev 普通十连铸造
     */
    function mintNormalTen(address to) external nonReentrant returns (uint256[] memory) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMintTen(to, false), "E6");
        require(mintModule != address(0), "Module not set");
        (NFTDataTypes.ZodiacType[] memory types, uint256[] memory growthValues) = IMintModule(mintModule).generateTenNormalTypes();
        return _mintBatchRaw(to, types, growthValues, true);
    }

    /**
     * @dev 光暗十连铸造
     */
    function mintRareTen(address to) external nonReentrant returns (uint256[] memory) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMintTen(to, true), "E6");
        require(mintModule != address(0), "Module not set");
        (NFTDataTypes.ZodiacType[] memory types, uint256[] memory growthValues) = IMintModule(mintModule).generateTenRareTypes();
        return _mintBatchRaw(to, types, growthValues, false);
    }

    /**
     * @dev 指定铸造：选择一个生肖，铸造该生肖所有属性和性别的NFT（共10张）
     */
    function mintTargeted(address to, NFTDataTypes.BaseZodiac baseZodiac) external nonReentrant returns (uint256[] memory) {
        require(tokenBurner != address(0) && rewardManager != address(0), "E2");
        require(ITokenBurner(tokenBurner).burnAndMintTargeted(to), "E6");
        (uint256[] memory tokenIds, uint256 newId) = NFTMintDelegator.mintTargetedLogic(address(this), metadataContract, mintModule, nextCardId, to, baseZodiac);
        nextCardId = newId;
        return tokenIds;
    }

    // ====================== Transfer Hook ======================

    /**
     * @dev 转账前的钩子函数
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        uint8 lv = m.tokenLevel(tokenId);
        if (from != address(0) && from != BLACK_HOLE) {
            m.removeUserToken(from, t, tokenId);
            _updateReward(from, t, false);
            _updateUserWeight(from, tokenId, lv, false);
        }
        if (to != address(0) && to != BLACK_HOLE) {
            m.addUserToken(to, t, tokenId);
            _updateReward(to, t, true);
            _updateUserWeight(to, tokenId, lv, true);
        }
    }

    /**
     * @dev 更新奖励管理器中的用户卡牌计数
     */
    function _updateReward(address u, NFTDataTypes.ZodiacType t, bool add) internal {
        NFTMintDelegator.updateReward(rewardManager, u, t, add);
    }

    // ====================== Upgrade (主逻辑 + 模块调用) ======================

    function upgradeWithNFT(uint256 tokenId) external nonReentrant returns (uint8) {
        return NFTMintDelegator.upgradeWithNFTLogic(address(this), metadataContract, upgradeModule, tokenId, msg.sender, BLACK_HOLE);
    }

    function upgradeWithToken(uint256 tokenId) external nonReentrant returns (uint8) {
        return NFTMintDelegator.upgradeWithTokenLogic(address(this), metadataContract, upgradeModule, tokenContract, tokenId, msg.sender, BLACK_HOLE);
    }

    function upgradeWithUSDValue(uint256 tokenId) external nonReentrant returns (uint8) {
        return NFTMintDelegator.upgradeWithUSDValueLogic(address(this), metadataContract, upgradeModule, tokenContract, priceOracle, tokenId, msg.sender, BLACK_HOLE);
    }

    function _upgradeLevel(uint id, uint8 oldLv) internal returns (uint8) {
        return NFTMintDelegator.upgradeLevel(address(this), metadataContract, id, oldLv, msg.sender);
    }

    // ====================== Config Setters ======================

    /**
     * @dev 设置TokenBurner和RewardManager地址
     */
    function setAddresses(address tb, address rm) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenBurner = tb;
        rewardManager = rm;
        IRewardManager(rm).setAuthorizedNFTContract(address(this), true);
    }

    /**
     * @dev 设置元数据合约地址
     */
    function setMetadataContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        metadataContract = a;
    }

    /**
     * @dev 设置代币合约地址
     */
    function setTokenContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenContract = a;
    }

    /**
     * @dev 设置繁殖合约地址
     */
    function setBreedingContract(address a) external onlyOwner {
        breedingContract = a;
    }

    /**
     * @dev 设置NFT升级合约地址（旧版兼容）
     */
    function setNFTUpdateContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        nftUpdateContract = a;
    }

    /**
     * @dev 授权/取消铸造者
     */
    function authorizeMinter(address a) external onlyOwner { authorizedMinter[a] = true; }
    function unauthorizedMinter(address a) external onlyOwner { authorizedMinter[a] = false; }

    /**
     * @dev 设置授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner { authorizer = a; }

    // ---- 模块地址设置 ----

    /**
     * @dev 设置铸造模块合约地址
     */
    function setMintModule(address a) external onlyOwner {
        require(a != address(0), "Zero address");
        mintModule = a;
    }

    /**
     * @dev 设置升级模块合约地址
     */
    function setUpgradeModule(address a) external onlyOwner {
        require(a != address(0), "Zero address");
        upgradeModule = a;
    }

    /**
     * @dev 设置价格预言机合约地址
     */
    function setPriceOracle(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        priceOracle = a;
    }

    // ====================== Weight ======================

    /**
     * @dev 更新用户权重缓存
     */
    function _updateUserWeight(address user, uint256 tokenId, uint8 level, bool add) internal {
        NFTMintDelegator.updateUserWeight(metadataContract, user, tokenId, level, add);
    }

    /**
     * @dev 计算用户权重（用于分红计算）
     */
    function calcUserWeight(address user) external view returns (uint256) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.userWeightCache(user);
    }

    // ====================== Query ======================

    function tokenType(uint256 tokenId) external view override returns (NFTDataTypes.ZodiacType) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.tokenType(tokenId);
    }

    function tokenLevel(uint256 tokenId) external view override returns (uint8) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.tokenLevel(tokenId);
    }

    function tokenGrowthValue(uint256 tokenId) external view returns (uint256) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.tokenGrowthValue(tokenId);
    }

    function getCardCount(address u, NFTDataTypes.ZodiacType t) external view returns (uint) {
        return IRewardManager(rewardManager).cardCount(u, t);
    }

    function totalSupply() external view returns (uint256) {
        return nextCardId - 1;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        return NFTQueryLib.tokenOfOwnerByIndex(metadataContract, owner, index);
    }

    function balanceOf(address owner) public view override returns (uint256) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        return m.userAllTokens(owner).length;
    }

    // ====================== Pagination (delegates to NFTQueryLib) ======================

    function getTokensByPage(address owner, uint256 page, uint256 pageSize) external view returns (uint256[] memory, bool) {
        return NFTQueryLib.getTokensByPage(metadataContract, owner, page, pageSize);
    }

    function getTokenDetailsByPage(address owner, uint256 page, uint256 pageSize) external view returns (
        uint256[] memory,
        NFTDataTypes.ZodiacType[] memory,
        uint8[] memory,
        bool
    ) {
        return NFTQueryLib.getTokenDetailsByPage(metadataContract, owner, page, pageSize);
    }

    // ====================== ERC721 Overrides ======================

    function ownerOf(uint256 tokenId) public view override(ERC721Upgradeable, INFTMint) returns (address) {
        return super.ownerOf(tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, INFTMint) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, INFTMint) {
        super.transferFrom(from, to, tokenId);
    }

    function isApprovedForAll(address owner, address operator) public view override(ERC721Upgradeable, INFTMint) returns (bool) {
        return super.isApprovedForAll(owner, operator);
    }

    function getApproved(uint256 tokenId) public view override(ERC721Upgradeable, INFTMint) returns (address) {
        return super.getApproved(tokenId);
    }

    // ====================== ERC721 Delegator Callback Wrappers ======================

    /**
     * @dev 供 NFTMintDelegator 库回调 _safeMint（ERC721Upgradeable internal）
     */
    function delegator_safeMint(address to, uint256 tokenId) external {
        require(msg.sender == address(this), "!self");
        _safeMint(to, tokenId);
    }

    /**
     * @dev 供 NFTMintDelegator 库回调 _safeTransfer（ERC721Upgradeable internal）
     */
    function delegator_safeTransfer(address from, address to, uint256 tokenId) external {
        require(msg.sender == address(this), "!self");
        _safeTransfer(from, to, tokenId, "");
    }

    /**
     * @dev 供 NFTMintDelegator 库回调 _ownerOf（ERC721Upgradeable internal）
     */
    function delegator_ownerOf(uint256 tokenId) external view returns (address) {
        require(msg.sender == address(this), "!self");
        return _ownerOf(tokenId);
    }

    // ====================== Events ======================

    event CardMinted(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner, uint64 timestamp);
    event CardBurned(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner);
    event CardUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);
    event TenCardsMinted(uint256[] indexed tokenIds, address indexed owner, bool isNormal, uint64 timestamp);
    event TargetedMintCompleted(uint256[] indexed tokenIds, address indexed owner, NFTDataTypes.BaseZodiac indexed baseZodiac, uint64 timestamp);
    event RewardUpdateFailed(address indexed user, NFTDataTypes.ZodiacType indexed zodiacType, uint256 count, bool add);
}
