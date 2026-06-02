// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";

/**
 * @title Staking
 * @dev NFT质押合约（优化版：支持大规模用户，实时奖励计算）
 */
contract Staking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public minStakingDuration = 30 minutes;
    uint256 public rewardRate = 10; // 万分比 (0.1%)
    uint256 public maxRewardRate = 20;
    uint256 public rateStep = 1;

    uint256 public totalStakedNFTs;
    uint256 public totalWeightedNFTs;
    
    // 核心优化：全局累积的每单位权重奖励值
    // 每次 calculateDailyReward 时增加，用户领取时做差值计算
    uint256 public globalRewardPerWeight;

    mapping(address => uint256) public pendingRewards;
    uint256 public todayIncomingTokens;
    uint256 public todayRewardAmount;
    uint256 public todayStart;

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
        authorizer = a;
    }

    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "Staking: Invalid NFT contract address");
        nftContract = _nftContract;
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
            require(stakingInfo[tokenId].owner == address(0), "Staking: Already staked");
            require(nft.ownerOf(tokenId) == msg.sender, "Staking: Not owner of token");

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
            totalWeightedNFTs += isRareToken ? rareNFTWeight : normalNFTWeight;
        }
        emit Staked(msg.sender, tokenIds);
    }

    function unstake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        require(nftContract != address(0), "Staking: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            StakingInfo storage info = stakingInfo[tokenId];
            require(info.owner == msg.sender, "Staking: Not owner");
            require(block.timestamp >= info.stakeTime + minStakingDuration, "Staking: Lock period");

            // 赎回前先结算该 NFT 的奖励
            _settleNFTReward(info);

            bool wasRare = info.isRare;
            delete stakingInfo[tokenId];
            _removeFromUserStakedNFTs(msg.sender, tokenId);
            totalStakedNFTs--;
            totalWeightedNFTs -= wasRare ? rareNFTWeight : normalNFTWeight;

            nft.safeTransferFrom(address(this), msg.sender, tokenId);
        }

        if (userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = false;
            _removeFromStakingUsers(msg.sender);
        }
        emit Unstaked(msg.sender, tokenIds);
    }

    /**
     * @dev 领取奖励（优化：实时计算，无 Gas 瓶颈）
     */
    function claimReward() external whenNotPaused nonReentrant {
        uint256[] storage nfts = userStakedNFTs[msg.sender];
        require(nfts.length > 0, "Staking: No staked NFTs");
        require(rewardTokenContract != address(0), "Staking: Reward token not set");

        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < nfts.length; i++) {
            StakingInfo storage info = stakingInfo[nfts[i]];
            if (info.owner == msg.sender) {
                totalClaimable += _calculatePendingForNFT(info);
                info.accumulatedReward = globalRewardPerWeight;
                info.lastClaimTime = block.timestamp;
            }
        }

        require(totalClaimable > 0, "Staking: No pending reward");

        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance");
        
        pendingRewards[msg.sender] = 0;
        
        require(rewardToken.transfer(msg.sender, totalClaimable), "Staking: Transfer failed");
        
        emit RewardClaimed(msg.sender, totalClaimable);
    }

    // --- 内部核心逻辑 ---

    function _calculatePendingForNFT(StakingInfo storage info) internal view returns (uint256) {
        uint256 weight = info.isRare ? rareNFTWeight : normalNFTWeight;
        // 奖励 = (当前全局值 - 上次快照) * 权重 / 精度
        if (globalRewardPerWeight <= info.accumulatedReward) return 0;
        return (globalRewardPerWeight - info.accumulatedReward) * weight / REWARD_PRECISION;
    }

    function _settleNFTReward(StakingInfo storage info) internal {
        uint256 reward = _calculatePendingForNFT(info);
        if (reward > 0) {
            pendingRewards[info.owner] += reward;
            info.accumulatedReward = globalRewardPerWeight;
        }
    }

    uint256 public constant REWARD_PRECISION = 1e18;

    /**
     * @dev 每日奖励计算（仅增加全局增量，不遍历用户）
     */
    function calculateDailyReward() external whenNotPaused onlyAuthorized {
        _checkNewDay();
        
        if (_shouldCalculateDailyReward()) {
            IERC20 rewardToken = IERC20(rewardTokenContract);
            uint256 contractBalance = rewardToken.balanceOf(address(this));
            
            uint256 dailyReward = contractBalance * rewardRate / 10000;
            
            if (totalWeightedNFTs > 0 && dailyReward > 0) {
                uint256 increment = dailyReward * REWARD_PRECISION / totalWeightedNFTs;
                globalRewardPerWeight += increment;
                todayRewardAmount = dailyReward;
                emit DailyRewardCalculated(dailyReward, increment);
            }
        }
    }

    /**
     * @dev 内部检查是否需要计算每日奖励
     */
    function _shouldCalculateDailyReward() internal view returns (bool) {
        return rewardTokenContract != address(0) && 
               totalWeightedNFTs > 0;
    }

    /**
     * @dev 在用户操作时自动触发每日奖励计算
     */
    function _autoCalculateDailyReward() internal {
        _checkNewDay();
        if (_shouldCalculateDailyReward()) {
            IERC20 rewardToken = IERC20(rewardTokenContract);
            uint256 contractBalance = rewardToken.balanceOf(address(this));
            
            uint256 dailyReward = contractBalance * rewardRate / 10000;
            
            if (totalWeightedNFTs > 0 && dailyReward > 0) {
                uint256 increment = dailyReward * REWARD_PRECISION / totalWeightedNFTs;
                globalRewardPerWeight += increment;
                todayRewardAmount = dailyReward;
                emit DailyRewardCalculated(dailyReward, increment);
            }
        }
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

    function getPendingReward(address user) external view returns (uint256) {
        uint256[] storage nfts = userStakedNFTs[user];
        uint256 total = 0;
        for (uint256 i = 0; i < nfts.length; i++) {
            total += _calculatePendingForNFT(stakingInfo[nfts[i]]);
        }
        return total;
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
     * @dev 获取用户质押统计
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
        totalPendingReward = 0;
        rareCount = 0;
        normalCount = 0;
        
        for (uint256 i = 0; i < nfts.length; i++) {
            StakingInfo memory info = stakingInfo[nfts[i]];
            totalPendingReward += _calculatePendingForNFT(info);
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

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Staking: Amount must be > 0");
        require(amount <= address(this).balance, "Staking: Insufficient balance");
        payable(owner()).transfer(amount);
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Staking: Amount must be > 0");
        require(rewardTokenContract != address(0), "Staking: Token contract not set");
        IERC20 token = IERC20(rewardTokenContract);
        require(token.balanceOf(address(this)) >= amount, "Staking: Insufficient token balance");
        require(token.transfer(owner(), amount), "Staking: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }
}