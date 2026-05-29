// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";

/**
 * @title Staking
 * @dev NFT质押合约（优化版：支持大规模用户，实时奖励计算）
 */
contract Staking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
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
    address[] public stakingUsers;
    mapping(address => bool) public isStakingUser;

    uint256 public normalNFTWeight = 66;
    uint256 public rareNFTWeight = 76;
    address public rewardTokenContract;
    address public nftContract;
    address public authorizer;
    
    bool public paused;
    string public pauseReason;

    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    function setNFTContract(address _nftContract) external onlyAuthorized {
        nftContract = _nftContract;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "Staking: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    event Staked(address indexed user, uint256[] tokenIds);
    event Unstaked(address indexed user, uint256[] tokenIds);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event DailyRewardCalculated(uint256 totalReward, uint256 incrementPerWeight);
    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "Staking: Paused");
        _;
    }

    function stake(uint256[] calldata tokenIds) external whenNotPaused {
        require(tokenIds.length > 0, "Staking: Empty tokenIds");
        require(nftContract != address(0), "Staking: NFT contract not set");
        
        _checkNewDay();
        _autoCalculateDailyReward();

        if (!isStakingUser[msg.sender] && userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = true;
            stakingUsers.push(msg.sender);
        }

        INFT nft = INFT(nftContract);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakingInfo[tokenId].owner == address(0), "Staking: Already staked");

            bool isRareToken = nft.isRare(tokenId);
            nft.transferFrom(msg.sender, address(this), tokenId);

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

    function unstake(uint256[] calldata tokenIds) external whenNotPaused {
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

            nft.transferFrom(address(this), msg.sender, tokenId);
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
    function claimReward() external whenNotPaused {
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
        require(rewardTokenContract != address(0), "Staking: Reward token not set");
        
        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance");
        
        pendingRewards[msg.sender] = 0;
        
        require(rewardToken.transfer(msg.sender, totalClaimable), "Staking: Transfer failed");
        
        emit RewardClaimed(msg.sender, totalClaimable);
    }

    // --- 内部核心逻辑 ---

    function _calculatePendingForNFT(StakingInfo storage info) internal view returns (uint256) {
        uint256 weight = info.isRare ? rareNFTWeight : normalNFTWeight;
        // 奖励 = (当前全局值 - 上次快照) * 权重
        if (globalRewardPerWeight <= info.accumulatedReward) return 0;
        return (globalRewardPerWeight - info.accumulatedReward) * weight;
    }

    function _settleNFTReward(StakingInfo storage info) internal {
        uint256 reward = _calculatePendingForNFT(info);
        if (reward > 0) {
            pendingRewards[info.owner] += reward;
            info.accumulatedReward = globalRewardPerWeight;
        }
    }

    /**
     * @dev 每日奖励计算（仅增加全局增量，不遍历用户）
     */
    function calculateDailyReward() external whenNotPaused {
        _checkNewDay();
        
        if (_shouldCalculateDailyReward()) {
            IERC20 rewardToken = IERC20(rewardTokenContract);
            uint256 contractBalance = rewardToken.balanceOf(address(this));
            
            uint256 dailyReward = contractBalance * rewardRate / 10000;
            
            if (totalWeightedNFTs > 0 && dailyReward > 0) {
                uint256 increment = dailyReward / totalWeightedNFTs;
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
               totalWeightedNFTs > 0 && 
               todayRewardAmount == 0;
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
                uint256 increment = dailyReward / totalWeightedNFTs;
                globalRewardPerWeight += increment;
                todayRewardAmount = dailyReward;
                emit DailyRewardCalculated(dailyReward, increment);
            }
        }
    }

    function _removeFromUserStakedNFTs(address user, uint256 tokenId) internal {
        uint256[] storage nfts = userStakedNFTs[user];
        for (uint256 i = 0; i < nfts.length; i++) {
            if (nfts[i] == tokenId) {
                nfts[i] = nfts[nfts.length - 1];
                nfts.pop();
                break;
            }
        }
    }

    function _removeFromStakingUsers(address user) internal {
        for (uint256 i = 0; i < stakingUsers.length; i++) {
            if (stakingUsers[i] == user) {
                stakingUsers[i] = stakingUsers[stakingUsers.length - 1];
                stakingUsers.pop();
                break;
            }
        }
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
}