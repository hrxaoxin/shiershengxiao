// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./AddressLib.sol";
import "./TokenStakingLPLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenStakingLP
 * @dev 代币质押LP奖励合约，负责管理TokenStaking质押池的LP奖励分发
 * 
 * 核心功能：
 * 1. LP奖励池管理：接收BNB并转换为LP份额
 * 2. LP奖励分发：根据用户质押份额分配LP奖励
 * 3. 奖励领取：用户领取应得的LP奖励，自动兑换为代币+WBNB
 * 
 * 奖励机制：
 * - 全局累积LP奖励/代币（dailyLPRewardPerToken）持续累积
 * - 用户领取时计算其快照与当前值的差值 × 质押数量 = 应得LP奖励
 * - 用户快照（lastLPAccumulatedRate）记录上次领取时的累积值，防止重复计算
 * 
 * 与TokenStaking合约的交互：
 * - 通过IAuthorizer获取TokenStaking地址
 * - 直接读取TokenStaking的总质押量计算LP奖励分配
 * - 不需要同步权重，由LP合约实时读取
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - onlyOwnerOrAuthorizer：管理权限控制
 * 
 * 合约升级：
 * - UUPS可升级模式，由onlyOwner授权升级
 */
contract TokenStakingLP is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    
    /** @dev 奖励精度缩放因子（1e18），用于避免 dailyRewardPerToken 整数截断 */
    uint256 private constant REWARD_PRECISION = 1e18;
    
    address public authorizer;
    
    RewardType private rewardType;
    
    uint256 private lpRewardPoolBalance;
    uint256 private tokenRewardPoolBalance;
    uint256 private bnbRewardPoolBalance;
    
    uint256 private rewardRate = 100;
    uint256 private maxRewardRate = 500;
    uint256 private maxDailyRewardPercent = 100;
    uint256 private rateStep = 10;
    
    uint256 private todayStart;
    uint256 private todayRewardAmount;
    uint256 private todayIncomingTokens;
    
    uint256 private dailyRewardPerToken;
    
    /** @dev 当前纪元（循环复用，MAX_EPOCHS次后回到0） */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    /** @dev 用户奖励快照累积率映射（epoch => 地址 => 用户上次领取时的累积率） */
    mapping(uint256 => mapping(address => uint256)) private _lastRewardAccumulatedRate;

    uint256 private constant DAILY_REWARD_PRECISION = 10000;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[47] private __gap;

    // Custom errors for reduced bytecode size
    error TSLP_InvalidAuthorizer();
    error TSLP_NotAuthorized();
    error TSLP_AmountZero();
    error TSLP_InvalidToken();
    error TSLP_InvalidRecipient();
    error TSLP_NoStakedTokens();
    error TSLP_InsufficientLP();
    error TSLP_InsufficientToken();
    error TSLP_InsufficientBNB();
    error TSLP_InvalidRewardRate();
    error TSLP_InvalidMaxRate();
    error TSLP_InvalidPercent();
    error TSLP_InvalidStep();
    error TSLP_AlreadyInitialized();
    error TSLP_AuthorizerNotSet();
    error TSLP_BNBTransferFailed();

    /**
     * @dev LP奖励领取事件
     * @param user 用户地址
     * @param amount 领取LP数量
     */
    event LPRewardsClaimed(address indexed user, uint256 amount);
    
    /** @dev 代币奖励领取事件
     * @param user 用户地址
     * @param amount 领取代币数量
     */
    event TokenRewardsClaimed(address indexed user, uint256 amount);
    
    /** @dev BNB奖励领取事件
     * @param user 用户地址
     * @param amount 领取BNB数量
     */
    event BNBRewardsClaimed(address indexed user, uint256 amount);

    /** @dev LP奖励添加事件 */
    event LPAddedToPool(uint256 amount);
    /** @dev 代币奖励添加事件 */
    event TokenAddedToPool(uint256 amount);
    /** @dev BNB奖励添加事件 */
    event BNBAddedToPool(uint256 amount);

    /** @dev 紧急提取WBNB事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyWBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    
    /** @dev 奖励类型切换事件 */
    event RewardTypeChanged(RewardType oldType, RewardType newType);
    /** @dev 每日奖励计算事件 */
    event DailyRewardCalculated(uint256 dailyReward, uint256 increment);
    /** @dev 奖励率更新事件 */
    event RewardRateUpdated(uint256 rewardRate);

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizerAddress) external initializer {
        if (_authorizerAddress == address(0)) revert TSLP_InvalidAuthorizer();
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
        rewardType = RewardType.BNB;
        
        rewardRate = 100;
        maxRewardRate = 500;
        maxDailyRewardPercent = 100;
        rateStep = 10;
        todayStart = 0;
        todayRewardAmount = 0;
        todayIncomingTokens = 0;
        dailyRewardPerToken = 0;
        epoch = 1;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }
    
    /**
     * @dev 暂停合约（仅owner）
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev 恢复合约（仅owner）
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev UUPS升级授权函数
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 仅owner或authorizer或系统合约的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        if (authorizer == address(0)) revert TSLP_AuthorizerNotSet();
        IAuthorizer auth = IAuthorizer(authorizer);
        if (!auth.isSystemContract(msg.sender)) revert TSLP_NotAuthorized();
        _;
    }

    /**
     * @dev 回退函数：接收BNB并根据奖励类型处理
     */
    receive() external payable {
        if (msg.value > 0) {
            TokenStakingLPLib.RewardPoolState memory state = _getSimplePoolState();
            uint256 lpBefore = state.lpRewardPoolBalance;
            uint256 tokenBefore = state.tokenRewardPoolBalance;
            state = TokenStakingLPLib.processIncomingBNB(state, IAuthorizer(authorizer), rewardType, msg.value);
            _setSimplePoolState(state);
            _updateRewardPerToken(lpBefore, tokenBefore, state);
        }
    }

    /**
     * @dev 记录流入的BNB并根据奖励类型处理
     * @param amount BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        if (amount == 0) revert TSLP_AmountZero();
        TokenStakingLPLib.RewardPoolState memory state = _getSimplePoolState();
        uint256 lpBefore = state.lpRewardPoolBalance;
        uint256 tokenBefore = state.tokenRewardPoolBalance;
        state = TokenStakingLPLib.processIncomingBNB(state, IAuthorizer(authorizer), rewardType, amount);
        _setSimplePoolState(state);
        _updateRewardPerToken(lpBefore, tokenBefore, state);
    }

    /**
     * @dev 接收ERC20代币（WBNB或Token）并根据奖励类型处理
     * @param token 代币地址
     * @param amount 代币数量
     */
    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        if (token == address(0)) revert TSLP_InvalidToken();
        if (amount == 0) revert TSLP_AmountZero();
        
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        TokenStakingLPLib.RewardPoolState memory state = _getSimplePoolState();
        uint256 lpBefore = state.lpRewardPoolBalance;
        uint256 tokenBefore = state.tokenRewardPoolBalance;
        state = TokenStakingLPLib.processIncomingToken(state, IAuthorizer(authorizer), rewardType, token, amount);
        _setSimplePoolState(state);
        _updateRewardPerToken(lpBefore, tokenBefore, state);
    }



    function _getSimplePoolState() internal view returns (TokenStakingLPLib.RewardPoolState memory state) {
        state.lpRewardPoolBalance = lpRewardPoolBalance;
        state.tokenRewardPoolBalance = tokenRewardPoolBalance;
        state.bnbRewardPoolBalance = bnbRewardPoolBalance;
        state.rewardType = rewardType;
        state.stakingRewardPrecision = REWARD_PRECISION;
    }

    function _setSimplePoolState(TokenStakingLPLib.RewardPoolState memory state) internal {
        lpRewardPoolBalance = state.lpRewardPoolBalance;
        tokenRewardPoolBalance = state.tokenRewardPoolBalance;
        bnbRewardPoolBalance = state.bnbRewardPoolBalance;
    }

    function _updateRewardPerToken(uint256 lpBefore, uint256 tokenBefore, TokenStakingLPLib.RewardPoolState memory state) internal {
        uint256 increment = TokenStakingLPLib.calculateRewardPerTokenIncrement(state, lpBefore, tokenBefore, IAuthorizer(authorizer), REWARD_PRECISION);
        if (increment > 0) {
            dailyRewardPerToken += increment;
        }
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
        
        _convertPoolAssets(oldType, _rewardType);
        
        rewardType = _rewardType;
        emit RewardTypeChanged(oldType, _rewardType);
    }

    /**
     * @dev 转换奖励池资产（内部函数）
     * @param fromType 原奖励类型
     * @param toType 目标奖励类型
     */
    function _convertPoolAssets(RewardType fromType, RewardType toType) internal {
        TokenStakingLPLib.RewardPoolState memory state = _getSimplePoolState();
        state = TokenStakingLPLib.convertPoolAssets(state, IAuthorizer(authorizer), fromType, toType);
        _setSimplePoolState(state);
    }

    /**
     * @dev 复利手续费（仅owner）
     */
    function compoundFees() external onlyOwner {
        TokenStakingLPLib.compoundFees(IAuthorizer(authorizer));
    }

    function claimLPReward() external nonReentrant whenNotPaused {
        _claimLPReward();
    }

    function _claimLPReward() internal {
        address tokenStaking = IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN_STAKING);
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(msg.sender);
        if (stake.amount == 0) revert TSLP_NoStakedTokens();

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            uint256 reward = bnbRewardPoolBalance * stake.amount / (totalStaked + 1);
            if (reward > 0 && reward <= bnbRewardPoolBalance) {
                bnbRewardPoolBalance -= reward;
                (bool success, ) = payable(msg.sender).call{value: reward}("");
                if (!success) revert TSLP_BNBTransferFailed();
                emit BNBRewardsClaimed(msg.sender, reward);
            }
            return;
        }

        uint256 currentEpoch = _currentEpoch();
        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = _lastRewardAccumulatedRate[currentEpoch][msg.sender];
        
        if (currentRate <= lastRate) {
            return;
        }

        uint256 reward = stake.amount * (currentRate - lastRate) / REWARD_PRECISION;
        
        if (currentType == RewardType.LP) {
            if (reward > lpRewardPoolBalance) revert TSLP_InsufficientLP();
            lpRewardPoolBalance -= reward;
            TokenStakingLPLib.redeemLPToUser(IAuthorizer(authorizer), reward, msg.sender);
            emit LPRewardsClaimed(msg.sender, reward);
        } else if (currentType == RewardType.TOKEN) {
            if (reward > tokenRewardPoolBalance) revert TSLP_InsufficientToken();
            tokenRewardPoolBalance -= reward;
            IERC20(IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN)).safeTransfer(msg.sender, reward);
            emit TokenRewardsClaimed(msg.sender, reward);
        }

        _lastRewardAccumulatedRate[currentEpoch][msg.sender] = currentRate;
    }

    /**
     * @dev 查询待领取奖励
     * @param user 用户地址
     * @return uint256 待领取奖励金额
     */
    function getPendingLPReward(address user) external view returns (uint256) {
        address tokenStaking = IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN_STAKING);
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(user);
        if (stake.amount == 0) return 0;

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            return bnbRewardPoolBalance * stake.amount / (totalStaked + 1);
        }
        
        uint256 currentEpoch = _currentEpoch();
        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = _lastRewardAccumulatedRate[currentEpoch][user];
        
        if (currentRate <= lastRate) {
            return 0;
        }
        
        return stake.amount * (currentRate - lastRate) / REWARD_PRECISION;
    }

    /**
     * @dev 紧急提取WBNB（仅owner）
     * @param amount 提取金额
     */
    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        TokenStakingLPLib.emergencyWithdrawWBNB(IAuthorizer(authorizer), amount);
        emit EmergencyWBNBWithdrawn(msg.sender, owner(), amount);
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        if (_authorizerAddress == address(0)) revert TSLP_InvalidAuthorizer();
        authorizer = _authorizerAddress;
    }
    
    /**
     * @dev 设置每日释放比例
     * @param _rewardRate 新的奖励率（万分比）
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        if (_rewardRate == 0 || _rewardRate > maxRewardRate) revert TSLP_InvalidRewardRate();
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @dev 设置最大每日释放比例
     * @param _maxRewardRate 最大奖励率（万分比）
     */
    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        if (_maxRewardRate < rewardRate) revert TSLP_InvalidMaxRate();
        maxRewardRate = _maxRewardRate;
    }

    /**
     * @dev 设置每日最大释放百分比
     * @param _percent 百分比（千分比，100 = 10%）
     */
    function setMaxDailyRewardPercent(uint256 _percent) external onlyOwner {
        if (_percent == 0 || _percent > 500) revert TSLP_InvalidPercent();
        maxDailyRewardPercent = _percent;
    }

    function calculateDailyReward() external whenNotPaused {
        _calculateDailyReward();
    }

    function _calculateDailyReward() internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart <= todayStart) return;

        todayStart = currentDayStart;
        rewardRate = 100;

        address tokenStaking = IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN_STAKING);
        uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();

        RewardType currentType = rewardType;
        uint256 poolBalance;

        if (currentType == RewardType.LP) {
            poolBalance = lpRewardPoolBalance;
        } else if (currentType == RewardType.TOKEN) {
            poolBalance = tokenRewardPoolBalance;
        } else {
            poolBalance = bnbRewardPoolBalance;
        }

        if (poolBalance == 0 || totalStaked == 0) {
            todayRewardAmount = 0;
            todayIncomingTokens = 0;
            return;
        }

        uint256 expectedDailyReward = poolBalance * rewardRate / DAILY_REWARD_PRECISION;
        
        if (expectedDailyReward > 0 && todayIncomingTokens > expectedDailyReward) {
            uint256 multiple = todayIncomingTokens / expectedDailyReward;
            uint256 steps = multiple - 1;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);
            if (newRate != rewardRate) {
                rewardRate = newRate;
                emit RewardRateUpdated(rewardRate);
            }
        }

        uint256 dailyReward = poolBalance * rewardRate / DAILY_REWARD_PRECISION;
        uint256 maxDailyReward = poolBalance * maxDailyRewardPercent / 1000;
        
        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }

        if (dailyReward > 0) {
            uint256 increment = (dailyReward * REWARD_PRECISION) / totalStaked;
            dailyRewardPerToken += increment;
            todayRewardAmount = dailyReward;
            
            if (currentType == RewardType.LP) {
                lpRewardPoolBalance -= dailyReward;
            } else if (currentType == RewardType.TOKEN) {
                tokenRewardPoolBalance -= dailyReward;
            } else {
                bnbRewardPoolBalance -= dailyReward;
            }
            
            emit DailyRewardCalculated(dailyReward, increment);
        }

        todayIncomingTokens = 0;
    }

    /**
     * @dev 记录当日流入代币数量
     * @param amount 流入代币数量
     */
    function recordIncomingTokens(uint256 amount) external onlyOwnerOrAuthorizer {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart != todayStart) {
            todayStart = currentDayStart;
            todayIncomingTokens = 0;
        }
        todayIncomingTokens += amount;
    }

    /**
     * @dev 设置奖励率调整步长
     * @param _rateStep 调整步长（万分比）
     */
    function setRateStep(uint256 _rateStep) external onlyOwner {
        if (_rateStep == 0) revert TSLP_InvalidStep();
        rateStep = _rateStep;
    }

    function emergencyWithdraw(uint256 tokenType, address tokenOrTo, uint256 amount) external onlyOwner {
        if (tokenOrTo == address(0)) revert TSLP_InvalidRecipient();
        if (tokenType == 0) {
            if (amount > address(this).balance) revert TSLP_InsufficientBNB();
            (bool success, ) = payable(tokenOrTo).call{value: amount}("");
            if (!success) revert TSLP_BNBTransferFailed();
        } else {
            uint256 balance = IERC20(tokenOrTo).balanceOf(address(this));
            if (amount > balance) revert TSLP_InsufficientToken();
            IERC20(tokenOrTo).safeTransfer(tokenOrTo, amount);
        }
    }

    function lastRewardAccumulatedRate(address user) external view returns (uint256) {
        return _lastRewardAccumulatedRate[_currentEpoch()][user];
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     * @param oldEpoch 旧纪元
     * @param newEpoch 新纪元
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        lpRewardPoolBalance = 0;
        tokenRewardPoolBalance = 0;
        bnbRewardPoolBalance = 0;
        dailyRewardPerToken = 0;
        todayStart = 0;
        todayRewardAmount = 0;
        todayIncomingTokens = 0;
        rewardRate = 100;
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}
