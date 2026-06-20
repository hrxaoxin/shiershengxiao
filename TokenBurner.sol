// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title TokenBurner
 * @dev 代币销毁与NFT铸造合约，负责管理代币销毁和NFT铸造流程
 *
 * 核心功能：
 * 1. 代币销毁：将用户代币转入黑洞地址进行永久销毁，实现代币通缩机制
 * 2. NFT铸造：销毁代币后调用NFTMint合约进行NFT铸造
 * 3. 费用管理：支持动态调整普通、稀有NFT铸造费用
 *
 * 铸造模式：
 * - 单抽模式：销毁一次代币，铸造一个NFT（普通或稀有）
 * - 十连抽模式：销毁十倍代币，连续铸造十个NFT
 * - 定向铸造：按指定生肖类型铸造（6普通、4稀有的组合）
 *
 * 权限控制：
 * - 仅所有者、授权合约可调用铸造相关函数
 * - 仅所有者可调整铸造费用参数
 *
 * 安全机制：
 * - 重入保护：nonReentrant修饰器防止重入攻击
 * - 暂停机制：paused标志支持紧急暂停
 * - 零地址检查：所有外部地址参数均需验证
 */
contract TokenBurner is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 黑洞地址，用于永久销毁代币
     * 转入此地址的代币将永久不可访问，实现通缩机制
     */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /**
     * @dev 暂停状态标志，true表示合约已暂停
     */
    bool public paused;
    /**
     * @dev 暂停原因说明，用于记录暂停操作的具体原因
     */
    string public pauseReason;

    /**
     * @dev 合约暂停事件，记录执行暂停的账户和原因
     */
    event Paused(address account, string reason);
    /**
     * @dev 合约取消暂停事件，记录执行取消暂停的账户
     */
    event Unpaused(address account);

    /**
     * @dev 修饰器：确保合约未处于暂停状态时才能执行函数
     */
    modifier whenNotPaused() {
        require(!paused, "TokenBurner: Paused");
        _;
    }

    /**
     * @dev 验证合约地址是否为有效地址
     * @param addr 要验证的地址
     * @param name 地址名称（用于错误消息）
     */
    function _validateContractAddress(address addr, string memory name) internal view {
        require(addr != address(0), string(abi.encodePacked("TokenBurner: ", name, " is zero address")));
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }
        require(codeSize > 0, string(abi.encodePacked("TokenBurner: ", name, " is not a contract")));
    }

    /**
     * @dev 暂停合约，停止所有铸造和销毁操作
     * 仅合约所有者可以调用，用于紧急情况下暂停服务
     * @param reason 暂停原因，将被记录在事件日志中
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消合约暂停，恢复铸造和销毁操作
     * 仅合约所有者可以调用
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 普通NFT单次铸造费用（单位：代币，18位小数）
     * 默认值：8888 * 10^18 = 8888 个代币
     */
    uint256 public normalMintCost = 8888 * 10**18;
    /**
     * @dev 稀有NFT单次铸造费用（单位：代币，18位小数）
     * 稀有NFT费用更高，默认值：88888 * 10^18 = 88888 个代币
     */
    uint256 public rareMintCost = 88888 * 10**18;

    /**
     * @dev 授权管理合约地址，用于授权其他合约的操作权限
     * 所有关联合约地址通过 authorizer 动态获取
     */
    address public authorizer;

    /**
     * @dev 代币销毁事件，记录用户地址、销毁数量和时间戳
     */
    event TokenBurned(address indexed user, uint256 amount, uint256 timestamp);
    /**
     * @dev 铸造费用更新事件，记录新旧费用值和更新时间
     */
    event MintCostUpdated(uint256 oldNormalCost, uint256 newNormalCost, uint256 oldRareCost, uint256 newRareCost, uint256 timestamp);
    /**
     * @dev NFT铸造完成事件，记录用户、NFT ID、生肖类型和是否稀有
     */
    event NFTMinted(address indexed user, uint256 tokenId, uint256 zodiacType, bool isRare);


    /**
     * @dev 修饰器：仅管理员或授权器可调用
     * 用于保护合约配置更新函数，如设置各种合约地址
     */
    modifier onlyAdminOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Not admin or authorizer");
        _;
    }

    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Not owner or authorizer");
        _;
    }

    /**
     * @dev 合约初始化函数（仅可调用一次）
     * 初始化合约地址和OpenZeppelin升级组件
     * @param _authorizerAddress 授权管理合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "TokenBurner: Invalid authorizer address");
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        
        // 初始化带默认值的参数
        normalMintCost = 8888 * 10**18;
        rareMintCost = 88888 * 10**18;
    }

    /**
     * @dev UUPS升级授权函数
     * 仅允许合约所有者升级合约实现
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权器地址
     * 仅所有者可调用，用于更改授权管理合约
     * @param _authorizerAddress 新的授权器地址，不可为零地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "TokenBurner: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置普通NFT铸造费用
     * 仅所有者可调整，用于更改单抽普通NFT的代币消耗
     * @param cost 新的普通NFT铸造费用（必须大于0）
     */
    function setNormalMintCost(uint256 cost) external onlyOwner {
        require(cost > 0, "TokenBurner: cost must be > 0");
        uint256 oldNormal = normalMintCost;
        uint256 oldRare = rareMintCost;
        normalMintCost = cost;
        emit MintCostUpdated(oldNormal, cost, oldRare, rareMintCost, block.timestamp);
    }

    /**
     * @dev 设置稀有NFT铸造费用
     * 仅所有者可调整，用于更改单抽稀有NFT的代币消耗
     * @param cost 新的稀有NFT铸造费用（必须大于0）
     */
    function setRareMintCost(uint256 cost) external onlyOwner {
        require(cost > 0, "TokenBurner: cost must be > 0");
        uint256 oldNormal = normalMintCost;
        uint256 oldRare = rareMintCost;
        rareMintCost = cost;
        emit MintCostUpdated(oldNormal, normalMintCost, oldRare, cost, block.timestamp);
    }

    /**
     * @dev 获取普通NFT十连抽总费用
     * @return 十连抽普通NFT所需总代币数
     */
    function normalMintTenCost() external view returns (uint256) {
        return normalMintCost * 10;
    }

    /**
     * @dev 获取稀有NFT十连抽总费用
     * @return 十连抽稀有NFT所需总代币数
     */
    function rareMintTenCost() external view returns (uint256) {
        return rareMintCost * 10;
    }

    /**
     * @dev 获取定向铸造费用
     * 定向铸造 = 6 * 普通铸造 + 4 * 稀有铸造，再乘以10（十连抽倍数）
     * @return 定向铸造所需总代币数
     */
    function targetedMintCost() external view returns (uint256) {
        return (normalMintCost * 6 + rareMintCost * 4) * 10;
    }

    /**
     * @dev 单次代币销毁并铸造NFT
     * 流程：验证合约配置 -> 检查用户余额和授权 -> 销毁代币 -> 调用NFTMint铸造
     * @param user 目标用户地址（将获得NFT的用户）
     * @param isRare 是否铸造稀有NFT（true=稀有，false=普通）
     * @return 操作是否成功，成功返回true
     */
    function burnAndMint(address user, bool isRare) external nonReentrant whenNotPaused returns (bool) {
        require(authorizer != address(0), "TokenBurner: authorizer not set");
        require(user != address(0), "TokenBurner: Zero user address");

        address tokenAddress = IAuthorizer(authorizer).getToken();
        _validateContractAddress(tokenAddress, "tokenContract");

        address nftMintAddress = IAuthorizer(authorizer).getNFTMintCore();
        _validateContractAddress(nftMintAddress, "nftMintContract");

        // 检查 NFTMintCore 是否暂停
        require(!INFTMintCore(nftMintAddress).paused(), "TokenBurner: NFT Mint paused");

        uint256 cost = isRare ? rareMintCost : normalMintCost;
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(user) >= cost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= cost, "TokenBurner: Insufficient allowance");
        token.safeTransferFrom(user, BLACK_HOLE, cost);

        emit TokenBurned(user, cost, block.timestamp);

        INFTMint nftMint = INFTMint(nftMintAddress);
        uint256 tokenId;
        if (isRare) {
            tokenId = nftMint.mintRare(user);
        } else {
            tokenId = nftMint.mintNormal(user);
        }
        require(tokenId > 0, "TokenBurner: NFT mint failed");

        emit NFTMinted(user, tokenId, nftMint.tokenType(tokenId), isRare);

        return true;
    }

    /**
     * @dev 十连代币销毁并批量铸造NFT
     * 一次性销毁十倍代币并铸造十个NFT，适合批量抽卡场景
     * @param user 目标用户地址（将获得NFT的用户）
     * @param isRare 是否铸造稀有NFT（true=稀有，false=普通）
     * @return 操作是否成功，成功返回true
     */
    function burnAndMintTen(address user, bool isRare) external nonReentrant whenNotPaused returns (bool) {
        require(authorizer != address(0), "TokenBurner: authorizer not set");
        require(user != address(0), "TokenBurner: Zero user address");

        address tokenAddress = IAuthorizer(authorizer).getToken();
        _validateContractAddress(tokenAddress, "tokenContract");

        address nftMintBatchAddress = IAuthorizer(authorizer).getNFTMintBatch();
        _validateContractAddress(nftMintBatchAddress, "nftMintBatchContract");

        address nftMintAddress = IAuthorizer(authorizer).getNFTMintCore();
        _validateContractAddress(nftMintAddress, "nftMintContract");

        // 检查 NFTMintCore 是否暂停
        require(!INFTMintCore(nftMintAddress).paused(), "TokenBurner: NFT Mint paused");

        // 检查 NFTMintBatch 是否暂停
        require(!INFTMintBatch(nftMintBatchAddress).paused(), "TokenBurner: NFT Mint Batch paused");

        uint256 cost = isRare ? rareMintCost * 10 : normalMintCost * 10;
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(user) >= cost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= cost, "TokenBurner: Insufficient allowance");
        token.safeTransferFrom(user, BLACK_HOLE, cost);

        emit TokenBurned(user, cost, block.timestamp);

        uint256[] memory tokenIds;
        if (isRare) {
            tokenIds = INFTMintBatch(nftMintBatchAddress).mintRareTen(user);
        } else {
            tokenIds = INFTMintBatch(nftMintBatchAddress).mintNormalTen(user);
        }
        require(tokenIds.length == 10, "TokenBurner: Batch mint failed");

        INFTMint nftMint = INFTMint(nftMintAddress);
        for (uint256 i = 0; i < 10; i++) {
            emit NFTMinted(user, tokenIds[i], nftMint.tokenType(tokenIds[i]), isRare);
        }

        return true;
    }

    /**
 * @dev 定向代币销毁并铸造指定生肖NFT
 * 按指定生肖类型铸造，费用 = (普通费用 * 6 + 稀有费用 * 4) * 10
 * 生成10个NFT：6个普通属性（水/风/火）+ 4个稀有属性（暗/光）
 * @param user 目标用户地址（将获得NFT的用户）
 * @param zodiac 目标生肖索引（0-11，对应十二生肖：0=鼠, 1=牛, ..., 11=猪）
 * @return 操作是否成功，成功返回true
 */
function burnAndMintTargeted(address user, uint8 zodiac) external nonReentrant whenNotPaused returns (bool) {
    require(authorizer != address(0), "TokenBurner: authorizer not set");
    require(user != address(0), "TokenBurner: Zero user address");
    require(zodiac < 12, "TokenBurner: Invalid zodiac type");

    address tokenAddress = IAuthorizer(authorizer).getToken();
    _validateContractAddress(tokenAddress, "tokenContract");

    address nftMintAddress = IAuthorizer(authorizer).getNFTMintCore();
    _validateContractAddress(nftMintAddress, "nftMintContract");

    // 检查 NFTMintCore 是否暂停
    require(!INFTMintCore(nftMintAddress).paused(), "TokenBurner: NFT Mint paused");

    uint256 totalCost = (normalMintCost * 6 + rareMintCost * 4) * 10;
    IERC20 token = IERC20(tokenAddress);
    require(token.balanceOf(user) >= totalCost, "TokenBurner: Insufficient balance");
    require(token.allowance(user, address(this)) >= totalCost, "TokenBurner: Insufficient allowance");
    token.safeTransferFrom(user, BLACK_HOLE, totalCost);

    emit TokenBurned(user, totalCost, block.timestamp);

    INFTMint nftMint = INFTMint(nftMintAddress);
    uint256 zodiacType;
    
    // 普通铸造：6个（水/风/火属性 × 公/母）
    for (uint256 i = 0; i < 6; i++) {
        zodiacType = (i / 2) * 24 + zodiac * 2 + (i % 2);
        uint256 tokenId = nftMint.mint(user, zodiacType);
        require(tokenId > 0, "TokenBurner: NFT mint failed");
        emit NFTMinted(user, tokenId, zodiacType, false);
    }
    
    // 稀有铸造：4个（暗/光属性 × 公/母）
    for (uint256 i = 0; i < 4; i++) {
        zodiacType = (3 + i / 2) * 24 + zodiac * 2 + (i % 2);
        uint256 tokenId = nftMint.mint(user, zodiacType);
        require(tokenId > 0, "TokenBurner: NFT mint failed");
        emit NFTMinted(user, tokenId, zodiacType, true);
    }

    return true;
}

    /**
     * @dev 获取铸造费用
     * @param isRare 是否稀有
     * @param count 数量
     * @return 总费用
     */
    function getMintCost(bool isRare, uint256 count) external view returns (uint256) {
        require(count > 0, "TokenBurner: Invalid count");
        uint256 singleCost = isRare ? rareMintCost : normalMintCost;
        return singleCost * count;
    }

    /**
     * @dev 获取定向铸造费用
     * @return 普通部分费用
     * @return 稀有部分费用
     * @return 总费用
     */
    function getTargetedMintCost() external view returns (uint256, uint256, uint256) {
        uint256 normalPart = normalMintCost * 6 * 10;
        uint256 rarePart = rareMintCost * 4 * 10;
        return (normalPart, rarePart, normalPart + rarePart);
    }

    /**
     * @dev 获取所有费用配置
     * @return 普通铸造费用
     * @return 稀有铸造费用
     */
    function getAllCosts() external view returns (uint256, uint256) {
        return (normalMintCost, rareMintCost);
    }

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}