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
 * @title ArenaRewardLP
 * @dev 竞技场LP奖励合约，负责管理ArenaReward的LP奖励分发
 * 
 * 核心功能：
 * 1. LP奖励池管理：接收BNB并转换为LP份额
 * 2. LP奖励分发：玩家领取赛季奖励时以LP形式发放
 * 3. 奖励领取：自动兑换为代币+WBNB
 * 
 * 与ArenaReward合约的交互：
 * - 通过IAuthorizer获取ArenaReward地址
 * - 读取ArenaReward的玩家赛季奖励信息
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - onlyOwnerOrAuthorizer：管理权限控制
 */
contract ArenaRewardLP is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using LPLib for IAuthorizer;
    
    /** @dev 授权合约地址 */
    address public authorizer;
    
    /** @dev LP奖励池余额 */
    uint256 public lpRewardPoolBalance;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev LP奖励领取事件
     * @param user 用户地址
     * @param seasonId 赛季ID
     * @param amount 领取LP数量
     */
    event RewardClaimed(address user, uint256 seasonId, uint256 amount);

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
        require(_authorizerAddress != address(0), "ArenaRewardLP: Invalid authorizer");
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
        require(auth.isSystemContract(msg.sender), "ArenaRewardLP: Not authorized");
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
     * @dev 添加到LP奖励池（内部函数）
     * @param lpAmount LP数量
     */
    function _addToLPRewardPool(uint256 lpAmount) internal {
        lpRewardPoolBalance += lpAmount;
    }

    /**
     * @dev 记录流入的BNB并转换为LP
     * @param amount BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        require(amount > 0, "ArenaRewardLP: Amount must be > 0");
        uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(amount);
        if (lpAmount > 0) {
            _addToLPRewardPool(lpAmount);
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
     * @param seasonId 赛季ID
     */
    function claimLPReward(uint256 seasonId) external nonReentrant whenNotPaused {
        // 获取ArenaReward合约信息
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        IArenaReward arenaRewardContract = IArenaReward(arenaReward);
        
        uint256 reward = arenaRewardContract.getPendingRewardsByPlayer(msg.sender, seasonId);
        require(reward > 0, "ArenaRewardLP: No LP reward to claim");
        
        // 检查是否已领取（通过ArenaReward合约）
        bool alreadyClaimed = arenaRewardContract.isRewardClaimed(msg.sender, seasonId);
        require(!alreadyClaimed, "ArenaRewardLP: Already claimed");
        
        // 调用ArenaReward合约标记为已领取
        // 注意：ArenaReward的claimedRewards是internal，这里需要在ArenaReward合约中调用claimReward
        // 或者通过外部调用ArenaReward.claimReward后再调用此函数
        
        require(lpRewardPoolBalance >= reward, "ArenaRewardLP: Insufficient LP balance");
        lpRewardPoolBalance -= reward;
        
        IAuthorizer(authorizer).redeemLPToUser(reward, msg.sender);
        emit RewardClaimed(msg.sender, seasonId, reward);
    }

    /**
     * @dev 查询待领取LP奖励
     * @param user 用户地址
     * @param seasonId 赛季ID
     * @return 待领取LP奖励金额
     */
    function getPendingLPReward(address user, uint256 seasonId) external view returns (uint256) {
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        IArenaReward arenaRewardContract = IArenaReward(arenaReward);
        
        bool alreadyClaimed = arenaRewardContract.isRewardClaimed(user, seasonId);
        if (alreadyClaimed) {
            return 0;
        }
        
        return arenaRewardContract.getPendingRewardsByPlayer(user, seasonId);
    }

    /**
     * @dev 紧急提取WBNB（仅owner）
     * @param amount 提取金额
     */
    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        IAuthorizer(authorizer).emergencyWithdrawWBNB(amount);
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaRewardLP: Invalid authorizer");
        authorizer = _authorizerAddress;
    }
}
