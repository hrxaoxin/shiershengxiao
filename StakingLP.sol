// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./StakingLPLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakingLP
 * @dev NFT质押LP奖励合约
 * 
 * 核心功能：
 * 1. LP奖励池管理：接收BNB自动转换为LP
 * 2. LP奖励领取：用户领取累计的LP奖励，自动兑换为代币+WBNB
 * 3. 复利功能：自动复投LP交易手续费
 * 4. 紧急提取：owner紧急提取WBNB
 * 
 * 奖励机制：
 * - 接收BNB后自动一半兑换为代币，一半兑换为WBNB，组成LP
 * - LP按用户质押权重分配给质押用户
 * - 用户领取时LP自动解除为代币+WBNB
 * - LP交易手续费自动复投为更多LP
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - onlyOwner：紧急提取权限控制
 * 
 * 合约升级：
 * - UUPS可升级模式，需onlyOwner授权升级
 */
contract StakingLP is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /** @dev 授权合约地址 */
    address public authorizer;
    
    /** @dev 当前奖励类型 */
    RewardType public rewardType;
    
    /** @dev LP奖励池余额 */
    uint256 public lpRewardPoolBalance;
    /** @dev 代币奖励池余额 */
    uint256 public tokenRewardPoolBalance;
    /** @dev BNB奖励池余额 */
    uint256 public bnbRewardPoolBalance;
    
    /** @dev 滑点保护参数（默认1000 = 10%容差） */
    uint256 private _slippage = 1000;
    
    /** @dev 每日释放比例（万分比，默认1% = 100/10000） */
    uint256 private _rewardRate = 100;
    /** @dev 最大每日释放比例（万分比） */
    uint256 private _maxRewardRate = 500;
    /** @dev 每日最大释放百分比（10% = 100/1000） */
    uint256 private _maxDailyRewardPercent = 100;
    /** @dev 奖励率调整步长（万分比，10 = 0.1%） */
    uint256 private _rateStep = 10;
    
    /** @dev 今日开始时间 */
    uint256 private _todayStart;
    /** @dev 今日已释放奖励金额 */
    uint256 private _todayRewardAmount;
    /** @dev 今日流入代币数量 */
    uint256 private _todayIncomingTokens;
    
    /** @dev 全局奖励累积值（每单位权重的奖励）- 用于LP和TOKEN类型 */
    uint256 public globalRewardPerWeight;
    /** @dev 当前纪元（循环复用，MAX_EPOCHS次后回到0） */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    /** @dev 用户奖励快照权重映射（epoch => 地址 => 用户快照） */
    mapping(uint256 => mapping(address => uint256)) private _userRewardSnapshotWeight;
    
    /** @dev 质押奖励精度缩放因子（1e18） */
    uint256 public constant STAKING_REWARD_PRECISION = 1e18;
    /** @dev 奖励比例精度（万分比） */
    uint256 public constant REWARD_PRECISION = 10000;
    
    /** @dev 总质押权重（从主合约同步） */
    uint256 public totalWeightedNFTs;

    error InvalidParam();
    error Unauthorized();
    error InsufficientLP();
    error InsufficientToken();
    error InsufficientBNB();
    error NoStakedNFTs();
    error SameRewardType();
    error SameDEXType();
    error InvalidDexType();
    error ContractPaused();
    error AlreadyInitialized();
    error SLP_BNBTransferFailed();

    /** @dev LP奖励领取事件 */
    event LPRewardClaimed(address indexed user, uint256 lpAmount);
    /** @dev 代币奖励领取事件 */
    event TokenRewardClaimed(address indexed user, uint256 tokenAmount);
    /** @dev BNB奖励领取事件 */
    event BNBRewardClaimed(address indexed user, uint256 bnbAmount);
    /** @dev 复利执行事件 */
    event FeesCompounded(uint256 lpAmount);
    /** @dev 紧急提取WBNB事件 */
    event EmergencyWBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    /** @dev 奖励类型切换事件 */
    event RewardTypeChanged(RewardType oldType, RewardType newType);
    /** @dev 每日奖励计算事件 */
    event DailyRewardCalculated(uint256 dailyReward, uint256 increment);
    /** @dev 奖励率更新事件 */
    event RewardRateUpdated(uint256 rewardRate);
    /** @dev LP迁移事件 */
    event LPMigrated(uint8 oldDexType, uint8 newDexType, uint256 oldLPAmount, uint256 newLPAmount);
    /** @dev 紧急赎回LP事件 */
    event EmergencyLPRedeemed(uint256 tokenAmount, uint256 wbnbAmount);

    /**
     * @dev 构造函数：禁用初始化器
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        if (_authorizerAddress == address(0)) revert InvalidParam();
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        authorizer = _authorizerAddress;
        rewardType = RewardType.BNB;
        
        _slippage = 1000;
        
        _rewardRate = 100;
        _maxRewardRate = 500;
        _maxDailyRewardPercent = 100;
        _rateStep = 10;
        _todayStart = 0;
        _todayRewardAmount = 0;
        _todayIncomingTokens = 0;
        globalRewardPerWeight = 0;
        totalWeightedNFTs = 0;
        epoch = 1;
    }
    
    

    /**
     * @dev 仅owner或authorizer的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        if (authorizer == address(0)) revert Unauthorized();
        IAuthorizer auth = IAuthorizer(authorizer);
        if (!auth.isSystemContract(msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @dev UUPS升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

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
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        if (_authorizerAddress == address(0)) revert InvalidParam();
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 接收BNB - 根据当前奖励类型处理
     */
    receive() external payable {
        if (msg.value > 0) {
            StakingLPLib.RewardPoolState memory state = _getPoolState();
            state = StakingLPLib.processIncomingBNB(state, IAuthorizer(authorizer), rewardType, msg.value);
            _setPoolState(state);
        }
    }

    /**
     * @dev 记录流入的BNB并根据奖励类型处理
     * @param amount BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        if (amount == 0) revert InvalidParam();
        StakingLPLib.RewardPoolState memory state = _getPoolState();
        state = StakingLPLib.processIncomingBNB(state, IAuthorizer(authorizer), rewardType, amount);
        _setPoolState(state);
    }

    /**
     * @dev 接收ERC20代币（WBNB或Token）并根据奖励类型处理
     * @param token 代币地址
     * @param amount 代币数量
     */
    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        if (token == address(0)) revert InvalidParam();
        if (amount == 0) revert InvalidParam();
        
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        StakingLPLib.RewardPoolState memory state = _getPoolState();
        state = StakingLPLib.processIncomingToken(state, IAuthorizer(authorizer), rewardType, token, amount);
        _setPoolState(state);
    }

    /**
     * @dev 获取奖励池状态（内部函数）
     */
    function _getPoolState() internal view returns (StakingLPLib.RewardPoolState memory) {
        return StakingLPLib.RewardPoolState({
            lpRewardPoolBalance: lpRewardPoolBalance,
            tokenRewardPoolBalance: tokenRewardPoolBalance,
            bnbRewardPoolBalance: bnbRewardPoolBalance,
            totalWeightedNFTs: totalWeightedNFTs,
            globalRewardPerWeight: globalRewardPerWeight,
            stakingRewardPrecision: STAKING_REWARD_PRECISION,
            rewardType: rewardType,
            todayStart: _todayStart,
            rewardRate: _rewardRate,
            maxRewardRate: _maxRewardRate,
            maxDailyRewardPercent: _maxDailyRewardPercent,
            rateStep: _rateStep,
            todayRewardAmount: _todayRewardAmount,
            todayIncomingTokens: _todayIncomingTokens,
            rewardPrecision: REWARD_PRECISION
        });
    }

    /**
     * @dev 设置奖励池状态（内部函数）
     */
    function _setPoolState(StakingLPLib.RewardPoolState memory state) internal {
        lpRewardPoolBalance = state.lpRewardPoolBalance;
        tokenRewardPoolBalance = state.tokenRewardPoolBalance;
        bnbRewardPoolBalance = state.bnbRewardPoolBalance;
        totalWeightedNFTs = state.totalWeightedNFTs;
        globalRewardPerWeight = state.globalRewardPerWeight;
        _todayStart = state.todayStart;
        _rewardRate = state.rewardRate;
        _todayRewardAmount = state.todayRewardAmount;
        _todayIncomingTokens = state.todayIncomingTokens;
    }

    /**
     * @dev 更新总质押权重（从主合约同步）
     * @param _totalWeightedNFTs 新的总质押权重
     */
    function updateTotalWeight(uint256 _totalWeightedNFTs) external onlyOwnerOrAuthorizer {
        totalWeightedNFTs = _totalWeightedNFTs;
    }

    /**
     * @dev 同步用户权重快照（从主合约同步）
     * @param user 用户地址
     * @param snapshotWeight 用户快照权重
     */
    function syncUserWeight(address user, uint256 snapshotWeight) external onlyOwnerOrAuthorizer {
        _userRewardSnapshotWeight[epoch][user] = snapshotWeight;
    }

    /**
     * @dev 设置奖励类型（仅owner）
     * @param _rewardType 新的奖励类型
     */
    function setRewardType(RewardType _rewardType) external onlyOwner {
        RewardType oldType = rewardType;
        if (oldType == _rewardType) {
            return;
        }
        
        StakingLPLib.RewardPoolState memory state = _getPoolState();
        state = StakingLPLib.convertPoolAssets(state, IAuthorizer(authorizer), oldType, _rewardType);
        _setPoolState(state);
        
        rewardType = _rewardType;
        emit RewardTypeChanged(oldType, _rewardType);
    }

    /**
     * @dev 复利手续费（仅owner）
     */
    function compoundFees() external onlyOwner whenNotPaused {
        StakingLPLib.compoundFees(IAuthorizer(authorizer));
        emit FeesCompounded(0);
    }

    /**
     * @dev 领取奖励
     */
    function claimLPReward() external nonReentrant whenNotPaused {
        address staking = IAuthorizer(authorizer).getAddressByName("staking");
        uint256 userWeight = IStaking(staking).userStakedWeight(msg.sender);
        if (userWeight == 0) revert NoStakedNFTs();

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 reward = StakingLPLib.claimBNBReward(bnbRewardPoolBalance, userWeight, totalWeightedNFTs, msg.sender);
            if (reward > 0) {
                bnbRewardPoolBalance -= reward;
                emit BNBRewardClaimed(msg.sender, reward);
            }
            return;
        }

        uint256 currentEpoch = epoch;
        uint256 rewardBase = globalRewardPerWeight * userWeight;
        uint256 snapshotBase = _userRewardSnapshotWeight[currentEpoch][msg.sender];
        
        if (rewardBase <= snapshotBase) {
            return;
        }

        uint256 reward = (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
        
        if (currentType == RewardType.LP) {
            if (reward > lpRewardPoolBalance) revert InsufficientLP();
            lpRewardPoolBalance -= reward;
            StakingLPLib.redeemLPToUser(IAuthorizer(authorizer), reward, msg.sender);
            emit LPRewardClaimed(msg.sender, reward);
        } else if (currentType == RewardType.TOKEN) {
            if (reward > tokenRewardPoolBalance) revert InsufficientToken();
            tokenRewardPoolBalance -= reward;
            IERC20(IAuthorizer(authorizer).getAddressByName("token")).safeTransfer(msg.sender, reward);
            emit TokenRewardClaimed(msg.sender, reward);
        }

        _userRewardSnapshotWeight[currentEpoch][msg.sender] = globalRewardPerWeight;
    }

    /**
     * @dev 查询待领取奖励
     * @param user 用户地址
     * @return 待领取奖励金额
     */
    function getPendingLPReward(address user) external view returns (uint256) {
        address staking = IAuthorizer(authorizer).getAddressByName("staking");
        uint256 userWeight = IStaking(staking).userStakedWeight(user);
        if (userWeight == 0) return 0;

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            return bnbRewardPoolBalance * userWeight / (totalWeightedNFTs + 1);
        }
        
        uint256 currentEpoch = epoch;
        uint256 rewardBase = globalRewardPerWeight * userWeight;
        uint256 snapshotBase = _userRewardSnapshotWeight[currentEpoch][user];
        
        if (rewardBase <= snapshotBase) {
            return 0;
        }
        
        return (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
    }

    /**
     * @dev 紧急提取WBNB（仅owner）
     * @param amount 提取金额
     */
    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        StakingLPLib.emergencyWithdrawWBNB(IAuthorizer(authorizer), amount);
        emit EmergencyWBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev LP迁移：将旧DEX的LP转换为新DEX的LP（用于FlapSwap迁移到PancakeSwap等场景）
     * 步骤：
     * 1. 从旧DEX赎回LP获得代币+WBNB
     * 2. 使用代币+WBNB在新DEX创建新LP
     * @param oldDexType 旧DEX类型（0=FlapSwap, 1=PancakeSwap, 2=Uniswap）
     * @param newDexType 新DEX类型（0=FlapSwap, 1=PancakeSwap, 2=Uniswap）
     * @param lpAmount 要迁移的LP数量
     * @return 新DEX的LP数量
     */
    function migrateLP(uint8 oldDexType, uint8 newDexType, uint256 lpAmount) public onlyOwner nonReentrant whenNotPaused returns (uint256) {
        StakingLPLib.RewardPoolState memory state = _getPoolState();
        uint256 newLPAmount;
        (state, newLPAmount) = StakingLPLib.migrateLP(state, IAuthorizer(authorizer), oldDexType, newDexType, lpAmount);
        _setPoolState(state);
        return newLPAmount;
    }

    /**
     * @dev 设置滑点保护参数
     * @param __slippage 新的滑点参数
     */
    function setSlippage(uint256 __slippage) external onlyOwner {
        if (__slippage == 0 || __slippage > 10000) revert InvalidParam();
        _slippage = __slippage;
    }

    /**
     * @dev 设置每日释放比例
     * @param __rewardRate 新的奖励率（万分比）
     */
    function setRewardRate(uint256 __rewardRate) external onlyOwner {
        if (__rewardRate == 0 || __rewardRate > _maxRewardRate) revert InvalidParam();
        _rewardRate = __rewardRate;
        emit RewardRateUpdated(__rewardRate);
    }

    /**
     * @dev 设置最大每日释放比例
     * @param __maxRewardRate 最大奖励率（万分比）
     */
    function setMaxRewardRate(uint256 __maxRewardRate) external onlyOwner {
        if (__maxRewardRate < _rewardRate) revert InvalidParam();
        _maxRewardRate = __maxRewardRate;
    }

    /**
     * @dev 设置每日最大释放百分比
     * @param __percent 百分比（千分比，100 = 10%）
     */
    function setMaxDailyRewardPercent(uint256 __percent) external onlyOwner {
        if (__percent == 0 || __percent > 500) revert InvalidParam();
        _maxDailyRewardPercent = __percent;
    }

    /**
     * @dev 检查是否应该计算每日奖励
     */
    function shouldCalculateDailyReward() public view returns (bool) {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        return currentDayStart > _todayStart;
    }

    /**
     * @dev 计算并释放每日奖励
     */
    function calculateDailyReward() external whenNotPaused {
        StakingLPLib.RewardPoolState memory state = _getPoolState();
        state = StakingLPLib.calculateDailyReward(state);
        _setPoolState(state);
    }

    /**
     * @dev 记录当日流入代币数量
     * @param amount 流入代币数量
     */
    function recordIncomingTokens(uint256 amount) external onlyOwnerOrAuthorizer {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart != _todayStart) {
            _todayStart = currentDayStart;
            _todayIncomingTokens = 0;
        }
        _todayIncomingTokens += amount;
    }

    /**
     * @dev 设置奖励率调整步长
     * @param __rateStep 调整步长（万分比）
     */
    function setRateStep(uint256 __rateStep) external onlyOwner {
        if (__rateStep == 0) revert InvalidParam();
        _rateStep = __rateStep;
    }

    // ============================================================
    //  紧急取款函数（仅所有者）
    // ============================================================

    /**
     * @dev 提取指定代币（仅owner）
     * @param token 代币地址
     * @param to 接收地址
     */
    function withdrawToken(address token, address to) external onlyOwner {
        if (token == address(0)) revert InvalidParam();
        if (to == address(0)) revert InvalidParam();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
        }
    }

    /**
     * @dev 提取BNB（仅owner）
     * @param to 接收地址
     */
    function withdrawBNB(address to) external onlyOwner {
        if (to == address(0)) revert InvalidParam();
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(to).call{value: balance}("");
            if (!success) revert SLP_BNBTransferFailed();
        }
    }

    function userRewardSnapshotWeight(address user) external view returns (uint256) {
        return _userRewardSnapshotWeight[epoch][user];
    }

    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        lpRewardPoolBalance = 0;
        tokenRewardPoolBalance = 0;
        bnbRewardPoolBalance = 0;
        globalRewardPerWeight = 0;
        totalWeightedNFTs = 0;
        _todayStart = 0;
        _todayRewardAmount = 0;
        _todayIncomingTokens = 0;
        _rewardRate = 100;
        _slippage = 1000;
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }

    
}
