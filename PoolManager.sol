// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

/**
 * @title PoolManager
 * @dev 资金池管理合约，管理游戏的各种奖励池
 *
 * 池子类型：
 * - 0: NFT质押池
 * - 1: 代币质押池
 * - 2: 竞技场奖励池
 *
 * 资金来源：
 * - 交易手续费
 * - 战斗费用
 * - 繁殖费用
 *
 * 功能特性：
 * - 支持多个独立资金池
 * - 紧急暂停功能
 * - 管理员提取权限
 * - 支持UUPS升级
 */
contract PoolManager is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
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
     * @dev 紧急暂停标志
     */
    bool public paused;

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
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
    function addToNFTStakingPool(uint256 amount) external onlyAuthorized {
        require(!paused, "PoolManager: Paused");
        require(amount > 0, "PoolManager: Invalid amount");
        require(msg.sender == owner() || msg.sender == authorizer, "PoolManager: Not authorized");
        poolBalances[0] += amount;
        emit PoolDeposited(0, amount);
    }

    /**
     * @dev 添加到代币质押池
     */
    function addToTokenStakingPool(uint256 amount) external onlyAuthorized {
        require(!paused, "PoolManager: Paused");
        require(amount > 0, "PoolManager: Invalid amount");
        require(msg.sender == owner() || msg.sender == authorizer, "PoolManager: Not authorized");
        poolBalances[1] += amount;
        emit PoolDeposited(1, amount);
    }

    /**
     * @dev 添加到竞技场奖励池
     */
    function addToArenaRewardPool(uint256 amount) external onlyAuthorized {
        require(!paused, "PoolManager: Paused");
        require(amount > 0, "PoolManager: Invalid amount");
        require(msg.sender == owner() || msg.sender == authorizer, "PoolManager: Not authorized");
        poolBalances[2] += amount;
        emit PoolDeposited(2, amount);
    }

    event PoolDeposited(uint256 indexed poolType, uint256 amount);

    /**
     * @dev 从NFT质押池提取
     * @param amount 提取数量
     */
    function withdrawFromNFTStakingPool(uint256 amount) external onlyOwner whenNotPaused {
        require(poolBalances[0] >= amount, "PoolManager: Insufficient balance");
        poolBalances[0] -= amount;
        emit PoolWithdrawn(0, amount);
    }

    /**
     * @dev 从代币质押池提取
     * @param amount 提取数量
     */
    function withdrawFromTokenStakingPool(uint256 amount) external onlyOwner whenNotPaused {
        require(poolBalances[1] >= amount, "PoolManager: Insufficient balance");
        poolBalances[1] -= amount;
        emit PoolWithdrawn(1, amount);
    }

    event PoolWithdrawn(uint256 indexed poolType, uint256 amount);

    /**
     * @dev 获取池子余额
     */
    function getPoolBalance(uint256 poolType) external view returns (uint256) {
        return poolBalances[poolType];
    }

    /**
     * @dev 紧急提取（仅用于极端情况）
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 提取数量
     */
    uint256 public emergencyWithdrawLimit = 10 ether;
    uint256 public emergencyWithdrawCooldown = 1 days;
    uint256 public lastEmergencyWithdrawTime;
    uint256 public lastEmergencyWithdrawAmount;
    uint256 public constant EMERGENCY_WEEKLY_LIMIT = 100 ether;
    uint256 public emergencyWithdrawWeeklyAccumulated;
    uint256 public lastWeeklyResetTime;
    address public emergencyWithdrawReceiver;
    bool public emergencyWithdrawReceiverInitialized;

    event EmergencyWithdrawLimitUpdated(uint256 newLimit);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount, uint256 timestamp);
    event EmergencyWithdrawReceiverSet(address indexed receiver);

    function setEmergencyWithdrawReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "PoolManager: Invalid receiver");
        emergencyWithdrawReceiver = _receiver;
        emergencyWithdrawReceiverInitialized = true;
        emit EmergencyWithdrawReceiverSet(_receiver);
    }

    function setEmergencyWithdrawLimit(uint256 _limit) external onlyOwner {
        emergencyWithdrawLimit = _limit;
        emit EmergencyWithdrawLimitUpdated(_limit);
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "PoolManager: Invalid address");
        require(amount > 0, "PoolManager: Invalid amount");
        require(amount <= emergencyWithdrawLimit, "PoolManager: Exceeds withdrawal limit");

        if (block.timestamp >= lastWeeklyResetTime + 7 days) {
            emergencyWithdrawWeeklyAccumulated = 0;
            lastWeeklyResetTime = block.timestamp;
        }
        require(
            emergencyWithdrawWeeklyAccumulated + amount <= EMERGENCY_WEEKLY_LIMIT,
            "PoolManager: Exceeds weekly limit"
        );

        require(
            block.timestamp >= lastEmergencyWithdrawTime + emergencyWithdrawCooldown,
            "PoolManager: Cooldown not elapsed"
        );

        lastEmergencyWithdrawTime = block.timestamp;
        lastEmergencyWithdrawAmount = amount;
        emergencyWithdrawWeeklyAccumulated += amount;

        if (token == address(0)) {
            require(address(this).balance >= amount, "PoolManager: Insufficient BNB balance");
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "PoolManager: BNB transfer failed");
        } else {
            require(IERC20(token).transfer(to, amount), "PoolManager: Transfer failed");
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
     * @dev 资金流动记录数组
     */
    FlowRecord[] public flowRecords;

    /**
     * @dev 记录资金流动
     */
    function _recordFlow(uint256 poolType, uint256 amount, address from, address to, uint8 flowType) internal {
        flowRecords.push(FlowRecord({
            timestamp: block.timestamp,
            poolType: poolType,
            amount: amount,
            from: from,
            to: to,
            flowType: flowType
        }));
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
        uint256 totalDeposited,
        uint256 totalWithdrawn
    ) {
        nftStakingBalance = poolBalances[0];
        tokenStakingBalance = poolBalances[1];
        arenaRewardBalance = poolBalances[2];

        totalDeposited = 0;
        totalWithdrawn = 0;

        for (uint256 i = 0; i < flowRecords.length; i++) {
            if (flowRecords[i].flowType == 0) {
                totalDeposited += flowRecords[i].amount;
            } else if (flowRecords[i].flowType == 1) {
                totalWithdrawn += flowRecords[i].amount;
            }
        }
    }
}
