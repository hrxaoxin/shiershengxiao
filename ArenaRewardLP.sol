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
    
    /** @dev 当前奖励类型 */
    RewardType public rewardType;
    
    /** @dev LP奖励池余额 */
    uint256 public lpRewardPoolBalance;
    /** @dev 代币奖励池余额 */
    uint256 public tokenRewardPoolBalance;
    /** @dev BNB奖励池余额 */
    uint256 public bnbRewardPoolBalance;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev LP奖励领取事件
     * @param user 用户地址
     * @param seasonId 赛季ID
     * @param amount 领取LP数量
     */
    event LPRewardClaimed(address user, uint256 seasonId, uint256 amount);
    
    /** @dev 代币奖励领取事件
     * @param user 用户地址
     * @param seasonId 赛季ID
     * @param amount 领取代币数量
     */
    event TokenRewardClaimed(address user, uint256 seasonId, uint256 amount);
    
    /** @dev BNB奖励领取事件
     * @param user 用户地址
     * @param seasonId 赛季ID
     * @param amount 领取BNB数量
     */
    event BNBRewardClaimed(address user, uint256 seasonId, uint256 amount);

    /** @dev LP奖励添加事件 */
    event LPAddedToPool(uint256 amount);
    /** @dev 代币奖励添加事件 */
    event TokenAddedToPool(uint256 amount);
    /** @dev BNB奖励添加事件 */
    event BNBAddedToPool(uint256 amount);

    /** @dev 奖励类型切换事件 */
    event RewardTypeChanged(RewardType oldType, RewardType newType);

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
        rewardType = RewardType.LP;
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
     * @dev 回退函数：接收BNB并根据奖励类型处理
     */
    receive() external payable {
        if (msg.value > 0) {
            _processIncomingBNB(msg.value);
        }
    }

    /**
     * @dev 记录流入的BNB并根据奖励类型处理
     * @param amount BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        require(amount > 0, "ArenaRewardLP: Amount must be > 0");
        _processIncomingBNB(amount);
    }

    /**
     * @dev 处理流入的BNB（内部函数）
     * @param amount BNB数量
     */
    function _processIncomingBNB(uint256 amount) internal {
        RewardType currentType = rewardType;
        
        if (currentType == RewardType.LP) {
            uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(amount);
            if (lpAmount > 0) {
                _addToRewardPool(lpAmount, currentType);
            }
        } else if (currentType == RewardType.TOKEN) {
            uint256 tokenAmount = IAuthorizer(authorizer).swapBNBToToken(amount);
            if (tokenAmount > 0) {
                _addToRewardPool(tokenAmount, currentType);
            }
        } else if (currentType == RewardType.BNB) {
            _addToRewardPool(amount, currentType);
        }
    }

    /**
     * @dev 添加到奖励池（内部函数）
     * @param amount 奖励数量
     * @param type_ 奖励类型
     */
    function _addToRewardPool(uint256 amount, RewardType type_) internal {
        if (type_ == RewardType.LP) {
            lpRewardPoolBalance += amount;
            emit LPAddedToPool(amount);
        } else if (type_ == RewardType.TOKEN) {
            tokenRewardPoolBalance += amount;
            emit TokenAddedToPool(amount);
        } else if (type_ == RewardType.BNB) {
            bnbRewardPoolBalance += amount;
            emit BNBAddedToPool(amount);
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
        if (fromType == RewardType.LP && toType == RewardType.TOKEN) {
            if (lpRewardPoolBalance > 0) {
                uint256 tokenAmount = IAuthorizer(authorizer).redeemLPToToken(lpRewardPoolBalance);
                lpRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    tokenRewardPoolBalance += tokenAmount;
                }
            }
        } else if (fromType == RewardType.LP && toType == RewardType.BNB) {
            if (lpRewardPoolBalance > 0) {
                uint256 wbnbAmount = IAuthorizer(authorizer).redeemLPToWBNB(lpRewardPoolBalance);
                lpRewardPoolBalance = 0;
                if (wbnbAmount > 0) {
                    bnbRewardPoolBalance += wbnbAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.LP) {
            if (tokenRewardPoolBalance > 0) {
                uint256 lpAmount = IAuthorizer(authorizer).convertTokenToLP(tokenRewardPoolBalance);
                tokenRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.BNB) {
            if (tokenRewardPoolBalance > 0) {
                uint256 bnbAmount = IAuthorizer(authorizer).swapTokenToBNB(tokenRewardPoolBalance);
                tokenRewardPoolBalance = 0;
                if (bnbAmount > 0) {
                    bnbRewardPoolBalance += bnbAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.LP) {
            if (bnbRewardPoolBalance > 0) {
                uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(bnbRewardPoolBalance);
                bnbRewardPoolBalance = 0;
                if (lpAmount > 0) {
                    lpRewardPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.TOKEN) {
            if (bnbRewardPoolBalance > 0) {
                uint256 tokenAmount = IAuthorizer(authorizer).swapBNBToToken(bnbRewardPoolBalance);
                bnbRewardPoolBalance = 0;
                if (tokenAmount > 0) {
                    tokenRewardPoolBalance += tokenAmount;
                }
            }
        }
    }

    /**
     * @dev 复利手续费（仅owner）
     */
    function compoundFees() external onlyOwner {
        IAuthorizer(authorizer).compoundFees();
    }

    /**
     * @dev 领取奖励
     * @param seasonId 赛季ID
     */
    function claimLPReward(uint256 seasonId) external nonReentrant whenNotPaused {
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        IArenaReward arenaRewardContract = IArenaReward(arenaReward);
        
        uint256 reward = arenaRewardContract.getPendingRewardsByPlayer(msg.sender, seasonId);
        require(reward > 0, "ArenaRewardLP: No reward to claim");
        
        bool alreadyClaimed = arenaRewardContract.isRewardClaimed(msg.sender, seasonId);
        require(!alreadyClaimed, "ArenaRewardLP: Already claimed");

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.LP) {
            require(lpRewardPoolBalance >= reward, "ArenaRewardLP: Insufficient LP balance");
            lpRewardPoolBalance -= reward;
            IAuthorizer(authorizer).redeemLPToUser(reward, msg.sender);
            emit LPRewardClaimed(msg.sender, seasonId, reward);
        } else if (currentType == RewardType.TOKEN) {
            require(tokenRewardPoolBalance >= reward, "ArenaRewardLP: Insufficient Token balance");
            tokenRewardPoolBalance -= reward;
            IBEP20 token = IBEP20(IAuthorizer(authorizer).getToken());
            token.transfer(msg.sender, reward);
            emit TokenRewardClaimed(msg.sender, seasonId, reward);
        } else if (currentType == RewardType.BNB) {
            require(bnbRewardPoolBalance >= reward, "ArenaRewardLP: Insufficient BNB balance");
            bnbRewardPoolBalance -= reward;
            payable(msg.sender).transfer(reward);
            emit BNBRewardClaimed(msg.sender, seasonId, reward);
        }
    }

    /**
     * @dev 查询待领取奖励
     * @param user 用户地址
     * @param seasonId 赛季ID
     * @return 待领取奖励金额
     */
    function getPendingLPReward(address user, uint256 seasonId) external view returns (uint256) {
        address arenaReward = IAuthorizer(authorizer).getArenaReward();
        IArenaReward arenaRewardContract = IArenaReward(arenaReward);
        
        bool alreadyClaimed = arenaRewardContract.isRewardClaimed(user, seasonId);
        if (alreadyClaimed) {
            return 0;
        }
        
        uint256 reward = arenaRewardContract.getPendingRewardsByPlayer(user, seasonId);
        
        RewardType currentType = rewardType;
        if (currentType == RewardType.LP) {
            return reward > lpRewardPoolBalance ? lpRewardPoolBalance : reward;
        } else if (currentType == RewardType.TOKEN) {
            return reward > tokenRewardPoolBalance ? tokenRewardPoolBalance : reward;
        } else {
            return reward > bnbRewardPoolBalance ? bnbRewardPoolBalance : reward;
        }
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
