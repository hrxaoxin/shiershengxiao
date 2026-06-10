// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

contract ArenaReward is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    struct SeasonRewardInfo {
        uint256 rewardPool;
        uint256 tokenRewardPool;
        uint256 pendingRewards;
        bool rewardCalculated;
        uint256 totalDistributed;
    }

    address public rankingContract;
    address public tokenContract;
    address public mockRewardRecipient;
    address public authorizer;
    uint8 public rewardType;
    
    uint256 public todayRewardAmount;
    uint256 public rewardRate = 100;
    uint256 public maxRewardRate = 200;
    uint256 public rateStep = 10;
    
    uint256 public todayStart;
    uint256 public todayIncomingReward;
    
    mapping(uint256 => SeasonRewardInfo) public seasonRewards;
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    mapping(uint256 => mapping(address => bool)) public claimedRewards;
    
    event SeasonRewardsCalculated(uint256 seasonId, uint256 totalReward, uint256 distributed);
    event RewardClaimed(address player, uint256 seasonId, uint256 amount);
    event MockRewardDistributed(address recipient, uint256 amount, uint256 seasonId);
    event RewardAdded(uint256 amount);
    event EmergencyWithdraw(address recipient, uint256 amount);

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == rankingContract, "ArenaReward: Not authorized");
        _;
    }

    function initialize(address _rankingContract, address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        rankingContract = _rankingContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
        rewardType = 0;
    }
    
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaReward: Invalid authorizer address");
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRankingContract(address a) external onlyAuthorized {
        rankingContract = a;
    }

    function setTokenContract(address a) external onlyAuthorized {
        tokenContract = a;
    }

    function setMockRewardRecipient(address recipient) external onlyOwner {
        mockRewardRecipient = recipient;
    }

    function calculateSeasonRewards(uint256 seasonId) external onlyAuthorized whenNotPaused {
        require(!seasonRewards[seasonId].rewardCalculated, "ArenaReward: Already calculated");
        
        (uint256 rewardPool, uint256 tokenRewardPool, uint256 totalPlayers) = _getSeasonData(seasonId);
        require(rewardPool + tokenRewardPool > 0, "ArenaReward: No reward in pool");
        
        SeasonRewardInfo storage seasonReward = seasonRewards[seasonId];
        seasonReward.rewardPool = rewardPool;
        seasonReward.tokenRewardPool = tokenRewardPool;
        
        uint256 totalReward = rewardPool;
        if (rewardType == 1) {
            totalReward = tokenRewardPool;
        }
        
        uint256 mockRewardTotal = _calculateMockRewards(seasonId, totalReward);
        uint256 distributed = _calculateRealPlayerRewards(seasonId, totalReward, mockRewardTotal);
        
        if (mockRewardTotal > 0 && mockRewardRecipient != address(0)) {
            _distributeMockReward(mockRewardTotal);
            emit MockRewardDistributed(mockRewardRecipient, mockRewardTotal, seasonId);
        }
        
        seasonReward.pendingRewards += distributed;
        seasonReward.rewardCalculated = true;
        seasonReward.totalDistributed = distributed;
        
        emit SeasonRewardsCalculated(seasonId, totalReward, distributed);
    }

    function _getSeasonData(uint256 seasonId) internal view returns (uint256, uint256, uint256) {
        return IArenaRanking(rankingContract).getSeasonRewardData(seasonId);
    }

    function _calculateMockRewards(uint256 seasonId, uint256 totalReward) internal view returns (uint256) {
        address[] memory rankings = IArenaRanking(rankingContract).getSeasonRankings(seasonId);
        uint256 totalPlayers = rankings.length;
        uint256 mockRewardTotal = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = rankings[i];
            if (IArenaRanking(rankingContract).isMockPlayer(player)) {
                uint256 rank = i + 1;
                uint256 reward = ArenaRankingLib.calculateRankReward(rank, totalReward, totalPlayers);
                mockRewardTotal += reward;
            }
        }
        
        return mockRewardTotal;
    }

    function _calculateRealPlayerRewards(uint256 seasonId, uint256 totalReward, uint256 mockRewardTotal) internal returns (uint256) {
        address[] memory rankings = IArenaRanking(rankingContract).getSeasonRankings(seasonId);
        uint256 totalPlayers = rankings.length;
        uint256 totalRealPlayers = IArenaRanking(rankingContract).countRealPlayers(seasonId);
        uint256 realPlayerRewardPool = totalReward - mockRewardTotal;
        uint256 distributed = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = rankings[i];
            if (IArenaRanking(rankingContract).isMockPlayer(player)) {
                continue;
            }
            
            uint256 rank = IArenaRanking(rankingContract).getRealPlayerRank(seasonId, i);
            uint256 rankReward = ArenaRankingLib.calculateRankReward(rank, realPlayerRewardPool, totalRealPlayers);
            playerSeasonRewards[seasonId][player] = rankReward;
            distributed += rankReward;
        }
        
        return distributed;
    }

    function _distributeMockReward(uint256 amount) internal {
        if (rewardType == 0) {
            (bool success, ) = payable(mockRewardRecipient).call{value: amount}("");
            require(success, "ArenaReward: Mock reward transfer failed");
        } else {
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            require(IERC20(tokenContract).transfer(mockRewardRecipient, amount), "ArenaReward: Token transfer failed");
        }
    }

    function claimReward(uint256 seasonId) external nonReentrant whenNotPaused {
        require(seasonRewards[seasonId].rewardCalculated, "ArenaReward: Rewards not calculated");
        require(!claimedRewards[seasonId][msg.sender], "ArenaReward: Already claimed");
        
        uint256 reward = playerSeasonRewards[seasonId][msg.sender];
        require(reward > 0, "ArenaReward: No reward to claim");
        
        claimedRewards[seasonId][msg.sender] = true;
        
        if (rewardType == 0) {
            require(address(this).balance >= reward, "ArenaReward: Insufficient balance");
            (bool success, ) = payable(msg.sender).call{value: reward}("");
            require(success, "ArenaReward: Transfer failed");
        } else {
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            IERC20 token = IERC20(tokenContract);
            require(token.balanceOf(address(this)) >= reward, "ArenaReward: Insufficient token balance");
            require(token.transfer(msg.sender, reward), "ArenaReward: Token transfer failed");
        }
        
        emit RewardClaimed(msg.sender, seasonId, reward);
    }

    function claimSeasonReward() external nonReentrant whenNotPaused {
        uint256 currentSeasonId = IArenaRanking(rankingContract).currentSeasonId();
        this.claimReward(currentSeasonId);
    }

    function claimSeasonReward(address player, uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        require(player != address(0), "ArenaReward: Invalid player address");
        require(seasonId > 0, "ArenaReward: Invalid season ID");
        require(!claimedRewards[seasonId][player], "ArenaReward: Reward already claimed");
        require(seasonRewards[seasonId].rewardCalculated, "ArenaReward: Rewards not calculated");
        
        uint256 reward = playerSeasonRewards[seasonId][player];
        require(reward > 0, "ArenaReward: No reward to claim");
        
        claimedRewards[seasonId][player] = true;
        
        if (rewardType == 0) {
            (bool success, ) = payable(player).call{value: reward}("");
            require(success, "ArenaReward: BNB transfer failed");
        } else {
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            IERC20(tokenContract).transfer(player, reward);
        }
        
        emit RewardClaimed(player, seasonId, reward);
        return reward;
    }

    function getPendingRewardsBySeason(uint256 seasonId) external view returns (uint256) {
        if (!seasonRewards[seasonId].rewardCalculated) return 0;
        if (claimedRewards[seasonId][msg.sender]) return 0;
        return playerSeasonRewards[seasonId][msg.sender];
    }

    function getPendingRewardsByPlayer(address player, uint256 seasonId) external view returns (uint256) {
        if (!seasonRewards[seasonId].rewardCalculated) return 0;
        if (claimedRewards[seasonId][player]) return 0;
        return playerSeasonRewards[seasonId][player];
    }

    function getTotalPendingRewards(address player) external view returns (uint256) {
        uint256 currentSeasonId = IArenaRanking(rankingContract).currentSeasonId();
        uint256 total = 0;
        
        for (uint256 i = 1; i <= currentSeasonId; i++) {
            if (seasonRewards[i].rewardCalculated && !claimedRewards[i][player]) {
                total += playerSeasonRewards[i][player];
            }
        }
        
        return total;
    }

    function addRewardToPool() external payable onlyAuthorized {
        emit RewardAdded(msg.value);
    }

    function emergencyWithdrawBNB() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ArenaReward: Withdraw failed");
        emit EmergencyWithdraw(owner(), balance);
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "ArenaReward: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaReward: Withdraw failed");
        emit EmergencyWithdraw(owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(tokenContract != address(0), "ArenaReward: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "ArenaReward: Insufficient token balance");
        require(token.transfer(owner(), amount), "ArenaReward: Token transfer failed");
        emit EmergencyWithdraw(owner(), amount);
    }

    function isRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        return claimedRewards[seasonId][player];
    }

    function calculateRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaReward: Rank must be > 0");
        uint256 currentSeasonId = IArenaRanking(rankingContract).currentSeasonId();
        (uint256 rewardPool, , uint256 totalPlayers) = IArenaRanking(rankingContract).getSeasonRewardData(currentSeasonId);
        uint256 totalRealPlayers = IArenaRanking(rankingContract).countRealPlayers(currentSeasonId);
        return ArenaRankingLib.calculateRankReward(rank, rewardPool, totalRealPlayers);
    }

    function getRewardForRank(uint256 rank) external view returns (uint256) {
        return this.calculateRewardForRank(rank);
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        require(rate <= maxRewardRate, "ArenaReward: Rate exceeds max");
        rewardRate = rate;
    }

    function setMaxRewardRate(uint256 maxRate) external onlyOwner {
        maxRewardRate = maxRate;
    }

    function setRateStep(uint256 step) external onlyOwner {
        rateStep = step;
    }

    function setRewardType(uint8 _rewardType) external onlyOwner {
        require(_rewardType == 0 || _rewardType == 1, "ArenaReward: Invalid reward type");
        rewardType = _rewardType;
    }

    function checkNewDay() external onlyAuthorized {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;

        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingReward = 0;
            todayRewardAmount = 0;
            _adjustRewardRate();
        }
    }

    function updateTodayRewardAmount(uint256 amount) external onlyAuthorized {
        todayRewardAmount = amount;
    }

    function updateTodayIncomingReward(uint256 amount) external onlyAuthorized {
        todayIncomingReward += amount;
    }

    function _adjustRewardRate() internal {
        if (todayRewardAmount > 0 && todayIncomingReward > todayRewardAmount) {
            uint256 multiple = todayIncomingReward / todayRewardAmount;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;
            uint256 steps = multiple - 1;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);

            if (newRate != rewardRate) {
                rewardRate = newRate;
            }
        }
    }

    receive() external payable {}
}