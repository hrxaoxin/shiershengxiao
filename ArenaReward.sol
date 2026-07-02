﻿// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./ArenaRankingLib.sol";

/**
 * @title ArenaReward
 * @dev 竞技场奖励合约，负责赛季奖励的计算和发放
 * 
 * 核心功能：
 * 1. 赛季奖励计算：根据玩家排名计算奖励分配
 * 2. 奖励发放：处理玩家领取竞技奖励（LP形式）
 * 3. 奖励池管理：管理 LP 奖励池
 * 4. 模拟玩家奖励：处理虚拟玩家获得的奖励
 * 
 * 奖励机制：
 * - 赛季结束后计算奖励
 * - 根据玩家排名分配奖励
 * - 奖励以LP形式发放，领取时自动兑换为代币+WBNB
 * - 奖励率可配置，影响奖励分配比例
 * 
 * 与其他合约的交互：
 * - ArenaRanking / ArenaRankingManager：获取竞技数据和玩家排名
 * - ArenaLeaderboard：获取排行榜数据
 * - Token 合约：处理代币转账
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * 
 * 权限控制：
 * - onlyOwner：管理合约、设置参数
 * - onlyOwnerOrAuthorizer：计算奖励、设置合约地址
 */
contract ArenaReward is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 赛季奖励信息结构体
     * @param rewardPool BNB 奖励池
     * @param tokenRewardPool 代币奖励池
     * @param pendingRewards 待发放奖励
     * @param rewardCalculated 奖励是否已计算
     * @param totalDistributed 已发放奖励总额
     */
    struct SeasonRewardInfo {
        uint256 rewardPool;
        uint256 tokenRewardPool;
        uint256 pendingRewards;
        bool rewardCalculated;
        uint256 totalDistributed;
    }

    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    
    /**
     * @dev 赛季奖励信息映射
     */
    mapping(uint256 => mapping(uint256 => SeasonRewardInfo)) public seasonRewards;
    /**
     * @dev 玩家赛季奖励映射
     */
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public playerSeasonRewards;
    /**
     * @dev 玩家奖励领取状态映射
     */
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public claimedRewards;
    
    /**
     * @dev 纪元版本号，用于快速重置合约数据（循环复用，MAX_EPOCHS次后回到0）
     */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;

    /**
     * @dev 通过addRewardToPool累积的待分配BNB池
     * @notice 这笔BNB在calculateSeasonRewards时自动分配到当前赛季的rewardPool
     */
    uint256 public pendingBNBPool;

    /**
     * @dev 赛季奖励计算事件
     */
    event SeasonRewardsCalculated(uint256 seasonId, uint256 totalReward, uint256 distributed);
    /**
     * @dev 奖励添加事件
     */
    event RewardAdded(uint256 amount);

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "ArenaReward: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaReward: Not authorized");
        _;
    }

    /// @dev 构造函数：禁用初始化器，防止实现合约被直接部署后被初始化攻击
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(
        address _authorizerAddress
    ) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        authorizer = _authorizerAddress;
        epoch = 1;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaReward: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev UUPS 升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 计算赛季奖励
     * @param seasonId 赛季 ID
     */
    function calculateSeasonRewards(uint256 seasonId) external onlyOwnerOrAuthorizer whenNotPaused nonReentrant {
        uint256 currentEpoch = _currentEpoch();
        require(!seasonRewards[currentEpoch][seasonId].rewardCalculated, "ArenaReward: Already calculated");
        
        (uint256 rewardPool, uint256 tokenRewardPool, uint256 totalPlayers) = _getSeasonData(seasonId);
        
        // 修复：将pendingBNBPool和tokenRewardPool合并到总奖励池中
        uint256 totalRewardPool = rewardPool + tokenRewardPool + pendingBNBPool;
        require(totalRewardPool > 0, "ArenaReward: No reward in pool");
        
        SeasonRewardInfo storage seasonReward = seasonRewards[currentEpoch][seasonId];
        seasonReward.rewardPool = rewardPool;
        seasonReward.tokenRewardPool = tokenRewardPool;
        
        // 使用总奖励池进行分配计算
        uint256 mockRewardTotal = _calculateMockRewards(seasonId, totalRewardPool);
        uint256 distributed = _calculateRealPlayerRewards(seasonId, totalRewardPool, mockRewardTotal);
        
        // 清空pendingBNBPool
        pendingBNBPool = 0;
        
        seasonReward.pendingRewards += distributed;
        seasonReward.rewardCalculated = true;
        seasonReward.totalDistributed = distributed;
        
        emit SeasonRewardsCalculated(seasonId, totalRewardPool, distributed);
    }

    /**
     * @dev 内部函数：获取竞技数据
     * @param seasonId 赛季 ID
     * @return rewardPool BNB 奖励池, tokenRewardPool 代币奖励池, totalPlayers 总玩家数
     */
    function _getSeasonData(uint256 seasonId) internal view returns (uint256, uint256, uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        return IArenaRanking(arenaRankingManager).getSeasonRewardData(seasonId);
    }

    /**
     * @dev 内部函数：计算模拟玩家奖励
     * @param seasonId 赛季 ID
     * @param totalReward 总奖励金额
     * @return 模拟玩家奖励总额
     */
    function _calculateMockRewards(uint256 seasonId, uint256 totalReward) internal view returns (uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        address[] memory rankings = IArenaRanking(arenaRankingManager).getSeasonRankings(seasonId);
        uint256 totalPlayers = rankings.length;
        uint256 mockRewardTotal = 0;
        
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = rankings[i];
            if (IArenaRanking(arenaRankingManager).isMockPlayer(player)) {
                uint256 rank = i + 1;
                uint256 reward = ArenaRankingLib.calculateRankReward(rank, totalReward, totalPlayers);
                mockRewardTotal += reward;
            }
        }
        
        return mockRewardTotal;
    }

    /**
     * @dev 计算模拟玩家奖励（外部调用）
     * @param seasonId 赛季 ID
     * @param totalReward 总奖励金额
     * @return 模拟玩家奖励总额
     */
    function calculateSeasonRewardsMock(uint256 seasonId, uint256 totalReward) external view returns (uint256) {
        return _calculateMockRewards(seasonId, totalReward);
    }

    /**
     * @dev 内部函数：计算真实玩家奖励
     * @param seasonId 赛季 ID
     * @param totalReward 总奖励金额
     * @param mockRewardTotal 模拟玩家奖励总额
     * @return 已分配奖励总额
     */
    function _calculateRealPlayerRewards(uint256 seasonId, uint256 totalReward, uint256 mockRewardTotal) internal returns (uint256) {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        address[] memory rankings = IArenaRanking(arenaRankingManager).getSeasonRankings(seasonId);
        uint256 totalRealPlayers = IArenaRanking(arenaRankingManager).countRealPlayers(seasonId);
        
        uint256 realPlayerRewardPool = mockRewardTotal <= totalReward ? totalReward - mockRewardTotal : 0;
        
        return _distributeRealPlayerRewards(seasonId, rankings, arenaRankingManager, realPlayerRewardPool, totalRealPlayers);
    }

    /**
     * @dev 内部函数：分配真实玩家奖励
     * @param seasonId 赛季 ID
     * @param rankings 排名数组
     * @param arenaRankingManager 排名管理合约地址
     * @param realPlayerRewardPool 真实玩家奖励池
     * @param totalRealPlayers 真实玩家总数
     * @return distributed 已分配的奖励总额
     */
    function _distributeRealPlayerRewards(
        uint256 seasonId,
        address[] memory rankings,
        address arenaRankingManager,
        uint256 realPlayerRewardPool,
        uint256 totalRealPlayers
    ) internal returns (uint256) {
        uint256 distributed = 0;
        for (uint256 i = 0; i < rankings.length; i++) {
            address player = rankings[i];
            if (IArenaRanking(arenaRankingManager).isMockPlayer(player)) {
                continue;
            }
            uint256 rank = IArenaRanking(arenaRankingManager).getRealPlayerRank(seasonId, i);
            uint256 currentEpoch = _currentEpoch();
            uint256 rankReward = ArenaRankingLib.calculateRankReward(rank, realPlayerRewardPool, totalRealPlayers);
            playerSeasonRewards[currentEpoch][seasonId][player] = rankReward;
            distributed += rankReward;
        }
        return distributed;
    }

    /**
     * @dev 获取指定赛季的待领取奖励（调用者自己）
     * @param seasonId 赛季 ID
     * @return 待领取奖励金额
     */
    function getPendingRewardsBySeason(uint256 seasonId) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        if (!seasonRewards[currentEpoch][seasonId].rewardCalculated) return 0;
        if (claimedRewards[currentEpoch][seasonId][msg.sender]) return 0;
        return playerSeasonRewards[currentEpoch][seasonId][msg.sender];
    }

    /**
     * @dev 获取指定玩家在指定赛季的待领取奖励
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     * @return 待领取奖励金额
     */
    function getPendingRewardsByPlayer(address player, uint256 seasonId) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        if (!seasonRewards[currentEpoch][seasonId].rewardCalculated) return 0;
        if (claimedRewards[currentEpoch][seasonId][player]) return 0;
        return playerSeasonRewards[currentEpoch][seasonId][player];
    }

    /**
     * @dev 获取玩家所有赛季的待领取奖励总额
     * @param player 玩家地址
     * @return 待领取奖励总额
     */
    function getTotalPendingRewards(address player) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        uint256 total = 0;
        
        for (uint256 i = 1; i <= currentSeasonId; i++) {
            if (seasonRewards[currentEpoch][i].rewardCalculated && !claimedRewards[currentEpoch][i][player]) {
                total += playerSeasonRewards[currentEpoch][i][player];
            }
        }
        
        return total;
    }

    /**
     * @dev 添加奖励到池中（用于接收BNB）
     * @notice 当合约收到BNB时，暂存到pendingBNBPool，在calculateSeasonRewards时自动分配到赛季奖励池
     */
    function addRewardToPool() external payable onlyOwnerOrAuthorizer {
        pendingBNBPool += msg.value;
        emit RewardAdded(msg.value);
    }

    function isRewardClaimed(address player, uint256 seasonId) external view returns (bool) {
        uint256 currentEpoch = _currentEpoch();
        return claimedRewards[currentEpoch][seasonId][player];
    }

    /**
     * @dev 计算指定排名的奖励
     * @param rank 排名
     * @return 奖励金额
     */
    function calculateRewardForRank(uint256 rank) external view returns (uint256) {
        require(rank > 0, "ArenaReward: Rank must be > 0");
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName("arenaRankingManager");
        uint256 currentSeasonId = IArenaRanking(arenaRankingManager).currentSeasonId();
        (uint256 rewardPool, , uint256 totalPlayers) = IArenaRanking(arenaRankingManager).getSeasonRewardData(currentSeasonId);
        uint256 totalRealPlayers = IArenaRanking(arenaRankingManager).countRealPlayers(currentSeasonId);
        return ArenaRankingLib.calculateRankReward(rank, rewardPool, totalRealPlayers);
    }

    function getRewardForRank(uint256 rank) external view returns (uint256) {
        return this.calculateRewardForRank(rank);
    }

    /**
     * @dev 标记奖励已领取（由 ArenaRewardLP 调用）
     * @param player 玩家地址
     * @param seasonId 赛季 ID
     */
    function markRewardClaimed(address player, uint256 seasonId) external {
        require(msg.sender == IAuthorizer(authorizer).getAddressByName("arenaRewardLP"), "ArenaReward: Only ArenaRewardLP can call");
        uint256 currentEpoch = _currentEpoch();
        claimedRewards[currentEpoch][seasonId][player] = true;
    }

    /**
     * @dev 紧急提取WBNB
     * @param amount WBNB数量
     * @notice 仅限owner调用，用于紧急情况
     */
    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        address wbnb = IAuthorizer(authorizer).getAddressByName("wbnb");
        require(amount > 0, "ArenaReward: Amount must be > 0");
        require(IWBNB(wbnb).balanceOf(address(this)) >= amount, "ArenaReward: Insufficient WBNB");
        
        IWBNB(wbnb).withdraw(amount);
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ArenaReward: BNB transfer failed");
    }

    /**
     * @dev 重置合约数据
     * @notice 清空奖励数据，仅owner或authorizer可调用
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}