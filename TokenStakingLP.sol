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
    
    /** @dev 奖励精度缩放因子（1e18），用于避免 dailyRewardPerToken 整数截断 */
    uint256 private constant REWARD_PRECISION = 1e18;
    
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
    
    /** @dev 全局奖励累积值（每单位质押代币的奖励） */
    uint256 public dailyRewardPerToken;
    
    /** @dev 用户奖励快照累积率映射（地址 => 用户上次领取时的累积率） */
    mapping(address => uint256) public lastRewardAccumulatedRate;

    /** @dev 质押奖励精度缩放因子（1e18） */
    uint256 public constant STAKING_REWARD_PRECISION = 1e18;
    /** @dev 奖励比例精度（万分比） */
    uint256 public constant DAILY_REWARD_PRECISION = 10000;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[48] private __gap;

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
        require(auth.isSystemContract(msg.sender), "TokenStakingLP: Not authorized");
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
        require(amount > 0, "TokenStakingLP: Amount must be > 0");
        _processIncomingBNB(amount);
    }

    /**
     * @dev 接收ERC20代币（WBNB或Token）并根据奖励类型处理
     * @param token 代币地址
     * @param amount 代币数量
     */
    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        require(token != address(0), "TokenStakingLP: Invalid token address");
        require(amount > 0, "TokenStakingLP: Amount must be > 0");
        
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        _processIncomingToken(token, amount);
    }

    /**
     * @dev 批量接收多种资产
     * @param tokens 代币地址数组
     * @param amounts 代币数量数组
     */
    function receiveMultipleTokens(address[] calldata tokens, uint256[] calldata amounts) external onlyOwnerOrAuthorizer {
        require(tokens.length == amounts.length, "TokenStakingLP: Arrays length mismatch");
        
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
     * @dev 添加到奖励池（内部函数）
     * @param amount 奖励数量
     * @param type_ 奖励类型
     */
    function _addToRewardPool(uint256 amount, RewardType type_) internal {
        if (type_ == RewardType.LP) {
            uint256 newBalance = lpRewardPoolBalance + amount;
            require(newBalance >= lpRewardPoolBalance, "TokenStakingLP: LP overflow");
            lpRewardPoolBalance = newBalance;
            emit LPAddedToPool(amount);
        } else if (type_ == RewardType.TOKEN) {
            uint256 newBalance = tokenRewardPoolBalance + amount;
            require(newBalance >= tokenRewardPoolBalance, "TokenStakingLP: Token overflow");
            tokenRewardPoolBalance = newBalance;
            emit TokenAddedToPool(amount);
        } else if (type_ == RewardType.BNB) {
            uint256 newBalance = bnbRewardPoolBalance + amount;
            require(newBalance >= bnbRewardPoolBalance, "TokenStakingLP: BNB overflow");
            bnbRewardPoolBalance = newBalance;
            emit BNBAddedToPool(amount);
        }

        if ((type_ == RewardType.LP || type_ == RewardType.TOKEN)) {
            address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            
            if (totalStaked > 0) {
                uint256 increment = (amount * REWARD_PRECISION) / totalStaked;
                dailyRewardPerToken += increment;
            }
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
     */
    function claimLPReward() external nonReentrant whenNotPaused {
        address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(msg.sender);
        require(stake.amount > 0, "TokenStakingLP: No staked tokens");

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            uint256 reward = bnbRewardPoolBalance * stake.amount / (totalStaked + 1);
            if (reward > 0 && reward <= bnbRewardPoolBalance) {
                bnbRewardPoolBalance -= reward;
                payable(msg.sender).transfer(reward);
                emit BNBRewardsClaimed(msg.sender, reward);
            }
            return;
        }

        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = lastRewardAccumulatedRate[msg.sender];
        
        if (currentRate <= lastRate) {
            return;
        }

        uint256 reward = stake.amount * (currentRate - lastRate) / REWARD_PRECISION;
        
        if (currentType == RewardType.LP) {
            require(reward <= lpRewardPoolBalance, "TokenStakingLP: Insufficient LP");
            lpRewardPoolBalance -= reward;
            IAuthorizer(authorizer).redeemLPToUser(reward, msg.sender);
            emit LPRewardsClaimed(msg.sender, reward);
        } else if (currentType == RewardType.TOKEN) {
            require(reward <= tokenRewardPoolBalance, "TokenStakingLP: Insufficient Token");
            tokenRewardPoolBalance -= reward;
            IBEP20 token = IBEP20(IAuthorizer(authorizer).getToken());
            token.transfer(msg.sender, reward);
            emit TokenRewardsClaimed(msg.sender, reward);
        }

        lastRewardAccumulatedRate[msg.sender] = currentRate;
    }

    /**
     * @dev 查询待领取奖励
     * @param user 用户地址
     * @return uint256 待领取奖励金额
     */
    function getPendingLPReward(address user) external view returns (uint256) {
        address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
        ITokenStaking.StakeInfo memory stake = ITokenStaking(tokenStaking).getUserStake(user);
        if (stake.amount == 0) return 0;

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 totalStaked = ITokenStaking(tokenStaking).getTotalStaked();
            return bnbRewardPoolBalance * stake.amount / (totalStaked + 1);
        }
        
        uint256 currentRate = dailyRewardPerToken;
        uint256 lastRate = lastRewardAccumulatedRate[user];
        
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

    /**
     * @dev 设置每日释放比例
     * @param _rewardRate 新的奖励率（万分比）
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0 && _rewardRate <= maxRewardRate, "TokenStakingLP: Invalid reward rate");
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @dev 设置最大每日释放比例
     * @param _maxRewardRate 最大奖励率（万分比）
     */
    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        require(_maxRewardRate >= rewardRate, "TokenStakingLP: Max rate must be >= current rate");
        maxRewardRate = _maxRewardRate;
    }

    /**
     * @dev 设置每日最大释放百分比
     * @param _percent 百分比（千分比，100 = 10%）
     */
    function setMaxDailyRewardPercent(uint256 _percent) external onlyOwner {
        require(_percent > 0 && _percent <= 500, "TokenStakingLP: Invalid percent");
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

        address tokenStaking = IAuthorizer(authorizer).getTokenStaking();
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
        _adjustRewardRate(expectedDailyReward);

        uint256 dailyReward = poolBalance * rewardRate / DAILY_REWARD_PRECISION;
        uint256 maxDailyReward = poolBalance * maxDailyRewardPercent / 1000;
        
        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }

        if (dailyReward > 0) {
            uint256 increment = (dailyReward * STAKING_REWARD_PRECISION) / totalStaked;
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
        require(_rateStep > 0, "TokenStakingLP: Step must be > 0");
        rateStep = _rateStep;
    }
}
