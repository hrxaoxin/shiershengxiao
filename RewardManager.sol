// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";

/**
 * @title RewardManager
 * @dev 奖励管理合约，统一管理所有游戏奖励的分发
 *
 * 核心职责：
 * 1. 资金路由：接收游戏中产生的所有手续费、入场费、铸造费用统一归集
 *    2. 按预设比例路由到五大奖励池
 * 2. 向 DividendManager、Staking、TokenStaking、ArenaRanking、NFTBuyback 的资金分发
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
 * - 40% 进入分红池（DividendManager）
 * - 20% 进入 NFT 质押池（Staking）
 * - 15% 进入代币质押池（TokenStaking）
 * - 15% 进入竞技场奖励池（ArenaRanking）
 * - 10% 进入 NFT 回购销毁池（NFTBuyback）
 *
 * 资金流转模型：
 * - 外部合约 depositToken(address, amount) 或 接收并分发
 * 1. 接收代币（ERC20）→ 按比例分配给五大奖励池
 *    - 40% 转账至 DividendManager.tokenDividendPool
 *    - 20% 转账至 Staking.poolBalances[POOL_NFT_STAKING]
 *    - 15% 转账至 TokenStaking.stakingPool
 *    - 15% 转账至 ArenaRanking.seasonPrizePool
 *    - 10% 转账至 NFTBuyback 合约（用于回购销毁NFT）
 * 2. 接收 BNB（receive 回退函数）→ 同上分配
 *
 * 主要功能：
 * - depositToken / depositBNB：接收游戏手续费并按比例分配
 * - distributeRewards：手动触发分配（可选）
 * - claimDividend：用户领取分红（内部调用 DividendManager）
 * - setMinSwapAmount：设置最小金额（防止小额不分配，集中到池中）
 * - emergencyWithdraw：紧急提取（owner only）
 * - setNFTBuybackPool：设置NFT回购销毁池地址
 *
 * 数据结构：
 * - dividendShare / stakingShare / tokenStakingShare / arenaShare / buybackShare
 * 分别记录各自池的历史流入流出
 *
 * 与其他合约联动：
 * - Authorizer：通过 Authorizer 管理 address 验证
 * - PriceOracle：读取当前价格以分配时用于奖励金额
 * - NFTBuyback：10%资金用于回购销毁NFT，减少流通量
 *
 * 安全限制：
 * - ReentrancyGuard：防止 claimDividend 时防止重入
 * - Pausable：暂停所有分配操作（维护时）
 * - onlyOwner：设置分配比例、暂停等
 * - 最小金额 minSwapAmount：防止微小金额
 *
 * 典型流程：
 * 1. NFTTrading 产生 5% 手续费转入 RewardManager
 * 2. RewardManager 按比例分配到五个奖励池
 * 3. 用户领取时自动同步各池
 * 4. 前端同步各池分配给用户（质押/分红/竞技场奖励）
 * 5. 10%资金进入NFTBuyback用于回购销毁，减少代币流通量
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

    /**
     * @dev 合约暂停事件
     * @param account 执行暂停操作的账户
     * @param reason 暂停原因
     */
    event Paused(address account, string reason);
    
    /**
     * @dev 合约取消暂停事件
     * @param account 执行取消暂停操作的账户
     */
    event Unpaused(address account);

    /**
     * @dev 暂停修饰器：确保合约未处于暂停状态时才能执行函数
     */
    modifier whenNotPaused() {
        require(!paused, "RewardManager: Paused");
        _;
    }

    /**
     * @dev 暂停合约，停止所有奖励分发操作
     * 仅合约所有者可调用，用于紧急情况下暂停服务
     * @param reason 暂停原因，将被记录在事件日志中
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消合约暂停，恢复奖励分发操作
     * 仅合约所有者可调用
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 授权管理合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "RewardManager: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        epoch = 1;
        
        // 初始化带默认值的参数
        autoSwapEnabled = true;
        minSwapAmount = 1000000000000000;
        slippage = 1000;
        dividendPercent = 4000;
        nftStakingPercent = 2000;
        tokenStakingPercent = 1500;
        arenaRewardPercent = 1500;
        nftBuybackPercent = 1000;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "RewardManager: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "RewardManager: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    
    
    /**
     * @dev 自动兑换设置
     */
    bool public autoSwapEnabled = true;
    uint256 public minSwapAmount = 1000000000000000;  // 0.001 BNB
    
    /**
     * @dev 滑点保护参数（万分比）
     * 注意：slippage 使用万分比精度，100 = 1%, 1000 = 10%
     */
    uint256 public slippage = 1000;  // 默认10%滑点保护
    
    /**
     * @dev 当前活跃的DEX类型
     * 0: FlapSwap
     * 1: PancakeSwap
     * 2: Uniswap
     */
    uint8 public activeDEX;

    /**
     * @dev 奖励分配比例（精度四位小数，万分比）
     * 注意：setDistributionPercents 会校验总和必须等于 PRECISION（10000）
     */
    uint256 public dividendPercent = 4000;     // 40%
    uint256 public nftStakingPercent = 2000;   // 20%
    uint256 public tokenStakingPercent = 1500;  // 15%
    uint256 public arenaRewardPercent = 1500;   // 15%
    uint256 public nftBuybackPercent = 1000;    // 10%（用于NFT回购销毁）

    /**
     * @dev 设置分配比例（仅owner）
     * 五个比例之和必须严格等于 PRECISION（10000），即 100%
     */
    function setDistributionPercents(uint256 _dividend, uint256 _nftStaking, uint256 _tokenStaking, uint256 _arena, uint256 _nftBuyback) external onlyOwner {
        require(_dividend + _nftStaking + _tokenStaking + _arena + _nftBuyback == PRECISION, "RewardManager: Percentages must sum to 10000");
        dividendPercent = _dividend;
        nftStakingPercent = _nftStaking;
        tokenStakingPercent = _tokenStaking;
        arenaRewardPercent = _arena;
        nftBuybackPercent = _nftBuyback;
        emit DistributionPercentsChanged(_dividend, _nftStaking, _tokenStaking, _arena, _nftBuyback);
    }

    /**
     * @dev 分配比例变更事件
     */
    event DistributionPercentsChanged(uint256 dividend, uint256 nftStaking, uint256 tokenStaking, uint256 arenaReward, uint256 nftBuyback);

    /**
     * @dev 精度
     */
    uint256 public constant PRECISION = 10000;

    /**
     * @dev 纪元版本号，用于快速重置合约数据
     * @dev 纪元版本号，用于快速重置合约数据（循环复用，MAX_EPOCHS次后回到0）
     */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;

    /**
     * @dev 累计分发总量（用于统计和前端展示）
     */
    uint256 public totalDistributed;

    /**
     * @dev 当前持有者数量（有分红资格的用户数）
     */
    uint256 public holdersCount;
    
    /**
     * @dev 锁定的BNB金额（因转账失败而暂时保留在合约中的BNB）
     */
    uint256 public lockedBNBAmount;

    /**
     * @dev 用于追踪已记录的用户（用于 holdersCount 计数）
     */
    mapping(uint256 => mapping(address => bool)) private _isRecordedHolder;

    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }

    /**
     * @dev 奖励事件
     */
    event RewardDistributed(
        address indexed from,
        uint256 totalAmount,
        uint256 dividendAmount,
        uint256 nftStakingAmount,
        uint256 tokenStakingAmount,
        uint256 arenaRewardAmount,
        uint256 buybackAmount
    );

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
        // 修复：滑点必须大于 0 且不超过 10%（1000），原20%上限过高可能导致大滑点损失
        require(_slippage > 0 && _slippage <= 1000, "RewardManager: Slippage must be > 0 and <= 1000");
        slippage = _slippage;
    }

    /**
     * @dev 接收BNB并自动处理
     */
    receive() external payable {
        if (msg.value > 0) {
            emit BNBReceived(msg.sender, msg.value);
        }
    }
    
    event BNBReceived(address indexed sender, uint256 amount);

    /**
     * @dev 手动触发BNB分配（用于处理小额BNB或调试）
     */
    function distributeBNB() external onlyOwnerOrAuthorizer nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            return; // 没有 BNB 可分配，直接返回而不 revert，确保流程不中断
        }
        _distributeBNB(balance);
    }

    /**
     * @dev 内部函数：分配BNB到各池
     * - 分红池：直接转账BNB
     * - NFT质押池、代币质押池、竞技场奖励池：优先兑换为代币后转账；兑换失败时将 BNB 直接转入 dividendPool 作为价值储备
     * - NFT回购池：直接转账BNB
     */
    function _distributeBNB(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        _distributeDividendPool(amount);
        _distributeStakingPool(amount);
        _distributeTokenStakingPool(amount);
        _distributeArenaPool(amount);
        _distributeBuybackPool(amount);
    }

    function _distributeDividendPool(uint256 amount) private {
        address dividendPool = IAuthorizer(authorizer).getAddressByName("dividendManager");
        uint256 dividendAmount = amount * dividendPercent / PRECISION;
        
        if (dividendPool != address(0) && dividendAmount > 0) {
            (bool success, ) = payable(dividendPool).call{value: dividendAmount}("");
            if (success) {
                try IDividendManager(dividendPool).syncDividendPool() {} catch {}
            } else {
                emit BNBTransferFailed(0, dividendPool, dividendAmount);
                lockedBNBAmount += dividendAmount;
            }
        }
    }

    function _distributeStakingPool(uint256 amount) private {
        address stakingLPReward = IAuthorizer(authorizer).getAddressByName("stakingLPReward");
        uint256 stakingAmount = amount * nftStakingPercent / PRECISION;
        
        if (stakingLPReward != address(0) && stakingAmount > 0) {
            (bool success, ) = payable(stakingLPReward).call{value: stakingAmount}("");
            if (success) {
                try IStakingLPReward(stakingLPReward).recordIncomingBNB(stakingAmount) {} catch {}
            } else {
                lockedBNBAmount += stakingAmount;
                emit BNBTransferFailed(1, stakingLPReward, stakingAmount);
            }
        }
    }

    function _distributeTokenStakingPool(uint256 amount) private {
        address tokenStakingLP = IAuthorizer(authorizer).getAddressByName("tokenStakingLP");
        uint256 tokenStakingAmount = amount * tokenStakingPercent / PRECISION;
        
        if (tokenStakingLP != address(0) && tokenStakingAmount > 0) {
            (bool success, ) = payable(tokenStakingLP).call{value: tokenStakingAmount}("");
            if (success) {
                try ITokenStakingLP(tokenStakingLP).recordIncomingBNB(tokenStakingAmount) {} catch {}
            } else {
                lockedBNBAmount += tokenStakingAmount;
                emit BNBTransferFailed(2, tokenStakingLP, tokenStakingAmount);
            }
        }
    }

    function _distributeArenaPool(uint256 amount) private {
        address arenaRewardLP = IAuthorizer(authorizer).getAddressByName("arenaRewardLP");
        uint256 arenaAmount = amount * arenaRewardPercent / PRECISION;
        
        if (arenaRewardLP != address(0) && arenaAmount > 0) {
            (bool success, ) = payable(arenaRewardLP).call{value: arenaAmount}("");
            if (success) {
                try IArenaRewardLP(arenaRewardLP).recordIncomingBNB(arenaAmount) {} catch {}
            } else {
                lockedBNBAmount += arenaAmount;
                emit BNBTransferFailed(3, arenaRewardLP, arenaAmount);
            }
        }
    }

    function _distributeBuybackPool(uint256 amount) private {
        address nftBuybackPool = IAuthorizer(authorizer).getAddressByName("nftBuyback");
        uint256 buybackAmount = amount * nftBuybackPercent / PRECISION;
        
        if (nftBuybackPool != address(0) && buybackAmount > 0) {
            (bool success, ) = payable(nftBuybackPool).call{value: buybackAmount}("");
            if (success) {
                try IBuybackReceiver(nftBuybackPool).recordIncomingBNB(buybackAmount) {} catch {}
            } else {
                lockedBNBAmount += buybackAmount;
                emit BNBTransferFailed(4, nftBuybackPool, buybackAmount);
            }
        }
    }

    /**
     * @dev 内部函数：将BNB兑换为代币
     */
    function _swapBNBToToken(uint256 bnbAmount, address tokenContract) internal returns (uint256) {
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        
        // 根据 activeDEX 选择正确的 DEX 路由
        address dexRouter;
        if (activeDEX == 1) {
            dexRouter = IAuthorizer(authorizer).getAddressByName("pancakeSwapRouter");
        } else if (activeDEX == 2) {
            dexRouter = IAuthorizer(authorizer).getAddressByName("uniswapRouter");
        } else {
            dexRouter = IAuthorizer(authorizer).getAddressByName("flapSwapRouter");
        }
        address wbnb = IAuthorizer(authorizer).getAddressByName("wbnb");
        
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = tokenContract;

        // 获取预估输出金额并计算滑点
        uint256[] memory amounts = IDexRouter(dexRouter).getAmountsOut(bnbAmount, path);
        uint256 expectedOut = amounts[1];
        uint256 minOut = expectedOut * (10000 - slippage) / 10000;

        try IDexRouter(dexRouter).swapExactETHForTokens{value: bnbAmount}(
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
     * @dev 内部函数：分配兑换后的代币到NFT质押池、代币质押池和竞技场奖励池
     * 分红池直接使用BNB，不需要兑换
     */
    function _distributeSwappedTokens(
        uint256 totalTokenAmount,
        uint256 nftStakingBNBAmount,
        uint256 tokenStakingBNBAmount,
        uint256 arenaRewardBNBAmount,
        uint256 totalBNBAmount,
        address tokenContract
    ) internal {
        IERC20 token = IERC20(tokenContract);
        address nftStakingPool = IAuthorizer(authorizer).getAddressByName("staking");
        address tokenStakingPool = IAuthorizer(authorizer).getAddressByName("tokenStaking");
        address arenaRewardPool = IAuthorizer(authorizer).getAddressByName("arenaReward");
        address poolManager = IAuthorizer(authorizer).getAddressByName("poolManager");
        
        // 计算各池应得代币数量（按BNB金额比例）
        uint256 nftStakingTokenAmount;
        uint256 tokenStakingTokenAmount;
        uint256 arenaRewardTokenAmount;
        if (totalBNBAmount > 0) {
            nftStakingTokenAmount = totalTokenAmount * nftStakingBNBAmount / totalBNBAmount;
            tokenStakingTokenAmount = totalTokenAmount * tokenStakingBNBAmount / totalBNBAmount;
            arenaRewardTokenAmount = totalTokenAmount * arenaRewardBNBAmount / totalBNBAmount;
        }
        
        // 分配到NFT质押池
        if (nftStakingPool != address(0) && nftStakingTokenAmount > 0) {
            token.safeTransfer(nftStakingPool, nftStakingTokenAmount);
            if (poolManager != address(0)) {
                try IPoolManager(poolManager).addToNFTStakingPool(nftStakingTokenAmount) {} catch {}
            }
        }

        // 分配到代币质押池
        if (tokenStakingPool != address(0) && tokenStakingTokenAmount > 0) {
            token.safeTransfer(tokenStakingPool, tokenStakingTokenAmount);
            if (poolManager != address(0)) {
                try IPoolManager(poolManager).addToTokenStakingPool(tokenStakingTokenAmount) {} catch {}
            }
            // 调用 TokenStaking 的 recordIncomingTokens 记录流入
            try ITokenStaking(tokenStakingPool).recordIncomingTokens(tokenStakingTokenAmount) {} catch {}
        }

        // 分配到竞技场奖励池
        if (arenaRewardPool != address(0) && arenaRewardTokenAmount > 0) {
            token.safeTransfer(arenaRewardPool, arenaRewardTokenAmount);
            if (poolManager != address(0)) {
                try IPoolManager(poolManager).addToArenaRewardPool(arenaRewardTokenAmount) {} catch {}
            }
        }
    }

    // DEX相关事件
    event DEXRouterUpdated(address indexed router, uint8 indexed dexType);
    event BNBConverted(uint256 bnbAmount, uint256 tokenAmount);
    event SwapFailed(uint256 bnbAmount);
    event SwapFailedFallback(uint256 bnbAmount);
    event BNBDistributed(address indexed from, uint256 totalAmount, uint256 dividendAmount, uint256 nftStakingAmount, uint256 tokenStakingAmount, uint256 arenaRewardAmount, uint256 buybackAmount);
    event BNBTransferFailed(uint256 poolType, address pool, uint256 amount);

    /**
     * @dev 添加质押池奖励
     * 用于直接向指定质押池添加代币奖励
     * @param amount 奖励代币数量
     * @param poolType 池子类型（0=NFT质押池, 1=代币质押池, 2=竞技场奖励池）
     */
    function addStakingReward(uint256 amount, uint256 poolType) external onlyOwnerOrAuthorizer whenNotPaused {
        require(amount > 0, "RewardManager: Invalid amount");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "RewardManager: Token contract not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(msg.sender) >= amount, "RewardManager: Insufficient balance");

        address nftStakingPool = IAuthorizer(authorizer).getAddressByName("staking");
        address tokenStakingPool = IAuthorizer(authorizer).getAddressByName("tokenStaking");
        address arenaRewardPool = IAuthorizer(authorizer).getAddressByName("arenaReward");

        if (poolType == 0 && nftStakingPool != address(0)) {
            token.safeTransferFrom(msg.sender, nftStakingPool, amount);
        } else if (poolType == 1 && tokenStakingPool != address(0)) {
            token.safeTransferFrom(msg.sender, tokenStakingPool, amount);
        } else if (poolType == 2 && arenaRewardPool != address(0)) {
            token.safeTransferFrom(msg.sender, arenaRewardPool, amount);
        }
    }

    /// @dev 用户可领取分红映射（epoch-keyed）
    mapping(uint256 => mapping(address => uint256)) public pendingDividends;
    
    /// @dev 用户权重映射，用于计算分红比例（epoch-keyed）
    mapping(uint256 => mapping(address => uint256)) public userWeights;

    /**
     * @dev 分红发放事件
     * @param user 用户地址
     * @param amount 领取的分红数量
     */
    event DividendClaimed(address indexed user, uint256 amount);

    /**
     * @dev 领取当前用户的分红（无参版本 - 前端直接调用）
     * 用户调用此函数领取自己在分红池中的应得分红
     * @return 实际领取的分红数量
     */
    function claimDividend() external whenNotPaused nonReentrant returns (uint256) {
        address user = msg.sender;
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        
        uint256 currentEpoch = _currentEpoch();
        uint256 dividend = pendingDividends[currentEpoch][user];
        require(dividend > 0, "RewardManager: No pending dividend");
        
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "RewardManager: Insufficient contract balance");
        
        pendingDividends[currentEpoch][user] = 0;
        
        SafeERC20.safeTransfer(token, user, dividend);
        
        emit DividendClaimed(user, dividend);
        return dividend;
    }

    /**
     * @dev 领取指定用户的分红（带参数版本 - owner/authorizer可为其他用户领取）
     * 用于批量给用户发放分红或帮助离线用户领取
     * @param user 目标用户地址
     * @return 实际领取的分红数量
     */
    function claimDividendFor(address user) external whenNotPaused nonReentrant returns (uint256) {
        require(
            msg.sender == owner() || msg.sender == authorizer,
            "RewardManager: Not authorized to claim for other users"
        );
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        require(user != address(0), "RewardManager: Invalid user address");
        
        uint256 currentEpoch = _currentEpoch();
        uint256 dividend = pendingDividends[currentEpoch][user];
        require(dividend > 0, "RewardManager: No pending dividend");
        
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= dividend, "RewardManager: Insufficient contract balance");
        
        pendingDividends[currentEpoch][user] = 0;
        
        SafeERC20.safeTransfer(token, user, dividend);
        
        emit DividendClaimed(user, dividend);
        return dividend;
    }

    /**
     * @dev 获取用户待领取分红金额
     * @param user 用户地址
     * @return 用户待领取的分红数量
     */
    function getDividend(address user) external view returns (uint256) {
        return pendingDividends[_currentEpoch()][user];
    }

    /**
     * @dev 计算用户可领取分红（用于前端展示）
     * @param user 用户地址
     * @return pending 用户待领取的分红数量
     * @return weight 用户当前权重
     */
    function calcUserDividend(address user) external view returns (uint256 pending, uint256 weight) {
        uint256 currentEpoch = _currentEpoch();
        return (pendingDividends[currentEpoch][user], userWeights[currentEpoch][user]);
    }
    
    /**
     * @dev 获取用户待领取分红（仅返回金额）
     * @param user 用户地址
     * @return 用户待领取的分红数量
     */
    function getUserPendingDividend(address user) external view returns (uint256) {
        return pendingDividends[_currentEpoch()][user];
    }

    /**
     * @dev 获取分红池余额
     * @return 分红池中代币余额
     */
    function dividendPoolBalance() external view returns (uint256) {
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        address dividendPool = IAuthorizer(authorizer).getAddressByName("dividendManager");
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        return IERC20(tokenContract).balanceOf(dividendPool);
    }

    /**
     * @dev 分配奖励到各个池
     */
    function _distributeReward(uint256 amount) internal {
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        address dividendPool = IAuthorizer(authorizer).getAddressByName("dividendManager");
        address nftStakingPool = IAuthorizer(authorizer).getAddressByName("staking");
        address tokenStakingPool = IAuthorizer(authorizer).getAddressByName("tokenStaking");
        address arenaRewardPool = IAuthorizer(authorizer).getAddressByName("arenaReward");
        address nftBuybackPool = IAuthorizer(authorizer).getAddressByName("nftBuyback");
        address poolManager = IAuthorizer(authorizer).getAddressByName("poolManager");
        require(tokenContract != address(0), "RewardManager: Token contract not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "RewardManager: Insufficient contract balance");

        uint256 dividendAmount = amount * dividendPercent / PRECISION;
        uint256 nftStakingAmount = amount * nftStakingPercent / PRECISION;
        uint256 tokenStakingAmount = amount * tokenStakingPercent / PRECISION;
        uint256 arenaRewardAmount = amount * arenaRewardPercent / PRECISION;
        uint256 buybackAmount = amount * nftBuybackPercent / PRECISION;

        // 使用 try-catch 分别处理每个分配，允许部分成功
        if (dividendPool != address(0) && dividendAmount > 0) {
            token.safeTransfer(dividendPool, dividendAmount);
                try IDividendManager(dividendPool).syncDividendPool() {} catch {}
        }
        if (nftStakingPool != address(0) && nftStakingAmount > 0) {
            token.safeTransfer(nftStakingPool, nftStakingAmount);
            if (poolManager != address(0)) {
                try IPoolManager(poolManager).addToNFTStakingPool(nftStakingAmount) {} catch {}
            }
        }
        if (tokenStakingPool != address(0) && tokenStakingAmount > 0) {
            token.safeTransfer(tokenStakingPool, tokenStakingAmount);
            if (poolManager != address(0)) {
                try IPoolManager(poolManager).addToTokenStakingPool(tokenStakingAmount) {} catch {}
            }
            // 调用 TokenStaking 的 recordIncomingTokens 记录流入
            try ITokenStaking(tokenStakingPool).recordIncomingTokens(tokenStakingAmount) {} catch {}
        }
        if (arenaRewardPool != address(0) && arenaRewardAmount > 0) {
            token.safeTransfer(arenaRewardPool, arenaRewardAmount);
            if (poolManager != address(0)) {
                try IPoolManager(poolManager).addToArenaRewardPool(arenaRewardAmount) {} catch {}
            }
        }
        // NFT回购销毁池：直接转账代币到回购合约，回购合约收到代币后可用于回购销毁NFT
        if (nftBuybackPool != address(0) && buybackAmount > 0) {
            token.safeTransfer(nftBuybackPool, buybackAmount);
            // 尝试调用回购合约的记录函数（如果实现）
            try IBuybackReceiver(nftBuybackPool).recordIncomingTokens(buybackAmount) {} catch {}
        }

        totalDistributed += amount;
        _addDistributionRecord(amount, dividendAmount, nftStakingAmount, tokenStakingAmount, arenaRewardAmount, buybackAmount);

        emit RewardDistributed(
            msg.sender,
            amount,
            dividendAmount,
            nftStakingAmount,
            tokenStakingAmount,
            arenaRewardAmount,
            buybackAmount
        );
    }

    /**
     * @dev 在分配到用户分红时记录新的持有者
     */
    function _recordHolder(address user) internal {
        if (user != address(0) && !_isRecordedHolder[_currentEpoch()][user]) {
            _isRecordedHolder[_currentEpoch()][user] = true;
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
        uint256 arenaRewardAmount,
        uint256 buybackAmount
    ) internal {
        DistributionRecord memory record = DistributionRecord({
            timestamp: block.timestamp,
            totalAmount: totalAmount,
            dividendAmount: dividendAmount,
            nftStakingAmount: nftStakingAmount,
            tokenStakingAmount: tokenStakingAmount,
            arenaRewardAmount: arenaRewardAmount,
            buybackAmount: buybackAmount,
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
        uint256,
        uint256
    ) {
        return (dividendPercent, nftStakingPercent, tokenStakingPercent, arenaRewardPercent, nftBuybackPercent);
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
        uint256 buybackAmount;
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
     * @return totalDistributed_ 总分发金额
     */
    function getRewardPoolStats() external view returns (
        uint256 dividendPoolBalance,
        uint256 tokenStakingBalance,
        uint256 arenaRewardBalance,
        uint256 totalDistributed_
    ) {
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        address dividendPool = IAuthorizer(authorizer).getAddressByName("dividendManager");
        address tokenStakingPool = IAuthorizer(authorizer).getAddressByName("tokenStaking");
        address arenaRewardPool = IAuthorizer(authorizer).getAddressByName("arenaReward");
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

        totalDistributed_ = totalDistributed;
    }

    /**
     * @dev 紧急提取BNB（仅所有者可调用）
     * 用于在紧急情况下提取合约持有的BNB
     * @param amount 提取数量
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "RewardManager: Amount must be > 0");
        require(amount <= address(this).balance, "RewardManager: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "RewardManager: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币（仅所有者可调用）
     * 用于在紧急情况下提取合约持有的代币
     * @param amount 提取数量
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "RewardManager: Amount must be > 0");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "RewardManager: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "RewardManager: Insufficient token balance");
        SafeERC20.safeTransfer(token, owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    
    /**
     * @dev 重试分配锁定的BNB（仅owner或authorizer可调用）
     * 当BNB转账失败时会被锁定，此函数尝试重新分配锁定的BNB
     */
    function retryLockedBNBDistribution() external onlyOwnerOrAuthorizer nonReentrant {
        uint256 lockedAmount = lockedBNBAmount;
        if (lockedAmount == 0) {
            return;
        }
        
        address dividendPool = IAuthorizer(authorizer).getAddressByName("dividendManager");
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        address dexRouter = IAuthorizer(authorizer).getAddressByName("pancakeSwapRouter");
        
        uint256 dividendAmount = lockedAmount * dividendPercent / PRECISION;
        uint256 nftStakingAmount = lockedAmount * nftStakingPercent / PRECISION;
        uint256 tokenStakingAmount = lockedAmount * tokenStakingPercent / PRECISION;
        uint256 arenaRewardAmount = lockedAmount * arenaRewardPercent / PRECISION;
        
        uint256 successfullyDistributed = 0;
        
        if (dividendPool != address(0) && dividendAmount > 0) {
            (bool success, ) = payable(dividendPool).call{value: dividendAmount}("");
            if (success) {
                try IDividendManager(dividendPool).syncDividendPool() {} catch {}
                successfullyDistributed += dividendAmount;
            }
        }
        
        uint256 totalSwapAmount = nftStakingAmount + tokenStakingAmount + arenaRewardAmount;
        if (totalSwapAmount > 0 && dexRouter != address(0)) {
            uint256 tokenAmount = _swapBNBToToken(totalSwapAmount, tokenContract);
            if (tokenAmount > 0) {
                _distributeSwappedTokens(tokenAmount, nftStakingAmount, tokenStakingAmount, arenaRewardAmount, totalSwapAmount, tokenContract);
                successfullyDistributed += totalSwapAmount;
            }
        }
        
        // 修复：确保 only subtract successfully distributed amount
        // 如果 successfullyDistributed = 0，lockedBNBAmount 保持不变，允许重试
        if (successfullyDistributed > 0 && successfullyDistributed <= lockedBNBAmount) {
            lockedBNBAmount -= successfullyDistributed;
        }
        emit LockedBNBRedistributed(lockedAmount, successfullyDistributed, lockedBNBAmount);
    }
    
    event LockedBNBRedistributed(uint256 totalLocked, uint256 successfullyDistributed, uint256 remainingLocked);

    /**
     * @dev 重置合约数据
     * 仅合约所有者和authorizer合约可调用
     * 通过递增纪元版本号快速重置所有用户相关的mapping数据
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        
        totalDistributed = 0;
        holdersCount = 0;
        lockedBNBAmount = 0;
        
        autoSwapEnabled = true;
        minSwapAmount = 1000000000000000;
        slippage = 1000;
        activeDEX = 0;
        
        dividendPercent = 4000;
        nftStakingPercent = 2000;
        tokenStakingPercent = 1500;
        arenaRewardPercent = 1500;
        nftBuybackPercent = 1000;
        
        delete distributionHistory;
        distributionHistoryStartIndex = 0;
        
        paused = false;
        pauseReason = "";
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 执行重置的操作者地址
     * @param timestamp 重置时间戳
     * @param oldEpoch 重置前的纪元版本号
     * @param newEpoch 重置后的纪元版本号
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);
}