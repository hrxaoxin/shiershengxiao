// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DividendManager
 * @dev 分红管理合约，管理NFT持有者的分红分发
 *
 * 核心职责：
 * 1. 维护每个地址的分红权重（基于持有 NFT 的等级和稀有度）
 * 2. 接收来自游戏生态的手续费（交易、战斗、繁殖、铸造）作为分红资金
 * 3. 允许用户按比例领取累计分红（代币和 BNB 两种分红池）
 *
 * 分红资金来源：
 * - NFTTrading.sol：交易手续费（3%）进入分红池
 * - Battle.sol：战斗入场费的部分进入分红池
 * - Breeding.sol：繁殖费用的部分进入分红池
 * - TokenBurner.sol：铸造费用的部分进入分红池
 * - 其他游戏收益（如限时活动、付费宝箱）
 *
 * 权重体系（决定每位用户在分红池中的份额）：
 * 普通 NFT（水/风/火属性，zodiacType < 72）：
 *   - 1级 权重 1
 *   - 2级 权重 2
 *   - 3级 权重 6
 *   - 4级 权重 18
 *   - 5级 权重 66
 * 稀有 NFT（暗/光属性，zodiacType >= 72）：
 *   - 1级 权重 10
 *   - 2级 权重 12
 *   - 3级 权重 16
 *   - 4级 权重 28
 *   - 5级 权重 76
 * 注意：用户总权重 = Σ（其每张 NFT 的权重）；质押中的 NFT 同样计入权重
 *
 * 分红计算公式：
 * 用户应得分红 = 分红池总余额 × (用户权重 / 全网总权重)
 * - 通过 WeightManager 获取用户实时权重
 * - 用户领取时按比例从池中扣除对应金额
 * - 支持按周期（每日/每周）结算，也支持累计随时领取
 *
 * 两种分红池：
 * 1. 代币分红池（tokenDividendPool）：接收代币形式的手续费
 * 2. BNB 分红池（bnbDividendPool）：接收 BNB 形式的手续费
 * 用户可分别调用 claimTokenDividend() / claimBnbDividend() 领取
 *
 * 分红事件与提醒：
 * - DividendClaimed(user, amount)：用户领取分红时触发
 * - DividendClaimWarning(user, daysSinceLastClaim)：当用户超过 30 天未领取时触发
 *   （供前端提醒用户及时领取分红）
 *
 * 权重更新流程：
 * - NFTMint 铸造 → addWeight(user, type)
 * - NFTTrading 交易 → removeWeight(oldUser) + addWeight(newUser)
 * - NFTUpdate 升级 → 先 remove 旧等级权重，再 add 新等级权重
 * - Staking 质押 → 权重保留（仍计入用户分红）
 * - Breeding 繁殖 → 新 NFT 给用户，增加权重
 *
 * 安全限制：
 * - ReentrancyGuard：领取分红时外部转账需防止重入
 * - Pausable：可暂停分红领取（维护/攻击时）
 * - 最小领取金额：防止微小金额领取浪费 Gas
 * - 地址校验：零地址校验，防止资金误转入黑洞
 *
 * 典型分红流程：
 * 1. 游戏中产生手续费 → NFTTrading/Battle/Breeding 转账给 DividendManager
 * 2. DividendManager 将资金计入 tokenDividendPool / bnbDividendPool
 * 3. 用户在前端点击"领取分红"按钮
 * 4. 前端调用 claimTokenDividend() 或 claimBnbDividend()
 * 5. 合约按用户当前权重比例计算分红，转账给用户
 * 6. 事件 DividendClaimed 被触发，前端展示领取成功
 *
 * 升级与治理：
 * - UUPS 可升级：未来可调整权重表 / 分红比例 / 增加新资金来源
 * - 由 owner 可调整权重表和分红分配参数
 */
contract DividendManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    bool public paused;
    string public pauseReason;

    event Paused(address indexed account, string reason);
    event Unpaused(address indexed account);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    modifier whenNotPaused() {
        require(!paused, "DividendManager: Paused");
        _;
    }

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }
    /**
     * @dev 分红领取事件
     */
    event DividendClaimed(address indexed user, uint256 amount);

    /**
     * @dev 分红领取警告事件（用户超过30天未领取）
     * @param user 用户地址
     * @param daysSinceLastClaim 距离上次领取的天数
     */
    event DividendClaimWarning(address indexed user, uint256 daysSinceLastClaim);

    /**
     * @dev 分红池增加事件
     */
    event DividendPoolAdded(uint256 amount, uint256 totalDividend, uint256 perWeightDividendIncrement);

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 用户权重映射
     * user => weight
     */
    mapping(address => uint256) public userWeights;

    /**
     * @dev 最大快照数量限制，防止无限增长
     */
    uint256 public constant MAX_SNAPSHOTS = 100;
    
    /**
     * @dev 分红领取警告阈值（秒）- 用户超过此时间未领取分红将触发警告
     */
    uint256 public constant DIVIDEND_CLAIM_WARNING_THRESHOLD = 30 days;
    
    /**
     * @dev 用户上次领取分红时间
     */
    mapping(address => uint256) public lastClaimTime;

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "DividendManager: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "DividendManager: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(
            msg.sender == auth.getNFTUpdate() || 
            msg.sender == auth.getRewardManager() || 
            msg.sender == auth.getWeightManager(), 
            "DividendManager: Not authorized"
        );
        _;
    }

    /**
     * @dev 用户待领取分红映射
     * user => pendingDividend
     */
    mapping(address => uint256) public pendingDividends;

    /**
     * @dev 总权重
     */
    uint256 public totalWeight;

    /**
     * @dev 分红池余额
     */
    uint256 public dividendPoolBalance;

    

    /**
     * @dev 最后更新快照时间
     */
    uint256 public lastSnapshotTime;

    /**
     * @dev 分红快照结构
     */
    struct DividendSnapshot {
        uint256 totalWeight;
        uint256 totalDividend;
        uint256 perWeightDividend;
        uint256 timestamp;
    }

    /**
     * @dev 历史快照 - 使用环形缓冲区限制数量
     */
    DividendSnapshot[] public snapshots;
    
    /**
     * @dev 快照数组起始索引（用于环形缓冲区）
     */
    uint256 public snapshotStartIndex;

    /**
     * @dev 上次同步时的合约代币余额（用于自动检测新增资金）
     */
    uint256 public lastSyncedBalance;
    
    /**
     * @dev 自动同步的最小时间间隔（6小时）
     */
    uint256 public constant AUTO_SYNC_INTERVAL = 6 hours;
    
    /**
     * @dev 最后一次自动同步的时间
     */
    uint256 public lastAutoSyncTime;

    /**
     * @dev 添加到分红池（手动指定金额）
     */
    function addDividendPool(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "DividendManager: Invalid amount");
        _addToDividendPool(amount);
        address tokenContract = IAuthorizer(authorizer).getToken();
        if (tokenContract != address(0)) {
            lastSyncedBalance = IERC20(tokenContract).balanceOf(address(this));
        }
    }

    /**
     * @dev 同步分红池余额（自动检测合约中新增的代币）
     */
    function syncDividendPool() external onlyOwnerOrAuthorizer {
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        uint256 currentBalance = token.balanceOf(address(this));

        if (currentBalance > lastSyncedBalance) {
            uint256 newFunds = currentBalance - lastSyncedBalance;
            _addToDividendPool(newFunds);
        }

        lastSyncedBalance = currentBalance;
        lastAutoSyncTime = block.timestamp;
    }
    
    /**
     * @dev 自动同步分红池（在用户操作时调用）
     */
    function _autoSyncDividendPool() internal {
        address tokenContract = IAuthorizer(authorizer).getToken();
        if (tokenContract == address(0)) return;
        
        if (block.timestamp >= lastAutoSyncTime + AUTO_SYNC_INTERVAL) {
            IERC20 token = IERC20(tokenContract);
            uint256 currentBalance = token.balanceOf(address(this));

            if (currentBalance > lastSyncedBalance) {
                uint256 newFunds = currentBalance - lastSyncedBalance;
                _addToDividendPool(newFunds);
            }

            lastSyncedBalance = currentBalance;
            lastAutoSyncTime = block.timestamp;
        }
    }

    /**
     * @dev 内部函数：将金额添加到分红池并创建快照
     */
    /**
     * @dev 累计的每权重分红额
     */
    uint256 public cumulativePerWeightDividend;
    
    /**
     * @dev 用户上次累计分红快照
     */
    mapping(address => uint256) public userCumulativeSnapshots;

    function _addToDividendPool(uint256 amount) internal {
        // 修复：使用 SafeMath 风格的检查防止溢出
        uint256 newBalance = dividendPoolBalance + amount;
        require(newBalance >= dividendPoolBalance, "DividendManager: Overflow");
        dividendPoolBalance = newBalance;

        uint256 perWeightDividendIncrement = 0;
        if (totalWeight > 0) {
            // 修复：在乘法之前检查 amount * 1e18 是否会溢出
            if (amount > 0) {
                require(type(uint256).max / amount >= 1e18, "DividendManager: Amount scaling overflow");
            }
            perWeightDividendIncrement = (amount * 1e18) / totalWeight;
            uint256 newCumulative = cumulativePerWeightDividend + perWeightDividendIncrement;
            require(newCumulative >= cumulativePerWeightDividend, "DividendManager: Cumulative overflow");
            cumulativePerWeightDividend = newCumulative;
        }

        DividendSnapshot memory newSnapshot = DividendSnapshot({
            totalWeight: totalWeight,
            totalDividend: dividendPoolBalance,
            perWeightDividend: perWeightDividendIncrement,
            timestamp: block.timestamp
        });

        if (snapshots.length < MAX_SNAPSHOTS) {
            snapshots.push(newSnapshot);
        } else {
            require(snapshotStartIndex < MAX_SNAPSHOTS, "DividendManager: Invalid snapshot index");
            snapshots[snapshotStartIndex] = newSnapshot;
            snapshotStartIndex = (snapshotStartIndex + 1) % MAX_SNAPSHOTS;
        }

        emit DividendPoolAdded(amount, dividendPoolBalance, perWeightDividendIncrement);
    }

    /**
     * @dev 获取当前有效快照数量
     */
    function getSnapshotCount() external view returns (uint256) {
        return snapshots.length;
    }

    /**
     * @dev 获取指定逻辑索引的快照（处理环形缓冲区）
     * 逻辑索引 0 为最旧的快照
     */
    function getSnapshot(uint256 index) external view returns (uint256, uint256, uint256, uint256) {
        require(index < snapshots.length, "DividendManager: Invalid snapshot index");
        uint256 actualIndex = _getActualIndex(index);
        DividendSnapshot memory snapshot = snapshots[actualIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend, snapshot.timestamp);
    }
    
    /**
     * @dev 内部函数：将逻辑索引转换为环形缓冲区实际索引
     */
    function _getActualIndex(uint256 logicalIndex) internal view returns (uint256) {
        return (snapshotStartIndex + logicalIndex) % snapshots.length;
    }

    /**
     * @dev 领取分红
     */
    function claim() external nonReentrant whenNotPaused returns (uint256) {
        _autoSyncDividendPool();

        uint256 userWeight = userWeights[msg.sender];

        if (lastClaimTime[msg.sender] > 0 &&
            block.timestamp - lastClaimTime[msg.sender] > DIVIDEND_CLAIM_WARNING_THRESHOLD) {
            emit DividendClaimWarning(msg.sender, block.timestamp - lastClaimTime[msg.sender]);
        }

        uint256 newDividend = 0;
        if (userWeight > 0) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[msg.sender];
            newDividend = (userWeight * cumulativeDiff) / 1e18;
        }

        uint256 totalDividend = pendingDividends[msg.sender] + newDividend;

        require(totalDividend > 0, "DividendManager: No dividend");

        pendingDividends[msg.sender] = 0;
        if (userWeight > 0) {
            userCumulativeSnapshots[msg.sender] = cumulativePerWeightDividend;
        }
        lastClaimTime[msg.sender] = block.timestamp;

        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= totalDividend, "DividendManager: Insufficient contract balance");
        token.safeTransfer(msg.sender, totalDividend);

        emit DividendClaimed(msg.sender, totalDividend);
        return totalDividend;
    }

    /**
     * @dev 领取分红并转账（供前端直接调用，委托给 claim() 以消除代码重复）
     */
    function claimDividend() external nonReentrant whenNotPaused {
        this.claim();
    }

    /**
     * @dev 计算用户可领取分红（别名，兼容前端调用）
     * @param user 用户地址
     * @return 可领取分红金额和用户权重
     */
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        uint256 claimable = this.getClaimableDividend(user);
        return (claimable, userWeights[user]);
    }

    /**
     * @dev 接收BNB（用于分红池充值）
     */
    receive() external payable {}

    /**
     * @dev 获取可领取分红
     */
    function getClaimableDividend(address user) external view returns (uint256) {
        uint256 userWeight = userWeights[user];
        if (userWeight == 0) return pendingDividends[user];
        
        uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
        uint256 newDividend = userWeight * cumulativeDiff / 1e18;
        return pendingDividends[user] + newDividend;
    }

    /**
     * @dev 获取用户权重
     */
    function getUserWeight(address user) external view returns (uint256) {
        return userWeights[user];
    }

    /**
     * @dev 获取总权重
     */
    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    /** @dev 最大单用户权重限制 */
    uint256 public constant MAX_USER_WEIGHT = 100000;
    
    /**
     * @dev 设置用户权重（直接设置）
     */
    function setUserWeight(address user, uint256 weight) external onlyOwnerOrAuthorizer {
        require(weight <= MAX_USER_WEIGHT, "DividendManager: Weight exceeds maximum");
        
        // 先结算用户当前未领取的分红
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            // 修复：移除 unchecked 块，使用显式溢出检查
            uint256 weightedProduct = userWeights[user] * cumulativeDiff;
            require(weightedProduct / userWeights[user] == cumulativeDiff, "DividendManager: Pending calculation overflow");
            uint256 pending = weightedProduct / 1e18;
            pendingDividends[user] += pending;
        }
        
        totalWeight = totalWeight - userWeights[user] + weight;
        userWeights[user] = weight;
        userCumulativeSnapshots[user] = cumulativePerWeightDividend;
    }

    /**
     * @dev 更新用户权重（支持等级和元素计算）
     * @param user 用户地址
     * @param level NFT等级
     * @param isAdd 是否增加权重（true=增加，false=减少）
     * @param element 元素类型（0-4对应水风火暗光）
     */
    /** @dev 最小权重更新间隔（秒）- 防止频繁操作，默认0秒（不限制）
     * 可由 owner 调整以控制更新频率
     */
    uint256 public minWeightUpdateInterval = 0;
    
    /** @dev 用户上次权重更新时间 */
    mapping(address => uint256) public lastWeightUpdateTime;

    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external onlyOwnerOrAuthorizer {
        require(user != address(0), "DividendManager: Zero user address");
        uint256 weight = _calculateWeight(level, element);

        // 检查最小更新间隔（仅当设置了大于0的值时才检查）
        if (minWeightUpdateInterval > 0) {
            require(block.timestamp >= lastWeightUpdateTime[user] + minWeightUpdateInterval, 
                "DividendManager: Weight update too frequent");
        }
        
        // 先结算用户当前未领取的分红
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            // 修复：移除 unchecked 块，使用显式溢出检查
            uint256 weightedProduct = userWeights[user] * cumulativeDiff;
            require(weightedProduct / userWeights[user] == cumulativeDiff, "DividendManager: Weight calculation overflow");
            uint256 pending = weightedProduct / 1e18;
            pendingDividends[user] += pending;
        }

        if (isAdd) {
            // 修复：在加法之前检查不超过 MAX_USER_WEIGHT，防止单用户累积过高权重
            uint256 newUserWeight = userWeights[user] + weight;
            require(newUserWeight >= userWeights[user], "DividendManager: Weight overflow");
            require(newUserWeight <= MAX_USER_WEIGHT, "DividendManager: New user weight exceeds maximum");
            uint256 newTotalWeight = totalWeight + weight;
            require(newTotalWeight >= totalWeight, "DividendManager: Total weight overflow");
            totalWeight = newTotalWeight;
            userWeights[user] = newUserWeight;
        } else {
            require(userWeights[user] >= weight, "DividendManager: Insufficient weight");
            require(totalWeight >= weight, "DividendManager: Total weight underflow");
            totalWeight -= weight;
            userWeights[user] -= weight;
        }
        
        userCumulativeSnapshots[user] = cumulativePerWeightDividend;
        lastWeightUpdateTime[user] = block.timestamp;
    }

    /**
     * @dev 设置最小权重更新间隔
     * @param seconds_ 间隔秒数
     */
    function setMinWeightUpdateInterval(uint256 seconds_) external onlyOwner {
        minWeightUpdateInterval = seconds_;
    }

    /**
     * @dev 同步用户权重（由NFTTrading、Staking等合约调用）
     * 仅授权合约可调用，防止恶意调用影响分红计算
     * @param user 用户地址
     */
    function syncUserWeight(address user) external onlyOwnerOrAuthorizer {
        require(user != address(0), "DividendManager: Zero user address");
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        if (nftDataContract == address(0)) return;
        
        INFTDataInterface nftData = INFTDataInterface(nftDataContract);
        uint256 newWeight = nftData.calcUserWeight(user);
        
        // 先结算用户当前未领取的分红
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            uint256 pending = userWeights[user] * cumulativeDiff / 1e18;
            pendingDividends[user] += pending;
        }
        
        // 更新权重
        totalWeight = totalWeight - userWeights[user] + newWeight;
        userWeights[user] = newWeight;
        userCumulativeSnapshots[user] = cumulativePerWeightDividend;
        lastWeightUpdateTime[user] = block.timestamp;
        
        emit WeightUpdated(user, newWeight);
    }

    uint256 public constant MAX_NFT_LEVEL = 5;

    /**
     * @dev 根据等级和元素计算权重
     * @param level NFT等级 (1-5)
     * @param element 元素类型 (0-4)
     * @return uint256 计算后的权重
     */
    function _calculateWeight(uint256 level, uint8 element) internal pure returns (uint256) {
        bool isRare = (element == 3 || element == 4);
        
        if (level == 0) return 0;
        
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        } else {
            uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        }
    }

    /**
     * @dev 公开获取NFT权重（根据等级和是否稀有）
     * @param level NFT等级
     * @param isRare 是否稀有
     * @return uint256 权重值
     */
    function getNFTWeight(uint256 level, bool isRare) external pure returns (uint256) {
        if (level == 0) return 0;
        
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        } else {
            uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
            if (level <= MAX_NFT_LEVEL) {
                return weights[level - 1];
            }
            return weights[MAX_NFT_LEVEL - 1];
        }
    }

    /**
     * @dev 获取所有权重配置
     * @return normalWeights 普通NFT权重数组 [level1, level2, level3, level4, level5]
     * @return rareWeights 稀有NFT权重数组 [level1, level2, level3, level4, level5]
     */
    function getWeightConfig() external pure returns (uint256[5] memory normalWeights, uint256[5] memory rareWeights) {
        normalWeights = [uint256(1), 2, 6, 18, 66];
        rareWeights = [uint256(10), 12, 16, 28, 76];
    }

    /**
     * @dev 批量更新用户权重（原子性操作）
     */
    function updateUserWeightsBatch(
        address[] calldata users,
        uint256[] calldata weights
    ) external onlyOwner {
        require(users.length == weights.length, "DividendManager: Length mismatch");
        
        uint256 usersLength = users.length;
        uint256 totalWeightChange = 0;
        
        for (uint256 i = 0; i < usersLength; i++) {
            address user = users[i];
            uint256 newWeight = weights[i];
            uint256 oldWeight = userWeights[user];
            
            if (oldWeight > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
                uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
                pendingDividends[user] += oldWeight * cumulativeDiff / 1e18;
            }
            
            totalWeightChange = totalWeightChange - oldWeight + newWeight;
            userWeights[user] = newWeight;
            userCumulativeSnapshots[user] = cumulativePerWeightDividend;
        }
        
        totalWeight = totalWeight + totalWeightChange;
    }

    /**
     * @dev 计算每权重分红
     * @param amount 分红池总金额
     * @return 每权重的分红金额
     */
    function calculateDividend(uint256 amount) external view returns (uint256) {
        if (totalWeight == 0) return 0;
        return (amount * 1e18) / totalWeight / 1e18;
    }

    /**
     * @dev 获取最新快照（正确处理环形缓冲区）
     */
    function getCurrentSnapshot() external view returns (uint256, uint256, uint256) {
        if (snapshots.length == 0) {
            return (0, 0, 0);
        }
        uint256 latestIndex = snapshots.length < MAX_SNAPSHOTS 
            ? snapshots.length - 1 
            : (snapshotStartIndex + MAX_SNAPSHOTS - 1) % MAX_SNAPSHOTS;
        DividendSnapshot memory snapshot = snapshots[latestIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend);
    }

    /**
     * @dev 获取快照历史长度
     */
    function getSnapshotHistoryLength() external view returns (uint256) {
        return snapshots.length;
    }

    /**
     * @dev 获取指定范围的快照（正确处理环形缓冲区）
     * @param startIndex 起始逻辑索引
     * @param count 获取数量
     */
    function getSnapshotHistory(uint256 startIndex, uint256 count) external view returns (DividendSnapshot[] memory) {
        uint256 totalCount = snapshots.length;
        require(startIndex < totalCount, "DividendManager: Invalid start index");
        require(count > 0, "DividendManager: Invalid count");

        uint256 endIndex = startIndex + count;
        if (endIndex > totalCount) {
            endIndex = totalCount;
        }

        DividendSnapshot[] memory result = new DividendSnapshot[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 actualIndex = _getActualIndex(i);
            result[i - startIndex] = snapshots[actualIndex];
        }

        return result;
    }

    /**
     * @dev 获取最新N条快照记录（正确处理环形缓冲区）
     * @param count 记录数量
     */
    function getRecentSnapshots(uint256 count) external view returns (DividendSnapshot[] memory) {
        if (snapshots.length == 0) {
            return new DividendSnapshot[](0);
        }

        uint256 totalCount = snapshots.length;
        if (count > totalCount) {
            count = totalCount;
        }

        DividendSnapshot[] memory result = new DividendSnapshot[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 logicalIndex = totalCount - count + i;
            uint256 actualIndex = (snapshotStartIndex + logicalIndex) % totalCount;
            result[i] = snapshots[actualIndex];
        }

        return result;
    }

    /**
     * @dev 获取分红池统计
     * @return currentPool 当前池余额
     * @return totalWeight 总权重
     * @return snapshotCount 快照数量
     * @return lastSnapshotTime 最后快照时间
     */
    function getDividendPoolStats() external view returns (
        uint256 currentPool,
        uint256 totalWeight,
        uint256 snapshotCount,
        uint256 lastSnapshotTime
    ) {
        address tokenContract = IAuthorizer(authorizer).getToken();
        if (tokenContract != address(0)) {
            currentPool = IERC20(tokenContract).balanceOf(address(this));
        }
        totalWeight = this.totalWeight();
        snapshotCount = snapshots.length;
        if (snapshots.length > 0) {
            uint256 latestIndex = snapshots.length < MAX_SNAPSHOTS 
                ? snapshots.length - 1 
                : (snapshotStartIndex + MAX_SNAPSHOTS - 1) % MAX_SNAPSHOTS;
            lastSnapshotTime = snapshots[latestIndex].timestamp;
        }
    }

    /** @dev 紧急提现时间锁（秒），默认24小时 */
    uint256 public emergencyWithdrawTimelock = 86400;
    
    /** @dev 紧急提现请求时间 */
    uint256 public emergencyWithdrawRequestedAt;
    
    /** @dev 是否已请求紧急提现 */
    bool public emergencyWithdrawRequested;

    function requestEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawRequested = true;
        emergencyWithdrawRequestedAt = block.timestamp;
        emit EmergencyWithdrawRequested(msg.sender, block.timestamp);
    }
    
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(emergencyWithdrawRequested, "DividendManager: Withdrawal not requested");
        require(block.timestamp >= emergencyWithdrawRequestedAt + emergencyWithdrawTimelock, 
            "DividendManager: Timelock not expired");
        require(amount > 0, "DividendManager: Amount must be > 0");
        require(amount <= address(this).balance, "DividendManager: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "DividendManager: BNB transfer failed");
        emergencyWithdrawRequested = false;
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(emergencyWithdrawRequested, "DividendManager: Withdrawal not requested");
        require(block.timestamp >= emergencyWithdrawRequestedAt + emergencyWithdrawTimelock, 
            "DividendManager: Timelock not expired");
        require(amount > 0, "DividendManager: Amount must be > 0");
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "DividendManager: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emergencyWithdrawRequested = false;
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }
    
    event EmergencyWithdrawRequested(address indexed operator, uint256 timestamp);

}