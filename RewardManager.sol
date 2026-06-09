// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

/**
 * @dev DEX Router 接口（兼容 Uniswap V2 标准）
 * 支持 FlapSwap、PancakeSwap、Uniswap
 */
interface IDEXRouter {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    
    function WETH() external pure returns (address);
    
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

/**
 * @title RewardManager
 * @dev 奖励管理合约，统一管理所有游戏奖励的分发
 *
 * 核心职责：
 * 1. 资金路由：接收游戏中产生的所有手续费、入场费、铸造费用统一归集
 *    → 按预设比例路由到四大奖励池
 * 2. 与 DividendManager、Staking、TokenStaking、ArenaRanking 的资金分发
 * 3. 提供 owner 应急操作：在特殊活动奖励、VIP 空投、活动奖励池注入等
 *
 * 奖励资金来源：
 * - NFTTrading.sol：交易手续费 5% 转入 RewardManager
 * - Battle.sol：战斗入场费的部分
 * - Breeding.sol：繁殖费用的部分
 * - TokenBurner.sol：铸造费用的部分
 * - PoolManager.sol：按 owner 可从池中注入
 *
 * 默认分配比例（可由 owner 调整）：
 * - 50% 进入分红池（DividendManager）
 * - 20% 进入 NFT 质押池（Staking）
 * - 15% 进入代币质押池（TokenStaking）
 * - 15% 进入竞技场奖励池（ArenaRanking）
 *
 * 资金流转模型：
 * - 外部合约 depositToken(address, amount) → 接收并分配
 * 1. 接收代币（ERC20）→ 按比例分配给四大奖励池
 *    - 50% 转账到 DividendManager.tokenDividendPool
 *    - 20% 转账到 Staking.poolBalances[POOL_NFT_STAKING]
 *    - 15% 转账到 TokenStaking.stakingPool
 *    - 15% 转账到 ArenaRanking.seasonPrizePool
 * 2. 接收 BNB（receive 回退函数）→ 同上分配
 *
 * 主要功能：
 * - depositToken / depositBNB：接收游戏手续费并按比例分配
 * - distributeRewards：手动触发分配（可选）
 * - claimDividend：用户领取分红（内部调用 DividendManager）
 * - setMinSwapAmount：设置最小金额（防止小额不分配，集中到池）
 * - emergencyWithdraw：紧急提取（owner only）
 *
 * 数据结构：
 * - dividendShare / stakingShare / tokenStakingShare / arenaShare
 * 分别记录各自池的历史流入流出
 *
 * 与其他合约联动：
 * - Authorizer：通过 Authorizer 管理 address 验证
 * - PriceOracle：读取当前价格以分配时用于奖励金额
 *
 * 安全限制：
 * - ReentrancyGuard：防止 claimDividend 时防止重入
 * - Pausable：暂停所有分配操作（维护）
 * - onlyOwner：设置分配比例、暂停等
 * - 最小金额 minSwapAmount：防止微小金额
 *
 * 典型流程：
 * 1. NFTTrading 产生 5% 手续费转入 RewardManager
 * 2. RewardManager 按比例分配到四个奖励池
 * 3. 用户领取时自动同步各池
 * 4. 前端同步各池分配给用户（质押/分红/竞技场奖励）
 *
 * 升级与治理：
 * - UUPS 可升级：未来可调整分配比例、新增奖励池
 */
contract RewardManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "RewardManager: Paused");
        _;
    }

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 代币合约地址
     */
    address public tokenContract;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "RewardManager: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "RewardManager: Invalid authorizer address");
        authorizer = a;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "RewardManager: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 分红池地址
     */
    address public dividendPool;

    /**
     * @dev NFT质押池地址
     */
    address public nftStakingPool;

    /**
     * @dev 代币质押池地址
     */
    address public tokenStakingPool;

    /**
     * @dev 竞技场奖励池地址
     */
    address public arenaRewardPool;

    /**
     * @dev 资金池管理合约地址（用于追踪各池余额）
     */
    address public poolManager;

    /**
     * @dev DEX Router 配置 - 支持 FlapSwap、PancakeSwap、Uniswap
     */
    address public dexRouter;
    address public wbnb;
    
    /**
     * @dev 自动兑换设置
     */
    bool public autoSwapEnabled = true;
    uint256 public minSwapAmount = 1000000000000000;  // 0.001 BNB
    
    /**
     * @dev 滑点保护参数（千分比）
     */
    uint256 public slippage = 100;  // 10%
    
    /**
     * @dev 当前活跃的DEX类型
     * 0: FlapSwap
     * 1: PancakeSwap
     * 2: Uniswap
     */
    uint8 public activeDEX;

    /**
     * @dev 奖励分配比例（精度4位小数，万分比）
     * 注意：setDistributionPercents 会校验总和必须等于 PRECISION（10000）
     */
    uint256 public dividendPercent = 5000;     // 50%
    uint256 public nftStakingPercent = 2000;   // 20%
    uint256 public tokenStakingPercent = 1500;  // 15%
    uint256 public arenaRewardPercent = 1500;   // 15%

    /**
     * @dev 设置分配比例（仅owner）
     * 四个比例之和必须严格等于 PRECISION（10000），即 100%
     */
    function setDistributionPercents(uint256 _dividend, uint256 _nftStaking, uint256 _tokenStaking, uint256 _arena) external onlyOwner {
        require(_dividend + _nftStaking + _tokenStaking + _arena == PRECISION, "RewardManager: Percentages must sum to 10000");
        dividendPercent = _dividend;
        nftStakingPercent = _nftStaking;
        tokenStakingPercent = _tokenStaking;
        arenaRewardPercent = _arena;
        emit DistributionPercentsChanged(_dividend, _nftStaking, _tokenStaking, _arena);
    }

    /**
     * @dev 分配比例变更事件
     */
    event DistributionPercentsChanged(uint256 dividend, uint256 nftStaking, uint256 tokenStaking, uint256 arena);

    /**
     * @dev 精度
     */
    uint256 public constant PRECISION = 10000;

    /**
     * @dev 累计分发总量（用于统计和前端展示）
     */
    uint256 public totalDistributed;

    /**
     * @dev 当前持有者数量（有分红资格的用户数）
     */
    uint256 public holdersCount;

    /**
     * @dev 用于追踪已记录的用户（用于 holdersCount 计数）
     */
    mapping(address => bool) private _isRecordedHolder;

    /**
     * @dev 奖励事件
     */
    event RewardDistributed(
        address indexed from,
        uint256 totalAmount,
        uint256 dividendAmount,
        uint256 nftStakingAmount,
        uint256 tokenStakingAmount,
        uint256 arenaRewardAmount
    );

    /**
     * @dev 设置分红池地址
     */
    function setDividendPool(address _dividendPool) external onlyAuthorized {
        require(_dividendPool != address(0), "RewardManager: Invalid dividend pool");
        dividendPool = _dividendPool;
    }

    /**
     * @dev 设置NFT质押池地址
     */
    function setNFTStakingPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "RewardManager: Invalid NFT staking pool");
        nftStakingPool = _pool;
    }

    /**
     * @dev 设置代币质押池地址
     */
    function setTokenStakingPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "RewardManager: Invalid token staking pool");
        tokenStakingPool = _pool;
    }

    /**
     * @dev 设置代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "RewardManager: Invalid token contract");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置竞技场奖励池地址
     */
    function setArenaRewardPool(address _pool) external onlyAuthorized {
        require(_pool != address(0), "RewardManager: Invalid arena reward pool");
        arenaRewardPool = _pool;
    }

    /**
     * @dev 设置资金池管理合约地址
     */
    function setPoolManager(address _poolManager) external onlyAuthorized {
        require(_poolManager != address(0), "RewardManager: Invalid pool manager address");
        poolManager = _poolManager;
    }

    /**
     * @dev 设置DEX Router地址（支持 FlapSwap、PancakeSwap、Uniswap）
     * @param _dexRouter DEX Router 合约地址
     * @param _dexType DEX类型：0=FlapSwap, 1=PancakeSwap, 2=Uniswap
     */
    function setDEXRouter(address _dexRouter, uint8 _dexType) external onlyOwner {
        require(_dexRouter != address(0), "RewardManager: Invalid DEX router");
        require(_dexType <= 2, "RewardManager: Invalid DEX type");
        
        dexRouter = _dexRouter;
        activeDEX = _dexType;
        // 自动获取 WBNB 地址
        wbnb = IDEXRouter(_dexRouter).WETH();
        
        emit DEXRouterUpdated(_dexRouter, _dexType);
    }

    /**
     * @dev 设置自动兑换开关
     */
    function setAutoSwapEnabled(bool enabled) external onlyOwner {
        autoSwapEnabled = enabled;
    }

    /**
     * @dev 设置最小兑换金额
     */
    function setMinSwapAmount(uint256 amount) external onlyOwner {
        require(amount > 0, "RewardManager: Amount must be greater than 0");
        minSwapAmount = amount;
    }

    /**
     * @dev 设置滑点保护
     */
    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= 2000, "RewardManager: Slippage too high (max 20%)");
        slippage = _slippage;
    }

    /**
     * @dev 接收BNB并自动处理
     */
    receive() external payable {
        if (msg.value > 0 && autoSwapEnabled && dexRouter != address(0)) {
            if (msg.value >= minSwapAmount) {
                _distributeBNB(msg.value);
            }
        }
    }

    /**
     * @dev 手动触发BNB分配（用于处理小额BNB或调试）
     */
    function distributeBNB() external onlyAuthorized nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            return; // 没有 BNB 可分配，直接返回而不是 revert，确保流程不中断
        }
        _distributeBNB(balance);
    }

    /**
     * @dev 内部函数：分配BNB到各池
     * - 分红池：直接转账BNB
     * - 代币质押池：直接转账BNB
     * - NFT质押池、竞技场奖励池：优先兑换为代币后转账；兑换失败时将 BNB 直接转入 dividendPool 作为价值储备
     */
    function _distributeBNB(uint256 amount) internal {
        if (amount == 0) {
            return; // 0 金额直接返回，不中断流程
        }
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        require(dexRouter != address(0), "RewardManager: DEX router not set");

        // 计算各池分配金额
        uint256 dividendAmount = amount * dividendPercent / PRECISION;
        uint256 nftStakingAmount = amount * nftStakingPercent / PRECISION;
        uint256 tokenStakingAmount = amount * tokenStakingPercent / PRECISION;
        uint256 arenaRewardAmount = amount * arenaRewardPercent / PRECISION;

        // 分红池：直接转账BNB
        if (dividendPool != address(0) && dividendAmount > 0) {
            (bool success, ) = payable(dividendPool).call{value: dividendAmount}("");
            if (success) {
                try IDividendManager(dividendPool).syncDividendPool() {} catch {}
            } else {
                emit BNBTransferFailed(0, dividendPool, dividendAmount);
            }
        }

        // 代币质押池：直接转账BNB
        if (tokenStakingPool != address(0) && tokenStakingAmount > 0) {
            (bool success, ) = payable(tokenStakingPool).call{value: tokenStakingAmount}("");
            if (success) {
                if (poolManager != address(0)) {
                    try IPoolManager(poolManager).addToTokenStakingPool(tokenStakingAmount) {} catch {}
                }
            } else {
                emit BNBTransferFailed(2, tokenStakingPool, tokenStakingAmount);
            }
        }

        // 需要兑换为代币的总金额（仅NFT质押池和竞技场奖励池）
        uint256 totalSwapAmount = nftStakingAmount + arenaRewardAmount;
        
        if (totalSwapAmount > 0) {
            // 兑换 BNB -> 代币
            uint256 tokenAmount = _swapBNBToToken(totalSwapAmount);
            
            if (tokenAmount > 0) {
                // 分配兑换后的代币到NFT质押池和竞技场奖励池
                _distributeSwappedTokens(tokenAmount, 0, nftStakingAmount, arenaRewardAmount, totalSwapAmount);
            } else {
                // 兑换失败时，将未兑换的BNB作为价值储备转入分红池（最终回退）
                if (dividendPool != address(0)) {
                    (bool fbSuccess, ) = payable(dividendPool).call{value: totalSwapAmount}("");
                    if (fbSuccess) {
                        try IDividendManager(dividendPool).syncDividendPool() {} catch {}
                        emit SwapFailedFallback(totalSwapAmount);
                    } else {
                        // 如果连分红池转账也失败，发出最终失败事件（BNB 保留在合约中）
                        emit SwapFailed(totalSwapAmount);
                    }
                } else {
                    emit SwapFailed(totalSwapAmount);
                }
            }
        }

        emit BNBDistributed(msg.sender, amount, dividendAmount, nftStakingAmount, tokenStakingAmount, arenaRewardAmount);
    }

    /**
     * @dev 内部函数：将BNB兑换为代币
     */
    function _swapBNBToToken(uint256 bnbAmount) internal returns (uint256) {
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = tokenContract;

        // 获取预估输出金额并计算滑点
        uint256[] memory amounts = IDEXRouter(dexRouter).getAmountsOut(bnbAmount, path);
        uint256 expectedOut = amounts[1];
        uint256 minOut = expectedOut * (1000 - slippage) / 1000;

        try IDEXRouter(dexRouter).swapExactETHForTokens{value: bnbAmount}(
            minOut,
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory outputAmounts) {
            emit BNBConverted(bnbAmount, outputAmounts[1]);
            return outputAmounts[1];
        } catch {
            emit SwapFailed(bnbAmount);
            return 0;
        }
    }

    /**
     * @dev 内部函数：分配兑换后的代币到NFT质押池和竞技场奖励池
     * 分红池和代币质押池直接使用BNB，不需要兑换
     */
    function _distributeSwappedTokens(
        uint256 totalTokenAmount,
        uint256 /*dividendBNBAmount*/,
        uint256 nftStakingBNBAmount,
        uint256 arenaRewardBNBAmount,
        uint256 totalBNBAmount
    ) internal {
        IERC20 token = IERC20(tokenContract);
        
        // 计算各池应得代币数量（按BNB金额比例）
        uint256 nftStakingTokenAmount = totalTokenAmount * nftStakingBNBAmount / totalBNBAmount;
        uint256 arenaRewardTokenAmount = totalTokenAmount * arenaRewardBNBAmount / totalBNBAmount;

        // 分配到NFT质押池
        if (nftStakingPool != address(0) && nftStakingTokenAmount > 0) {
            try token.transfer(nftStakingPool, nftStakingTokenAmount) {
                if (poolManager != address(0)) {
                    try IPoolManager(poolManager).addToNFTStakingPool(nftStakingTokenAmount) {} catch {}
                }
            } catch {
                emit RewardTransferFailed(1, nftStakingPool, nftStakingTokenAmount);
            }
        }

        // 分配到竞技场奖励池
        if (arenaRewardPool != address(0) && arenaRewardTokenAmount > 0) {
            try token.transfer(arenaRewardPool, arenaRewardTokenAmount) {
                if (poolManager != address(0)) {
                    try IPoolManager(poolManager).addToArenaRewardPool(arenaRewardTokenAmount) {} catch {}
                }
            } catch {
                emit RewardTransferFailed(3, arenaRewardPool, arenaRewardTokenAmount);
            }
        }
    }

    // DEX相关事件
    event DEXRouterUpdated(address indexed router, uint8 indexed dexType);
    event BNBConverted(uint256 bnbAmount, uint256 tokenAmount);
    event SwapFailed(uint256 bnbAmount);
    event SwapFailedFallback(uint256 bnbAmount);
    event BNBDistributed(address indexed from, uint256 totalAmount, uint256 dividendAmount, uint256 nftStakingAmount, uint256 tokenStakingAmount, uint256 arenaRewardAmount);
    event BNBTransferFailed(uint256 poolType, address pool, uint256 amount);

    /**
     * @dev 添加质押池奖励
     */
    function addStakingReward(uint256 amount, uint256 poolType) external onlyAuthorized whenNotPaused {
        require(amount > 0, "RewardManager: Invalid amount");
        require(tokenContract != address(0), "RewardManager: Token contract not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(msg.sender) >= amount, "RewardManager: Insufficient balance");

        if (poolType == 0 && nftStakingPool != address(0)) {
            token.safeTransferFrom(msg.sender, nftStakingPool, amount);
        } else if (poolType == 1 && tokenStakingPool != address(0)) {
            token.safeTransferFrom(msg.sender, tokenStakingPool, amount);
        } else if (poolType == 2 && arenaRewardPool != address(0)) {
            token.safeTransferFrom(msg.sender, arenaRewardPool, amount);
        }
    }

    /**
     * @dev 用户可领取分红映射
     * user => pendingDividend
     */
    mapping(address => uint256) public pendingDividends;
    
    /**
     * @dev 用户权重映射
     * user => weight
     */
    mapping(address => uint256) public userWeights;

    /**
     * @dev 分红发放事件
     */
    event DividendClaimed(address indexed user, uint256 amount);

    /**
     * @dev 领取分红（无参版本，前端直接调用 - 领取 msg.sender 的分红）
     */
    function claimDividend() external whenNotPaused nonReentrant returns (uint256) {
        address user = msg.sender;
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        
        uint256 dividend = pendingDividends[user];
        require(dividend > 0, "RewardManager: No pending dividend");
        
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "RewardManager: Insufficient contract balance");
        
        pendingDividends[user] = 0;
        
        require(token.transfer(user, dividend), "RewardManager: Transfer failed");
        
        emit DividendClaimed(user, dividend);
        return dividend;
    }

    /**
     * @dev 领取分红（带参数版本 - owner/authorizer 可为其他用户领取）
     */
    function claimDividendFor(address user) external whenNotPaused nonReentrant returns (uint256) {
        require(
            msg.sender == owner() || msg.sender == authorizer,
            "RewardManager: Not authorized to claim for other users"
        );
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        require(user != address(0), "RewardManager: Invalid user address");
        
        uint256 dividend = pendingDividends[user];
        require(dividend > 0, "RewardManager: No pending dividend");
        
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "RewardManager: Insufficient contract balance");
        
        pendingDividends[user] = 0;
        
        require(token.transfer(user, dividend), "RewardManager: Transfer failed");
        
        emit DividendClaimed(user, dividend);
        return dividend;
    }

    /**
     * @dev 获取用户可领取分红
     */
    function getDividend(address user) external view returns (uint256) {
        return pendingDividends[user];
    }

    /**
     * @dev 计算用户可领取分红（前端调用）
     */
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        return (pendingDividends[user], userWeights[user]);
    }
    
    /**
     * @dev 获取用户待领取分红（仅返回金额）
     */
    function getUserPendingDividend(address user) external view returns (uint256) {
        return pendingDividends[user];
    }

    /**
     * @dev 获取分红池余额
     */
    function dividendPoolBalance() external view returns (uint256) {
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        return IERC20(tokenContract).balanceOf(dividendPool);
    }

    /**
     * @dev 分配奖励到各个池
     */
    function _distributeReward(uint256 amount) internal {
        require(tokenContract != address(0), "RewardManager: Token contract not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "RewardManager: Insufficient contract balance");

        uint256 dividendAmount = amount * dividendPercent / PRECISION;
        uint256 nftStakingAmount = amount * nftStakingPercent / PRECISION;
        uint256 tokenStakingAmount = amount * tokenStakingPercent / PRECISION;
        uint256 arenaRewardAmount = amount * arenaRewardPercent / PRECISION;

        // 使用try-catch分别处理每个分配，允许部分成功
        if (dividendPool != address(0) && dividendAmount > 0) {
            try token.transfer(dividendPool, dividendAmount) {
                // 同步 DividendManager 分红池，使转账的代币被正确计入分红计算
                try IDividendManager(dividendPool).syncDividendPool() {} catch {}
            } catch {
                emit RewardTransferFailed(0, dividendPool, dividendAmount);
            }
        }
        if (nftStakingPool != address(0) && nftStakingAmount > 0) {
            try token.transfer(nftStakingPool, nftStakingAmount) {
                if (poolManager != address(0)) {
                    try IPoolManager(poolManager).addToNFTStakingPool(nftStakingAmount) {} catch {}
                }
            } catch {
                emit RewardTransferFailed(1, nftStakingPool, nftStakingAmount);
            }
        }
        if (tokenStakingPool != address(0) && tokenStakingAmount > 0) {
            try token.transfer(tokenStakingPool, tokenStakingAmount) {
                if (poolManager != address(0)) {
                    try IPoolManager(poolManager).addToTokenStakingPool(tokenStakingAmount) {} catch {}
                }
            } catch {
                emit RewardTransferFailed(2, tokenStakingPool, tokenStakingAmount);
            }
        }
        if (arenaRewardPool != address(0) && arenaRewardAmount > 0) {
            try token.transfer(arenaRewardPool, arenaRewardAmount) {
                if (poolManager != address(0)) {
                    try IPoolManager(poolManager).addToArenaRewardPool(arenaRewardAmount) {} catch {}
                }
            } catch {
                emit RewardTransferFailed(3, arenaRewardPool, arenaRewardAmount);
            }
        }

        totalDistributed += amount;
        _addDistributionRecord(amount, dividendAmount, nftStakingAmount, tokenStakingAmount, arenaRewardAmount);

        emit RewardDistributed(
            msg.sender,
            amount,
            dividendAmount,
            nftStakingAmount,
            tokenStakingAmount,
            arenaRewardAmount
        );
    }

    /**
     * @dev 在分配到用户分红时记录新的持有者
     */
    function _recordHolder(address user) internal {
        if (user != address(0) && !_isRecordedHolder[user]) {
            _isRecordedHolder[user] = true;
            holdersCount++;
        }
    }

    event RewardTransferFailed(uint256 poolType, address pool, uint256 amount);
    
    /**
     * @dev 内部函数：添加分发记录（使用环形缓冲区）
     */
    function _addDistributionRecord(
        uint256 totalAmount,
        uint256 dividendAmount,
        uint256 nftStakingAmount,
        uint256 tokenStakingAmount,
        uint256 arenaRewardAmount
    ) internal {
        DistributionRecord memory record = DistributionRecord({
            timestamp: block.timestamp,
            totalAmount: totalAmount,
            dividendAmount: dividendAmount,
            nftStakingAmount: nftStakingAmount,
            tokenStakingAmount: tokenStakingAmount,
            arenaRewardAmount: arenaRewardAmount,
            distributor: msg.sender
        });
        
        if (distributionHistory.length < MAX_DISTRIBUTION_RECORDS) {
            distributionHistory.push(record);
        } else {
            distributionHistory[distributionHistoryStartIndex] = record;
            distributionHistoryStartIndex = (distributionHistoryStartIndex + 1) % MAX_DISTRIBUTION_RECORDS;
        }
    }

    /**
     * @dev 获取分配比例
     */
    function getDistributionPercents() external view returns (
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (dividendPercent, nftStakingPercent, tokenStakingPercent, arenaRewardPercent);
    }

    /**
     * @dev 分发历史记录结构体
     */
    struct DistributionRecord {
        uint256 timestamp;
        uint256 totalAmount;
        uint256 dividendAmount;
        uint256 nftStakingAmount;
        uint256 tokenStakingAmount;
        uint256 arenaRewardAmount;
        address distributor;
    }

    /**
     * @dev 分发历史记录数组（使用环形缓冲区）
     */
    DistributionRecord[] public distributionHistory;
    
    /**
     * @dev 最大分发历史记录数
     */
    uint256 public constant MAX_DISTRIBUTION_RECORDS = 1000;
    
    /**
     * @dev 分发历史记录起始索引（环形缓冲区）
     */
    uint256 public distributionHistoryStartIndex;

    /**
     * @dev 获取分发历史记录长度
     */
    function getDistributionHistoryLength() external view returns (uint256) {
        return distributionHistory.length;
    }

    /**
     * @dev 获取指定范围的分发历史
     * @param startIndex 起始索引（逻辑索引）
     * @param count 获取数量
     */
    function getDistributionHistory(uint256 startIndex, uint256 count) external view returns (DistributionRecord[] memory) {
        require(startIndex < distributionHistory.length, "RewardManager: Invalid start index");
        require(count > 0, "RewardManager: Invalid count");

        uint256 totalCount = distributionHistory.length;
        uint256 endIndex = startIndex + count;
        if (endIndex > totalCount) {
            endIndex = totalCount;
        }

        DistributionRecord[] memory records = new DistributionRecord[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 actualIndex = (distributionHistoryStartIndex + i) % totalCount;
            records[i - startIndex] = distributionHistory[actualIndex];
        }

        return records;
    }

    /**
     * @dev 获取最新N条分发记录
     * @param count 记录数量
     */
    function getRecentDistributions(uint256 count) external view returns (DistributionRecord[] memory) {
        if (distributionHistory.length == 0) {
            return new DistributionRecord[](0);
        }

        uint256 totalCount = distributionHistory.length;
        if (count > totalCount) {
            count = totalCount;
        }

        DistributionRecord[] memory records = new DistributionRecord[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 logicalIndex = totalCount - count + i;
            uint256 actualIndex = (distributionHistoryStartIndex + logicalIndex) % totalCount;
            records[i] = distributionHistory[actualIndex];
        }

        return records;
    }

    /**
     * @dev 获取奖励池统计
     * @return dividendPoolBalance NFT质押池余额
     * @return tokenStakingBalance 代币质押池余额
     * @return arenaRewardBalance 竞技场奖励池余额
     * @return totalDistributed 总分发金额
     */
    function getRewardPoolStats() external view returns (
        uint256 dividendPoolBalance,
        uint256 tokenStakingBalance,
        uint256 arenaRewardBalance,
        uint256 totalDistributed
    ) {
        IERC20 token = IERC20(tokenContract);

        if (dividendPool != address(0)) {
            dividendPoolBalance = token.balanceOf(dividendPool);
        }
        if (tokenStakingPool != address(0)) {
            tokenStakingBalance = token.balanceOf(tokenStakingPool);
        }
        if (arenaRewardPool != address(0)) {
            arenaRewardBalance = token.balanceOf(arenaRewardPool);
        }

        totalDistributed = 0;
        for (uint256 i = 0; i < distributionHistory.length; i++) {
            totalDistributed += distributionHistory[i].totalAmount;
        }
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "RewardManager: Amount must be > 0");
        require(amount <= address(this).balance, "RewardManager: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "RewardManager: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "RewardManager: Amount must be > 0");
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "RewardManager: Insufficient token balance");
        require(token.transfer(owner(), amount), "RewardManager: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
}
