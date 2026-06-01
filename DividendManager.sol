// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

/**
 * @title DividendManager
 * @dev 分红管理合约，管理NFT持有者的分红分发
 *
 * 分红来源：
 * 1. 交易手续费（3%进入分红池）
 * 2. 战斗胜利奖励
 * 3. 其他游戏收益
 *
 * 分红计算：
 * - 用户分红 = 总分红 × (用户权重 / 总权重)
 * - 权重由用户持有的NFT等级和稀有度决定
 *
 * 权重表（普通NFT）：
 * - 1级: 1
 * - 2级: 2
 * - 3级: 6
 * - 4级: 18
 * - 5级: 66
 *
 * 权重表（稀有NFT）：
 * - 1级: 10
 * - 2级: 12
 * - 3级: 16
 * - 4级: 28
 * - 5级: 76
 */
contract DividendManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

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
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "DividendManager: Not authorized");
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
     * @dev 分红池地址（用于查询外部池余额）
     */
    address public dividendPool;

    /**
     * @dev 代币合约地址（用于领取分红转账）
     */
    address public tokenContract;

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
     * @dev 添加到分红池（手动指定金额）
     */
    function addDividendPool(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "DividendManager: Invalid amount");
        _addToDividendPool(amount);
        if (tokenContract != address(0)) {
            lastSyncedBalance = IERC20(tokenContract).balanceOf(address(this));
        }
    }

    /**
     * @dev 同步分红池余额（自动检测合约中新增的代币）
     */
    function syncDividendPool() external onlyAuthorized {
        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        uint256 currentBalance = token.balanceOf(address(this));

        if (currentBalance > lastSyncedBalance) {
            uint256 newFunds = currentBalance - lastSyncedBalance;
            _addToDividendPool(newFunds);
        }

        lastSyncedBalance = currentBalance;
    }

    /**
     * @dev 内部函数：将金额添加到分红池并创建快照
     */
    /**
     * @dev 累计的每权重分红值
     */
    uint256 public cumulativePerWeightDividend;
    
    /**
     * @dev 用户上次累计分红快照
     */
    mapping(address => uint256) public userCumulativeSnapshots;

    function _addToDividendPool(uint256 amount) internal {
        dividendPoolBalance += amount;

        uint256 perWeightDividendIncrement = 0;
        if (totalWeight > 0) {
            perWeightDividendIncrement = amount * 1e18 / totalWeight;
            cumulativePerWeightDividend += perWeightDividendIncrement;
        }

        DividendSnapshot memory newSnapshot = DividendSnapshot({
            totalWeight: totalWeight,
            totalDividend: dividendPoolBalance,
            perWeightDividend: perWeightDividendIncrement,
            timestamp: block.timestamp
        });

        // 使用环形缓冲区添加快照
        if (snapshots.length < MAX_SNAPSHOTS) {
            snapshots.push(newSnapshot);
        } else {
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
     * @dev 获取指定索引的快照（处理环形缓冲区）
     */
    function getSnapshot(uint256 index) external view returns (uint256, uint256, uint256, uint256) {
        require(index < snapshots.length, "DividendManager: Invalid snapshot index");
        uint256 actualIndex = (snapshotStartIndex + index) % snapshots.length;
        DividendSnapshot memory snapshot = snapshots[actualIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend, snapshot.timestamp);
    }

    /**
     * @dev 领取分红
     */
    function claim() external nonReentrant whenNotPaused returns (uint256) {
        uint256 userWeight = userWeights[msg.sender];
        require(userWeight > 0, "DividendManager: No weight");

        // 计算用户应得的增量分红
        uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[msg.sender];
        uint256 newDividend = userWeight * cumulativeDiff / 1e18;
        uint256 totalDividend = pendingDividends[msg.sender] + newDividend;
        
        require(totalDividend > 0, "DividendManager: No dividend");

        pendingDividends[msg.sender] = 0;
        userCumulativeSnapshots[msg.sender] = cumulativePerWeightDividend;

        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= totalDividend, "DividendManager: Insufficient contract balance");
        require(token.transfer(msg.sender, totalDividend), "DividendManager: Transfer failed");

        emit DividendClaimed(msg.sender, totalDividend);
        return totalDividend;
    }

    /**
     * @dev 领取分红并转账（供前端直接调用）
     */
    function claimDividend() external nonReentrant whenNotPaused {
        uint256 userWeight = userWeights[msg.sender];
        require(userWeight > 0, "DividendManager: No weight");

        // 计算用户应得的增量分红
        uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[msg.sender];
        uint256 newDividend = userWeight * cumulativeDiff / 1e18;
        uint256 totalDividend = pendingDividends[msg.sender] + newDividend;

        require(totalDividend > 0, "DividendManager: No dividend");

        pendingDividends[msg.sender] = 0;
        userCumulativeSnapshots[msg.sender] = cumulativePerWeightDividend;

        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= totalDividend, "DividendManager: Insufficient contract balance");
        require(token.transfer(msg.sender, totalDividend), "DividendManager: Transfer failed");

        emit DividendClaimed(msg.sender, totalDividend);
    }

    /**
     * @dev 计算用户可领取分红（别名，兼容前端调用）
     * @param user 用户地址
     * @return 可领取分红金额和用户权重
     */
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        uint256 claimable = getClaimableDividend(user);
        return (claimable, userWeights[user]);
    }

    /**
     * @dev 设置分红池地址
     * @param _pool 分红池合约地址
     */
    function setDividendPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "DividendManager: Invalid pool address");
        dividendPool = _pool;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "DividendManager: Invalid token contract");
        tokenContract = _tokenContract;
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

    /**
     * @dev 设置用户权重（直接设置）
     */
    function setUserWeight(address user, uint256 weight) external onlyAuthorized {
        // 先结算用户当前未领取的分红
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            uint256 pending = userWeights[user] * cumulativeDiff / 1e18;
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
    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external onlyAuthorized {
        uint256 weight = _calculateWeight(level, element);
        
        // 先结算用户当前未领取的分红
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            uint256 pending = userWeights[user] * cumulativeDiff / 1e18;
            pendingDividends[user] += pending;
        }

        if (isAdd) {
            totalWeight += weight;
            userWeights[user] += weight;
        } else {
            require(userWeights[user] >= weight, "DividendManager: Insufficient weight");
            require(totalWeight >= weight, "DividendManager: Total weight underflow");
            totalWeight -= weight;
            userWeights[user] -= weight;
        }
        
        userCumulativeSnapshots[user] = cumulativePerWeightDividend;
    }

    /**
     * @dev 根据等级和元素计算权重
     */
    function _calculateWeight(uint256 level, uint8 element) internal pure returns (uint256) {
        bool isRare = (element == 3 || element == 4);
        if (isRare) {
            uint256[5] memory weights = [uint256(10), 12, 16, 28, 76];
            if (level > 0 && level <= 5) {
                return weights[level - 1];
            }
            return 76;
        } else {
            uint256[5] memory weights = [uint256(1), 2, 6, 18, 66];
            if (level > 0 && level <= 5) {
                return weights[level - 1];
            }
            return 66;
        }
    }

    /**
     * @dev 批量更新用户权重
     */
    function updateUserWeightsBatch(
        address[] calldata users,
        uint256[] calldata weights
    ) external onlyOwner {
        require(users.length == weights.length, "DividendManager: Length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 newWeight = weights[i];
            
            // 先结算用户当前未领取的分红
            if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
                uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
                uint256 pending = userWeights[user] * cumulativeDiff / 1e18;
                pendingDividends[user] += pending;
            }
            
            totalWeight = totalWeight - userWeights[user] + newWeight;
            userWeights[user] = newWeight;
            userCumulativeSnapshots[user] = cumulativePerWeightDividend;
        }
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
     * @dev 获取当前快照
     */
    function getCurrentSnapshot() external view returns (uint256, uint256, uint256) {
        if (snapshots.length == 0) {
            return (0, 0, 0);
        }
        DividendSnapshot memory snapshot = snapshots[snapshots.length - 1];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend);
    }

    /**
     * @dev 获取快照历史长度
     */
    function getSnapshotHistoryLength() external view returns (uint256) {
        return snapshots.length;
    }

    /**
     * @dev 获取指定范围的快照
     * @param startIndex 起始索引
     * @param count 获取数量
     */
    function getSnapshotHistory(uint256 startIndex, uint256 count) external view returns (DividendSnapshot[] memory) {
        require(startIndex < snapshots.length, "DividendManager: Invalid start index");
        require(count > 0, "DividendManager: Invalid count");

        uint256 endIndex = startIndex + count;
        if (endIndex > snapshots.length) {
            endIndex = snapshots.length;
        }

        DividendSnapshot[] memory result = new DividendSnapshot[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = snapshots[i];
        }

        return result;
    }

    /**
     * @dev 获取最新N条快照记录
     * @param count 记录数量
     */
    function getRecentSnapshots(uint256 count) external view returns (DividendSnapshot[] memory) {
        if (snapshots.length == 0) {
            return new DividendSnapshot[](0);
        }

        if (count > snapshots.length) {
            count = snapshots.length;
        }

        DividendSnapshot[] memory result = new DividendSnapshot[](count);
        uint256 startIndex = snapshots.length - count;
        for (uint256 i = 0; i < count; i++) {
            result[i] = snapshots[startIndex + i];
        }

        return result;
    }

    /**
     * @dev [DEPRECATED] 此功能暂未实现
     */
    function getUserWeightAtSnapshot(address user, uint256 snapshotIndex) external pure returns (uint256) {
        return 0;
    }

    /**
     * @dev [DEPRECATED] 此功能暂未实现
     */
    function getUserSnapshotCount(address user) external pure returns (uint256) {
        return 0;
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
        if (tokenContract != address(0)) {
            currentPool = IERC20(tokenContract).balanceOf(address(this));
        }
        totalWeight = this.totalWeight;
        snapshotCount = snapshots.length;
        if (snapshots.length > 0) {
            lastSnapshotTime = snapshots[snapshots.length - 1].timestamp;
        }
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner {
        require(amount > 0, "DividendManager: Amount must be > 0");
        require(amount <= address(this).balance, "DividendManager: Insufficient balance");
        payable(owner()).transfer(amount);
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner {
        require(amount > 0, "DividendManager: Amount must be > 0");
        require(tokenContract != address(0), "DividendManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "DividendManager: Insufficient token balance");
        require(token.transfer(owner(), amount), "DividendManager: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
}