// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RewardManager
 * @dev 奖励管理器合约，负责管理NFT持有者的分红和权重计算
 * 支持添加/移除持有者、计算用户权重、分配分红等功能
 * 基于OpenZeppelin UUPS可升级合约实现
 */

import "./NFTData.sol";

// 全部统一适配 OpenZeppelin Upgradeable v4.9
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @dev IERC2981接口：NFT版税标准接口
 */
interface IERC2981 {
    /**
     * @dev 获取NFT版税信息
     * @param tokenId NFT ID
     * @param salePrice 销售价格
     * @return receiver 版税接收地址
     * @return royaltyAmount 版税金额
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

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
    /** @dev 最低所有者权重 */
    uint256 public constant MIN_OWNER_WEIGHT = 1000;
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

    /** @dev 授权的NFT合约映射 */
    mapping(address => bool) public authorizedNFTContracts;
    /** @dev 用户卡牌数量映射（用户地址 => 生肖类型 => 数量） */
    mapping(address => mapping(NFTDataTypes.ZodiacType => uint256)) public cardCount;
    /** @dev 是否为持有者映射 */
    mapping(address => bool) public isHolder;
    /** @dev 用户已领取分红映射 */
    mapping(address => uint256) public claimedDividend;
    /** @dev 用户精度累积映射 */
    mapping(address => uint256) public precisionAcc;
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
     * @dev 初始化合�?
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
        address _authorizer
    ) external initializer nonZeroAddress(initialOwner) nonZeroAddress(_operator) nonZeroAddress(_nftContract) {
        __Ownable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        royaltyWallet = _royaltyWallet == address(0) ? 0x55d398326f99059fF775485246999027B3197955 : _royaltyWallet;
        operator = _operator;
        nftContract = _nftContract;
        authorizer = _authorizer;
        ownerWeight = MIN_OWNER_WEIGHT;
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
     * @dev 获取NFT版税信息（ERC2981接口实现�?
     * @param tokenId NFT ID
     * @param salePrice 销售价�?
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
        require(oldNFTContract != _newNFTContract, "RM: same nft contract");
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
        require(_w >= MIN_OWNER_WEIGHT, "RM: w low");

        uint256 oldOwnerWeight = ownerWeight;
        totalWeight = totalWeight - oldOwnerWeight + _w;
        ownerWeight = _w;

        emit TotalWeightUpdated(totalWeight + oldOwnerWeight - _w, totalWeight, block.timestamp);
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
     * @param _f 新版税比�?
     */
    function setRoyaltyFee(uint256 _f) external onlyOwner {
        require(_f >= 0 && _f <= MAX_ROYALTY_FEE, "RM: fee invalid");
        royaltyFee = _f;
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
     * @dev 计算用户权重
     * @param user 用户地址
     * @return 用户权重
     */
    function _calcUserWeight(address user) internal view returns (uint256) {
        if (user == owner()) return 0;
        if (nftContract == address(0)) return 0;
        return INFTMintWeight(nftContract).calcUserWeight(user);
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
            totalWeight = totalWeight - oldWeight + newWeight;
            userWeight[user] = newWeight;

            emit UserWeightUpdated(user, oldWeight, newWeight, block.timestamp);
            emit TotalWeightUpdated(oldTotal, totalWeight, block.timestamp);
        }
    }

    /**
     * @dev 获取用户总卡牌数�?
     * @param user 用户地址
     * @return 总卡牌数�?
     */
    function _getTotalCardCount(address user) internal view returns (uint256 cnt) {
        for (uint i = 0; i < 120; i++) {
            cnt += cardCount[user][NFTDataTypes.ZodiacType(i)];
        }
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
        cardCount[user][t] = cnt;
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

    /**
     * @dev 添加持有�?
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
        require(_hasEligibility(user), "RM: no elig");

        uint256 totalW = totalWeight;
        require(totalW > 0 && dividendPool > 0, "RM: no div");

        uint256 userW = user == owner() ? ownerWeight : userWeight[user];
        require(userW > 0, "RM: no weight");

        require(dividendPool <= type(uint256).max / userW, "RM: overflow");
        uint256 totalDiv = dividendPool * userW;
        uint256 base = totalDiv / totalW;
        uint256 precRemain = totalDiv % totalW;

        uint256 acc = precisionAcc[user] + precRemain;
        uint256 precBonus = acc / totalW;
        uint256 finalAmt = base + precBonus;
        require(finalAmt > 0, "RM: no amt");
        require(finalAmt <= address(this).balance, "RM: insufficient balance");

        precisionAcc[user] = acc % totalW;
        unchecked {
            dividendPool -= finalAmt;
            claimedDividend[user] += finalAmt;
            totalDistributed += finalAmt;
        }
        emit DividendClaimed(user, finalAmt, precisionAcc[user], block.timestamp);

        (bool success, ) = payable(user).call{value: finalAmt}("");
        require(success, "RM: transfer fail");
    }

    /**
     * @dev 接收ETH分红
     */
    receive() external payable {
        require(msg.value > 0, "RM: zero");
        unchecked { dividendPool += msg.value; }
        emit DividendDeposited(msg.value, msg.sender, block.timestamp);
    }

    /**
     * @dev 提取额外资金（超出分红池的余额）
     */
    function withdrawExtraFunds() external onlyOwner nonReentrant whenNotPaused {
        uint256 contractBalance = address(this).balance;
        uint256 extraFunds = contractBalance - dividendPool;
        require(extraFunds > 0, "RM: no extra funds to withdraw");
        require(contractBalance >= dividendPool, "RM: insufficient balance for dividend pool");

        emit ExtraFundsWithdrawn(owner(), extraFunds, block.timestamp);
        (bool success, ) = payable(owner()).call{value: extraFunds}("");
        require(success, "RM: extra funds transfer failed");
    }

    /**
     * @dev 提取所有资�?
     */
    function withdrawAllFunds() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "RM: no balance");

        unchecked {
            dividendPool = 0;
        }
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
            return (ownerTotalDiv / totalW, ownerTotalDiv % totalW);
        }

        if (!_hasEligibility(user) || userWeight[user] == 0) return (0, 0);

        uint256 userW = userWeight[user];
        uint256 userTotalDiv = dividendPool * userW;
        uint256 base = userTotalDiv / totalW;
        uint256 acc = precisionAcc[user] + (userTotalDiv % totalW);

        return (base + (acc / totalW), acc % totalW);
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

