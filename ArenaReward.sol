// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

/**
 * @title ArenaReward
 * @dev 绔炴妧鍦哄鍔卞悎绾︼紝璐熻矗璧涘濂栧姳鐨勮绠楀拰鍙戞斁
 * 
 * 鏍稿績鑱岃矗锟?
 * 1. 璧涘濂栧姳璁＄畻锛氭牴鎹帺瀹舵帓鍚嶈绠楀鍔卞垎锟?
 * 2. 濂栧姳鍙戞斁锛氬鐞嗙帺瀹堕鍙栬禌瀛ｅ锟?
 * 3. 濂栧姳姹犵鐞嗭細绠＄悊 BNB 鍜屼唬甯佸鍔辨睜
 * 4. 妯℃嫙鐜╁濂栧姳锛氬鐞嗘ā鎷熺帺瀹舵寫鎴樼殑濂栧姳
 * 
 * 濂栧姳鏈哄埗锟?
 * - 璧涘缁撴潫鍚庤绠楀锟?
 * - 鏍规嵁鐜╁鎺掑悕鍒嗛厤濂栧姳锟?
 * - 鏀寔 BNB 鍜屼唬甯佷袱绉嶅鍔辩被锟?
 * - 濂栧姳鐜囧彲閰嶇疆锛屽奖鍝嶅鍔卞垎閰嶆瘮锟?
 * 
 * 涓庡叾浠栧悎绾︾殑浜や簰锟?
 * - ArenaRanking / ArenaRankingManager锛氳幏鍙栬禌瀛ｆ暟鎹拰鐜╁鎺掑悕
 * - ArenaLeaderboard锛氳幏鍙栨帓琛屾鏁版嵁
 * - Token 鍚堢害锛氬鐞嗕唬甯佽浆锟?
 * 
 * 瀹夊叏鏈哄埗锟?
 * - ReentrancyGuard锛氶槻姝㈤噸鍏ユ敾锟?
 * - Pausable锛氬彲鏆傚仠鎵€鏈夋搷锟?
 * 
 * 鏉冮檺鎺у埗锟?
 * - onlyOwner锛氭殏鍋滃悎绾︺€佽缃弬锟?
 * - onlyAuthorized锛氳绠楀鍔便€佽缃悎绾﹀湴鍧€
 */
contract ArenaReward is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 璧涘濂栧姳淇℃伅缁撴瀯锟?
     * @param rewardPool BNB 濂栧姳锟?
     * @param tokenRewardPool 浠ｅ竵濂栧姳锟?
     * @param pendingRewards 寰呭彂鏀惧锟?
     * @param rewardCalculated 濂栧姳鏄惁宸茶锟?
     * @param totalDistributed 宸插彂鏀惧鍔辨€婚
     */
    struct SeasonRewardInfo {
        uint256 rewardPool;
        uint256 tokenRewardPool;
        uint256 pendingRewards;
        bool rewardCalculated;
        uint256 totalDistributed;
    }

    /**
     * @dev 绔炴妧鍦烘帓鍚嶇鐞嗗悎绾﹀湴鍧€
     */
    address public arenaRankingManagerContract;
    /**
     * @dev 浠ｅ竵鍚堢害鍦板潃
     */
    address public tokenContract;
    /**
     * @dev 妯℃嫙鐜╁濂栧姳鎺ユ敹鍦板潃
     */
    address public mockRewardRecipient;
    /**
     * @dev 鎺堟潈鍚堢害鍦板潃
     */
    address public authorizer;
    /**
     * @dev 濂栧姳绫诲瀷锟? = BNB, 1 = 浠ｅ竵
     */
    uint8 public rewardType;
    
    /**
     * @dev 浠婃棩濂栧姳閲戦
     */
    uint256 public todayRewardAmount;
    /**
     * @dev 濂栧姳鐜囷紙鐧惧垎姣旓級
     */
    uint256 public rewardRate = 100;
    /**
     * @dev 鏈€澶у鍔辩巼
     */
    uint256 public maxRewardRate = 200;
    /**
     * @dev 濂栧姳鐜囨锟?
     */
    uint256 public rateStep = 10;
    
    /**
     * @dev 浠婃棩寮€濮嬫椂锟?
     */
    uint256 public todayStart;
    /**
     * @dev 浠婃棩鏀跺叆濂栧姳
     */
    uint256 public todayIncomingReward;
    
    /**
     * @dev 璧涘濂栧姳淇℃伅鏄犲皠
     */
    mapping(uint256 => SeasonRewardInfo) public seasonRewards;
    /**
     * @dev 鐜╁璧涘濂栧姳鏄犲皠
     */
    mapping(uint256 => mapping(address => uint256)) public playerSeasonRewards;
    /**
     * @dev 鐜╁濂栧姳棰嗗彇鐘舵€佹槧锟?
     */
    mapping(uint256 => mapping(address => bool)) public claimedRewards;
    
    /**
     * @dev 璧涘濂栧姳璁＄畻浜嬩欢
     */
    event SeasonRewardsCalculated(uint256 seasonId, uint256 totalReward, uint256 distributed);
    /**
     * @dev 濂栧姳棰嗗彇浜嬩欢
     */
    event RewardClaimed(address player, uint256 seasonId, uint256 amount);
    /**
     * @dev 妯℃嫙鐜╁濂栧姳鍙戞斁浜嬩欢
     */
    event MockRewardDistributed(address recipient, uint256 amount, uint256 seasonId);
    /**
     * @dev 濂栧姳娣诲姞浜嬩欢
     */
    event RewardAdded(uint256 amount);
    /**
     * @dev 绱ф€ユ彁鍙栦簨锟?
     */
    event EmergencyWithdraw(address recipient, uint256 amount);

    /**
     * @dev 鎺堟潈妫€鏌ヤ慨楗板櫒
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == arenaRankingManagerContract, "ArenaReward: Not authorized");
        _;
    }

    /**
     * @dev 鍒濆鍖栧嚱锟?
     * @param _arenaRankingManagerContract 绔炴妧鍦烘帓鍚嶇鐞嗗悎绾﹀湴鍧€
     * @param _tokenContract 浠ｅ竵鍚堢害鍦板潃
     * @param _authorizer 鎺堟潈鍚堢害鍦板潃
     */
    function initialize(address _arenaRankingManagerContract, address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        arenaRankingManagerContract = _arenaRankingManagerContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
        rewardType = 1;
    }
    
    /**
     * @dev 璁剧疆鎺堟潈鍚堢害鍦板潃
     * @param _authorizer 鎺堟潈鍚堢害鍦板潃
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaReward: Invalid authorizer address");
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS 鍗囩骇鎺堟潈
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 鏆傚仠鍚堢害
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 鍙栨秷鏆傚仠鍚堢害
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 璁剧疆绔炴妧鍦烘帓鍚嶇鐞嗗悎绾﹀湴鍧€
     * @param _arenaRankingManagerContract 绔炴妧鍦烘帓鍚嶇鐞嗗悎绾﹀湴鍧€
     */
    function setArenaRankingManagerContract(address _arenaRankingManagerContract) external onlyOwnerOrAuthorizer {
        arenaRankingManagerContract = _arenaRankingManagerContract;
    }

    /**
     * @dev 璁剧疆浠ｅ竵鍚堢害鍦板潃
     * @param _tokenContract 浠ｅ竵鍚堢害鍦板潃
     */
    function setTokenContract(address _tokenContract) external onlyOwnerOrAuthorizer {
        tokenContract = _tokenContract;
    }

    /**
     * @dev 璁剧疆妯℃嫙鐜╁濂栧姳鎺ユ敹鍦板潃
     * @param recipient 鎺ユ敹鍦板潃
     */
    function setMockRewardRecipient(address recipient) external onlyOwner {
        mockRewardRecipient = recipient;
    }

    /**
     * @dev 璁＄畻璧涘濂栧姳
     * @param seasonId 璧涘 ID
     */
    function calculateSeasonRewards(uint256 seasonId) external onlyOwnerOrAuthorizer whenNotPaused nonReentrant {
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

    /**
     * @dev 鍐呴儴鍑芥暟锛氳幏鍙栬禌瀛ｆ暟锟?
     * @param seasonId 璧涘 ID
     * @return rewardPool BNB 濂栧姳锟? tokenRewardPool 浠ｅ竵濂栧姳锟? totalPlayers 鎬荤帺瀹舵暟
     */
    function _getSeasonData(uint256 seasonId) internal view returns (uint256, uint256, uint256) {
        return IArenaRanking(arenaRankingManagerContract).getSeasonRewardData(seasonId);
    }

    /**
     * @dev 鍐呴儴鍑芥暟锛氳绠楁ā鎷熺帺瀹跺锟?
     * @param seasonId 璧涘 ID
     * @param totalReward 鎬诲鍔遍噾锟?
     * @return 妯℃嫙鐜╁濂栧姳鎬婚
     */
    function _calculateMockRewards(uint256 seasonId, uint256 totalReward) internal view returns (uint256) {
        address[] memory rankings = IArenaRanking(arenaRankingManagerContract).getSeasonRankings(seasonId);
        uint256 totalPlayers = rankings.length;
        uint256 mockRewardTotal = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = rankings[i];
            if (IArenaRanking(arenaRankingManagerContract).isMockPlayer(player)) {
                uint256 rank = i + 1;
                uint256 reward = ArenaRankingLib.calculateRankReward(rank, totalReward, totalPlayers);
                mockRewardTotal += reward;
            }
        }
        
        return mockRewardTotal;
    }

    /**
     * @dev 鍐呴儴鍑芥暟锛氳绠楃湡瀹炵帺瀹跺锟?
     * @param seasonId 璧涘 ID
     * @param totalReward 鎬诲鍔遍噾锟?
     * @param mockRewardTotal 妯℃嫙鐜╁濂栧姳鎬婚
     * @return 宸插垎閰嶅鍔辨€婚
     */
    function _calculateRealPlayerRewards(uint256 seasonId, uint256 totalReward, uint256 mockRewardTotal) internal returns (uint256) {
        address[] memory rankings = IArenaRanking(arenaRankingManagerContract).getSeasonRankings(seasonId);
        uint256 totalPlayers = rankings.length;
        uint256 totalRealPlayers = IArenaRanking(arenaRankingManagerContract).countRealPlayers(seasonId);
        uint256 realPlayerRewardPool = totalReward - mockRewardTotal;
        uint256 distributed = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = rankings[i];
            if (IArenaRanking(arenaRankingManagerContract).isMockPlayer(player)) {
                continue;
            }
            
            uint256 rank = IArenaRanking(arenaRankingManagerContract).getRealPlayerRank(seasonId, i);
            uint256 rankReward = ArenaRankingLib.calculateRankReward(rank, realPlayerRewardPool, totalRealPlayers);
            playerSeasonRewards[seasonId][player] = rankReward;
            distributed += rankReward;
        }
        
        return distributed;
    }

    /**
     * @dev 鍐呴儴鍑芥暟锛氬彂鏀炬ā鎷熺帺瀹跺锟?
     * @param amount 濂栧姳閲戦
     */
    function _distributeMockReward(uint256 amount) internal {
        if (rewardType == 0) {
            (bool success, ) = payable(mockRewardRecipient).call{value: amount}("");
            require(success, "ArenaReward: Mock reward transfer failed");
        } else {
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            SafeERC20.safeTransfer(IERC20(tokenContract), mockRewardRecipient, amount);
        }
    }

    /**
     * @dev 棰嗗彇璧涘濂栧姳
     * @param seasonId 璧涘 ID
     */
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
            // 淇锛氫娇锟?safeTransfer 鏇夸唬鏅拷?transfer锛岀‘淇濆畨锟?
            token.safeTransfer(msg.sender, reward);
        }
        
        emit RewardClaimed(msg.sender, seasonId, reward);
    }

    /**
     * @dev 棰嗗彇褰撳墠璧涘濂栧姳锛堥噸杞斤級
     */
    function claimSeasonReward() external nonReentrant whenNotPaused {
        uint256 currentSeasonId = IArenaRanking(arenaRankingManagerContract).currentSeasonId();
        _claimRewardFor(msg.sender, currentSeasonId);
    }

    /**
     * @dev 棰嗗彇鎸囧畾璧涘濂栧姳锛堝彲浠ｉ锟?
     * @param player 鐜╁鍦板潃
     * @param seasonId 璧涘 ID
     * @return 棰嗗彇鐨勫鍔遍噾锟?
     */
    function claimSeasonReward(address player, uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        require(player != address(0), "ArenaReward: Invalid player address");
        require(seasonId > 0, "ArenaReward: Invalid season ID");
        require(msg.sender == player || msg.sender == authorizer || msg.sender == owner(),
            "ArenaReward: Not authorized to claim for this player");
        return _claimRewardFor(player, seasonId);
    }

    /**
     * @dev 鍐呴儴鍑芥暟锛氫负鎸囧畾鐜╁棰嗗彇鎸囧畾璧涘濂栧姳
     * @param player 鐜╁鍦板潃
     * @param seasonId 璧涘 ID
     * @return 棰嗗彇鐨勫鍔遍噾锟?
     */
    function _claimRewardFor(address player, uint256 seasonId) internal returns (uint256) {
        require(seasonRewards[seasonId].rewardCalculated, "ArenaReward: Rewards not calculated");
        require(!claimedRewards[seasonId][player], "ArenaReward: Reward already claimed");

        uint256 reward = playerSeasonRewards[seasonId][player];
        require(reward > 0, "ArenaReward: No reward to claim");

        claimedRewards[seasonId][player] = true;

        if (rewardType == 0) {
            require(address(this).balance >= reward, "ArenaReward: Insufficient balance");
            (bool success, ) = payable(player).call{value: reward}("");
            require(success, "ArenaReward: BNB transfer failed");
        } else {
            require(tokenContract != address(0), "ArenaReward: Token contract not set");
            IERC20 token = IERC20(tokenContract);
            require(token.balanceOf(address(this)) >= reward, "ArenaReward: Insufficient token balance");
            token.safeTransfer(player, reward);
        }

        emit RewardClaimed(player, seasonId, reward);
        return reward;
    }

    /**
     * @dev 鑾峰彇鎸囧畾璧涘鐨勫緟棰嗗彇濂栧姳锛堣皟鐢ㄨ€呰嚜宸憋級
     * @param seasonId 璧涘 ID
     * @return 寰呴鍙栧鍔遍噾锟?
     */
    function getPendingRewardsBySeason(uint256 seasonId) external view returns (uint256) {
        if (!seasonRewards[seasonId].rewardCalculated) return 0;
        if (claimedRewards[seasonId][msg.sender]) return 0;
        return playerSeasonRewards[seasonId][msg.sender];
    }

    /**
     * @dev 鑾峰彇鎸囧畾鐜╁鍦ㄦ寚瀹氳禌瀛ｇ殑寰呴鍙栧锟?
     * @param player 鐜╁鍦板潃
     * @param seasonId 璧涘 ID
     * @return 寰呴鍙栧鍔遍噾锟?
     */
    function getPendingRewardsByPlayer(address player, uint256 seasonId) external view returns (uint256) {
        if (!seasonRewards[seasonId].rewardCalculated) return 0;
        if (claimedRewards[seasonId][player]) return 0;
        return playerSeasonRewards[seasonId][player];
    }

    /**
     * @dev 鑾峰彇鐜╁鎵€鏈夎禌瀛ｇ殑寰呴鍙栧鍔辨€婚
     * @param player 鐜╁鍦板潃
     * @return 寰呴鍙栧鍔辨€婚
     */
    function getTotalPendingRewards(address player) external view returns (uint256) {
        uint256 currentSeasonId = IArenaRanking(arenaRankingManagerContract).currentSeasonId();
        uint256 total = 0;
        
        for (uint256 i = 1; i <= currentSeasonId; i++) {
            if (seasonRewards[i].rewardCalculated && !claimedRewards[i][player]) {
                total += playerSeasonRewards[i][player];
            }
        }
        
        return total;
    }

    function addRewardToPool() external payable onlyOwnerOrAuthorizer {
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
        // 淇锛氫娇锟?safeTransfer 鏇夸唬鏅拷?transfer锛岀‘淇濆畨锟?
        token.safeTransfer(owner(), amount);
        emit EmergencyWithdraw(owner(), amount);
    }

    function isRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        return claimedRewards[seasonId][player];
    }

    function calculateRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaReward: Rank must be > 0");
        uint256 currentSeasonId = IArenaRanking(arenaRankingManagerContract).currentSeasonId();
        (uint256 rewardPool, , uint256 totalPlayers) = IArenaRanking(arenaRankingManagerContract).getSeasonRewardData(currentSeasonId);
        uint256 totalRealPlayers = IArenaRanking(arenaRankingManagerContract).countRealPlayers(currentSeasonId);
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

    function checkNewDay() external onlyOwnerOrAuthorizer {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;

        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingReward = 0;
            todayRewardAmount = 0;
            _adjustRewardRate();
        }
    }

    function updateTodayRewardAmount(uint256 amount) external onlyOwnerOrAuthorizer {
        todayRewardAmount = amount;
    }

    function updateTodayIncomingReward(uint256 amount) external onlyOwnerOrAuthorizer {
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