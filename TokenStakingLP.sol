// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./LPLib.sol";

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
    using LPLib for IAuthorizer;
    
    /** @dev 奖励精度缩放因子（1e18），用于避免 dailyLPRewardPerToken 整数截断 */
    uint256 private constant REWARD_PRECISION = 1e18;
    
    /** @dev 授权合约地址 */
    address public authorizer;
    
    /** @dev LP奖励池余额 */
    uint256 public lpRewardPoolBalance;
    
    /** @dev 全局LP奖励累积值（每单位质押代币的LP奖励） */
    uint256 public dailyLPRewardPerToken;
    
    /** @dev 用户LP快照累积率映射（地址 => 用户上次领取时的累积率） */
    mapping(address => uint256) public lastLPAccumulatedRate;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev LP奖励领取事件
     * @param user 用户地址
     * @param amount 领取LP数量
     */
    event RewardsClaimed(address indexed user, uint256 amount);

    /** @dev 紧急提取WBNB事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyWBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "TokenStakingLP: Invalid authorizer");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
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
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "TokenStakingLP: Not authorized");
        _;
    }

    /**
     * @dev 回退函数：接收BNB并自动转换为LP
     */
    receive() external payable {
        if (msg.value > 0) {
            uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(msg.value);
            if (lpAmount > 0) {
                _addToLPRewardPool(lpAmount);
            }
        }
    }

    /**
     * @dev 记录流入的BNB并转换为LP
     * @param amount BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        require(amount > 0, "TokenStakingLP: Amount must be > 0");
        uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(amount);
        if (lpAmount > 0) {
            _addToLPRewardPool(lpAmount);
        }
    }

    /**
     * @dev 添加到LP奖励池（内部函数）
     * @param lpAmount LP数量
     */
    function _addToLPRewardPool(uint256 lpAmount) internal {
        uint256 newBalance = lpRewardPoolBalance + lpAmount;
        require(newBalance >= lpRewardPoolBalance, "TokenStakingLP: LP overflow");
        lpRewardPoolBalance = newBalance;

        // 获取TokenStaking总质押量
        address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
        uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
        
        if (totalStaked > 0) {
            uint256 increment = (lpAmount * REWARD_PRECISION) / totalStaked;
            dailyLPRewardPerToken += increment;
        }
    }

    /**
     * @dev 复利手续费（仅owner）
     */
    function compoundFees() external onlyOwner {
        IAuthorizer(authorizer).compoundFees();
    }

    /**
     * @dev 领取LP奖励
     */
    function claimLPReward() external nonReentrant whenNotPaused {
        // 获取用户质押信息
        address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(msg.sender);
        require(stake.amount > 0, "TokenStakingLP: No staked tokens");

        uint256 currentRate = dailyLPRewardPerToken;
        uint256 lastRate = lastLPAccumulatedRate[msg.sender];
        
        if (currentRate <= lastRate) {
            return;
        }

        uint256 lpReward = stake.amount * (currentRate - lastRate) / REWARD_PRECISION;
        
        require(lpReward <= lpRewardPoolBalance, "TokenStakingLP: Insufficient LP");

        lpRewardPoolBalance -= lpReward;
        lastLPAccumulatedRate[msg.sender] = currentRate;

        IAuthorizer(authorizer).redeemLPToUser(lpReward, msg.sender);
        emit RewardsClaimed(msg.sender, lpReward);
    }

    /**
     * @dev 查询待领取LP奖励
     * @param user 用户地址
     * @return uint256 待领取LP奖励金额
     */
    function getPendingLPReward(address user) external view returns (uint256) {
        address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(user);
        if (stake.amount == 0) return 0;
        
        uint256 currentRate = dailyLPRewardPerToken;
        uint256 lastRate = lastLPAccumulatedRate[user];
        
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
        IAuthorizer(authorizer).emergencyWithdrawWBNB(amount);
        emit EmergencyWBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "TokenStakingLP: Invalid authorizer");
        authorizer = _authorizerAddress;
    }
}
