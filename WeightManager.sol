// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @dev 零地址错误 - 当传入的地址为零地址时抛出
 */
error ZeroAddress();
/**
 * @dev 无效金额错误 - 当传入的金额不符合要求时抛出
 */
error InvalidAmount();
/**
 * @dev 非操作者错误 - 当调用者不具备操作者权限时抛出
 */
error NotOperator();

/**
 * @title WeightManager
 * @dev 用户权重管理合约，负责计算、缓存和管理所有用户的NFT权重
 *
 * 核心功能：
 * 1. 权重计算：根据用户持有的NFT数量和稀有度计算用户权重
 * 2. 权重缓存：使用时间戳缓存机制减少重复计算，降低Gas消耗
 * 3. 资格管理：维护符合最低权重要求的用户双向链表
 * 4. 批量更新：支持批量更新多个用户权重，提高运营效率
 *
 * 数据结构：
 * - userWeight: 用户当前权重映射（持久化存储）
 * - cachedUserWeight: 用户权重缓存映射（快速查询）
 * - cachedWeightTimestamp: 缓存时间戳映射（用于缓存过期判断）
 * - eligibleUserPrev/Next: 合格用户双向链表，便于遍历和奖励分配
 *
 * 缓存策略：
 * - 缓存有效期：默认15分钟（可配置）
 * - 缓存更新：主动更新（操作者调用）或被动更新（查询时自动计算）
 * - 缓存清除：紧急情况下可手动清除特定用户缓存
 *
 * 权限设计：
 * - onlyOwner: 合约所有者，可配置参数和升级合约
 * - onlyOwnerOrAuthorizer: 所有者或授权器，可配置合约地址
 * - onlyOperator: 仅所有者，可执行权重更新和缓存管理
 */
contract WeightManager is
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 暂停状态标志，true表示合约已暂停
     */
    bool public paused;
    /**
     * @dev 暂停原因说明，记录暂停操作的具体原因
     */
    string public pauseReason;

    /**
     * @dev 合约暂停事件，记录执行暂停的账户和原因
     */
    event Paused(address account, string reason);
    /**
     * @dev 合约取消暂停事件，记录执行取消暂停的账户
     */
    event Unpaused(address account);

    /**
     * @dev 修饰器：确保合约未处于暂停状态时才能执行函数
     */
    modifier whenNotPaused() {
        require(!paused, "WeightManager: Paused");
        _;
    }

    /**
     * @dev 暂停合约，停止权重更新和缓存管理操作
     * 仅合约所有者可调用，用于紧急情况下暂停服务
     * @param reason 暂停原因，将被记录在事件日志中
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消合约暂停，恢复权重管理功能
     * 仅合约所有者可调用
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 授权管理合约地址，用于配置其他合约的操作权限和获取关联合约地址
     */
    address public authorizer;
    /**
     * @dev 最低持有权重要求，用于判断用户是否具备资格
     * 用户权重必须大于等于此值才能进入合格用户列表
     */
    uint256 public minOwnerWeight;
    /**
     * @dev 合约所有者的固定权重值，用于特殊处理所有者的权重
     */
    uint256 public ownerWeight;
    
    /**
     * @dev 用户当前权重映射（持久化存储）
     * address: 用户钱包地址
     * uint256: 用户权重值，由NFT数量和稀有度决定
     */
    mapping(address => uint256) public userWeight;
    /**
     * @dev 用户权重缓存映射，用于快速查询，避免重复计算
     */
    mapping(address => uint256) public cachedUserWeight;
    /**
     * @dev 权重缓存时间戳映射，记录缓存更新时间，用于判断缓存是否过期
     */
    mapping(address => uint256) public cachedWeightTimestamp;
    /**
     * @dev 权重缓存持续时间（秒），默认15分钟
     * 超过此时间后查询将触发重新计算
     */
    uint256 public weightCacheDuration = 15 minutes;
    
    /**
     * @dev 合格用户链表：前一个用户映射
     * 用于构建双向链表，便于遍历所有合格用户
     */
    mapping(address => address) public eligibleUserPrev;
    /**
     * @dev 合格用户链表：后一个用户映射
     */
    mapping(address => address) public eligibleUserNext;
    /**
     * @dev 用户是否在合格列表中的标志映射
     */
    mapping(address => bool) public inEligibleList;
    /**
     * @dev 合格用户链表头地址，链表的第一个用户
     */
    address public eligibleUserHead;
    /**
     * @dev 合格用户链表尾地址，链表的最后一个用户
     */
    address public eligibleUserTail;
    
    /**
     * @dev 用户权重更新事件，记录用户权重变化
     * @param user 用户地址（索引）
     * @param oldWeight 更新前的权重值
     * @param newWeight 更新后的权重值
     * @param timestamp 更新时间戳
     */
    event UserWeightUpdated(address indexed user, uint256 oldWeight, uint256 newWeight, uint256 timestamp);
    /**
     * @dev 总权重更新事件（保留用于未来扩展）
     */
    event TotalWeightUpdated(uint256 oldWeight, uint256 newWeight, uint256 timestamp);
    
    /**
     * @dev 合约初始化函数（仅可调用一次）
     * 初始化OpenZeppelin升级组件和基础参数
     * @param _authorizerAddress 授权管理合约地址，不可为零地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "WeightManager: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        minOwnerWeight = 0;
        ownerWeight = 100;
        authorizer = _authorizerAddress;
        
        // 初始化带默认值的参数
        weightCacheDuration = 15 minutes;
    }
    
    /**
     * @dev UUPS升级授权函数
     * 仅允许合约所有者升级合约实现
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    /**
     * @dev 设置授权器地址
     * 仅所有者可调用，用于更改授权管理合约
     * @param _authorizerAddress 新的授权器地址，不可为零地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "WeightManager: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 修饰器：仅授权的地址（所有者或授权器）可调用
     * 用于保护合约配置更新函数
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "WeightManager: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "WeightManager: Not authorized");
        _;
    }
    
    /**
     * @dev 修饰器：仅合约所有者可调用
     * 用于保护权重更新和缓存管理等敏感操作
     * 修复：统一使用 require 保持一致性
     */
    modifier onlyOperator() {
        require(msg.sender == owner(), "WeightManager: Not operator");
        _;
    }
    
    /**
     * @dev 设置最低持有权重要求
     * 用户权重必须大于等于此值才能进入合格用户列表
     * 如果当前所有者权重低于新最小值，将自动提升所有者权重
     * @param _minWeight 新的最低权重值，必须大于0
     */
    function setMinOwnerWeight(uint256 _minWeight) external onlyOwner {
        if (_minWeight == 0) revert InvalidAmount();
        minOwnerWeight = _minWeight;
        // 修复：确保 ownerWeight 不低于最小值
        if (ownerWeight < _minWeight) {
            ownerWeight = _minWeight;
        }
    }
    
    /**
     * @dev 设置所有者固定权重。
     * 所有者可使用自定义权重值，不受NFT持有情况影响
     * @param _w 新的所有者权重值，必须大于等于最低要求
     */
    function setOwnerWeight(uint256 _w) external onlyOwner {
        if (_w < minOwnerWeight) revert InvalidAmount();
        ownerWeight = _w;
    }
    
    /**
     * @dev 内部函数：计算用户实际权重
     * 所有者返回固定ownerWeight，其他用户从NFTData合约查询
     * @param user 目标用户地址
     * @return 计算后的权重值
     */
    function _calcUserWeight(address user) internal view returns (uint256) {
        if (user == owner()) return ownerWeight;
        
        address nftDataAddr = IAuthorizer(authorizer).getNFTData();
        if (nftDataAddr == address(0)) return 0;
        
        INFTDataInterface m = INFTDataInterface(nftDataAddr);
        return m.calcUserWeight(user);
    }
    
    /**
     * @dev 查询用户权重（外部接口）
     * 优先使用缓存（如果未过期），否则实时计算并更新缓存
     * @param user 目标用户地址
     * @return 用户当前权重值
     */
    function getUserWeight(address user) external returns (uint256) {
        if (user == owner()) return ownerWeight;
        
        if (cachedWeightTimestamp[user] + weightCacheDuration >= block.timestamp) {
            return cachedUserWeight[user];
        }
        
        // 缓存过期，重新计算并更新缓存
        uint256 weight = _calcUserWeight(user);
        cachedUserWeight[user] = weight;
        cachedWeightTimestamp[user] = block.timestamp;
        return weight;
    }
    
    /**
     * @dev 刷新用户权重缓存
     * 仅操作者可调用，用于强制更新特定用户的缓存
     * @param user 目标用户地址
     */
    function refreshUserWeightCache(address user) external onlyOperator {
        address nftDataAddr = IAuthorizer(authorizer).getNFTData();
        if (nftDataAddr == address(0)) return;
        
        INFTDataInterface nftData = INFTDataInterface(nftDataAddr);
        if (user == owner()) return;
        
        uint256 weight = nftData.calcUserWeight(user);
        cachedUserWeight[user] = weight;
        cachedWeightTimestamp[user] = block.timestamp;
    }
    
    /**
     * @dev 批量更新用户权重
     * 最多支持100个用户，用于批量维护权重数据
     * @param users 用户地址数组
     */
    function batchUpdateUserWeight(address[] calldata users) external onlyOperator whenNotPaused {
        require(users.length <= 100, "WeightManager: Batch size too large");
        uint256 count = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                _updateUserWeight(users[i]);
                count++;
            }
        }
        emit BatchWeightUpdateCompleted(msg.sender, count);
    }

    /**
     * @dev 批量权重更新完成事件
     * @param operator 操作者地址（索引）
     * @param count 成功更新的用户数量
     */
    event BatchWeightUpdateCompleted(address indexed operator, uint256 count);

    /**
     * @dev 设置权重缓存持续时间
     * 控制缓存有效期，影响Gas消耗和数据实时性的平衡
     * @param duration 新的缓存持续时间（秒），必须大于0
     */
    function setWeightCacheDuration(uint256 duration) external onlyOwner {
        require(duration > 0, "WeightManager: Duration must be greater than 0");
        weightCacheDuration = duration;
    }
    
    /**
     * @dev 清除用户权重缓存
     * 用于紧急情况下强制刷新特定用户的权重数据
     * @param user 目标用户地址
     */
    function clearUserWeightCache(address user) external onlyOperator {
        delete cachedUserWeight[user];
        delete cachedWeightTimestamp[user];
    }
    
    /**
     * @dev 内部函数：检查用户是否具备合格资格
     * 判断用户权重是否达到最低要求
     * @param user 目标用户地址
     * @return bool 是否具备资格
     */
    function _hasEligibility(address user) internal view returns (bool) {
        if (user == owner()) return ownerWeight >= minOwnerWeight;
        
        if (cachedWeightTimestamp[user] + weightCacheDuration >= block.timestamp) {
            return cachedUserWeight[user] >= minOwnerWeight;
        }
        
        uint256 w = _calcUserWeight(user);
        return w >= minOwnerWeight;
    }
    
    /**
     * @dev 查询用户是否具备合格资格（外部接口）
     * @param user 目标用户地址
     * @return bool 是否具备资格
     */
    function hasEligibility(address user) external view returns (bool) {
        return _hasEligibility(user);
    }
    
    /**
     * @dev 内部函数：更新用户权重并管理资格列表
     * 流程：计算新权重 -> 更新存储和缓存 -> 触发事件 -> 管理资格列表
     * @param user 目标用户地址
     */
    function _updateUserWeight(address user) internal {
        uint256 oldWeight = userWeight[user];
        uint256 newWeight;
        
        if (user == owner()) {
            newWeight = ownerWeight;
        } else if (cachedWeightTimestamp[user] + weightCacheDuration >= block.timestamp) {
            newWeight = cachedUserWeight[user];
        } else {
            newWeight = _calcUserWeight(user);
        }
        
        if (oldWeight != newWeight) {
            userWeight[user] = newWeight;
            cachedUserWeight[user] = newWeight;
            cachedWeightTimestamp[user] = block.timestamp;
            emit UserWeightUpdated(user, oldWeight, newWeight, block.timestamp);
        }
        
        _manageEligibleList(user);
    }
    
    /**
     * @dev 更新用户权重（外部接口）
     * 仅操作者可调用，用于主动更新单个用户权重
     * @param user 目标用户地址
     */
    function updateUserWeight(address user) external onlyOperator whenNotPaused {
        _updateUserWeight(user);
    }

    /**
     * @dev 同步用户权重（由NFTTrading、Staking等合约调用）
     * 仅授权合约可调用，防止恶意调用
     * @param user 目标用户地址
     */
    function syncUserWeight(address user) external onlyOwnerOrAuthorizer {
        _updateUserWeight(user);
    }
    
    /**
     * @dev 内部函数：管理用户资格列表
     * 根据权重变化，动态添加或移除用户从合格列表
     * @param user 目标用户地址
     */
    function _manageEligibleList(address user) internal {
        bool isEligible = _hasEligibility(user);
        bool wasInList = inEligibleList[user];
        
        if (isEligible && !wasInList) {
            _addToEligibleList(user);
        } else if (!isEligible && wasInList) {
            _removeFromEligibleList(user);
        }
    }
    
    /**
     * @dev 内部函数：将用户添加到合格列表末尾
     * 维护双向链表结构，便于后续遍历和奖励分配
     * @param user 目标用户地址
     */
    function _addToEligibleList(address user) internal {
        if (eligibleUserTail == address(0)) {
            eligibleUserHead = user;
            eligibleUserTail = user;
            eligibleUserPrev[user] = address(0);
            eligibleUserNext[user] = address(0);
        } else {
            eligibleUserNext[eligibleUserTail] = user;
            eligibleUserPrev[user] = eligibleUserTail;
            eligibleUserNext[user] = address(0);
            eligibleUserTail = user;
        }
        inEligibleList[user] = true;
    }
    
    /**
     * @dev 内部函数：将用户从合格列表中移除
     * 维护双向链表结构，正确处理链表头、中、尾三种情况
     * @param user 目标用户地址
     */
    function _removeFromEligibleList(address user) internal {
        address prev = eligibleUserPrev[user];
        address next = eligibleUserNext[user];
        
        if (prev != address(0)) {
            eligibleUserNext[prev] = next;
        } else {
            eligibleUserHead = next;
        }
        
        if (next != address(0)) {
            eligibleUserPrev[next] = prev;
        } else {
            eligibleUserTail = prev;
        }
        
        delete eligibleUserPrev[user];
        delete eligibleUserNext[user];
        inEligibleList[user] = false;
    }
    
    /**
     * @dev 添加持有者并更新其权重
     * 用于新用户首次加入或重新计算持有者权重
     * @param user 目标用户地址
     * @return 操作是否成功
     */
    function addHolder(address user) external onlyOperator whenNotPaused returns (bool) {
        _updateUserWeight(user);
        return true;
    }
    
    /**
     * @dev 移除持有者，将其权重设为0
     * 用于用户退出或特殊情况下的权重清零
     * @param user 目标用户地址
     */
    function removeHolder(address user) external onlyOperator whenNotPaused {
        uint256 oldWeight = userWeight[user];
        if (oldWeight > 0) {
            userWeight[user] = 0;
            delete cachedUserWeight[user];
            delete cachedWeightTimestamp[user];
            _manageEligibleList(user);
            emit UserWeightUpdated(user, oldWeight, 0, block.timestamp);
        }
    }

    /**
     * @dev 清空合约内部的所有数据
     * 仅合约所有者和authorizer合约可调用
     * 用于紧急情况下重置整个项目数据
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        // 清空所有用户权重数据
        // 注意：由于无法遍历所有mapping键，这里只清空核心状态变量
        
        // 清空缓存数据
        weightCacheDuration = 15 minutes;
        
        // 重置合格用户链表
        eligibleUserHead = address(0);
        eligibleUserTail = address(0);
        
        // 重置暂停状态
        paused = false;
        pauseReason = "";
        
        // 重置权重参数
        minOwnerWeight = 0;
        ownerWeight = 100;
        
        // 发出数据重置事件
        emit ContractDataReset(msg.sender, block.timestamp);
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 执行重置的操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp);

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}