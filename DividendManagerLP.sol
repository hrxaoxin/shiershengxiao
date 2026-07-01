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
 * @title DividendManagerLP
 * @dev 分红管理LP奖励合约，负责管理NFT分红池的LP奖励分发
 * 
 * 核心功能：
 * 1. LP分红池管理：接收BNB并转换为LP份额
 * 2. LP分红分发：根据用户权重分配LP分红
 * 3. 分红领取：用户领取应得的LP分红，自动兑换为代币+WBNB
 * 
 * 奖励机制：
 * - 全局累积每权重LP分红（cumulativePerWeightLPDividend）持续累积
 * - 用户领取时计算其快照与当前值的差值 × 用户权重 = 应得LP分红
 * - 用户快照（userLPSnapshots）记录上次领取时的累积值，防止重复计算
 * 
 * 与DividendManager合约的交互：
 * - 通过IAuthorizer获取DividendManager地址
 * - 直接读取DividendManager的用户权重计算LP分红分配
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - onlyOwnerOrAuthorizer：管理权限控制
 */
contract DividendManagerLP is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using LPLib for IAuthorizer;
    
    /** @dev 授权合约地址 */
    address public authorizer;
    
    /** @dev 当前奖励类型 */
    RewardType public rewardType;
    
    /** @dev LP分红池余额 */
    uint256 public lpDividendPoolBalance;
    /** @dev 代币分红池余额 */
    uint256 public tokenDividendPoolBalance;
    /** @dev BNB分红池余额 */
    uint256 public bnbDividendPoolBalance;
    
    /** @dev 当前纪元 */
    uint256 public epoch;
    
    /** @dev 用户待领取代币分红金额（epoch => 用户地址 => 金额） */
    mapping(uint256 => mapping(address => uint256)) public pendingTokenDividends;
    
    /** @dev 累计每权重分红（用于计算LP和代币分红） */
    uint256 public cumulativePerWeightDividend;
    
    /** @dev 用户分红快照（epoch => 用户地址 => 快照值） */
    mapping(uint256 => mapping(address => uint256)) public userRewardSnapshots;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev LP分红领取事件
     * @param user 用户地址
     * @param amount 领取LP数量
     */
    event LPDividendClaimed(address indexed user, uint256 amount);
    
    /** @dev 代币分红领取事件
     * @param user 用户地址
     * @param amount 领取代币数量
     */
    event TokenDividendClaimed(address indexed user, uint256 amount);
    
    /** @dev BNB分红领取事件
     * @param user 用户地址
     * @param amount 领取BNB数量
     */
    event BNBDividendClaimed(address indexed user, uint256 amount);

    /** @dev LP分红添加事件 */
    event LPAddedToDividendPool(uint256 amount);
    /** @dev 代币分红添加事件 */
    event TokenAddedToDividendPool(uint256 amount);
    /** @dev BNB分红添加事件 */
    event BNBAddedToDividendPool(uint256 amount);

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
        require(_authorizerAddress != address(0), "DividendManagerLP: Invalid authorizer");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
        rewardType = RewardType.LP;
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
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "DividendManagerLP: Not authorized");
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
        require(amount > 0, "DividendManagerLP: Amount must be > 0");
        _processIncomingBNB(amount);
    }

    /**
     * @dev 接收ERC20代币（WBNB或Token）并根据奖励类型处理
     * @param token 代币地址
     * @param amount 代币数量
     */
    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        require(token != address(0), "DividendManagerLP: Invalid token address");
        require(amount > 0, "DividendManagerLP: Amount must be > 0");
        
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        _processIncomingToken(token, amount);
    }

    /**
     * @dev 批量接收多种资产
     * @param tokens 代币地址数组
     * @param amounts 代币数量数组
     */
    function receiveMultipleTokens(address[] calldata tokens, uint256[] calldata amounts) external onlyOwnerOrAuthorizer {
        require(tokens.length == amounts.length, "DividendManagerLP: Arrays length mismatch");
        
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
                _addToDividendPool(lpAmount, currentType);
            }
        } else if (currentType == RewardType.TOKEN) {
            uint256 tokenAmount = IAuthorizer(authorizer).swapBNBToToken(amount);
            if (tokenAmount > 0) {
                _addToDividendPool(tokenAmount, currentType);
            }
        } else if (currentType == RewardType.BNB) {
            _addToDividendPool(amount, currentType);
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
                    _addToDividendPool(lpAmount, currentType);
                }
            } else if (currentType == RewardType.TOKEN) {
                uint256 tokenAmount = IAuthorizer(authorizer).swapWBNBToToken(amount);
                if (tokenAmount > 0) {
                    _addToDividendPool(tokenAmount, currentType);
                }
            } else if (currentType == RewardType.BNB) {
                IWBNB(wbnb).withdraw(amount);
                _addToDividendPool(amount, currentType);
            }
        } else if (token == mainToken) {
            if (currentType == RewardType.LP) {
                uint256 lpAmount = IAuthorizer(authorizer).convertTokenToLP(amount);
                if (lpAmount > 0) {
                    _addToDividendPool(lpAmount, currentType);
                }
            } else if (currentType == RewardType.TOKEN) {
                _addToDividendPool(amount, currentType);
            } else if (currentType == RewardType.BNB) {
                uint256 bnbAmount = IAuthorizer(authorizer).swapTokenToBNB(amount);
                if (bnbAmount > 0) {
                    _addToDividendPool(bnbAmount, currentType);
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
     * @dev 添加到分红池（内部函数）
     * @param amount 分红数量
     * @param type_ 分红类型
     */
    function _addToDividendPool(uint256 amount, RewardType type_) internal {
        if (type_ == RewardType.LP) {
            uint256 newBalance = lpDividendPoolBalance + amount;
            require(newBalance >= lpDividendPoolBalance, "DividendManagerLP: LP overflow");
            lpDividendPoolBalance = newBalance;
            emit LPAddedToDividendPool(amount);
        } else if (type_ == RewardType.TOKEN) {
            uint256 newBalance = tokenDividendPoolBalance + amount;
            require(newBalance >= tokenDividendPoolBalance, "DividendManagerLP: Token overflow");
            tokenDividendPoolBalance = newBalance;
            emit TokenAddedToDividendPool(amount);
        } else if (type_ == RewardType.BNB) {
            uint256 newBalance = bnbDividendPoolBalance + amount;
            require(newBalance >= bnbDividendPoolBalance, "DividendManagerLP: BNB overflow");
            bnbDividendPoolBalance = newBalance;
            emit BNBAddedToDividendPool(amount);
        }

        if (type_ == RewardType.LP || type_ == RewardType.TOKEN) {
            address dividendManager = IAuthorizer(authorizer).getDividendManager();
            uint256 totalWeight = IDividendManager(dividendManager).getTotalWeight();
            
            if (totalWeight > 0) {
                uint256 perWeightIncrement = (amount * 1e18) / totalWeight;
                uint256 newCumulative = cumulativePerWeightDividend + perWeightIncrement;
                require(newCumulative >= cumulativePerWeightDividend, "DividendManagerLP: Cumulative overflow");
                cumulativePerWeightDividend = newCumulative;
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
        IAuthorizer auth = IAuthorizer(authorizer);
        if (fromType == RewardType.LP && toType == RewardType.TOKEN) {
            if (lpDividendPoolBalance > 0) {
                uint256 tokenAmount = auth.redeemLPToToken(lpDividendPoolBalance);
                lpDividendPoolBalance = 0;
                if (tokenAmount > 0) {
                    tokenDividendPoolBalance += tokenAmount;
                }
            }
        } else if (fromType == RewardType.LP && toType == RewardType.BNB) {
            if (lpDividendPoolBalance > 0) {
                uint256 wbnbAmount = auth.redeemLPToWBNB(lpDividendPoolBalance);
                lpDividendPoolBalance = 0;
                if (wbnbAmount > 0) {
                    bnbDividendPoolBalance += wbnbAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.LP) {
            if (tokenDividendPoolBalance > 0) {
                uint256 lpAmount = auth.convertTokenToLP(tokenDividendPoolBalance);
                tokenDividendPoolBalance = 0;
                if (lpAmount > 0) {
                    lpDividendPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.TOKEN && toType == RewardType.BNB) {
            if (tokenDividendPoolBalance > 0) {
                uint256 bnbAmount = auth.swapTokenToBNB(tokenDividendPoolBalance);
                tokenDividendPoolBalance = 0;
                if (bnbAmount > 0) {
                    bnbDividendPoolBalance += bnbAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.LP) {
            if (bnbDividendPoolBalance > 0) {
                uint256 lpAmount = auth.convertBNBToLP(bnbDividendPoolBalance);
                bnbDividendPoolBalance = 0;
                if (lpAmount > 0) {
                    lpDividendPoolBalance += lpAmount;
                }
            }
        } else if (fromType == RewardType.BNB && toType == RewardType.TOKEN) {
            if (bnbDividendPoolBalance > 0) {
                uint256 tokenAmount = auth.swapBNBToToken(bnbDividendPoolBalance);
                bnbDividendPoolBalance = 0;
                if (tokenAmount > 0) {
                    tokenDividendPoolBalance += tokenAmount;
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
     * @dev 领取分红
     */
    function claimLPDividend() external nonReentrant whenNotPaused {
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        uint256 userWeight = IDividendManager(dividendManager).getUserWeight(msg.sender);
        require(userWeight > 0, "DividendManagerLP: No weight");

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 totalWeight = IDividendManager(dividendManager).getTotalWeight();
            uint256 reward = bnbDividendPoolBalance * userWeight / (totalWeight + 1);
            if (reward > 0 && reward <= bnbDividendPoolBalance) {
                bnbDividendPoolBalance -= reward;
                payable(msg.sender).transfer(reward);
                emit BNBDividendClaimed(msg.sender, reward);
            }
            return;
        }

        uint256 currentEpoch = _currentEpoch();
        uint256 cumulativeDiff = cumulativePerWeightDividend - userRewardSnapshots[currentEpoch][msg.sender];
        uint256 dividend = userWeight * cumulativeDiff / 1e18;
        
        if (dividend == 0) {
            return;
        }

        if (currentType == RewardType.LP) {
            require(dividend <= lpDividendPoolBalance, "DividendManagerLP: Insufficient LP");
            lpDividendPoolBalance -= dividend;
            IAuthorizer(authorizer).redeemLPToUser(dividend, msg.sender);
            emit LPDividendClaimed(msg.sender, dividend);
        } else if (currentType == RewardType.TOKEN) {
            require(dividend <= tokenDividendPoolBalance, "DividendManagerLP: Insufficient Token");
            tokenDividendPoolBalance -= dividend;
            IBEP20 token = IBEP20(IAuthorizer(authorizer).getToken());
            token.transfer(msg.sender, dividend);
            emit TokenDividendClaimed(msg.sender, dividend);
        }

        userRewardSnapshots[currentEpoch][msg.sender] = cumulativePerWeightDividend;
    }

    /**
     * @dev 获取用户可领取的分红金额
     * @param user 用户地址
     * @return 可领取的分红总额
     */
    function getClaimableLPDividend(address user) external view returns (uint256) {
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        uint256 userWeight = IDividendManager(dividendManager).getUserWeight(user);
        
        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            if (userWeight == 0) return 0;
            uint256 totalWeight = IDividendManager(dividendManager).getTotalWeight();
            return bnbDividendPoolBalance * userWeight / (totalWeight + 1);
        }
        
        uint256 currentEpoch = _currentEpoch();
        if (userWeight == 0) return pendingTokenDividends[currentEpoch][user];
        
        uint256 cumulativeDiff = cumulativePerWeightDividend - userRewardSnapshots[currentEpoch][user];
        uint256 newDividend = userWeight * cumulativeDiff / 1e18;
        return pendingTokenDividends[currentEpoch][user] + newDividend;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "DividendManagerLP: Invalid authorizer");
        authorizer = _authorizerAddress;
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
        require(token != address(0), "DividendManagerLP: Invalid token");
        require(to != address(0), "DividendManagerLP: Invalid recipient");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(to, balance);
        }
    }

    /**
     * @dev 提取BNB（仅owner）
     * @param to 接收地址
     */
    function withdrawBNB(address to) external onlyOwner {
        require(to != address(0), "DividendManagerLP: Invalid recipient");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(to).transfer(balance);
        }
    }

    function pendingTokenDividends(address user) external view returns (uint256) {
        return pendingTokenDividends[_currentEpoch()][user];
    }

    function userRewardSnapshots(address user) external view returns (uint256) {
        return userRewardSnapshots[_currentEpoch()][user];
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch++;
        lpDividendPoolBalance = 0;
        tokenDividendPoolBalance = 0;
        bnbDividendPoolBalance = 0;
        cumulativePerWeightDividend = 0;
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}
