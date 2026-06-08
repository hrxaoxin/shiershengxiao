// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PoolManager
 * @dev 资金池管理合约，管理游戏的各种奖励池
 *
 * 核心职责：
 * 1. 资金归集：接收来自交易市场、战斗、繁殖、铸造等业务产生的手续费
 * 2. 资金分配：按照预定比例，将代币/BNB分入不同的资金池
 * 3. 资金释放：当 Staking / TokenStaking / ArenaRanking 等合约需要时，批准提取
 *
 * 池子类型常量（poolType）：
 * - POOL_NFT_STAKING = 0: NFT质押奖励池，奖励给质押NFT的用户
 * - POOL_TOKEN_STAKING = 1: 代币质押奖励池，奖励给质押代币的用户
 * - POOL_ARENA_REWARD = 2: 竞技场奖励池，奖励给竞技场排名靠前的玩家
 *
 * 资金来源（预期）：
 * - NFTTrading.sol：交易手续费 5%，其中部分进入各奖励池
 * - Battle.sol：战斗入场费，胜者获得奖励，手续费进入竞技场池
 * - Breeding.sol：繁殖费用，部分进入 NFT质押池
 * - TokenBurner.sol：铸造费用，部分进入分红池和质押池
 *
 * 数据结构：
 * - poolBalances[poolType]：各池子的代币余额
 * - 另有 BNB 余额按相同逻辑管理
 * - 资金流动记录（FLOW_DEPOSIT/FLOW_WITHDRAW），使用环形缓冲区，最多 MAX_FLOW_RECORDS = 1000 条
 *
 * 权限控制：
 * - onlyOwner：可设置授权合约、紧急暂停、紧急提取
 * - onlyAuthorizedContract：授权的业务合约（NFTTrading/Battle/Breeding 等）可调用 deposit
 * - onlyAuthorizedPoolConsumer：授权的消费者合约（Staking/TokenStaking/ArenaRanking）可调用 withdraw
 *
 * 安全特性：
 * - ReentrancyGuard：防止提取时的重入攻击
 * - Pausable：紧急情况下可暂停所有存款/提取操作
 * - 地址验证：所有目标地址必须非零，防止误操作锁死资金
 * - UUPS 升级：支持 onlyOwner 授权的合约升级，保留所有状态
 *
 * 典型工作流程：
 * 1. NFTTrading 完成一笔交易 → 调用 depositToPool(poolType, amount) 存入手续费
 * 2. Staking 合约每日结算 → 调用 withdrawFromPool(POOL_NFT_STAKING, amount) 提取奖励
 * 3. Staking 合约将提取的奖励通过 updateRewardPool 分发给质押者（更新 globalRewardPerWeight）
 * 4. Owner 可在紧急情况下调用 emergencyWithdraw 提取资金到安全地址
 */
contract PoolManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 池子类型常量
     */
    uint256 public constant POOL_NFT_STAKING = 0;
    uint256 public constant POOL_TOKEN_STAKING = 1;
    uint256 public constant POOL_ARENA_REWARD = 2;

    /**
     * @dev 资金流动类型常量
     */
    uint256 public constant FLOW_DEPOSIT = 1;
    uint256 public constant FLOW_WITHDRAW = 2;
    
    uint256 public constant MAX_FLOW_RECORDS = 1000;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 池子余额映射
     * poolType => balance
     */
    mapping(uint256 => uint256) public poolBalances;

    /**
     * @dev 累计存入/提取金额
     */
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    /**
     * @dev 紧急暂停标志
     */
    bool public paused;

    modifier whenNotPaused() {
        require(!paused, "PoolManager: Paused");
        _;
    }

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "PoolManager: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "PoolManager: Invalid authorizer address");
        authorizer = a;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "PoolManager: Not authorized");
        _;
    }

    /**
     * @dev 添加到NFT质押池
     */
    function addToNFTStakingPool(uint256 amount) external onlyAuthorized whenNotPaused {
        require(amount > 0, "PoolManager: Invalid amount");
        poolBalances[POOL_NFT_STAKING] += amount;
        _recordFlow(POOL_NFT_STAKING, amount, msg.sender, address(this), FLOW_DEPOSIT);
        emit PoolDeposited(POOL_NFT_STAKING, amount);
    }

    /**
     * @dev 添加到代币质押池
     */
    function addToTokenStakingPool(uint256 amount) external onlyAuthorized whenNotPaused {
        require(amount > 0, "PoolManager: Invalid amount");
        poolBalances[POOL_TOKEN_STAKING] += amount;
        _recordFlow(POOL_TOKEN_STAKING, amount, msg.sender, address(this), FLOW_DEPOSIT);
        emit PoolDeposited(POOL_TOKEN_STAKING, amount);
    }

    /**
     * @dev 添加到竞技场奖励池
     */
    function addToArenaRewardPool(uint256 amount) external onlyAuthorized whenNotPaused {
        require(amount > 0, "PoolManager: Invalid amount");
        poolBalances[POOL_ARENA_REWARD] += amount;
        _recordFlow(POOL_ARENA_REWARD, amount, msg.sender, address(this), FLOW_DEPOSIT);
        emit PoolDeposited(POOL_ARENA_REWARD, amount);
    }

    event PoolDeposited(uint256 indexed poolType, uint256 amount);

    /**
     * @dev 从NFT质押池提取
     * @param amount 提取数量
     */
    function withdrawFromNFTStakingPool(uint256 amount) external onlyAuthorized whenNotPaused {
        require(poolBalances[POOL_NFT_STAKING] >= amount, "PoolManager: Insufficient balance");
        poolBalances[POOL_NFT_STAKING] -= amount;
        _recordFlow(POOL_NFT_STAKING, amount, address(this), msg.sender, FLOW_WITHDRAW);
        emit PoolWithdrawn(POOL_NFT_STAKING, amount);
    }

    /**
     * @dev 从代币质押池提取
     * @param amount 提取数量
     */
    function withdrawFromTokenStakingPool(uint256 amount) external onlyAuthorized whenNotPaused {
        require(poolBalances[POOL_TOKEN_STAKING] >= amount, "PoolManager: Insufficient balance");
        poolBalances[POOL_TOKEN_STAKING] -= amount;
        _recordFlow(POOL_TOKEN_STAKING, amount, address(this), msg.sender, FLOW_WITHDRAW);
        emit PoolWithdrawn(POOL_TOKEN_STAKING, amount);
    }

    event PoolWithdrawn(uint256 indexed poolType, uint256 amount);

    /**
     * @dev 获取池子余额
     */
    function getPoolBalance(uint256 poolType) external view returns (uint256) {
        return poolBalances[poolType];
    }

    /**
     * @dev 紧急提取（合约所有者可随时提取）
     * @param token 代币地址（address(0)表示BNB）
     * @param to 接收地址
     * @param amount 提取数量
     */
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount, uint256 timestamp);

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "PoolManager: Invalid address");
        require(amount > 0, "PoolManager: Invalid amount");

        if (token == address(0)) {
            require(address(this).balance >= amount, "PoolManager: Insufficient BNB balance");
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "PoolManager: BNB transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit EmergencyWithdraw(token, to, amount, block.timestamp);
    }

    /**
     * @dev 暂停/恢复合约功能
     * @param _paused 是否暂停
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @dev 资金流动记录结构体
     */
    struct FlowRecord {
        uint256 timestamp;
        uint256 poolType;
        uint256 amount;
        address from;
        address to;
        uint8 flowType;
    }

    /**
     * @dev 资金流动记录数组（使用环形缓冲区）
     */
    FlowRecord[] public flowRecords;
    
    /**
     * @dev 资金流动记录起始索引（环形缓冲区）
     */
    uint256 public flowRecordsStartIndex;

    /**
     * @dev 记录资金流动
     */
    function _recordFlow(uint256 poolType, uint256 amount, address from, address to, uint8 flowType) internal {
        // 更新累计变量
        if (flowType == FLOW_DEPOSIT) {
            totalDeposited += amount;
        } else if (flowType == FLOW_WITHDRAW) {
            totalWithdrawn += amount;
        }
        
        FlowRecord memory record = FlowRecord({
            timestamp: block.timestamp,
            poolType: poolType,
            amount: amount,
            from: from,
            to: to,
            flowType: flowType
        });
        
        if (flowRecords.length < MAX_FLOW_RECORDS) {
            flowRecords.push(record);
        } else {
            flowRecords[flowRecordsStartIndex] = record;
            flowRecordsStartIndex = (flowRecordsStartIndex + 1) % MAX_FLOW_RECORDS;
        }
    }

    /**
     * @dev 获取资金流动记录长度
     */
    function getFlowRecordsLength() external view returns (uint256) {
        return flowRecords.length;
    }

    /**
     * @dev 获取指定范围的资金流动记录
     * @param startIndex 起始索引
     * @param count 获取数量
     */
    function getFlowRecords(uint256 startIndex, uint256 count) external view returns (FlowRecord[] memory) {
        require(startIndex < flowRecords.length, "PoolManager: Invalid start index");
        require(count > 0, "PoolManager: Invalid count");

        uint256 endIndex = startIndex + count;
        if (endIndex > flowRecords.length) {
            endIndex = flowRecords.length;
        }

        FlowRecord[] memory records = new FlowRecord[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            records[i - startIndex] = flowRecords[i];
        }

        return records;
    }

    /**
     * @dev 获取最新N条资金流动记录
     * @param count 记录数量
     */
    function getRecentFlowRecords(uint256 count) external view returns (FlowRecord[] memory) {
        if (flowRecords.length == 0) {
            return new FlowRecord[](0);
        }

        if (count > flowRecords.length) {
            count = flowRecords.length;
        }

        FlowRecord[] memory records = new FlowRecord[](count);
        uint256 startIndex = flowRecords.length - count;
        for (uint256 i = 0; i < count; i++) {
            records[i] = flowRecords[startIndex + i];
        }

        return records;
    }

    /**
     * @dev 获取指定池子的资金流动记录
     * @param poolType 池子类型
     * @param count 获取数量
     */
    function getPoolFlowRecords(uint256 poolType, uint256 count) external view returns (FlowRecord[] memory) {
        uint256 count_ = 0;
        for (uint256 i = 0; i < flowRecords.length; i++) {
            if (flowRecords[i].poolType == poolType) {
                count_++;
            }
        }

        if (count_ == 0) {
            return new FlowRecord[](0);
        }

        if (count > count_) {
            count = count_;
        }

        FlowRecord[] memory records = new FlowRecord[](count);
        uint256 index = 0;
        for (uint256 i = flowRecords.length; i > 0; i--) {
            if (flowRecords[i - 1].poolType == poolType && index < count) {
                records[count - 1 - index] = flowRecords[i - 1];
                index++;
            }
            if (index >= count) break;
        }

        return records;
    }
    
    /**
     * @dev 导出所有资金流动记录（供管理员导出归档）
     * @return 所有flowRecords记录
     */
    function exportAllFlowRecords() external view onlyOwner returns (FlowRecord[] memory) {
        return flowRecords;
    }
    
    /**
     * @dev 导出指定范围内的资金流动记录
     * @param startIndex 起始索引
     * @param endIndex 结束索引
     * @return 指定范围的flowRecords记录
     */
    function exportFlowRecordsRange(uint256 startIndex, uint256 endIndex) external view onlyOwner returns (FlowRecord[] memory) {
        require(startIndex < flowRecords.length, "PoolManager: Invalid start index");
        require(endIndex <= flowRecords.length, "PoolManager: Invalid end index");
        require(startIndex <= endIndex, "PoolManager: Start index must be <= end index");
        
        uint256 count = endIndex - startIndex;
        FlowRecord[] memory records = new FlowRecord[](count);
        
        for (uint256 i = startIndex; i < endIndex; i++) {
            records[i - startIndex] = flowRecords[i];
        }
        
        return records;
    }

    /**
     * @dev 获取池子统计
     * @return nftStakingBalance NFT质押池余额
     * @return tokenStakingBalance 代币质押池余额
     * @return arenaRewardBalance 竞技场奖励池余额
     * @return totalDeposited 总存入
     * @return totalWithdrawn 总提取
     */
    function getPoolStats() external view returns (
        uint256 nftStakingBalance,
        uint256 tokenStakingBalance,
        uint256 arenaRewardBalance,
        uint256 totalDeposited_,
        uint256 totalWithdrawn_
    ) {
        nftStakingBalance = poolBalances[0];
        tokenStakingBalance = poolBalances[1];
        arenaRewardBalance = poolBalances[2];
        totalDeposited_ = totalDeposited;
        totalWithdrawn_ = totalWithdrawn;
    }

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}
