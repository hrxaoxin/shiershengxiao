﻿// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./DividendManagerLib.sol";

/**
 * @title DividendManager - NFT分红管理合约
 * @dev 管理NFT持有者的分红分发，支持代币、BNB和LP分红
 * @dev 权重基于NFT等级和稀有度计算
 */
contract DividendManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using DividendManagerLib for *;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    // =========================================================================
    // 暂停功能相关状态变量
    // =========================================================================

    /// @dev 合约暂停状态标记
    bool public paused;
    
    /// @dev 暂停原因描述
    string public pauseReason;

    /// @notice 合约暂停事件
    /// @param account 触发暂停的账户地址
    /// @param reason 暂停原因
    event Paused(address indexed account, string reason);
    
    /// @notice 合约解除暂停事件
    /// @param account 触发解除暂停的账户地址
    event Unpaused(address indexed account);
    
    /// @notice 紧急提取BNB事件
    /// @param operator 操作者地址
    /// @param to 目标接收地址
    /// @param amount 提取金额
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    
    /// @notice 紧急提取代币事件
    /// @param operator 操作者地址
    /// @param to 目标接收地址
    /// @param amount 提取金额
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    /// @dev 暂停检查修饰符
    modifier whenNotPaused() {
        require(!paused, "DM: Paused");
        _;
    }

    // =========================================================================
    // 暂停/恢复管理函数
    // =========================================================================

    /// @notice 暂停合约所有操作
    /// @dev 仅管理员可调用，用于紧急情况下的合约保护
    /// @param reason 暂停原因描述
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /// @notice 恢复合约正常操作
    /// @dev 仅管理员可调用
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    // =========================================================================
    // 分红领取事件
    // =========================================================================

    /// @notice 用户领取分红事件
    /// @param user 用户地址
    /// @param amount 领取金额
    event DividendClaimed(address indexed user, uint256 amount);
    
    /// @notice 分红领取警告事件（超过30天未领取时触发）
    /// @param user 用户地址
    /// @param daysSinceLastClaim 距离上次领取的天数
    event DividendClaimWarning(address indexed user, uint256 daysSinceLastClaim);
    
    /// @notice 分红池增加事件
    /// @param amount 新增分红金额
    /// @param totalDividend 分红池总额
    /// @param perWeightDividendIncrement 每权重分红增量
    event DividendPoolAdded(uint256 amount, uint256 totalDividend, uint256 perWeightDividendIncrement);
    
    /// @notice 用户权重更新事件
    /// @param user 用户地址
    /// @param newWeight 新的权重值
    event WeightUpdated(address indexed user, uint256 newWeight);

    // =========================================================================
    // 核心状态变量
    // =========================================================================

    /// @dev 授权者合约地址，用于获取系统配置
    address public authorizer;
    
    /// @dev 当前纪元（循环复用，MAX_EPOCHS次后回到0）
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    /// @dev 用户权重映射：epoch => 用户地址 => 权重值
    mapping(uint256 => mapping(address => uint256)) public userWeights;
    
    /// @dev 最大快照数量，用于循环缓冲区
    uint256 public constant MAX_SNAPSHOTS = 100;
    
    /// @dev 分红领取警告阈值（30天）
    uint256 public constant DIVIDEND_CLAIM_WARNING_THRESHOLD = 30 days;
    
    /// @dev 用户最后领取分红的时间戳（epoch => 用户地址 => 时间戳）
    mapping(uint256 => mapping(address => uint256)) public lastClaimTime;

    // =========================================================================
    // 初始化函数
    // =========================================================================

    /// @notice 初始化合约
    /// @dev 只能在代理合约部署时调用一次
    /// @param _authorizerAddress 授权者合约地址
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "DM: Invalid authorizer");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        epoch = 1;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }

    /// @dev UUPS升级授权检查，仅管理员可升级
    /// @param newImplementation 新实现合约地址
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice 设置授权者合约地址
    /// @dev 仅管理员或授权者可调用
    /// @param _authorizerAddress 新的授权者合约地址
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "DM: Invalid authorizer");
        authorizer = _authorizerAddress;
    }

    /// @dev 管理员或授权者检查修饰符
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "DM: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "DM: Not authorized");
        _;
    }

    // =========================================================================
    // 用户分红相关变量
    // =========================================================================

    /// @dev 用户待领取分红映射：epoch => 用户地址 => 待领取分红金额
    mapping(uint256 => mapping(address => uint256)) public pendingDividends;
    
    /// @dev 所有用户的总权重
    uint256 public totalWeight;
    
    /// @dev 当前分红池余额
    uint256 public dividendPoolBalance;
    
    /// @dev 最后快照时间戳
    uint256 public lastSnapshotTime;
    
    /// @dev 分红快照结构体，用于记录历史分红状态
    struct DividendSnapshot {
        uint256 totalWeight;        // 快照时的总权重
        uint256 totalDividend;      // 快照时的分红池总额
        uint256 perWeightDividend;  // 快照时每权重分红额
        uint256 timestamp;          // 快照时间戳
    }
    
    /// @dev 分红快照数组（循环缓冲区）
    DividendSnapshot[] public snapshots;
    
    /// @dev 循环缓冲区起始索引
    uint256 public snapshotStartIndex;
    
    /// @dev 上次同步的代币余额
    uint256 public lastSyncedBalance;
    
    /// @dev 自动同步间隔（6小时）
    uint256 public constant AUTO_SYNC_INTERVAL = 6 hours;
    
    /// @dev 上次自动同步时间
    uint256 public lastAutoSyncTime;

    // =========================================================================
    // 分红池管理函数
    // =========================================================================

    /// @notice 向分红池添加分红
    /// @dev 仅管理员可调用，增加分红池余额并更新快照
    /// @param amount 要添加的分红金额
    function addDividendPool(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "DM: Invalid amount");
        _addToDividendPool(amount);
        address tokenContract = IAuthorizer(authorizer).getAddressByName(\"token\");
        if (tokenContract != address(0)) {
            lastSyncedBalance = IERC20(tokenContract).balanceOf(address(this));
        }
    }

    /// @notice 同步分红池
    /// @dev 手动同步合约代币余额与分红池，更新新的分红
    /// @dev 仅管理员或授权者可调用
    function syncDividendPool() external onlyOwnerOrAuthorizer {
        address tokenContract = IAuthorizer(authorizer).getAddressByName(\"token\");
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
    
    /// @dev 自动同步分红池的内部函数
    /// @dev 当距离上次同步超过6小时时自动执行
    function _autoSyncDividendPool() internal {
        address tokenContract = IAuthorizer(authorizer).getAddressByName(\"token\");
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

    // =========================================================================
    // 累计分红相关变量
    // =========================================================================

    /// @dev 累计每权重分红额（核心计算参数）
    uint256 public cumulativePerWeightDividend;
    
    /// @dev 用户累计分红快照：epoch => 用户地址 => 累计快照值
    mapping(uint256 => mapping(address => uint256)) public userCumulativeSnapshots;

    // =========================================================================
    // 内部分红池添加函数
    // =========================================================================

    /// @dev 内部函数：向分红池添加金额并更新快照
    /// @param amount 要添加的金额
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

    // =========================================================================
    // 快照查询函数
    // =========================================================================

    /// @notice 获取快照总数
    /// @return 快照数组长度
    function getSnapshotCount() external view returns (uint256) {
        return snapshots.length;
    }

    /// @notice 获取指定索引的快照
    /// @param index 快照索引
    /// @return totalWeight 快照时的总权重
    /// @return totalDividend 快照时的分红池总额
    /// @return perWeightDividend 快照时的每权重分红增量
    /// @return timestamp 快照时间戳
    function getSnapshot(uint256 index) external view returns (uint256, uint256, uint256, uint256) {
        require(index < snapshots.length, "DM: Invalid index");
        uint256 actualIndex = _getActualIndex(index);
        DividendSnapshot memory snapshot = snapshots[actualIndex];
        return (snapshot.totalWeight, snapshot.totalDividend, snapshot.perWeightDividend, snapshot.timestamp);
    }
    
    /// @dev 内部函数：根据逻辑索引获取实际数组索引
    /// @param logicalIndex 逻辑索引
    /// @return 实际数组索引
    function _getActualIndex(uint256 logicalIndex) internal view returns (uint256) {
        return DividendManagerLib.getActualIndex(logicalIndex, snapshotStartIndex, snapshots.length);
    }

    // =========================================================================
    // 分红领取函数
    // =========================================================================

    /// @notice 领取用户分红
    /// @dev 非重入修饰符，合约未暂停时可调用
    /// @return 实际领取的分红金额
    function claim() external nonReentrant whenNotPaused returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        _autoSyncDividendPool();

        uint256 userWeight = userWeights[currentEpoch][msg.sender];

        if (lastClaimTime[currentEpoch][msg.sender] > 0 &&
            block.timestamp - lastClaimTime[currentEpoch][msg.sender] > DIVIDEND_CLAIM_WARNING_THRESHOLD) {
            emit DividendClaimWarning(msg.sender, block.timestamp - lastClaimTime[currentEpoch][msg.sender]);
        }

        uint256 newDividend = DividendManagerLib.calculatePendingDividend(
            userWeight,
            cumulativePerWeightDividend,
            userCumulativeSnapshots[currentEpoch][msg.sender]
        );

        uint256 totalDividend = pendingDividends[currentEpoch][msg.sender] + newDividend;

        require(totalDividend > 0, "DM: No dividend");

        pendingDividends[currentEpoch][msg.sender] = 0;
        if (userWeight > 0) {
            userCumulativeSnapshots[currentEpoch][msg.sender] = cumulativePerWeightDividend;
        }
        lastClaimTime[currentEpoch][msg.sender] = block.timestamp;

        address tokenContract = IAuthorizer(authorizer).getAddressByName(\"token\");
        require(tokenContract != address(0), "DM: Token not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= totalDividend, "DM: Insufficient balance");
        token.safeTransfer(msg.sender, totalDividend);

        emit DividendClaimed(msg.sender, totalDividend);
        return totalDividend;
    }

    /// @notice 领取分红并转账（供前端直接调用）
    /// @dev 委托给 claim() 以消除代码重复
    function claimDividend() external nonReentrant whenNotPaused {
        this.claim();
    }

    /// @notice 计算用户可领取分红（别名，兼容前端调用）
    /// @param user 用户地址
    /// @return 可领取分红金额
    /// @return 用户当前权重
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        uint256 claimable = this.getClaimableDividend(user);
        return (claimable, userWeights[_currentEpoch()][user]);
    }

    // =========================================================================
    // 可领取分红查询函数
    // =========================================================================

    /// @notice 获取用户可领取的分红金额
    /// @param user 用户地址
    /// @return 可领取的分红总额（包含已记录的pendingDividends）
    function getClaimableDividend(address user) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        uint256 userWeight = userWeights[currentEpoch][user];
        if (userWeight == 0) return pendingDividends[currentEpoch][user];
        
        uint256 newDividend = DividendManagerLib.calculatePendingDividend(
            userWeight,
            cumulativePerWeightDividend,
            userCumulativeSnapshots[currentEpoch][user]
        );
        return pendingDividends[currentEpoch][user] + newDividend;
    }

    /// @notice 获取用户权重
    /// @param user 用户地址
    /// @return 用户当前权重
    function getUserWeight(address user) external view returns (uint256) {
        return userWeights[_currentEpoch()][user];
    }

    /// @notice 获取总权重
    /// @return 所有用户的权重总和
    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    // =========================================================================
    // 权重管理相关变量
    // =========================================================================

    /// @dev 用户权重上限
    uint256 public constant MAX_USER_WEIGHT = 100000;
    
    /// @dev 最小权重更新间隔（秒）
    uint256 public minWeightUpdateInterval = 0;
    
    /// @dev 用户上次权重更新时间（epoch => 用户地址 => 时间）
    mapping(uint256 => mapping(address => uint256)) public lastWeightUpdateTime;

    // =========================================================================
    // 权重设置函数
    // =========================================================================

    /// @notice 直接设置用户权重
    /// @dev 仅管理员或授权者可调用，会先结算用户的待领取分红
    /// @param user 用户地址
    /// @param weight 新的权重值
    function setUserWeight(address user, uint256 weight) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        require(weight <= MAX_USER_WEIGHT, "DM: Weight max");
        
        if (userWeights[currentEpoch][user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[currentEpoch][user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[currentEpoch][user];
            uint256 weightedProduct = userWeights[currentEpoch][user] * cumulativeDiff;
            require(weightedProduct / userWeights[currentEpoch][user] == cumulativeDiff, "DM: Pending overflow");
            uint256 pending = weightedProduct / 1e18;
            pendingDividends[currentEpoch][user] += pending;
        }
        
        totalWeight = totalWeight - userWeights[currentEpoch][user] + weight;
        userWeights[currentEpoch][user] = weight;
        userCumulativeSnapshots[currentEpoch][user] = cumulativePerWeightDividend;
    }

    /// @notice 更新用户权重（基于NFT等级和元素）
    /// @dev 仅管理员或授权者可调用，支持增加或减少权重
    /// @param user 用户地址
    /// @param level NFT等级（0-5）
    /// @param isAdd 是否为增加权重（true增加，false减少）
    /// @param element NFT元素类型（3或4为稀有元素）
    function updateUserWeight(address user, uint256 level, bool isAdd, uint8 element) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        require(user != address(0), "DM: Zero user");
        uint256 weight = _calculateWeight(level, element);

        if (minWeightUpdateInterval > 0) {
            require(block.timestamp >= lastWeightUpdateTime[currentEpoch][user] + minWeightUpdateInterval, "DM: Too frequent");
        }
        
        if (userWeights[currentEpoch][user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[currentEpoch][user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[currentEpoch][user];
            uint256 weightedProduct = userWeights[currentEpoch][user] * cumulativeDiff;
            require(weightedProduct / userWeights[currentEpoch][user] == cumulativeDiff, "DM: Weight calc overflow");
            uint256 pending = weightedProduct / 1e18;
            pendingDividends[currentEpoch][user] += pending;
        }

        if (isAdd) {
            uint256 newUserWeight = userWeights[currentEpoch][user] + weight;
            require(newUserWeight >= userWeights[currentEpoch][user], "DM: Weight overflow");
            require(newUserWeight <= MAX_USER_WEIGHT, "DM: New weight max");
            uint256 newTotalWeight = totalWeight + weight;
            require(newTotalWeight >= totalWeight, "DM: Total overflow");
            totalWeight = newTotalWeight;
            userWeights[currentEpoch][user] = newUserWeight;
        } else {
            require(userWeights[currentEpoch][user] >= weight, "DM: Insufficient weight");
            require(totalWeight >= weight, "DM: Total underflow");
            totalWeight -= weight;
            userWeights[currentEpoch][user] -= weight;
        }
        
        userCumulativeSnapshots[currentEpoch][user] = cumulativePerWeightDividend;
        lastWeightUpdateTime[currentEpoch][user] = block.timestamp;
    }

    /// @notice 设置最小权重更新间隔
    /// @dev 仅管理员可调用，防止频繁更新
    /// @param seconds_ 间隔秒数
    function setMinWeightUpdateInterval(uint256 seconds_) external onlyOwner {
        minWeightUpdateInterval = seconds_;
    }

    /// @notice 同步用户权重
    /// @dev 由NFTTrading、Staking等合约调用，从NFTData合约获取最新权重
    /// @dev 仅授权的系统合约可调用，防止恶意调用影响分红计算
    /// @param user 用户地址
    function syncUserWeight(address user) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        require(user != address(0), "DM: Zero user");
        address nftDataContract = IAuthorizer(authorizer).getAddressByName(\"nftData\");
        if (nftDataContract == address(0)) return;
        
        INFTDataInterface nftData = INFTDataInterface(nftDataContract);
        uint256 newWeight = nftData.calcUserWeight(user);
        
        if (userWeights[currentEpoch][user] > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[currentEpoch][user]) {
            uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[currentEpoch][user];
            uint256 weightedProduct = userWeights[currentEpoch][user] * cumulativeDiff;
            require(weightedProduct / userWeights[currentEpoch][user] == cumulativeDiff, "DM: Sync overflow");
            uint256 pending = weightedProduct / 1e18;
            uint256 newPending = pendingDividends[currentEpoch][user] + pending;
            require(newPending >= pendingDividends[currentEpoch][user], "DM: Pending overflow");
            pendingDividends[currentEpoch][user] = newPending;
        }
        
        require(totalWeight >= userWeights[currentEpoch][user], "DM: Total underflow");
        uint256 totalWeightAfterRemove = totalWeight - userWeights[currentEpoch][user];
        uint256 totalWeightAfterAdd = totalWeightAfterRemove + newWeight;
        require(totalWeightAfterAdd >= totalWeightAfterRemove, "DM: Total overflow");
        totalWeight = totalWeightAfterAdd;
        
        userWeights[currentEpoch][user] = newWeight;
        userCumulativeSnapshots[currentEpoch][user] = cumulativePerWeightDividend;
        lastWeightUpdateTime[currentEpoch][user] = block.timestamp;
        
        emit WeightUpdated(user, newWeight);
    }

    // =========================================================================
    // NFT权重计算
    // =========================================================================

    /// @dev 最大NFT等级
    uint256 public constant MAX_NFT_LEVEL = 5;

    /// @dev 内部函数：根据NFT等级和元素计算权重
    /// @param level NFT等级（0-5）
    /// @param element NFT元素类型（3或4为稀有）
    /// @return 计算得到的权重值
    function _calculateWeight(uint256 level, uint8 element) internal view returns (uint256) {
        bool isRare = (element == 3 || element == 4);
        return DividendManagerLib.getWeightByConfig(level, isRare, authorizer);
    }

    /// @notice 获取指定等级和稀有度的NFT权重
    /// @param level NFT等级（0-5）
    /// @param isRare 是否为稀有元素
    /// @return 权重值
    function getNFTWeight(uint256 level, bool isRare) external view returns (uint256) {
        return DividendManagerLib.getWeightByConfig(level, isRare, authorizer);
    }

    /// @notice 获取权重配置
    /// @return normalWeights 普通元素各等级权重
    /// @return rareWeights 稀有元素各等级权重
    function getWeightConfig() external view returns (uint256[5] memory normalWeights, uint256[5] memory rareWeights) {
        address nftDataAddr = IAuthorizer(authorizer).getAddressByName(\"nftData\");
        if (nftDataAddr != address(0)) {
            bool hasData = false;
            for (uint8 i = 0; i < 5; i++) {
                try INFTData(nftDataAddr).getWeightByLevel(i + 1, false) returns (uint256 w) {
                    if (w > 0) {
                        normalWeights[i] = w;
                        hasData = true;
                    } else {
                        hasData = false;
                        break;
                    }
                } catch {
                    hasData = false;
                    break;
                }
            }
            if (hasData) {
                for (uint8 i = 0; i < 5; i++) {
                    try INFTData(nftDataAddr).getWeightByLevel(i + 1, true) returns (uint256 w) {
                        if (w > 0) {
                            rareWeights[i] = w;
                        } else {
                            hasData = false;
                            break;
                        }
                    } catch {
                        hasData = false;
                        break;
                    }
                }
            }
            if (hasData) return (normalWeights, rareWeights);
        }
        
        normalWeights = [uint256(1), 2, 6, 18, 66];
        rareWeights = [uint256(10), 12, 16, 28, 76];
    }

    /// @notice 批量更新用户权重
    /// @dev 仅管理员或授权者可调用，单次最多100个用户
    /// @param users 用户地址数组
    /// @param weights 对应的权重数组
    function updateUserWeightsBatch(
        address[] calldata users,
        uint256[] calldata weights
    ) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        require(users.length == weights.length, "DM: Length mismatch");
        require(users.length <= 100, "DM: Batch max");
        
        uint256 usersLength = users.length;
        uint256 totalWeightChange = 0;
        
        for (uint256 i = 0; i < usersLength; i++) {
            address user = users[i];
            uint256 newWeight = weights[i];
            uint256 oldWeight = userWeights[currentEpoch][user];
            
            if (oldWeight > 0 && cumulativePerWeightDividend > userCumulativeSnapshots[currentEpoch][user]) {
                uint256 cumulativeDiff = cumulativePerWeightDividend - userCumulativeSnapshots[currentEpoch][user];
                pendingDividends[currentEpoch][user] += oldWeight * cumulativeDiff / 1e18;
            }
            
            if (newWeight > oldWeight) {
                uint256 increase = newWeight - oldWeight;
                totalWeightChange = totalWeightChange + increase;
            } else if (oldWeight > newWeight) {
                uint256 decrease = oldWeight - newWeight;
                require(totalWeightChange >= decrease, "DM: Change underflow");
                totalWeightChange = totalWeightChange - decrease;
            }
            
            userWeights[currentEpoch][user] = newWeight;
            userCumulativeSnapshots[currentEpoch][user] = cumulativePerWeightDividend;
        }
        
        totalWeight = totalWeight + totalWeightChange;
    }

    // =========================================================================
    // 分红计算与统计函数
    // =========================================================================

    /// @notice 计算指定金额的分红（每权重）
    /// @param amount 分红总金额
    /// @return 每权重可获得的分红
    function calculateDividend(uint256 amount) external view returns (uint256) {
        if (totalWeight == 0) return 0;
        return (amount * 1e18) / totalWeight / 1e18;
    }

    /// @notice 获取当前最新快照
    /// @return totalWeight 当前总权重
    /// @return totalDividend 当前分红池总额
    /// @return perWeightDividend 最新每权重分红增量
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

    /// @notice 获取快照历史长度
    /// @return 快照总数
    function getSnapshotHistoryLength() external view returns (uint256) {
        return snapshots.length;
    }

    /// @notice 获取快照历史（指定范围）
    /// @param startIndex 起始索引
    /// @param count 要获取的数量
    /// @return 分红快照数组
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

    /// @notice 获取最近的快照
    /// @param count 要获取的数量
    /// @return 分红快照数组
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

    /// @notice 获取分红池统计信息
    /// @return currentPool 当前分红池余额
    /// @return totalWeight 当前总权重
    /// @return snapshotCount 快照数量
    /// @return lastSnapshotTime 最后快照时间
    function getDividendPoolStats() external view returns (
        uint256 currentPool,
        uint256 totalWeight,
        uint256 snapshotCount,
        uint256 lastSnapshotTime
    ) {
        address tokenContract = IAuthorizer(authorizer).getAddressByName(\"token\");
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

    // =========================================================================
    // 紧急提取功能
    // =========================================================================

    /// @dev 紧急提取时间锁（24小时）
    uint256 public emergencyWithdrawTimelock = 86400;
    
    /// @dev 紧急提取请求时间戳
    uint256 public emergencyWithdrawRequestedAt;
    
    /// @dev 紧急提取请求标记
    bool public emergencyWithdrawRequested;

    /// @notice 请求紧急提取权限
    /// @dev 仅管理员可调用，开启24小时时间锁
    function requestEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawRequested = true;
        emergencyWithdrawRequestedAt = block.timestamp;
        emit EmergencyWithdrawRequested(msg.sender, block.timestamp);
    }
    
    /// @notice 紧急提取BNB
    /// @dev 需要先请求并等待24小时时间锁到期
    /// @param amount 要提取的BNB金额
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

    /// @notice 紧急提取代币
    /// @dev 需要先请求并等待24小时时间锁到期
    /// @param amount 要提取的代币金额
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(emergencyWithdrawRequested, "DM: Not requested");
        require(block.timestamp >= emergencyWithdrawRequestedAt + emergencyWithdrawTimelock, "DM: Timelock");
        require(amount > 0, "DM: Amount 0");
        address tokenContract = IAuthorizer(authorizer).getAddressByName(\"token\");
        require(tokenContract != address(0), "DM: Token not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "DM: Insufficient token");
        token.safeTransfer(owner(), amount);
        emergencyWithdrawRequested = false;
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }
    
    /// @notice 紧急提取请求事件
    /// @param operator 操作者地址
    /// @param timestamp 请求时间戳
    event EmergencyWithdrawRequested(address indexed operator, uint256 timestamp);

    function getUserWeights(address user) external view returns (uint256) {
        return userWeights[_currentEpoch()][user];
    }

    function getPendingDividends(address user) external view returns (uint256) {
        return pendingDividends[_currentEpoch()][user];
    }

    function getUserCumulativeSnapshots(address user) external view returns (uint256) {
        return userCumulativeSnapshots[_currentEpoch()][user];
    }

    /**
     * @dev 清空合约内部的所有数据
     * 仅合约所有者和authorizer合约可调用
     * 用于紧急情况下重置整个项目数据
     * 注意：由于Solidity无法遍历mapping的所有键，此函数只重置核心状态变量
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        totalWeight = 0;
        dividendPoolBalance = 0;
        lastSyncedBalance = 0;
        lastAutoSyncTime = 0;
        cumulativePerWeightDividend = 0;
        delete snapshots;
        snapshotStartIndex = 0;
        lastSnapshotTime = 0;
        emergencyWithdrawRequested = false;
        emergencyWithdrawRequestedAt = 0;
        paused = false;
        pauseReason = "";
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }

    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);
}
