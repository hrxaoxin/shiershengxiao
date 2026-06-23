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
    
    /** @dev LP分红池余额 */
    uint256 public lpDividendPoolBalance;
    
    /** @dev 用户待领取LP分红金额 */
    mapping(address => uint256) public pendingLPDividends;
    
    /** @dev 累计每权重LP分红（用于计算LP分红） */
    uint256 public cumulativePerWeightLPDividend;
    
    /** @dev 用户LP分红快照（记录用户上次领取时的累计分红值） */
    mapping(address => uint256) public userLPSnapshots;

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /**
     * @dev LP分红领取事件
     * @param user 用户地址
     * @param amount 领取LP数量
     */
    event DividendClaimed(address indexed user, uint256 amount);

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
     * @dev 回退函数：接收BNB并自动转换为LP
     */
    receive() external payable {
        if (msg.value > 0) {
            uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(msg.value);
            if (lpAmount > 0) {
                _addToLPDividendPool(lpAmount);
            }
        }
    }

    /**
     * @dev 记录流入的BNB并转换为LP
     * @param amount BNB数量
     */
    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        require(amount > 0, "DividendManagerLP: Amount must be > 0");
        uint256 lpAmount = IAuthorizer(authorizer).convertBNBToLP(amount);
        if (lpAmount > 0) {
            _addToLPDividendPool(lpAmount);
        }
    }

    /**
     * @dev 添加到LP分红池（内部函数）
     * @param lpAmount LP数量
     */
    function _addToLPDividendPool(uint256 lpAmount) internal {
        uint256 newBalance = lpDividendPoolBalance + lpAmount;
        require(newBalance >= lpDividendPoolBalance, "DividendManagerLP: LP overflow");
        lpDividendPoolBalance = newBalance;

        // 获取DividendManager总权重
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        uint256 totalWeight = IDividendManager(dividendManager).getTotalWeight();
        
        if (totalWeight > 0) {
            uint256 perWeightIncrement = (lpAmount * 1e18) / totalWeight;
            uint256 newCumulative = cumulativePerWeightLPDividend + perWeightIncrement;
            require(newCumulative >= cumulativePerWeightLPDividend, "DividendManagerLP: LP cumulative overflow");
            cumulativePerWeightLPDividend = newCumulative;
        }
    }

    /**
     * @dev 复利手续费（仅owner）
     */
    function compoundFees() external onlyOwner {
        IAuthorizer(authorizer).compoundFees();
    }

    /**
     * @dev 领取LP分红
     */
    function claimLPDividend() external nonReentrant whenNotPaused {
        // 获取用户权重
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        uint256 userWeight = IDividendManager(dividendManager).getUserWeight(msg.sender);
        require(userWeight > 0, "DividendManagerLP: No weight");

        uint256 cumulativeDiff = cumulativePerWeightLPDividend - userLPSnapshots[msg.sender];
        uint256 lpDividend = userWeight * cumulativeDiff / 1e18;
        
        if (lpDividend == 0) {
            return;
        }

        require(lpDividend <= lpDividendPoolBalance, "DividendManagerLP: Insufficient LP");

        lpDividendPoolBalance -= lpDividend;
        userLPSnapshots[msg.sender] = cumulativePerWeightLPDividend;

        IAuthorizer(authorizer).redeemLPToUser(lpDividend, msg.sender);
        emit DividendClaimed(msg.sender, lpDividend);
    }

    /**
     * @dev 获取用户可领取的LP分红金额
     * @param user 用户地址
     * @return 可领取的LP分红总额
     */
    function getClaimableLPDividend(address user) external view returns (uint256) {
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        uint256 userWeight = IDividendManager(dividendManager).getUserWeight(user);
        if (userWeight == 0) return pendingLPDividends[user];
        
        uint256 cumulativeDiff = cumulativePerWeightLPDividend - userLPSnapshots[user];
        uint256 newLPDividend = userWeight * cumulativeDiff / 1e18;
        return pendingLPDividends[user] + newLPDividend;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "DividendManagerLP: Invalid authorizer");
        authorizer = _authorizerAddress;
    }
}
