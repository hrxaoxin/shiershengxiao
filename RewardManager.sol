// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RewardManager
 * @dev 奖励管理器合约，负责管理NFT持有者的分红和权重计算
 * 支持添加/移除持有者、计算用户权重、分配分红等功能
 * 基于OpenZeppelin UUPS可升级合约实现
 */

import "./NFTInterface.sol";

// 全部统一适配 OpenZeppelin Upgradeable v4.9
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title RewardManager
 * @dev 奖励管理器合约，负责管理NFT持有者的分红和权重计算
 */
contract RewardManager is
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IERC2981
{
    /** @dev 合约版本号 */
    uint256 public constant VERSION = 2;
    /** @dev 每张卡牌的权重值 */
    uint256 public constant WEIGHT_PER_CARD = 8;
    /** @dev 最低所有者权重（可修改） */
    uint256 public minOwnerWeight = 100;
    /** @dev 最大版税比例（5000 = 50%） */
    uint256 public constant MAX_ROYALTY_FEE = 5000;

    /** @dev 当前持有者总数 */
    uint256 public holdersCount;
    /** @dev 分红池余额 */
    uint256 public dividendPool;
    /** @dev 已分发的分红总量 */
    uint256 public totalDistributed;
    /** @dev 运营者地址 */
    address public operator;
    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 授权合约地址 */
    address public authorizer;
    /** @dev 所有者权重 */
    uint256 public ownerWeight;
    /** @dev 版税接收钱包地址 */
    address public royaltyWallet;
    /** @dev 版税比例（默认500 = 5%） */
    uint256 public royaltyFee = 500;
    /** @dev 比例总和分母 */
    uint256 public constant RATIO_DENOMINATOR = 10000;
    /** @dev 用户分红比例（4500 = 45%）*/
    uint256 public dividendRatio = 4500;
    /** @dev 合约所有者比例（500 = 5%）*/
    uint256 public ownerRatio = 500;
    /** @dev NFT质押矿池比例（2500 = 25%）*/
    uint256 public nftStakingRatio = 2500;
    /** @dev 竞技场奖励矿池比例（1500 = 15%）*/
    uint256 public arenaRatio = 1500;
    /** @dev 代币质押矿池比例（1000 = 10%）*/
    uint256 public tokenStakingRatio = 1000;
    
    /** @dev 所有者资金池 */
    uint256 public ownerPool;
    /** @dev NFT质押矿池 */
    uint256 public nftStakingPool;
    /** @dev 竞技场奖励矿池 */
    uint256 public arenaPool;
    /** @dev 代币质押矿池 */
    uint256 public tokenStakingPool;
    /** @dev 分红池最大容量（1000 ETH/BNB）*/
    uint256 public constant MAX_DIVIDEND_POOL = 1000 ether;
    /** @dev 自动兑换阈值（达到此金额自动兑换）*/
    uint256 public autoSwapThreshold = 0.01 ether;
    /** @dev 代币合约地址 */
    address public rewardToken;
    /** @dev NFT质押合约地址 */
    address public stakingContract;
    /** @dev 代币质押合约地址 */
    address public tokenStakingContract;
    /** @dev 竞技场合约地址 */
    address public arenaContract;
    /** @dev SwapRouter 地址（PancakeSwap V2 Router）*/
    address public swapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    /** @dev PancakeFactory 地址（用于检测交易池）*/
    address public pancakeFactory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    /** @dev 授权的NFT合约映射 */
    mapping(address => bool) public authorizedNFTContracts;
    /** @dev NFT数据合约地址 */
    address public nftDataContract;
    /** @dev 是否为持有者映射 */
    mapping(address => bool) public isHolder;
    /** @dev 用户已领取分红映射 */
    mapping(address => uint256) public claimedDividend;
    /** @dev 用户精度累积映射 */
    mapping(address => uint256) public precisionAcc;
    /** @dev 用户精度累积次数（用于解决长期累积导致的精度丢失问题） */
    mapping(address => uint256) public precisionAccumulationCount;
    /** @dev 用户权重映射 */
    mapping(address => uint256) public userWeight;
    /** @dev 总权重 */
    uint256 public totalWeight;

    /** @dev 符合资格用户链表前驱映射 */
    mapping(address => address) public eligibleUserPrev;
    /** @dev 符合资格用户链表后继映射 */
    mapping(address => address) public eligibleUserNext;
    /** @dev 符合资格用户链表头 */
    address public eligibleUserHead;
    /** @dev 符合资格用户链表尾 */
    address public eligibleUserTail;
    /** @dev 用户是否在资格列表中 */
    mapping(address => bool) public inEligibleList;

    /** @dev 用户操作时间映射（用户地址 => 函数选择器 => 时间戳） */
    mapping(address => mapping(bytes4 => uint256)) public lastOperationTime;
    /** @dev 操作冷却时间（默认1秒） */
    uint256 public operationCooldown = 1 seconds;

    /** @dev 用户权重缓存映射 */
    mapping(address => uint256) public cachedUserWeight;
    /** @dev 用户权重缓存时间戳映射 */
    mapping(address => uint256) public cachedWeightTimestamp;
    /** @dev 权重缓存有效期（默认5分钟） */
    uint256 public weightCacheDuration = 5 minutes;

    /**
     * @dev 卡牌更新事件
     * @param user 用户地址
     * @param t 生肖类型
     * @param c 卡牌数量
     * @param ts 时间�?
     */
    event CardUpdated(address indexed user, NFTDataTypes.ZodiacType t, uint256 c, uint256 ts);
    /**
     * @dev 分红领取事件
     * @param user 用户地址
     * @param amt 领取金额
     * @param prec 精度�?
     * @param ts 时间�?
     */
    event DividendClaimed(address indexed user, uint256 amt, uint256 prec, uint256 ts);
    /**
     * @dev 分红存入事件
     * @param amt 存入金额
     * @param sender 发送者地址
     * @param ts 时间�?
     */
    event DividendDeposited(uint256 amt, address indexed sender, uint256 ts);
    /**
     * @dev 用户权重更新事件
     * @param user 用户地址
     * @param oldWeight 旧权�?
     * @param newWeight 新权�?
     * @param ts 时间�?
     */
    event UserWeightUpdated(address indexed user, uint256 oldWeight, uint256 newWeight, uint256 ts);
    /**
     * @dev 总权重更新事�?
     * @param oldTotal 旧总权�?
     * @param newTotal 新总权�?
     * @param ts 时间�?
     */
    event TotalWeightUpdated(uint256 oldTotal, uint256 newTotal, uint256 ts);
    /**
     * @dev NFT合约授权事件
     * @param nftContract NFT合约地址
     * @param authorized 是否授权
     * @param timestamp 时间�?
     */
    event NFTContractAuthorized(address indexed nftContract, bool authorized, uint256 timestamp);
    /**
     * @dev 紧急暂停事�?
     * @param owner 所有者地址
     * @param timestamp 时间�?
     */
    event EmergencyPause(address indexed owner, uint256 timestamp);
    /**
     * @dev NFT合约更新事件
     * @param oldNFTContract 旧NFT合约地址
     * @param newNFTContract 新NFT合约地址
     * @param timestamp 时间�?
     */
    event NFTContractUpdated(address indexed oldNFTContract, address indexed newNFTContract, uint256 timestamp);
    /**
     * @dev 版税钱包更新事件
     * @param oldWallet 旧钱包地址
     * @param newWallet 新钱包地址
     * @param timestamp 时间�?
     */
    event RoyaltyWalletUpdated(address indexed oldWallet, address indexed newWallet, uint256 timestamp);
    /**
     * @dev 额外资金提取事件
     * @param owner 所有者地址
     * @param amount 提取金额
     * @param timestamp 时间�?
     */
    event ExtraFundsWithdrawn(address indexed owner, uint256 amount, uint256 timestamp);
    /**
     * @dev 全部资金提取事件
     * @param owner 所有者地址
     * @param amount 提取金额
     * @param timestamp 时间�?
     */
    event FullFundsWithdrawn(address indexed owner, uint256 amount, uint256 timestamp);

    /** @dev 存储间隙，用于合约升级兼容�?*/
    uint256[90] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 授权检查修饰器
     * 只有owner、operator、nftContract、authorizer或已授权的合约才能调�?
     */
    modifier onlyAuthorized() {
        require(
            msg.sender == owner() ||
            msg.sender == operator ||
            msg.sender == nftContract ||
            msg.sender == authorizer ||
            authorizedNFTContracts[msg.sender],
            "RewardManager: Unauthorized"
        );
        _;
    }

    /**
     * @dev 非零地址检查修饰器
     * @param _addr 检查的地址
     */
    modifier nonZeroAddress(address _addr) {
        require(_addr != address(0), "RewardManager: Zero address");
        _;
    }

    /**
     * @dev 紧急所有者检查修饰器
     */
    modifier onlyEmergencyOwner() {
        require(msg.sender == owner(), "RewardManager: Only owner");
        _;
    }

    /**
     * @dev 速率限制检查修饰器
     * @param funcSig 函数选择�?
     */
    modifier rateLimited(bytes4 funcSig) {
        require(
            block.timestamp >= lastOperationTime[msg.sender][funcSig] + operationCooldown,
            "RewardManager: Operation cooldown active"
        );
        lastOperationTime[msg.sender][funcSig] = block.timestamp;
        _;
    }

    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _royaltyWallet 版税接收钱包地址
     * @param _operator 运营者地址
     * @param _nftContract NFT合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(
        address initialOwner,
        address _royaltyWallet,
        address _operator,
        address _nftContract,
        address _nftDataContract,
        address _authorizer,
        address _rewardToken,
        address _stakingContract,
        address _tokenStakingContract,
        address _arenaContract,
        address _swapRouter
    ) external initializer nonZeroAddress(initialOwner) nonZeroAddress(_operator) nonZeroAddress(_nftContract) {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        royaltyWallet = _royaltyWallet == address(0) ? initialOwner : _royaltyWallet;
        operator = _operator;
        nftContract = _nftContract;
        nftDataContract = _nftDataContract;
        authorizer = _authorizer;
        rewardToken = _rewardToken;
        stakingContract = _stakingContract;
        tokenStakingContract = _tokenStakingContract;
        arenaContract = _arenaContract;
        swapRouter = _swapRouter;
        ownerWeight = minOwnerWeight;
        totalWeight = ownerWeight;

        eligibleUserHead = address(0);
        eligibleUserTail = address(0);

        authorizedNFTContracts[_nftContract] = true;

        emit TotalWeightUpdated(0, totalWeight, block.timestamp);
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyEmergencyOwner
        nonZeroAddress(newImplementation)
    {}

    /**
     * @dev 获取NFT版税信息（ERC2981接口实现）
     * @param salePrice 销售价格
     * @return receiver 版税接收地址
     * @return royaltyAmount 版税金额
     */
    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        return (royaltyWallet, (salePrice * royaltyFee) / 10000);
    }

    /**
     * @dev 设置授权的NFT合约
     * @param nft NFT合约地址
     * @param ok 是否授权
     */
    function setAuthorizedNFTContract(address nft, bool ok) external nonZeroAddress(nft) {
        require(msg.sender == owner() || msg.sender == operator || msg.sender == nftContract || msg.sender == authorizer || authorizedNFTContracts[msg.sender], "RewardManager: Unauthorized");
        authorizedNFTContracts[nft] = ok;
        emit NFTContractAuthorized(nft, ok, block.timestamp);
    }

    /**
     * @dev 设置NFT合约地址
     * @param _newNFTContract 新NFT合约地址
     */
    function setNFTContract(address _newNFTContract) external onlyOwner nonZeroAddress(_newNFTContract) {
        address oldNFTContract = nftContract;
        require(oldNFTContract != _newNFTContract, "RewardManager: Cannot set same NFT contract");
        nftContract = _newNFTContract;
        emit NFTContractUpdated(oldNFTContract, _newNFTContract, block.timestamp);
    }

    /**
     * @dev 设置运营者地址
     * @param _op 新运营者地址
     */
    function setOperator(address _op) external onlyOwner nonZeroAddress(_op) {
        operator = _op;
    }

    /**
     * @dev 设置所有者权�?
     * @param _w 新权重�?
     */
    function setOwnerWeight(uint256 _w) external onlyOwner {
        require(_w >= minOwnerWeight, "RewardManager: Owner weight must be >= minimum weight");

        uint256 oldOwnerWeight = ownerWeight;
        totalWeight = totalWeight - oldOwnerWeight + _w;
        ownerWeight = _w;

        emit TotalWeightUpdated(oldOwnerWeight, totalWeight, block.timestamp);
    }

    /**
     * @dev 设置最低所有者权重
     * @param _minWeight 新的最低权重值
     */
    function setMinOwnerWeight(uint256 _minWeight) external onlyOwner {
        require(_minWeight > 0, "RewardManager: Minimum weight must be greater than 0");
        minOwnerWeight = _minWeight;
        if (ownerWeight < minOwnerWeight) {
            uint256 oldOwnerWeight = ownerWeight;
            totalWeight = totalWeight - oldOwnerWeight + minOwnerWeight;
            ownerWeight = minOwnerWeight;
            emit TotalWeightUpdated(oldOwnerWeight, totalWeight, block.timestamp);
        }
    }

    /**
     * @dev 设置版税接收钱包
     * @param _newRoyaltyWallet 新钱包地址
     */
    function setRoyaltyWallet(address _newRoyaltyWallet) external onlyOwner nonZeroAddress(_newRoyaltyWallet) {
        address oldRoyaltyWallet = royaltyWallet;
        require(oldRoyaltyWallet != _newRoyaltyWallet, "RM: same royalty wallet");
        royaltyWallet = _newRoyaltyWallet;
        emit RoyaltyWalletUpdated(oldRoyaltyWallet, _newRoyaltyWallet, block.timestamp);
    }

    /**
     * @dev 设置版税比例
     * @param _f 新版税比例
     */
    function setRoyaltyFee(uint256 _f) external onlyOwner {
        require(_f >= 0 && _f <= MAX_ROYALTY_FEE, "RM: fee invalid");
        royaltyFee = _f;
    }

    /**
     * @dev 设置用户分红比例
     * @param _ratio 新比例（精度4位，如4500表示45%）
     */
    function setDividendRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 0 && _ratio <= RATIO_DENOMINATOR, "RM: dividend ratio invalid");
        require(_ratio + ownerRatio + nftStakingRatio + arenaRatio + tokenStakingRatio <= RATIO_DENOMINATOR, "RM: total ratio exceeds 100%");
        dividendRatio = _ratio;
    }

    /**
     * @dev 设置合约所有者比例
     * @param _ratio 新比例（精度4位，如500表示5%）
     */
    function setOwnerRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 0 && _ratio <= RATIO_DENOMINATOR, "RM: owner ratio invalid");
        require(dividendRatio + _ratio + nftStakingRatio + arenaRatio + tokenStakingRatio <= RATIO_DENOMINATOR, "RM: total ratio exceeds 100%");
        ownerRatio = _ratio;
    }

    /**
     * @dev 设置NFT质押矿池比例
     * @param _ratio 新比例（精度4位，如2500表示25%）
     */
    function setNftStakingRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 0 && _ratio <= RATIO_DENOMINATOR, "RM: NFT staking ratio invalid");
        require(dividendRatio + ownerRatio + _ratio + arenaRatio + tokenStakingRatio <= RATIO_DENOMINATOR, "RM: total ratio exceeds 100%");
        nftStakingRatio = _ratio;
    }

    /**
     * @dev 设置竞技场奖励比例
     * @param _ratio 新比例（精度4位，如1500表示15%）
     */
    function setArenaRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 0 && _ratio <= RATIO_DENOMINATOR, "RM: arena ratio invalid");
        require(dividendRatio + ownerRatio + nftStakingRatio + _ratio + tokenStakingRatio <= RATIO_DENOMINATOR, "RM: total ratio exceeds 100%");
        arenaRatio = _ratio;
    }

    /**
     * @dev 设置代币质押矿池比例
     * @param _ratio 新比例（精度4位，如1000表示10%）
     */
    function setTokenStakingRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 0 && _ratio <= RATIO_DENOMINATOR, "RM: token staking ratio invalid");
        require(dividendRatio + ownerRatio + nftStakingRatio + arenaRatio + _ratio <= RATIO_DENOMINATOR, "RM: total ratio exceeds 100%");
        tokenStakingRatio = _ratio;
    }

    /**
     * @dev 批量设置所有资金分配比例
     * @param _dividendRatio 用户分红比例
     * @param _ownerRatio 合约所有者比例
     * @param _nftStakingRatio NFT质押矿池比例
     * @param _arenaRatio 竞技场奖励比例
     * @param _tokenStakingRatio 代币质押矿池比例
     */
    function setAllAllocationRatios(
        uint256 _dividendRatio,
        uint256 _ownerRatio,
        uint256 _nftStakingRatio,
        uint256 _arenaRatio,
        uint256 _tokenStakingRatio
    ) external onlyOwner {
        require(_dividendRatio >= 0 && _dividendRatio <= RATIO_DENOMINATOR, "RM: dividend ratio invalid");
        require(_ownerRatio >= 0 && _ownerRatio <= RATIO_DENOMINATOR, "RM: owner ratio invalid");
        require(_nftStakingRatio >= 0 && _nftStakingRatio <= RATIO_DENOMINATOR, "RM: NFT staking ratio invalid");
        require(_arenaRatio >= 0 && _arenaRatio <= RATIO_DENOMINATOR, "RM: arena ratio invalid");
        require(_tokenStakingRatio >= 0 && _tokenStakingRatio <= RATIO_DENOMINATOR, "RM: token staking ratio invalid");
        require(_dividendRatio + _ownerRatio + _nftStakingRatio + _arenaRatio + _tokenStakingRatio <= RATIO_DENOMINATOR, "RM: total ratio exceeds 100%");
        
        dividendRatio = _dividendRatio;
        ownerRatio = _ownerRatio;
        nftStakingRatio = _nftStakingRatio;
        arenaRatio = _arenaRatio;
        tokenStakingRatio = _tokenStakingRatio;
    }

    /**
     * @dev 设置操作冷却时间
     * @param _cooldown 新的冷却时间
     */
    function setOperationCooldown(uint256 _cooldown) external onlyOwner {
        operationCooldown = _cooldown;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    /**
     * @dev 设置NFT数据合约地址
     * @param _nftDataContract NFT数据合约地址
     */
    function setNFTDataContract(address _nftDataContract) external nonZeroAddress(_nftDataContract) {
        require(msg.sender == owner() || msg.sender == operator || msg.sender == nftContract || msg.sender == authorizer || authorizedNFTContracts[msg.sender], "RewardManager: Unauthorized");
        nftDataContract = _nftDataContract;
    }

    function setRewardToken(address _rewardToken) external onlyOwner nonZeroAddress(_rewardToken) {
        rewardToken = _rewardToken;
    }

    function setStakingContract(address _stakingContract) external onlyOwner nonZeroAddress(_stakingContract) {
        stakingContract = _stakingContract;
    }

    function setTokenStakingContract(address _tokenStakingContract) external onlyOwner nonZeroAddress(_tokenStakingContract) {
        tokenStakingContract = _tokenStakingContract;
    }

    function setArenaContract(address _arenaContract) external onlyOwner nonZeroAddress(_arenaContract) {
        arenaContract = _arenaContract;
    }

    function setSwapRouter(address _swapRouter) external onlyOwner nonZeroAddress(_swapRouter) {
        swapRouter = _swapRouter;
    }

    function setAutoSwapThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0, "RM: threshold must be > 0");
        autoSwapThreshold = _threshold;
    }

    /**
     * @dev 紧急暂停合�?
     */
    function emergencyPause() external onlyEmergencyOwner {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /**
     * @dev 紧急恢复合�?
     */
    function emergencyUnpause() external onlyEmergencyOwner {
        _unpause();
    }

    /**
     * @dev 运营者检查修饰器
     */
    modifier onlyOp() {
        bool isAuthorized = (msg.sender == operator) || (msg.sender == owner()) ||
                            (authorizedNFTContracts[msg.sender]) || (msg.sender == nftContract) || (msg.sender == authorizer);
        require(isAuthorized, "RM: not op");
        _;
    }

    /**
     * @dev 计算用户权重（非所有者）
     * 合约所有者的权重单独存储在ownerWeight中，初始值为1000
     * 普通用户的权重直接从 NFTData 合约计算，确保数据一致性
     * @param user 用户地址
     * @return 用户权重（所有者返回0，因为所有者权重单独处理）
     */
    function _calcUserWeight(address user) internal view returns (uint256) {
        if (user == owner()) return 0;
        if (nftDataContract == address(0)) return 0;
        
        return INFTDataInterface(nftDataContract).calcUserWeight(user);
    }

    /**
     * @dev 刷新用户权重缓存
     * @param user 用户地址
     */
    function refreshUserWeightCache(address user) external onlyOp {
        if (user == owner() || nftDataContract == address(0)) return;
        
        uint256 weight = INFTDataInterface(nftDataContract).calcUserWeight(user);
        cachedUserWeight[user] = weight;
        cachedWeightTimestamp[user] = block.timestamp;
    }

    /**
     * @dev 批量刷新用户权重缓存
     * @param users 用户地址列表
     */
    function batchRefreshUserWeightCache(address[] calldata users) external onlyOp {
        if (nftDataContract == address(0)) return;
        
        INFTDataInterface nftData = INFTDataInterface(nftDataContract);
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (user == owner()) continue;
            
            uint256 weight = nftData.calcUserWeight(user);
            cachedUserWeight[user] = weight;
            cachedWeightTimestamp[user] = block.timestamp;
        }
    }

    /**
     * @dev 设置权重缓存有效期
     * @param duration 缓存有效期（秒）
     */
    function setWeightCacheDuration(uint256 duration) external onlyOwner {
        weightCacheDuration = duration;
    }

    /**
     * @dev 清除用户权重缓存
     * @param user 用户地址
     */
    function clearUserWeightCache(address user) external onlyOp {
        delete cachedUserWeight[user];
        delete cachedWeightTimestamp[user];
    }

    /**
     * @dev 获取用户的实际权重（包括所有者）
     * @param user 用户地址
     * @return 用户权重
     */
    function getUserWeight(address user) external view returns (uint256) {
        if (user == owner()) {
            return ownerWeight;
        }
        return userWeight[user];
    }

    /**
     * @dev 更新用户权重
     * @param user 用户地址
     */
    function _updateUserWeight(address user) internal {
        if (user == owner()) return;

        uint256 oldWeight = userWeight[user];
        uint256 newWeight = _calcUserWeight(user);

        if (oldWeight != newWeight) {
            uint256 oldTotal = totalWeight;
            
            if (oldWeight > newWeight) {
                uint256 diff = oldWeight - newWeight;
                require(totalWeight >= diff, "RewardManager: Total weight would underflow");
                totalWeight -= diff;
            } else {
                require(totalWeight <= type(uint256).max - (newWeight - oldWeight), "RewardManager: Total weight would overflow");
                totalWeight += (newWeight - oldWeight);
            }
            
            userWeight[user] = newWeight;

            emit UserWeightUpdated(user, oldWeight, newWeight, block.timestamp);
            emit TotalWeightUpdated(oldTotal, totalWeight, block.timestamp);
        }
    }

    /**
     * @dev 获取用户总卡牌数
     * @param user 用户地址
     * @return cnt 总卡牌数
     */
    function _getTotalCardCount(address user) internal view returns (uint256 cnt) {
        if (nftDataContract == address(0)) return 0;
        return INFTDataInterface(nftDataContract).getUserTotalTokenCount(user);
    }

    /**
     * @dev 检查用户是否有资格分红
     * @param user 用户地址
     * @return 是否有资�?
     */
    function _hasEligibility(address user) internal view returns (bool) {
        if (user == owner()) return true;
        return _getTotalCardCount(user) > 0;
    }

    /**
     * @dev 管理符合资格用户链表
     * @param user 用户地址
     */
    function _manageEligibleList(address user) internal {
        bool eligible = _hasEligibility(user);

        if (eligible && !inEligibleList[user]) {
            if (eligibleUserTail == address(0)) {
                eligibleUserHead = user;
                eligibleUserTail = user;
            } else {
                eligibleUserNext[eligibleUserTail] = user;
                eligibleUserPrev[user] = eligibleUserTail;
                eligibleUserTail = user;
            }
            inEligibleList[user] = true;
        } else if (!eligible && inEligibleList[user]) {
            address prev = eligibleUserPrev[user];
            address next = eligibleUserNext[user];

            if (prev != address(0)) eligibleUserNext[prev] = next;
            if (next != address(0)) eligibleUserPrev[next] = prev;
            if (eligibleUserHead == user) eligibleUserHead = next;
            if (eligibleUserTail == user) eligibleUserTail = prev;

            delete eligibleUserPrev[user];
            delete eligibleUserNext[user];
            inEligibleList[user] = false;
        }
    }

    /**
     * @dev 更新用户卡牌信息
     * @param user 用户地址
     * @param t 生肖类型
     * @param cnt 卡牌数量
     * @return 是否成功
     */
    function updateCard(address user, NFTDataTypes.ZodiacType t, uint256 cnt) internal returns (bool) {
        _manageEligibleList(user);
        _updateUserWeight(user);
        emit CardUpdated(user, t, cnt, block.timestamp);
        return true;
    }

    /**
     * @dev 外部更新用户卡牌信息
     * @param user 用户地址
     * @param t 生肖类型
     * @param cnt 卡牌数量
     * @return 是否成功
     */
    function updateCardExternal(address user, NFTDataTypes.ZodiacType t, uint256 cnt) external onlyOp whenNotPaused returns (bool) {
        return updateCard(user, t, cnt);
    }

    function cardCount(address user, NFTDataTypes.ZodiacType zodiacType) external view returns (uint256) {
        if (nftDataContract == address(0)) return 0;
        return INFTDataInterface(nftDataContract).getUserTokenCount(user, zodiacType);
    }

    /**
     * @dev 原子性增加用户卡牌计数（解决时序问题）
     * 直接从NFTData获取最新计数，然后+1
     * @param user 用户地址
     * @param zodiacType 生肖类型
     * @return 是否成功
     */
    function addCardCount(address user, NFTDataTypes.ZodiacType zodiacType) external onlyOp whenNotPaused returns (bool) {
        if (nftDataContract == address(0)) return false;
        uint256 currentCount = INFTDataInterface(nftDataContract).getUserTokenCount(user, zodiacType);
        _updateUserWeight(user);
        emit CardUpdated(user, zodiacType, currentCount + 1, block.timestamp);
        return true;
    }

    /**
     * @dev 原子性减少用户卡牌计数（解决时序问题）
     * 直接从NFTData获取最新计数，然后-1（最小为0）
     * @param user 用户地址
     * @param zodiacType 生肖类型
     * @return 是否成功
     */
    function subCardCount(address user, NFTDataTypes.ZodiacType zodiacType) external onlyOp whenNotPaused returns (bool) {
        if (nftDataContract == address(0)) return false;
        uint256 currentCount = INFTDataInterface(nftDataContract).getUserTokenCount(user, zodiacType);
        uint256 newCount = currentCount > 0 ? currentCount - 1 : 0;
        _updateUserWeight(user);
        emit CardUpdated(user, zodiacType, newCount, block.timestamp);
        return true;
    }

    /**
     * @dev 添加持有者
     * @param user 用户地址
     * @return 是否成功
     */
    function addHolder(address user) external onlyOp whenNotPaused returns (bool) {
        if (!isHolder[user]) {
            isHolder[user] = true;
            if (holdersCount < type(uint256).max) {
                unchecked { holdersCount++; }
            } else {
                revert("Holders count overflow");
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
        }
        return true;
    }

    /**
     * @dev 移除持有�?
     * @param user 用户地址
     */
    function removeHolder(address user) external onlyOp whenNotPaused {
        if (isHolder[user]) {
            isHolder[user] = false;
            unchecked {
                holdersCount = holdersCount > 0 ? holdersCount - 1 : 0;
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
        }
    }

    /**
     * @dev 领取分红
     */
    function claimDividend() external nonReentrant whenNotPaused rateLimited(msg.sig) {
        address user = msg.sender;
        require(_hasEligibility(user), "RewardManager: User not eligible for dividend");

        uint256 totalW = totalWeight;
        require(totalW > 0 && dividendPool > 0, "RewardManager: No dividends available");

        uint256 userW = user == owner() ? ownerWeight : userWeight[user];
        require(userW > 0, "RewardManager: User weight is zero");

        uint256 contractBalance = address(this).balance;
        require(contractBalance >= dividendPool, "RewardManager: Insufficient contract balance");

        uint256 baseReward;
        uint256 carryOver;
        
        require(dividendPool <= type(uint256).max / userW, "RewardManager: Multiplication overflow risk");
        uint256 totalDiv = dividendPool * userW;
        baseReward = totalDiv / totalW;
        carryOver = totalDiv % totalW;
        
        // 简化的精度累积算法
        uint256 accumulated = precisionAcc[user] + carryOver;
        uint256 additionalReward = accumulated / totalW;
        carryOver = accumulated % totalW;
        
        require(baseReward <= dividendPool, "RewardManager: Base reward exceeds dividend pool");
        require(additionalReward <= dividendPool - baseReward, "RewardManager: Additional reward exceeds remaining pool");
        
        baseReward += additionalReward;
        
        require(baseReward > 0, "RewardManager: No reward amount to claim");
        require(baseReward <= dividendPool, "RewardManager: Total reward exceeds dividend pool");

        // 更新精度累积
        precisionAcc[user] = carryOver;
        precisionAccumulationCount[user] += 1;
        
        // 当累积次数达到阈值时，保留 10% 的精度值后重置
        // 这样可以减少分红损失，同时防止精度累积值过大
        if (precisionAccumulationCount[user] >= 1000) {
            // 保留 10% 的精度值，减少分红损失
            precisionAcc[user] = carryOver / 10;
            precisionAccumulationCount[user] = 0;
        }
        
        unchecked {
            dividendPool -= baseReward;
            claimedDividend[user] += baseReward;
            totalDistributed += baseReward;
        }
        emit DividendClaimed(user, baseReward, precisionAcc[user], block.timestamp);

        (bool success, ) = payable(user).call{value: baseReward}("");
        require(success, "RewardManager: Failed to transfer dividend");
    }
    
    function clearPrecisionAcc(address user) external onlyOwner {
        precisionAcc[user] = 0;
        precisionAccumulationCount[user] = 1;
    }
    
    function withdrawAllPrecisionAcc() external onlyOwner nonReentrant whenPaused {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0 && paused(), "RM: no balance or not paused");
        
        (bool success, ) = payable(owner()).call{value: contractBalance}("");
        require(success, "RewardManager: Failed to withdraw precision accumulator");
    }

    /**
     * @dev 接收ETH分红
     */
    receive() external payable {
        require(msg.value > 0, "RewardManager: Cannot deposit zero value");
        
        uint256 dividendAmount = (msg.value * DIVIDEND_RATIO) / 10000;
        uint256 ownerAmount = (msg.value * OWNER_RATIO) / 10000;
        uint256 nftStakingAmount = (msg.value * NFT_STAKING_RATIO) / 10000;
        uint256 arenaAmount = (msg.value * ARENA_RATIO) / 10000;
        uint256 tokenStakingAmount = (msg.value * TOKEN_STAKING_RATIO) / 10000;
        
        require(dividendPool + dividendAmount <= MAX_DIVIDEND_POOL, 
            "RewardManager: Dividend pool would exceed maximum capacity");
        require(ownerPool + ownerAmount <= MAX_DIVIDEND_POOL, 
            "RewardManager: Owner pool would exceed maximum capacity");
        require(nftStakingPool + nftStakingAmount <= MAX_DIVIDEND_POOL, 
            "RewardManager: NFT staking pool would exceed maximum capacity");
        require(arenaPool + arenaAmount <= MAX_DIVIDEND_POOL, 
            "RewardManager: Arena pool would exceed maximum capacity");
        require(tokenStakingPool + tokenStakingAmount <= MAX_DIVIDEND_POOL, 
            "RewardManager: Token staking pool would exceed maximum capacity");
        
        unchecked { 
            dividendPool += dividendAmount;
            ownerPool += ownerAmount;
            nftStakingPool += nftStakingAmount;
            arenaPool += arenaAmount;
            tokenStakingPool += tokenStakingAmount;
        }
        emit DividendDeposited(msg.value, msg.sender, block.timestamp);
        
        _processPools();
    }

    function _hasLiquidityPool() internal view returns (bool) {
        if (rewardToken == address(0) || pancakeFactory == address(0)) {
            return false;
        }
        address wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        address pair = IPancakeFactory(pancakeFactory).getPair(wbnb, rewardToken);
        return pair != address(0);
    }

    function _tryAutoSwapAndStake(uint256 amount, address targetContract) internal {
        if (!_hasLiquidityPool()) {
            return;
        }
        
        address[] memory path = new address[](2);
        path[0] = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        path[1] = rewardToken;
        
        uint256 deadline = block.timestamp + 300;
        
        try ISwapRouter(swapRouter).swapExactETHForTokens{value: amount}(
            0,
            path,
            address(this),
            deadline
        ) returns (uint256[] memory amounts) {
            uint256 tokenAmount = amounts[1];
            if (tokenAmount > 0) {
                IERC20(rewardToken).approve(targetContract, tokenAmount);
                IStakingContract(targetContract).depositToken(tokenAmount);
            }
        } catch {
        }
    }

    function _processPools() internal {
        if (nftStakingPool >= autoSwapThreshold && rewardToken != address(0) && 
            stakingContract != address(0) && swapRouter != address(0)) {
            uint256 amount = nftStakingPool;
            nftStakingPool = 0;
            _tryAutoSwapAndStake(amount, stakingContract);
        }
        
        if (arenaPool >= autoSwapThreshold && arenaContract != address(0)) {
            uint256 amount = arenaPool;
            arenaPool = 0;
            (bool success, ) = payable(arenaContract).call{value: amount}("");
            if (!success) {
                arenaPool += amount;
            }
        }
        
        if (tokenStakingPool >= autoSwapThreshold && tokenStakingContract != address(0)) {
            uint256 amount = tokenStakingPool;
            tokenStakingPool = 0;
            (bool success, ) = payable(tokenStakingContract).call{value: amount}("");
            if (!success) {
                tokenStakingPool += amount;
            }
        }
    }

    function manualProcessPools() external onlyOwner nonReentrant whenNotPaused {
        _processPools();
    }

    /**
     * @dev 提取额外资金（超出分红池的余额）
     */
    function withdrawExtraFunds() external onlyOwner nonReentrant whenNotPaused {
        uint256 contractBalance = address(this).balance;
        uint256 totalPools = dividendPool + ownerPool + nftStakingPool + arenaPool + tokenStakingPool;
        uint256 extraFunds = contractBalance - totalPools;
        require(extraFunds > 0, "RM: no extra funds to withdraw");
        require(contractBalance >= totalPools, "RM: insufficient balance for pools");

        emit ExtraFundsWithdrawn(owner(), extraFunds, block.timestamp);
        (bool success, ) = payable(owner()).call{value: extraFunds}("");
        require(success, "RM: extra funds transfer failed");
    }

    /**
     * @dev 提取所有者分红
     */
    function withdrawOwnerDividend() external onlyOwner nonReentrant whenNotPaused {
        uint256 amount = ownerPool;
        require(amount > 0, "RM: no owner dividend to withdraw");
        
        uint256 contractBalance = address(this).balance;
        require(contractBalance >= amount, "RM: insufficient contract balance");
        
        ownerPool = 0;
        
        emit ExtraFundsWithdrawn(owner(), amount, block.timestamp);
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "RM: owner dividend transfer failed");
    }

    /**
     * @dev 提取所有资金（仅在紧急情况下使用，需要暂停合约）
     */
    function withdrawAllFunds() external onlyOwner nonReentrant whenPaused {
        uint256 bal = address(this).balance;
        require(bal > 0, "RM: no balance");
        require(paused(), "RM: contract must be paused");

        emit FullFundsWithdrawn(owner(), bal, block.timestamp);
        (bool success, ) = payable(owner()).call{value: bal}("");
        require(success, "RM: withdraw fail");
    }

    /**
     * @dev 计算用户可领取的分红
     * @param user 用户地址
     * @return base 基本分红金额
     * @return precRemain 剩余精度�?
     */
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        uint256 totalW = totalWeight;
        if (totalW == 0 || dividendPool == 0) return (0, 0);

        if (user == owner()) {
            if (ownerWeight == 0) return (0, 0);
            uint256 ownerTotalDiv = dividendPool * ownerWeight;
            uint256 base = ownerTotalDiv / totalW;
            uint256 carryOver = ownerTotalDiv % totalW;
            uint256 accumulated = precisionAcc[user] + carryOver;
            return (base + (accumulated / totalW), accumulated % totalW);
        }

        if (!_hasEligibility(user) || userWeight[user] == 0) return (0, 0);

        uint256 userW = userWeight[user];
        uint256 userTotalDiv = dividendPool * userW;
        uint256 base = userTotalDiv / totalW;
        uint256 carryOver = userTotalDiv % totalW;
        uint256 accumulated = precisionAcc[user] + carryOver;

        return (base + (accumulated / totalW), accumulated % totalW);
    }

    /**
     * @dev 刷新单个用户权重
     * @param user 用户地址
     */
    function refreshUserWeight(address user) external onlyOwner {
        _updateUserWeight(user);
    }

    /**
     * @dev 刷新总权�?
     */
    function refreshTotalWeight() external onlyOwner {
        emit TotalWeightUpdated(totalWeight, totalWeight, block.timestamp);
    }
}

