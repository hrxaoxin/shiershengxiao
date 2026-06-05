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
    
    // 核心优化：全局累积的每单位权重奖励值
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
    }

    mapping(uint256 => StakingInfo) public stakingInfo;
    mapping(address => uint256[]) public userStakedNFTs;
    mapping(address => bool) public isStakingUser;
    mapping(address => uint256) public stakingUserIndex;
    address[] public stakingUsers;

    uint256 public normalNFTWeight = 66;
    uint256 public rareNFTWeight = 76;
    address public rewardTokenContract;
    address public nftContract;
    address public authorizer;
    address public breedingContract;
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

    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "Staking: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "Staking: Invalid authorizer address");
        authorizer = a;
    }

    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "Staking: Invalid NFT contract address");
        nftContract = _nftContract;
    }

    function setBreedingContract(address _breedingContract) external onlyAuthorized {
        require(_breedingContract != address(0), "Staking: Invalid breeding contract address");
        breedingContract = _breedingContract;
    }

    modifier onlyAuthorized() {
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
            
            // 检查 NFT 是否正在繁殖中
            if (breedingContract != address(0)) {
                require(!IBreeding(breedingContract).isNFTInActiveBreeding(tokenId), "Staking: NFT is in breeding");
            }

            bool isRareToken = nft.isRare(tokenId);
            nft.safeTransferFrom(msg.sender, address(this), tokenId);

            stakingInfo[tokenId] = StakingInfo({
                owner: msg.sender,
                stakeTime: block.timestamp,
                lastClaimTime: block.timestamp,
                accumulatedReward: globalRewardPerWeight, // 初始化快照为当前全局值
                isRare: isRareToken
            });

            userStakedNFTs[msg.sender].push(tokenId);
            totalStakedNFTs++;
            uint256 weight = isRareToken ? rareNFTWeight : normalNFTWeight;
            totalWeightedNFTs += weight;
            // 更新用户级别累计跟踪
            userStakedWeight[msg.sender] += weight;
            
            uint256 snapshotIncrement = globalRewardPerWeight * weight;
            require(_userSnapshotWeight[msg.sender] <= USER_SNAPSHOT_OVERFLOW_THRESHOLD - snapshotIncrement, "Staking: User snapshot overflow imminent");
            _userSnapshotWeight[msg.sender] += snapshotIncrement;
        }
        emit Staked(msg.sender, tokenIds);
    }

    function unstake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        require(nftContract != address(0), "Staking: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        // 先计算并领取当前用户的所有待领取奖励
        uint256 totalClaimable = _calcUserPending(msg.sender);
        if (totalClaimable > 0 && rewardTokenContract != address(0)) {
            IERC20 rewardToken = IERC20(rewardTokenContract);
            require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance for unstake");
            
            // 先领取奖励
            rewardToken.safeTransfer(msg.sender, totalClaimable);
            emit RewardClaimed(msg.sender, totalClaimable);
            
            // 重置用户状态
            uint256[] storage userNFTs = userStakedNFTs[msg.sender];
            for (uint256 j = 0; j < userNFTs.length; j++) {
                StakingInfo storage info = stakingInfo[userNFTs[j]];
                if (info.owner == msg.sender) {
                    info.accumulatedReward = globalRewardPerWeight;
                    info.lastClaimTime = block.timestamp;
                }
            }
            _userSnapshotWeight[msg.sender] = globalRewardPerWeight * userStakedWeight[msg.sender];
            pendingRewards[msg.sender] = 0;
        }
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Staking: Invalid token ID");
            StakingInfo storage info = stakingInfo[tokenId];
            require(info.owner == msg.sender, "Staking: Not owner");
            require(block.timestamp >= info.stakeTime + minStakingDuration, "Staking: Lock period");

            bool wasRare = info.isRare;
            uint256 weight = wasRare ? rareNFTWeight : normalNFTWeight;
            delete stakingInfo[tokenId];
            _removeFromUserStakedNFTs(msg.sender, tokenId);
            totalStakedNFTs--;
            totalWeightedNFTs -= weight;
            // 更新用户级别累计跟踪
            userStakedWeight[msg.sender] -= weight;
            _userSnapshotWeight[msg.sender] -= globalRewardPerWeight * weight;

            nft.safeTransferFrom(address(this), msg.sender, tokenId);
        }

        if (userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = false;
            _removeFromStakingUsers(msg.sender);
        }
        emit Unstaked(msg.sender, tokenIds);
    }

    /**
     * @dev 领取奖励（Gas优化：用户级别累计公式计算总量，避免逐NFT计算）
     */
    function claimReward() external whenNotPaused nonReentrant {
        uint256[] storage nfts = userStakedNFTs[msg.sender];
        require(nfts.length > 0, "Staking: No staked NFTs");
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
        uint256 weight = info.isRare ? rareNFTWeight : normalNFTWeight;
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
    function calculateDailyReward() external whenNotPaused onlyAuthorized {
        require(rewardTokenContract != address(0), "Staking: Reward token contract not set");
        _checkNewDay();
        require(todayRewardAmount == 0, "Staking: Daily reward already calculated");
        _doCalculateDailyReward();
    }

    /**
     * @dev 内部检查是否需要计算每日奖励
     */
    function _shouldCalculateDailyReward() internal view returns (bool) {
        return rewardTokenContract != address(0) && 
               totalWeightedNFTs > 0;
    }

    /**
     * @dev 核心每日奖励计算逻辑（消除代码重复）
     */
    function _doCalculateDailyReward() internal {
        if (!_shouldCalculateDailyReward()) return;
        
        IERC20 rewardToken = IERC20(rewardTokenContract);
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        
        uint256 dailyReward = contractBalance * rewardRate / 10000;
        uint256 maxDailyReward = contractBalance / 10;
        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }
        
        if (totalWeightedNFTs > 0 && dailyReward > 0) {
            uint256 increment = dailyReward * STAKING_REWARD_PRECISION / totalWeightedNFTs;
            // 在累加前检查溢出
            require(globalRewardPerWeight <= type(uint256).max - increment, "Staking: Reward overflow imminent");
            // 检查是否需要重置
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
        
        for (uint256 i = 0; i < stakingUsers.length; i++) {
            address user = stakingUsers[i];
            if (isStakingUser[user]) {
                uint256 pending = _calcUserPending(user);
                pendingRewards[user] += pending;
                _userSnapshotWeight[user] = 0;
            }
        }
        
        globalRewardPerWeight = 0;
    }

    /**
     * @dev 在用户操作时自动触发每日奖励计算
     */
    function _autoCalculateDailyReward() internal {
        _checkNewDay();
        _doCalculateDailyReward();
    }

    function _removeFromUserStakedNFTs(address user, uint256 tokenId) internal {
        uint256[] storage nfts = userStakedNFTs[user];
        bool found = false;
        uint256 removeIndex = 0;
        for (uint256 i = 0; i < nfts.length; i++) {
            if (nfts[i] == tokenId) {
                found = true;
                removeIndex = i;
                break;
            }
        }
        require(found, "Staking: Token not in user's staked list");
        nfts[removeIndex] = nfts[nfts.length - 1];
        nfts.pop();
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

    function recordIncomingTokens(uint256 amount) external onlyAuthorized {
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
     * 公式：Σ(G - Ai) * Wi / P = (G * ΣWi - Σ(Ai * Wi)) / PRECISION
     */
    function _calcUserPending(address user) internal view returns (uint256) {
        uint256 totalWeight = userStakedWeight[user];
        if (totalWeight == 0) return pendingRewards[user];

        uint256 snapshotBase = _userSnapshotWeight[user];

        uint256 rewardBase = globalRewardPerWeight * totalWeight;

        uint256 earnedReward = rewardBase <= snapshotBase ? 0 : (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
        
        return earnedReward + pendingRewards[user];
    }

    function setRewardTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "Staking: Invalid token address");
        rewardTokenContract = _tokenContract;
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
     * @return rank 排名（1开始），0表示未质押
     */
    function getUserStakingRank(address user) external view returns (uint256 rank) {
        if (!isStakingUser[user]) {
            return 0;
        }
        uint256 index = stakingUserIndex[user];
        return index + 1;
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner {
        require(block.timestamp >= emergencyWithdrawUnlockTime, "Staking: Timelock not expired");
        require(amount > 0, "Staking: Amount must be > 0");
        require(amount <= address(this).balance, "Staking: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Staking: BNB transfer failed");
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner {
        require(block.timestamp >= emergencyWithdrawUnlockTime, "Staking: Timelock not expired");
        require(amount > 0, "Staking: Amount must be > 0");
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
}