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
 * @title Staking
 * @dev NFT质押合约（优化版：支持大规模用户，实时奖励计算）
 *
 * 核心功能：
 * 1. NFT质押（stakeNFT）：用户将NFT转入合约，进入质押池开始产生奖励
 * 2. 奖励领取（claimReward）：用户领取累计奖励，基于全局累积奖励快照计算
 * 3. 解除质押（unstakeNFT）：取出质押的NFT，需经过最小锁仓期（minStakingDuration）
 * 4. 紧急提取（emergencyWithdraw）：经过 timelock 后可强制提取，防止合约异常锁死资产
 *
 * 奖励机制设计（O(1) 计算，Gas 优化版）：
 * - 核心思想：用一个全局累积变量（globalRewardPerWeight）记录"每单位权重的历史累积奖励"
 * - 每个 NFT 记录质押时的 globalRewardPerWeight 快照（accumulatedReward）
 * - 用户领取时：(当前 globalRewardPerWeight - NFT快照) × NFT权重 = 该NFT应得奖励
 * - 这样无论多少用户质押，每次新增奖励池只需更新全局变量，无需遍历所有用户
 *
 * 权重系统：
 * - 普通NFT（水/木/火属性，type < 72）：根据等级赋予权重 1/2/6/18/66
 * - 稀有NFT（暗/光属性，type >= 72）：根据等级赋予权重 10/12/16/28/76
 * - 等级越高，权重越大，奖励比例越高
 * - 权重同时会更新到 WeightManager / DividendManager，用于分红池分配
 *
 * 动态奖励率调整：
 * - 基础奖励率（rewardRate）：默认1%（100/10000）
 * - 最大奖励率（maxRewardRate）：默认2%
 * - 根据每日流入资金自动调整，激励长期持有者
 *
 * 溢出保护：
 * - globalRewardPerWeight 使用 uint256，设置 REWARD_OVERFLOW_THRESHOLD 预警
 * - 用户快照权重（_userSnapshotWeight）同样有溢出阈值保护
 * - 达到阈值时触发 rewardResetCount，重置累积变量防止溢出
 *
 * 安全限制：
 * - 最小质押持续时间（minStakingDuration = 30分钟）：防止刷奖励
 * - 重入保护（ReentrancyGuard）：防止 claimReward 时的重入攻击
 * - 紧急提取 timelock（emergencyWithdrawTimelock = 48小时）：防止恶意 owner 提取
 * - 暂停机制（paused）：紧急情况下暂停全部用户操作
 *
 * 典型用户流程：
 * 1. 授权合约转移NFT（approve/setApprovalForAll）
 * 2. 调用 stakeNFT(tokenId) 质押NFT
 * 3. 等待若干时间（合约持续更新 globalRewardPerWeight）
 * 4. 调用 claimReward() 领取累计奖励
 * 5. 30分钟锁仓期后调用 unstakeNFT(tokenId) 解除质押
 *
 * 合约升级：
 * - UUPS 可升级模式，需 onlyOwner 授权升级
 * - 所有状态变量均在 storage 存储，升级后保留
 */
contract Staking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    uint256 public minStakingDuration = 30 minutes;
    uint256 public rewardRate = 100; // 万分比 (1% = 100/10000)
    uint256 public maxRewardRate = 200; // 最大奖励率2%
    uint256 public rateStep = 10; // 调整步长0.1%

    uint256 public totalStakedNFTs;
    uint256 public totalWeightedNFTs;
    
    // 核心优化：全局累积的每单位权重奖励
    // 每次 calculateDailyReward 时增加，用户领取时做差值计算
    uint256 public globalRewardPerWeight;
    
    uint256 public constant REWARD_OVERFLOW_THRESHOLD = 0x8000000000000000000000000000000000000000000000000000000000000000; // ~50% of 2^256
    uint256 public rewardResetCount;

    uint256 public emergencyWithdrawTimelock = 48 hours;
    uint256 public emergencyWithdrawUnlockTime;

    mapping(address => uint256) public pendingRewards;
    uint256 public todayIncomingTokens;
    uint256 public todayRewardAmount;
    uint256 public todayStart;

    // 用户级别累计权重跟踪（优化 getPendingReward / claimReward 的 Gas 消耗）
    mapping(address => uint256) public userStakedWeight;      // 用户质押的NFT总权重
    mapping(address => uint256) private _userSnapshotWeight;   // Σ(accumulatedReward * weight) 每用户
    
    // 用户级别累计快照溢出保护阈值（距离最大值的安全距离）
    uint256 public constant USER_SNAPSHOT_OVERFLOW_THRESHOLD = 158456325028528675187087900672; // ~90% of 2^256

    struct StakingInfo {
        address owner;
        uint256 stakeTime;
        uint256 lastClaimTime;
        uint256 accumulatedReward; // 记录该 NFT 上次结算时的 globalRewardPerWeight 快照
        bool isRare;
        uint8 level; // 添加等级字段，用于计算权重
    }

    mapping(uint256 => StakingInfo) public stakingInfo;
    mapping(address => uint256[]) public userStakedNFTs;
    mapping(address => bool) public isStakingUser;
    mapping(address => uint256) public stakingUserIndex;
    address[] public stakingUsers;
    
    // 优化：tokenId 到用户在 userStakedNFTs 数组中的索引映射
    mapping(uint256 => uint256) public tokenIdToUserIndex;

    uint8 public minStakingLevel = 1;
    address public authorizer;
    
    uint256 public constant MAX_NFT_LEVEL = 5;
    
    function _calculateNFTWeight(bool isRare, uint8 level) internal pure returns (uint256) {
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
    uint256 public globalPendingRewards;
    
    bool public paused;
    string public pauseReason;

    event Staked(address indexed user, uint256[] tokenIds);
    event Unstaked(address indexed user, uint256[] tokenIds);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event DailyRewardCalculated(uint256 totalReward, uint256 incrementPerWeight);
    event Paused(address account, string reason);
    event Unpaused(address account);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "Staking: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        
        // 初始化带默认值的参数
        minStakingDuration = 30 minutes;
        rewardRate = 100;
        maxRewardRate = 200;
        rateStep = 10;
        emergencyWithdrawTimelock = 48 hours;
        minStakingLevel = 1;
        
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "Staking: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    function setMinStakingLevel(uint8 _minLevel) external onlyOwnerOrAuthorizer {
        require(_minLevel > 0, "Staking: Minimum level must be at least 1");
        minStakingLevel = _minLevel;
    }

    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "Staking: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier whenNotPaused() {
        require(!paused, "Staking: Paused");
        _;
    }

    function stake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        require(tokenIds.length > 0, "Staking: Empty tokenIds");
        address nftContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftContract != address(0), "Staking: NFT contract not set");
        
        _checkNewDay();
        _autoCalculateDailyReward();

        if (!isStakingUser[msg.sender] && userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = true;
            stakingUserIndex[msg.sender] = stakingUsers.length;
            stakingUsers.push(msg.sender);
        }

        INFT nft = INFT(nftContract);
        require(nft.isApprovedForAll(msg.sender, address(this)), "Staking: Contract not approved for transfer");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Staking: Invalid token ID");
            require(stakingInfo[tokenId].owner == address(0), "Staking: Already staked");
            require(nft.ownerOf(tokenId) == msg.sender, "Staking: Not owner of token");

            // 检查 NFT 等级是否满足质押要求
            uint8 tokenLevel = nft.tokenLevel(tokenId);
            require(tokenLevel >= minStakingLevel, "Staking: NFT level below minimum requirement");

            bool isRareToken = nft.isRare(tokenId);
            nft.safeTransferFrom(msg.sender, address(this), tokenId);

            stakingInfo[tokenId] = StakingInfo({
                owner: msg.sender,
                stakeTime: block.timestamp,
                lastClaimTime: block.timestamp,
                accumulatedReward: globalRewardPerWeight, // 初始化快照为当前全局值
                isRare: isRareToken,
                level: tokenLevel
            });

            uint256 newIndex = userStakedNFTs[msg.sender].length;
            userStakedNFTs[msg.sender].push(tokenId);
            tokenIdToUserIndex[tokenId] = newIndex;
            totalStakedNFTs++;
            uint256 weight = _calculateNFTWeight(isRareToken, tokenLevel);
            totalWeightedNFTs += weight;
            // 更新用户级别累计跟踪
            userStakedWeight[msg.sender] += weight;
            
            uint256 snapshotIncrement = globalRewardPerWeight * weight;
            // 修复：使用 < 而不是 <= 来正确防止溢出
            require(_userSnapshotWeight[msg.sender] < USER_SNAPSHOT_OVERFLOW_THRESHOLD - snapshotIncrement, "Staking: User snapshot overflow imminent");
            _userSnapshotWeight[msg.sender] += snapshotIncrement;
        }
        
        _syncUserWeight(msg.sender);
        emit Staked(msg.sender, tokenIds);
    }

    function unstake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        address nftContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftContract != address(0), "Staking: NFT contract not set");
        INFT nft = INFT(nftContract);

        uint256 totalWeightBefore = userStakedWeight[msg.sender];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Staking: Invalid token ID");
            StakingInfo storage info = stakingInfo[tokenId];
            require(info.owner == msg.sender, "Staking: Not owner");
            require(block.timestamp >= info.stakeTime + minStakingDuration, "Staking: Lock period");

            bool wasRare = info.isRare;
            uint256 weight = _calculateNFTWeight(wasRare, info.level);
            delete stakingInfo[tokenId];
            _removeFromUserStakedNFTs(msg.sender, tokenId);
            totalStakedNFTs--;
            totalWeightedNFTs -= weight;
            // 更新用户级别累计跟踪
            userStakedWeight[msg.sender] -= weight;
            uint256 snapshotDecrement = globalRewardPerWeight * weight;
            require(_userSnapshotWeight[msg.sender] >= snapshotDecrement, "Staking: Snapshot underflow");
            _userSnapshotWeight[msg.sender] -= snapshotDecrement;

            nft.safeTransferFrom(address(this), msg.sender, tokenId);
        }
        
        _syncUserWeight(msg.sender);

        if (userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = false;
            _removeFromStakingUsers(msg.sender);
            
            uint256 totalClaimable = _calcUserPending(msg.sender);
            if (totalClaimable > 0) {
                address rewardTokenContract = IAuthorizer(authorizer).getToken();
                require(rewardTokenContract != address(0), "Staking: Reward token contract not set");
                IERC20 rewardToken = IERC20(rewardTokenContract);
                require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance for unstake");
                rewardToken.safeTransfer(msg.sender, totalClaimable);
                emit RewardClaimed(msg.sender, totalClaimable);
                pendingRewards[msg.sender] = 0;
            }
        }
        emit Unstaked(msg.sender, tokenIds);
    }

    /**
     * @dev 领取奖励（Gas优化：用户级别累计公式计算总量，避免逐NFT计算）
     */
    function claimReward() external whenNotPaused nonReentrant {
        uint256[] storage nfts = userStakedNFTs[msg.sender];
        require(nfts.length > 0, "Staking: No staked NFTs");
        address rewardTokenContract = IAuthorizer(authorizer).getToken();
        require(rewardTokenContract != address(0), "Staking: Reward token not set");

        // O(1) 用户级别公式计算总量
        uint256 totalClaimable = _calcUserPending(msg.sender);
        require(totalClaimable > 0, "Staking: No pending reward");

        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance");
        
        // 重置所有 NFT 的快照为当前全局值（必须遍历以更新 storage）
        for (uint256 i = 0; i < nfts.length; i++) {
            StakingInfo storage info = stakingInfo[nfts[i]];
            if (info.owner == msg.sender) {
                info.accumulatedReward = globalRewardPerWeight;
                info.lastClaimTime = block.timestamp;
            }
        }
        
        // 重置用户级别累计快照
        _userSnapshotWeight[msg.sender] = globalRewardPerWeight * userStakedWeight[msg.sender];
        pendingRewards[msg.sender] = 0;
        
        rewardToken.safeTransfer(msg.sender, totalClaimable);
        
        emit RewardClaimed(msg.sender, totalClaimable);
    }

    // --- 内部核心逻辑 ---

    function _calculatePendingForNFT(StakingInfo storage info) internal view returns (uint256) {
        uint256 weight = _calculateNFTWeight(info.isRare, info.level);
        // 奖励 = (当前全局值 - 上次快照) * 权重 / 精度
        if (globalRewardPerWeight <= info.accumulatedReward) return 0;
        return (globalRewardPerWeight - info.accumulatedReward) * weight / STAKING_REWARD_PRECISION;
    }

    function _settleNFTReward(StakingInfo storage info) internal {
        uint256 reward = _calculatePendingForNFT(info);
        if (reward > 0) {
            pendingRewards[info.owner] += reward;
            info.accumulatedReward = globalRewardPerWeight;
        }
    }

    uint256 public constant STAKING_REWARD_PRECISION = 1e18;

    /**
     * @dev 每日奖励计算（仅增加全局增量，不遍历用户）
     */
    function calculateDailyReward() external whenNotPaused onlyOwnerOrAuthorizer {
        address rewardTokenContract = IAuthorizer(authorizer).getToken();
        require(rewardTokenContract != address(0), "Staking: Reward token contract not set");
        _checkNewDay();
        require(todayRewardAmount == 0, "Staking: Daily reward already calculated");
        _doCalculateDailyReward(rewardTokenContract);
    }

    /**
     * @dev 内部检查是否需要计算每日奖励
     */
    function _shouldCalculateDailyReward(address rewardTokenContract) internal view returns (bool) {
        return rewardTokenContract != address(0) && 
               totalWeightedNFTs > 0;
    }

    /**
     * @dev 核心每日奖励计算逻辑（消除代码重复）
     */
    function _doCalculateDailyReward(address rewardTokenContract) internal {
        if (!_shouldCalculateDailyReward(rewardTokenContract)) return;
        
        IERC20 rewardToken = IERC20(rewardTokenContract);
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        
        uint256 dailyReward = contractBalance * rewardRate / 10000;
        uint256 maxDailyReward = contractBalance / 10;
        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }
        
        if (totalWeightedNFTs > 0 && dailyReward > 0) {
            // 修复：移除 unchecked 块，添加安全检查防止溢出
            uint256 increment = (dailyReward * STAKING_REWARD_PRECISION) / totalWeightedNFTs;
            require(globalRewardPerWeight <= type(uint256).max - increment, "Staking: Reward overflow imminent");
            if (globalRewardPerWeight + increment >= REWARD_OVERFLOW_THRESHOLD) {
                _resetRewardTracking();
            }
            globalRewardPerWeight += increment;
            todayRewardAmount = dailyReward;
            emit DailyRewardCalculated(dailyReward, increment);
        }
    }

    /**
     * @dev 检查并处理globalRewardPerWeight溢出风险
     */
    function _checkRewardOverflow() internal {
        if (globalRewardPerWeight >= REWARD_OVERFLOW_THRESHOLD) {
            _resetRewardTracking();
        }
    }

    /**
     * @dev 重置奖励跟踪（溢出保护）
     */
    function _resetRewardTracking() internal {
        rewardResetCount++;
        
        uint256 batchSize = 100;
        uint256 totalUsers = stakingUsers.length;
        uint256 processed = 0;
        
        while (processed < totalUsers && gasleft() > 200000) {
            uint256 end = processed + batchSize;
            if (end > totalUsers) {
                end = totalUsers;
            }
            
            for (uint256 i = processed; i < end && gasleft() > 200000; i++) {
                address user = stakingUsers[i];
                if (isStakingUser[user]) {
                    uint256 pending = _calcUserPending(user);
                    pendingRewards[user] += pending;
                    _userSnapshotWeight[user] = 0;
                }
            }
            
            processed = end;
        }
        
        globalRewardPerWeight = 0;
        
        if (processed < totalUsers) {
            emit PartialResetWarning(rewardResetCount, processed, totalUsers);
        }
    }
    
    /**
     * @dev 继续未完成的重置操作（公开调用，用于批量处理）
     * @param startIndex 开始索引
     * @param batchSize 批量大小
     */
    function continueResetRewardTracking(uint256 startIndex, uint256 batchSize) external onlyOwnerOrAuthorizer {
        uint256 totalUsers = stakingUsers.length;
        uint256 endIndex = startIndex + batchSize;
        if (endIndex > totalUsers) {
            endIndex = totalUsers;
        }
        
        for (uint256 i = startIndex; i < endIndex; i++) {
            address user = stakingUsers[i];
            if (isStakingUser[user]) {
                uint256 pending = _calcUserPending(user);
                pendingRewards[user] += pending;
                _userSnapshotWeight[user] = 0;
            }
        }
        
        emit ResetContinued(startIndex, endIndex, totalUsers);
    }
    
    event PartialResetWarning(uint256 resetCount, uint256 processedUsers, uint256 totalUsers);
    event ResetContinued(uint256 startIndex, uint256 endIndex, uint256 totalUsers);

    /**
     * @dev 在用户操作时自动触发每日奖励计算
     */
    function _autoCalculateDailyReward() internal {
        _checkNewDay();
        address rewardTokenContract = IAuthorizer(authorizer).getToken();
        _doCalculateDailyReward(rewardTokenContract);
    }

    function _removeFromUserStakedNFTs(address user, uint256 tokenId) internal {
        uint256[] storage nfts = userStakedNFTs[user];
        uint256 removeIndex = tokenIdToUserIndex[tokenId];
        
        // 验证索引有效性：如果 removeIndex 超出范围，或者对应位置的 tokenId 不匹配，说明未质押
        require(removeIndex < nfts.length && nfts[removeIndex] == tokenId, "Staking: Token not in user's staked list");
        
        uint256 lastIndex = nfts.length - 1;
        if (removeIndex != lastIndex) {
            // 将最后一个元素移到当前位置
            uint256 lastTokenId = nfts[lastIndex];
            nfts[removeIndex] = lastTokenId;
            tokenIdToUserIndex[lastTokenId] = removeIndex;
        }
        nfts.pop();
        delete tokenIdToUserIndex[tokenId];
    }

    function _removeFromStakingUsers(address user) internal {
        uint256 index = stakingUserIndex[user];
        uint256 lastIndex = stakingUsers.length - 1;
        
        if (index != lastIndex) {
            address lastUser = stakingUsers[lastIndex];
            stakingUsers[index] = lastUser;
            stakingUserIndex[lastUser] = index;
        }
        
        stakingUsers.pop();
        delete stakingUserIndex[user];
        delete isStakingUser[user];
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0 && _rewardRate <= maxRewardRate, "Staking: Invalid reward rate");
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        require(_maxRewardRate >= rewardRate, "Staking: Max rate must be >= current rate");
        maxRewardRate = _maxRewardRate;
    }

    function setRateStep(uint256 _rateStep) external onlyOwner {
        require(_rateStep > 0, "Staking: Step must be > 0");
        rateStep = _rateStep;
    }

    function recordIncomingTokens(uint256 amount) external onlyOwnerOrAuthorizer {
        _checkNewDay();
        todayIncomingTokens += amount;
    }

    function _checkNewDay() internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingTokens = 0;
            todayRewardAmount = 0;
        }
    }

    function getStakingInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 stakeTime,
        uint256 lastClaimTime,
        uint256 accumulatedReward,
        bool isRare
    ) {
        StakingInfo memory info = stakingInfo[tokenId];
        return (info.owner, info.stakeTime, info.lastClaimTime, info.accumulatedReward, info.isRare);
    }

    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        return userStakedNFTs[user];
    }

    /**
     * @dev 查询待领取奖励（Gas 优化：O(1) 用户级别累计公式，不遍历 NFT 列表）
     */
    function getPendingReward(address user) external view returns (uint256) {
        return _calcUserPending(user);
    }

    /**
     * @dev 内部函数：O(1) 计算用户总待领取奖励
     * 公式：(G - Ai) * Wi / P = (G * ΣWi - Σ(Ai * Wi)) / PRECISION
     * 采用先乘后除方式，避免早期除法导致精度损失
     */
    function _calcUserPending(address user) internal view returns (uint256) {
        uint256 totalWeight = userStakedWeight[user];
        if (totalWeight == 0) return pendingRewards[user];

        uint256 snapshotBase = _userSnapshotWeight[user];
        
        // 修复：移除 unchecked 块，使用安全计算方式
        uint256 rewardBase = globalRewardPerWeight * totalWeight;

        if (rewardBase <= snapshotBase) return pendingRewards[user];
        
        // 修复：添加安全检查防止溢出
        uint256 earnedReward = (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
        return earnedReward + pendingRewards[user];
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
     * @dev 获取用户质押统计（Gas 优化：使用用户级别 O(1) 公式计算待领取奖励）
     * @param user 用户地址
     * @return totalStaked NFT总数
     * @return totalPendingReward 待领取奖励
     * @return rareCount 稀有NFT数量
     * @return normalCount 普通NFT数量
     */
    function getUserStakingStats(address user) external view returns (
        uint256 totalStaked,
        uint256 totalPendingReward,
        uint256 rareCount,
        uint256 normalCount
    ) {
        uint256[] storage nfts = userStakedNFTs[user];
        totalStaked = nfts.length;
        totalPendingReward = _calcUserPending(user);
        rareCount = 0;
        normalCount = 0;
        
        for (uint256 i = 0; i < nfts.length; i++) {
            StakingInfo memory info = stakingInfo[nfts[i]];
            if (info.isRare) {
                rareCount++;
            } else {
                normalCount++;
            }
        }
    }

    /**
     * @dev 获取质押池统计
     * @return totalStakers 质押者总数
     * @return totalNFTs 质押NFT总数
     * @return todayIncoming 今日流入
     */
    function getPoolStats() external view returns (
        uint256 totalStakers,
        uint256 totalNFTs,
        uint256 todayIncoming
    ) {
        totalStakers = stakingUsers.length;
        totalNFTs = totalStakedNFTs;
        todayIncoming = todayIncomingTokens;
    }

    /**
     * @dev 获取用户在质押池中的排名（按质押时间）
     * @param user 用户地址
     * @return rank 排名（从1开始），0表示未质押
     */
    function getUserStakingRank(address user) external view returns (uint256 rank) {
        if (!isStakingUser[user]) {
            return 0;
        }
        uint256 index = stakingUserIndex[user];
        return index + 1;
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= emergencyWithdrawUnlockTime, "Staking: Timelock not expired");
        require(amount > 0, "Staking: Amount must be > 0");
        require(amount <= address(this).balance, "Staking: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Staking: BNB transfer failed");
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= emergencyWithdrawUnlockTime, "Staking: Timelock not expired");
        require(amount > 0, "Staking: Amount must be > 0");
        address rewardTokenContract = IAuthorizer(authorizer).getToken();
        require(rewardTokenContract != address(0), "Staking: Token contract not set");
        IERC20 token = IERC20(rewardTokenContract);
        require(token.balanceOf(address(this)) >= amount, "Staking: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    function setEmergencyWithdrawTimelock(uint256 _timelock) external onlyOwner {
        require(_timelock >= 24 hours, "Staking: Timelock must be at least 24 hours");
        emergencyWithdrawTimelock = _timelock;
    }

    function scheduleEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
    }

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev 同步用户权重到WeightManager
     * @param user 用户地址
     */
<<<<<<< HEAD
    function _syncUserWeight(address user) internal {
=======
    function _syncWeightAfterStake(address user, uint256 tokenId, uint8 level, address nftContract) internal {
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        require(nftDataContract != address(0), "Staking: NFTData contract not set");
        INFTDataInterface(nftDataContract).removeUserNFT(user, tokenId);
        
        address weightManager = IAuthorizer(authorizer).getWeightManager();
        require(weightManager != address(0), "Staking: WeightManager contract not set");
        IWeightManager(weightManager).syncUserWeight(user);
        
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        require(dividendManager != address(0), "Staking: DividendManager contract not set");
        IDividendManager(dividendManager).syncUserWeight(user);
    }

    /**
     * @dev 解除质押后同步权重到WeightManager和DividendManager
     * @param user 用户地址
     * @param tokenId NFT ID
     * @param level NFT等级
     * @param nftContract NFT合约地址
     */
    function _syncWeightAfterUnstake(address user, uint256 tokenId, uint8 level, address nftContract) internal {
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        require(nftDataContract != address(0), "Staking: NFTData contract not set");
        INFTDataInterface(nftDataContract).addUserNFT(user, tokenId);
        
>>>>>>> c8ee94389caa14348e1c0f9b1e4bc3505a30770f
        address weightManager = IAuthorizer(authorizer).getWeightManager();
        require(weightManager != address(0), "Staking: WeightManager contract not set");
        IWeightManager(weightManager).syncUserWeight(user);
        
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        require(dividendManager != address(0), "Staking: DividendManager contract not set");
        IDividendManager(dividendManager).syncUserWeight(user);
    }

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}