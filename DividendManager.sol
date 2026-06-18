// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

/**
 * @title DividendManager - NFT分红管理合约
 * @dev 管理NFT持有者的分红分发，支持代币和BNB两种分红池
 * @dev 权重基于NFT等级和稀有度计算
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
        require(!paused, "DM: Paused");
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
    event DividendClaimed(address indexed user, uint256 amount);
    event DividendClaimWarning(address indexed user, uint256 daysSinceLastClaim);
    event DividendPoolAdded(uint256 amount, uint256 totalDividend, uint256 perWeightDividendIncrement);
    event WeightUpdated(address indexed user, uint256 newWeight);
    
    address public authorizer;
    mapping(address => uint256) public userWeights;
    uint256 public constant MAX_SNAPSHOTS = 100;
    uint256 public constant DIVIDEND_CLAIM_WARNING_THRESHOLD = 30 days;
    mapping(address => uint256) public lastClaimTime;

    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "DM: Invalid authorizer");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "DM: Invalid authorizer");
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
            "DM: Not authorized"
        );
        _;
    }

    /**
     * @dev 用户待领取分红映射
     * user => pendingDividend
     */
    mapping(address => uint256) public pendingDividends;

    uint256 public totalWeight;
    uint256 public dividendPoolBalance;
    uint256 public lastSnapshotTime;
    
    struct DividendSnapshot {
        uint256 totalWeight;
        uint256 totalDividend;
        uint256 perWeightDividend;
        uint256 timestamp;
    }
    DividendSnapshot[] public snapshots;
    uint256 public snapshotStartIndex;
    uint256 public lastSyncedBalance;
    uint256 public constant AUTO_SYNC_INTERVAL = 6 hours;
    uint256 public lastAutoSyncTime;

    function addDividendPool(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "DM: Invalid amount");
        _addToDividendPool(amount);
        address tokenContract = IAuthorizer(authorizer).getToken();
        if (tokenContract != address(0)) {
            lastSyncedBalance = IERC20(tokenContract).balanceOf(address(this));
        }
    }

    function syncDividendPool() external onlyOwnerOrAuthorizer {
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "DM: Token not set");
        IERC20 token = IERC20(tokenContract);
        uint256 currentBalance = token.balanceOf(address(this));

        if (currentBalance > lastSyncedBalance) {
            uint256 newFunds = currentBalance - lastSyncedBalance;
            _addToDividendPool(newFunds);
        }

        lastSyncedBalance = currentBalance;
        lastAutoSyncTime = block.timestamp;
    }
    
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
     * @dev 累计的每权重分红额
     */
    uint256 public cumulativePerWeightDividend;
    mapping(address => uint256) public userCumulativeSnapshots;

    function _addToDividendPool(uint256 amount) internal {
        uint256 newBalance = dividendPoolBalance + amount;
        require(newBalance >= dividendPoolBalance, "DM: Overflow");
        dividendPoolBalance = newBalance;

        uint256 perWeightDividendIncrement = 0;
        if (totalWeight > 0) {
            if (amount > 0) {
                require(type(uint256).max / amount >= 1e18, "DM: Scale overflow");
            }
            perWeightDividendIncrement = (amount * 1e18) / totalWeight;
            uint256 newCumulative = cumulativePerWeightDividend + perWeightDividendIncrement;
            require(newCumulative >= cumulativePerWeightDividend, "DM: Cum overflow");
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
            require(snapshotStartIndex < MAX_SNAPSHOTS, "DM: Invalid index");
            snapshots[snapshotStartIndex] = newSnapshot;
            snapshotStartIndex = (snapshotStartIndex + 1) % MAX_SNAPSHOTS;
        }

        emit DividendPoolAdded(amount, dividendPoolBalance, perWeightDividendIncrement);
    }

    function getSnapshotCount() external view returns (uint256) {
        return snapshots.length;
    }

    function getSnapshot(uint256 index) external view returns (uint256, uint256, uint256, uint256) {
        require(index < snapshots.length, "DM: Invalid index");
        uint256 actualIndex = _getActualIndex(index);
        DividendSnapshot memory snapshot = snapshots[actualIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend, snapshot.timestamp);
    }
    
    function _getActualIndex(uint256 logicalIndex) internal view returns (uint256) {
        return (snapshotStartIndex + logicalIndex) % snapshots.length;
    }

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

        require(totalDividend > 0, "DM: No dividend");

        pendingDividends[msg.sender] = 0;
        if (userWeight > 0) {
            userCumulativeSnapshots[msg.sender] = cumulativePerWeightDividend;
        }
        lastClaimTime[msg.sender] = block.timestamp;

        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "DM: Token not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= totalDividend, "DM: Insufficient balance");
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

    receive() external payable {}

    function getClaimableDividend(address user) external view returns (uint256) {
        uint256 userWeight = userWeights[user];
        if (userWeight == 0) return pendingDividends[user];
        
        uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
        uint256 newDividend = userWeight * cumulativeDiff / 1e18;
        return pendingDividends[user] + newDividend;
    }

    function getUserWeight(address user) external view returns (uint256) {
        return userWeights[user];
    }

    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    uint256 public constant MAX_USER_WEIGHT = 100000;
    uint256 public minWeightUpdateInterval = 0;
    mapping(address => uint256) public lastWeightUpdateTime;

    function setUserWeight(address user, uint256 weight) external onlyOwnerOrAuthorizer {
        require(weight <= MAX_USER_WEIGHT, "DM: Weight max");
        
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            uint256 weightedProduct = userWeights[user] * cumulativeDiff;
            require(weightedProduct / userWeights[user] == cumulativeDiff, "DM: Pending overflow");
            uint256 pending = weightedProduct / 1e18;
            pendingDividends[user] += pending;
        }
        
        totalWeight = totalWeight - userWeights[user] + weight;
        userWeights[user] = weight;
        userCumulativeSnapshots[user] = cumulativePerWeightDividend;
    }

    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external onlyOwnerOrAuthorizer {
        require(user != address(0), "DM: Zero user");
        uint256 weight = _calculateWeight(level, element);

        if (minWeightUpdateInterval > 0) {
            require(block.timestamp >= lastWeightUpdateTime[user] + minWeightUpdateInterval, "DM: Too frequent");
        }
        
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            uint256 weightedProduct = userWeights[user] * cumulativeDiff;
            require(weightedProduct / userWeights[user] == cumulativeDiff, "DM: Weight calc overflow");
            uint256 pending = weightedProduct / 1e18;
            pendingDividends[user] += pending;
        }

        if (isAdd) {
            uint256 newUserWeight = userWeights[user] + weight;
            require(newUserWeight >= userWeights[user], "DM: Weight overflow");
            require(newUserWeight <= MAX_USER_WEIGHT, "DM: New weight max");
            uint256 newTotalWeight = totalWeight + weight;
            require(newTotalWeight >= totalWeight, "DM: Total overflow");
            totalWeight = newTotalWeight;
            userWeights[user] = newUserWeight;
        } else {
            require(userWeights[user] >= weight, "DM: Insufficient weight");
            require(totalWeight >= weight, "DM: Total underflow");
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
        require(user != address(0), "DM: Zero user");
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        if (nftDataContract == address(0)) return;
        
        INFTDataInterface nftData = INFTDataInterface(nftDataContract);
        uint256 newWeight = nftData.calcUserWeight(user);
        
        if (userWeights[user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[user];
            uint256 weightedProduct = userWeights[user] * cumulativeDiff;
            require(weightedProduct / userWeights[user] == cumulativeDiff, "DM: Sync overflow");
            uint256 pending = weightedProduct / 1e18;
            uint256 newPending = pendingDividends[user] + pending;
            require(newPending >= pendingDividends[user], "DM: Pending overflow");
            pendingDividends[user] = newPending;
        }
        
        require(totalWeight >= userWeights[user], "DM: Total underflow");
        uint256 totalWeightAfterRemove = totalWeight - userWeights[user];
        uint256 totalWeightAfterAdd = totalWeightAfterRemove + newWeight;
        require(totalWeightAfterAdd >= totalWeightAfterRemove, "DM: Total overflow");
        totalWeight = totalWeightAfterAdd;
        
        userWeights[user] = newWeight;
        userCumulativeSnapshots[user] = cumulativePerWeightDividend;
        lastWeightUpdateTime[user] = block.timestamp;
        
        emit WeightUpdated(user, newWeight);
    }

    uint256 public constant MAX_NFT_LEVEL = 5;

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

    function getWeightConfig() external pure returns (uint256[5] memory normalWeights, uint256[5] memory rareWeights) {
        normalWeights = [uint256(1), 2, 6, 18, 66];
        rareWeights = [uint256(10), 12, 16, 28, 76];
    }

    function updateUserWeightsBatch(
        address[] calldata users,
        uint256[] calldata weights
    ) external onlyOwnerOrAuthorizer {
        require(users.length == weights.length, "DM: Length mismatch");
        require(users.length <= 100, "DM: Batch max");
        
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
            
            if (newWeight > oldWeight) {
                uint256 increase = newWeight - oldWeight;
                totalWeightChange = totalWeightChange + increase;
            } else if (oldWeight > newWeight) {
                uint256 decrease = oldWeight - newWeight;
                require(totalWeightChange >= decrease, "DM: Change underflow");
                totalWeightChange = totalWeightChange - decrease;
            }
            
            userWeights[user] = newWeight;
            userCumulativeSnapshots[user] = cumulativePerWeightDividend;
        }
        
        totalWeight = totalWeight + totalWeightChange;
    }

    function calculateDividend(uint256 amount) external view returns (uint256) {
        if (totalWeight == 0) return 0;
        return (amount * 1e18) / totalWeight / 1e18;
    }

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

    function getSnapshotHistoryLength() external view returns (uint256) {
        return snapshots.length;
    }

    function getSnapshotHistory(uint256 startIndex, uint256 count) external view returns (DividendSnapshot[] memory) {
        uint256 totalCount = snapshots.length;
        require(startIndex < totalCount, "DM: Invalid start");
        require(count > 0, "DM: Invalid count");

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

    uint256 public emergencyWithdrawTimelock = 86400;
    uint256 public emergencyWithdrawRequestedAt;
    bool public emergencyWithdrawRequested;

    function requestEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawRequested = true;
        emergencyWithdrawRequestedAt = block.timestamp;
        emit EmergencyWithdrawRequested(msg.sender, block.timestamp);
    }
    
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(emergencyWithdrawRequested, "DM: Not requested");
        require(block.timestamp >= emergencyWithdrawRequestedAt + emergencyWithdrawTimelock, "DM: Timelock");
        require(amount > 0, "DM: Amount 0");
        require(amount <= address(this).balance, "DM: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "DM: BNB failed");
        emergencyWithdrawRequested = false;
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(emergencyWithdrawRequested, "DM: Not requested");
        require(block.timestamp >= emergencyWithdrawRequestedAt + emergencyWithdrawTimelock, "DM: Timelock");
        require(amount > 0, "DM: Amount 0");
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "DM: Token not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "DM: Insufficient token");
        token.safeTransfer(owner(), amount);
        emergencyWithdrawRequested = false;
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }
    
    event EmergencyWithdrawRequested(address indexed operator, uint256 timestamp);
}