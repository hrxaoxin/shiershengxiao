// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./LPLib.sol";
import "./StakingLib.sol";

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
    
    /** @dev 滑点保护参数（默认1000 = 10%容差） */
    uint256 public slippage = 1000;
    /** @dev 自动复利开关 */
    bool public autoCompoundEnabled = true;
    /** @dev 最小复利金额（0.001 ETH） */
    uint256 public minCompoundAmount = 1000000000000000;
    
    /** @dev 每日释放比例（万分比，默认1% = 100/10000） */
    uint256 public rewardRate = 100;
    /** @dev 最大每日释放比例（万分比） */
    uint256 public maxRewardRate = 500;
    /** @dev 每日最大释放百分比（10% = 100/1000） */
    uint256 public maxDailyRewardPercent = 100;
    /** @dev 奖励率调整步长（万分比，10 = 0.1%） */
    uint256 public rateStep = 10;
    
    /** @dev 今日开始时间 */
    uint256 public todayStart;
    /** @dev 今日已释放奖励金额 */
    uint256 public todayRewardAmount;
    /** @dev 今日流入代币数量 */
    uint256 public todayIncomingTokens;
    
    /** @dev 全局奖励累积值（每单位权重的奖励）- 用于LP和TOKEN类型 */
    uint256 public globalRewardPerWeight;
    /** @dev 用户奖励快照权重映射（地址 => 用户快照） */
    mapping(address => uint256) public userRewardSnapshotWeight;
    
    /** @dev 质押奖励精度缩放因子（1e18） */
    uint256 public constant STAKING_REWARD_PRECISION = 1e18;
    /** @dev 奖励比例精度（万分比） */
    uint256 public constant REWARD_PRECISION = 10000;
    
    /** @dev 总质押权重（从主合约同步） */
    uint256 public totalWeightedNFTs;

    /** @dev LP奖励领取事件 */
    event LPRewardClaimed(address indexed user, uint256 lpAmount);
    /** @dev 代币奖励领取事件 */
    event TokenRewardClaimed(address indexed user, uint256 tokenAmount);
    /** @dev BNB奖励领取事件 */
    event BNBRewardClaimed(address indexed user, uint256 bnbAmount);
    /** @dev LP奖励添加事件 */
    event LPAddedToPool(uint256 lpAmount);
    /** @dev 代币奖励添加事件 */
    event TokenAddedToPool(uint256 tokenAmount);
    /** @dev BNB奖励添加事件 */
    event BNBAddedToPool(uint256 bnbAmount);
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
        require(_authorizerAddress != address(0), "StakingLP: Invalid authorizer");
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        authorizer = _authorizerAddress;
        rewardType = RewardType.LP;
        
        slippage = 1000;
        autoCompoundEnabled = true;
        minCompoundAmount = 1000000000000000;
        
        rewardRate = 100;
        maxRewardRate = 500;
        maxDailyRewardPercent = 100;
        rateStep = 10;
        todayStart = 0;
        todayRewardAmount = 0;
        todayIncomingTokens = 0;
        globalRewardPerWeight = 0;
        totalWeightedNFTs = 0;
    }

    /**
     * @dev 仅owner或authorizer的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "StakingLP: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "StakingLP: Not authorized");
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
        require(_authorizerAddress != address(0), "StakingLP: Invalid authorizer");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 接收BNB - 根据当前奖励类型处理
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
        require(amount > 0, "StakingLP: Amount must be > 0");
        _processIncomingBNB(amount);
    }

    /**
     * @dev 接收ERC20代币（WBNB或Token）并根据奖励类型处理
     * @param token 代币地址
     * @param amount 代币数量
     */
    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        require(token != address(0), "StakingLP: Invalid token address");
        require(amount > 0, "StakingLP: Amount must be > 0");
        
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        _processIncomingToken(token, amount);
    }

    /**
     * @dev 批量接收多种资产
     * @param tokens 代币地址数组
     * @param amounts 代币数量数组
     */
    function receiveMultipleTokens(address[] calldata tokens, uint256[] calldata amounts) external onlyOwnerOrAuthorizer {
        require(tokens.length == amounts.length, "StakingLP: Arrays length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IBEP20(tokens[i]).transferFrom(msg.sender, address(this), amounts[i]);
                _processIncomingToken(tokens[i], amounts[i]);
            }
        }
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
     * @dev 处理流入的代币（内部函数）
     * @param token 代币地址
     * @param amount 代币数量
     */
    function _processIncomingToken(address token, uint256 amount) internal {
        RewardType currentType = rewardType;
        address wbnb = IAuthorizer(authorizer).getWBNB();
        address mainToken = IAuthorizer(authorizer).getToken();
        
        if (token == wbnb) {
            if (currentType == RewardType.LP) {
                IWBNB(wbnb).withdraw(amount);
                uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(amount);
                if (lpAmount > 0) {
                    _addToRewardPool(lpAmount, currentType);
                }
            } else if (currentType == RewardType.TOKEN) {
                uint256 tokenAmount = IAuthorizer(authorizer).swapWBNBToToken(amount);
                if (tokenAmount > 0) {
                    _addToRewardPool(tokenAmount, currentType);
                }
            } else if (currentType == RewardType.BNB) {
                IWBNB(wbnb).withdraw(amount);
                _addToRewardPool(amount, currentType);
            }
        } else if (token == mainToken) {
            if (currentType == RewardType.LP) {
                uint256 lpAmount = IAuthorizer(authorizer).convertTokenToLP(amount);
                if (lpAmount > 0) {
                    _addToRewardPool(lpAmount, currentType);
                }
            } else if (currentType == RewardType.TOKEN) {
                _addToRewardPool(amount, currentType);
            } else if (currentType == RewardType.BNB) {
                uint256 bnbAmount = IAuthorizer(authorizer).swapTokenToBNB(amount);
                if (bnbAmount > 0) {
                    _addToRewardPool(bnbAmount, currentType);
                }
            }
        } else {
            uint256 bnbAmount = IAuthorizer(authorizer).swapTokenToBNB(amount);
            if (bnbAmount > 0) {
                _processIncomingBNB(bnbAmount);
            }
        }
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
        userRewardSnapshotWeight[user] = snapshotWeight;
    }

    /**
     * @dev 添加到奖励池（内部函数）
     * @param amount 奖励数量
     * @param type_ 奖励类型
     */
    function _addToRewardPool(uint256 amount, RewardType type_) internal {
        if (type_ == RewardType.LP) {
            uint256 newBalance = lpRewardPoolBalance + amount;
            require(newBalance >= lpRewardPoolBalance, "StakingLP: LP overflow");
            lpRewardPoolBalance = newBalance;
            emit LPAddedToPool(amount);
        } else if (type_ == RewardType.TOKEN) {
            uint256 newBalance = tokenRewardPoolBalance + amount;
            require(newBalance >= tokenRewardPoolBalance, "StakingLP: Token overflow");
            tokenRewardPoolBalance = newBalance;
            emit TokenAddedToPool(amount);
        } else if (type_ == RewardType.BNB) {
            uint256 newBalance = bnbRewardPoolBalance + amount;
            require(newBalance >= bnbRewardPoolBalance, "StakingLP: BNB overflow");
            bnbRewardPoolBalance = newBalance;
            emit BNBAddedToPool(amount);
        }

        if (totalWeightedNFTs > 0 && (type_ == RewardType.LP || type_ == RewardType.TOKEN)) {
            uint256 increment = (amount * STAKING_REWARD_PRECISION) / totalWeightedNFTs;
            require(globalRewardPerWeight <= type(uint256).max - increment, "StakingLP: Reward overflow");
            globalRewardPerWeight += increment;
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
    function compoundFees() external onlyOwner whenNotPaused {
        IAuthorizer(authorizer).compoundFees();
    }

    /**
     * @dev 领取奖励
     */
    function claimLPReward() external nonReentrant whenNotPaused {
        address staking = IAuthorizer(authorizer).getStaking();
        uint256 userWeight = IStaking(staking).userStakedWeight(msg.sender);
        require(userWeight > 0, "StakingLP: No staked NFTs");

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 reward = bnbRewardPoolBalance * userWeight / totalWeightedNFTs;
            if (reward > 0 && reward <= bnbRewardPoolBalance) {
                bnbRewardPoolBalance -= reward;
                payable(msg.sender).transfer(reward);
                emit BNBRewardClaimed(msg.sender, reward);
            }
            return;
        }

        uint256 rewardBase = globalRewardPerWeight * userWeight;
        uint256 snapshotBase = userRewardSnapshotWeight[msg.sender];
        
        if (rewardBase <= snapshotBase) {
            return;
        }

        uint256 reward = (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
        
        if (currentType == RewardType.LP) {
            require(reward <= lpRewardPoolBalance, "StakingLP: Insufficient LP");
            lpRewardPoolBalance -= reward;
            IAuthorizer(authorizer).redeemLPToUser(reward, msg.sender);
            emit LPRewardClaimed(msg.sender, reward);
        } else if (currentType == RewardType.TOKEN) {
            require(reward <= tokenRewardPoolBalance, "StakingLP: Insufficient Token");
            tokenRewardPoolBalance -= reward;
            IBEP20 token = IBEP20(IAuthorizer(authorizer).getToken());
            token.transfer(msg.sender, reward);
            emit TokenRewardClaimed(msg.sender, reward);
        }

        userRewardSnapshotWeight[msg.sender] = globalRewardPerWeight;
    }

    /**
     * @dev 查询待领取奖励
     * @param user 用户地址
     * @return 待领取奖励金额
     */
    function getPendingLPReward(address user) external view returns (uint256) {
        address staking = IAuthorizer(authorizer).getStaking();
        uint256 userWeight = IStaking(staking).userStakedWeight(user);
        if (userWeight == 0) return 0;

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            return bnbRewardPoolBalance * userWeight / (totalWeightedNFTs + 1);
        }
        
        uint256 rewardBase = globalRewardPerWeight * userWeight;
        uint256 snapshotBase = userRewardSnapshotWeight[user];
        
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
        IAuthorizer(authorizer).emergencyWithdrawWBNB(amount);
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
    function migrateLP(uint8 oldDexType, uint8 newDexType, uint256 lpAmount) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        require(oldDexType != newDexType, "StakingLP: Same DEX type");
        require(lpAmount > 0, "StakingLP: Amount must be > 0");
        require(lpAmount <= lpRewardPoolBalance, "StakingLP: Insufficient LP");

        uint256 tokenAmount;
        uint256 wbnbAmount;
        
        (tokenAmount, wbnbAmount) = IAuthorizer(authorizer).redeemLPFromDEX(lpAmount, oldDexType);
        
        require(tokenAmount > 0 || wbnbAmount > 0, "StakingLP: Failed to redeem old LP");

        uint256 newLPAmount = IAuthorizer(authorizer).convertToLP(tokenAmount, wbnbAmount, newDexType);
        
        require(newLPAmount > 0, "StakingLP: Failed to create new LP");

        lpRewardPoolBalance -= lpAmount;
        lpRewardPoolBalance += newLPAmount;
        
        emit LPMigrated(oldDexType, newDexType, lpAmount, newLPAmount);
        return newLPAmount;
    }

    /**
     * @dev 批量迁移所有LP到新DEX
     * @param oldDexType 旧DEX类型
     * @param newDexType 新DEX类型
     * @return 迁移后的新LP数量
     */
    function migrateAllLP(uint8 oldDexType, uint8 newDexType) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        require(oldDexType != newDexType, "StakingLP: Same DEX type");
        
        if (lpRewardPoolBalance == 0) {
            return 0;
        }
        
        return migrateLP(oldDexType, newDexType, lpRewardPoolBalance);
    }

    /**
     * @dev 紧急赎回所有LP为代币+WBNB（在DEX池子关闭前使用）
     * 将所有LP奖励池转换为代币和WBNB，用户领取时直接获得代币/WBNB
     */
    function emergencyRedeemAllLP() external onlyOwner nonReentrant whenNotPaused {
        if (lpRewardPoolBalance == 0) {
            return;
        }

        uint256 tokenAmount;
        uint256 wbnbAmount;
        
        (tokenAmount, wbnbAmount) = IAuthorizer(authorizer).redeemAllLP();
        
        lpRewardPoolBalance = 0;
        tokenRewardPoolBalance += tokenAmount;
        bnbRewardPoolBalance += wbnbAmount;
        
        rewardType = RewardType.TOKEN;
        
        emit EmergencyLPRedeemed(tokenAmount, wbnbAmount);
    }

    /**
     * @dev 检查特定DEX的LP余额
     * @param dexType DEX类型
     * @return LP余额
     */
    function checkLPBalanceOnDEX(uint8 dexType) external view returns (uint256) {
        return IAuthorizer(authorizer).getLPBalanceOnDEX(dexType);
    }

    /**
     * @dev 设置滑点保护参数
     * @param _slippage 新的滑点参数
     */
    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage > 0 && _slippage <= 10000, "StakingLP: Invalid slippage");
        slippage = _slippage;
    }

    /**
     * @dev 设置自动复利开关
     * @param _enabled 是否启用自动复利
     */
    function setAutoCompoundEnabled(bool _enabled) external onlyOwner {
        autoCompoundEnabled = _enabled;
    }

    /**
     * @dev 设置最小复利金额
     * @param _amount 最小复利金额
     */
    function setMinCompoundAmount(uint256 _amount) external onlyOwner {
        minCompoundAmount = _amount;
    }

    /**
     * @dev 设置每日释放比例
     * @param _rewardRate 新的奖励率（万分比）
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0 && _rewardRate <= maxRewardRate, "StakingLP: Invalid reward rate");
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @dev 设置最大每日释放比例
     * @param _maxRewardRate 最大奖励率（万分比）
     */
    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        require(_maxRewardRate >= rewardRate, "StakingLP: Max rate must be >= current rate");
        maxRewardRate = _maxRewardRate;
    }

    /**
     * @dev 设置每日最大释放百分比
     * @param _percent 百分比（千分比，100 = 10%）
     */
    function setMaxDailyRewardPercent(uint256 _percent) external onlyOwner {
        require(_percent > 0 && _percent <= 500, "StakingLP: Invalid percent");
        maxDailyRewardPercent = _percent;
    }

    /**
     * @dev 检查是否应该计算每日奖励
     */
    function shouldCalculateDailyReward() public view returns (bool) {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        return currentDayStart > todayStart;
    }

    /**
     * @dev 计算并释放每日奖励
     */
    function calculateDailyReward() external whenNotPaused {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart <= todayStart) return;

        todayStart = currentDayStart;
        rewardRate = 100;

        RewardType currentType = rewardType;
        uint256 poolBalance;

        if (currentType == RewardType.LP) {
            poolBalance = lpRewardPoolBalance;
        } else if (currentType == RewardType.TOKEN) {
            poolBalance = tokenRewardPoolBalance;
        } else {
            poolBalance = bnbRewardPoolBalance;
        }

        if (poolBalance == 0 || totalWeightedNFTs == 0) {
            todayRewardAmount = 0;
            todayIncomingTokens = 0;
            return;
        }

        uint256 expectedDailyReward = poolBalance * rewardRate / REWARD_PRECISION;
        _adjustRewardRate(expectedDailyReward);

        uint256 dailyReward = poolBalance * rewardRate / REWARD_PRECISION;
        uint256 maxDailyReward = poolBalance * maxDailyRewardPercent / 1000;
        
        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }

        if (dailyReward > 0) {
            uint256 increment = (dailyReward * STAKING_REWARD_PRECISION) / totalWeightedNFTs;
            globalRewardPerWeight += increment;
            todayRewardAmount = dailyReward;
            
            if (currentType == RewardType.LP) {
                lpRewardPoolBalance -= dailyReward;
            } else if (currentType == RewardType.TOKEN) {
                tokenRewardPoolBalance -= dailyReward;
            } else {
                bnbRewardPoolBalance -= dailyReward;
            }
            
            emit DailyRewardCalculated(dailyReward, increment);
        } else {
            todayRewardAmount = 0;
        }

        todayIncomingTokens = 0;
    }

    /**
     * @dev 动态调整奖励率
     * 规则：当日流入量超过预计释放量的倍数，每增加1倍，奖励率上调10（万分比）
     * 奖励率不会超过maxRewardRate
     * @param expectedDailyReward 当日预计释放量
     */
    function _adjustRewardRate(uint256 expectedDailyReward) internal {
        if (expectedDailyReward == 0) return;
        
        if (todayIncomingTokens > expectedDailyReward) {
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
        require(_rateStep > 0, "StakingLP: Step must be > 0");
        rateStep = _rateStep;
    }

    /**
     * @dev Fallback函数
     */
    fallback() external payable {}
}
