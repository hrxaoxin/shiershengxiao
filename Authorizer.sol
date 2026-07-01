// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

/**
 * @title Authorizer
 * @dev 授权管理器合约，统一管理所有合约地址的注册和验证
 *
 * 核心职责：
 * 1. 地址管理：通过字符串名称动态注册/查询所有游戏合约地址
 * 2. 系统合约验证：验证调用者是否为合法的系统合约
 * 3. 全局暂停：支持全局暂停所有合约操作
 * 4. 动态注册：支持运行时动态添加/移除合约地址，无需重新部署
 * 5. 一键操作：支持一键通知所有合约更新 authorizer、一键重置所有合约数据
 *
 * 动态注册机制（核心）：
 * - 调用 setContractAddress("合约名", 地址) 即可动态添加/更新合约地址
 * - 调用 setMultipleAddresses(["合约名1","合约名2"], [地址1,地址2]) 批量注册
 * - 调用 removeContractAddress("合约名") 即可动态移除合约地址
 * - 调用 removeMultipleContracts(["合约名1","合约名2"]) 批量移除
 * - 调用 getAddressByName("合约名") 查询任意已注册合约地址
 * - isSystemContract / resetAllContractData / notifyAllContractsSetAuthorizer 等一键函数自动适配动态注册表
 * - 新增/移除业务合约时，无需修改 Authorizer 代码，无需重新部署
 *
 * 一键操作函数：
 * - notifyAllContractsSetAuthorizer(newAddr)：遍历所有已注册合约，通知更新 authorizer 地址
 * - resetAllContractData()：遍历所有已注册合约，调用其 resetContractData()
 *
 * 安全特性：
 * - 仅Owner可以更新合约地址
 * - 系统合约白名单验证（基于动态注册表）
 * - 可全局暂停所有操作
 */
contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    error InvalidAuthorizer();
    error ContractPaused();
    error ContractNotRegistered(bytes32 key);

    bool public paused;
    string public pauseReason;

    // ============ 核心地址存储 ============
    mapping(bytes32 => address) private _addresses;
    address public currentAuthorizer;

    // ============ 动态注册表 ============
    // 系统合约地址白名单（用于 isSystemContract 快速查询）
    mapping(address => bool) private _systemContracts;
    // 已注册的合约 key 列表（用于一键遍历：notifyAllContractsSetAuthorizer、resetAllContractData）
    bytes32[] private _registeredKeys;
    // key => 在 _registeredKeys 中的索引+1（0 表示未注册）
    mapping(bytes32 => uint256) private _keyIndex;

    // ============ 事件 ============
    event Paused(address account, string reason);
    event Unpaused(address account);
    event ContractAddressUpdated(bytes32 indexed key, address value);
    event ContractAddressRemoved(bytes32 indexed key);
    event ContractResetSuccess(address indexed contractAddress);
    event ContractResetFailed(address indexed contractAddress);
    event AllContractDataReset(address indexed operator, uint256 timestamp);

    // ============ 修饰器 ============
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // ============ 暂停控制 ============

    /**
     * @dev 暂停合约，停止所有操作
     * 仅合约所有者可调用，用于紧急情况下暂停服务
     * @param reason 暂停原因，将被记录在事件日志中
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消合约暂停，恢复所有操作
     * 仅合约所有者可调用
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    // ============ 初始化和升级 ============

    /**
     * @dev 初始化合约
     * 初始化OpenZeppelin升级组件
     */
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @dev UUPS升级授权函数
     * 仅允许合约所有者升级合约实现
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ 地址查询（通用动态接口） ============

    /**
     * @dev 通过字符串名称获取合约地址（推荐使用）
     * @param name 合约名称，如 "token", "battle", "nftMintCore" 等
     * @return 地址，未注册则返回 address(0)
     */
    function getAddressByName(string calldata name) external view returns (address) {
        return _addresses[keccak256(abi.encodePacked(name))];
    }

    /**
     * @dev 通过bytes32 key获取合约地址（低级接口）
     * @param key 合约地址的keccak256哈希key
     * @return 地址，未注册则返回 address(0)
     */
    function getAddress(bytes32 key) external view returns (address) {
        return _addresses[key];
    }

    // ============ 动态注册核心（新增/更新） ============

    /**
     * @dev 动态设置/更新单个合约地址（使用字符串名称）
     * 如果该名称之前未注册，会自动添加到动态注册表
     * 如果已存在，则更新地址并自动维护白名单（移除旧地址，添加新地址）
     * @param name 合约名称，如 "nftTrading", "nftMintCore", "token" 等
     * @param value 合约地址
     */
    function setContractAddress(string calldata name, address value) external onlyOwner whenNotPaused {
        bytes32 key = keccak256(abi.encodePacked(name));
        _setContractAddress(key, value);
    }

    /**
     * @dev 批量动态设置/更新多个合约地址（使用字符串名称）
     * 每个名称若未注册则自动添加，已存在则更新
     * @param names 合约名称数组
     * @param values 合约地址数组
     */
    function setMultipleAddresses(string[] calldata names, address[] calldata values) external onlyOwner whenNotPaused {
        require(names.length == values.length, "Authorizer: arrays length mismatch");
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(names[i]));
            _setContractAddress(key, values[i]);
        }
    }

    /**
     * @dev 设置单个合约地址（使用bytes32 key，低级接口）
     * @param key 合约地址的keccak256哈希key
     * @param value 合约地址
     */
    function setAddress(bytes32 key, address value) external onlyOwner whenNotPaused {
        _setContractAddress(key, value);
    }

    // ============ 动态移除 ============

    /**
     * @dev 动态移除一个合约地址（使用字符串名称）
     * 从注册表中移除该合约，后续 isSystemContract 将返回 false
     * resetAllContractData / notifyAllContractsSetAuthorizer 也不会再遍历到该合约
     * @param name 要移除的合约名称
     */
    function removeContractAddress(string calldata name) external onlyOwner whenNotPaused {
        bytes32 key = keccak256(abi.encodePacked(name));
        if (_keyIndex[key] == 0) revert ContractNotRegistered(key);
        _removeContractAddressInternal(key);
    }

    /**
     * @dev 动态移除一个合约地址（使用bytes32 key，低级接口）
     * @param key 要移除的合约的keccak256哈希key
     */
    function removeContractByKey(bytes32 key) external onlyOwner whenNotPaused {
        if (_keyIndex[key] == 0) revert ContractNotRegistered(key);
        _removeContractAddressInternal(key);
    }

    /**
     * @dev 动态批量移除多个合约地址
     * 不会因某个名称未注册而回滚整个交易
     * @param names 要移除的合约名称数组
     */
    function removeMultipleContracts(string[] calldata names) external onlyOwner whenNotPaused {
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(names[i]));
            if (_keyIndex[key] != 0) {
                _removeContractAddressInternal(key);
            }
        }
    }

    // ============ 系统合约验证 ============

    /**
     * @dev 检查一个地址是否是系统合约（在 Authorizer 中注册的合约）
     * 基于动态注册表查询，自动适配所有已注册合约，无需硬编码
     * @param addr 要检查的地址
     * @return 是否是系统合约
     */
    function isSystemContract(address addr) external view returns (bool) {
        if (addr == address(0)) return false;
        if (addr == owner()) return true;
        if (addr == address(this)) return true;
        return _systemContracts[addr];
    }

    // ============ 动态注册表查询 ============

    /**
     * @dev 获取已注册合约的总数
     * @return 注册合约数量
     */
    function getRegisteredContractCount() external view returns (uint256) {
        return _registeredKeys.length;
    }

    /**
     * @dev 获取所有已注册合约的 key 列表
     * @return 所有已注册合约的 bytes32 key 数组
     */
    function getAllRegisteredKeys() external view returns (bytes32[] memory) {
        return _registeredKeys;
    }

    /**
     * @dev 获取所有已注册合约的 key 和对应地址
     * @return keys key数组
     * @return values 地址数组
     */
    function getAllRegisteredContracts() external view returns (bytes32[] memory keys, address[] memory values) {
        uint256 count = _registeredKeys.length;
        keys = new bytes32[](count);
        values = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            keys[i] = _registeredKeys[i];
            values[i] = _addresses[keys[i]];
        }
    }

    /**
     * @dev 按索引范围分页获取已注册合约
     * @param offset 起始索引
     * @param limit 最大返回数量
     * @return keys key数组
     * @return values 地址数组
     */
    function getRegisteredContractsByPage(uint256 offset, uint256 limit) external view returns (bytes32[] memory keys, address[] memory values) {
        uint256 count = _registeredKeys.length;
        if (offset >= count) {
            keys = new bytes32[](0);
            values = new address[](0);
            return (keys, values);
        }
        uint256 end = offset + limit;
        if (end > count) end = count;
        uint256 resultCount = end - offset;
        keys = new bytes32[](resultCount);
        values = new address[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            keys[i] = _registeredKeys[offset + i];
            values[i] = _addresses[keys[i]];
        }
    }

    // ============ 一键操作函数 ============

    /**
     * @dev 一键通知所有已注册的系统合约更新 authorizer 地址
     * 遍历动态注册表中的所有合约，调用其 setAuthorizer 接口
     * 新增/移除合约后自动生效，无需修改此函数
     * @param _newAuthorizer 新的 authorizer 地址
     */
    function notifyAllContractsSetAuthorizer(address _newAuthorizer) external onlyOwner whenNotPaused {
        if (_newAuthorizer == address(0)) revert InvalidAuthorizer();

        uint256 count = _registeredKeys.length;
        for (uint256 i = 0; i < count; i++) {
            address contractAddr = _addresses[_registeredKeys[i]];
            if (contractAddr != address(0)) {
                try ISetAuthorizer(contractAddr).setAuthorizer(_newAuthorizer) {
                    // success
                } catch {
                    // ignore contracts that don't support ISetAuthorizer
                }
            }
        }

        currentAuthorizer = _newAuthorizer;
    }

    /**
     * @dev 一键重置所有已注册合约的数据
     * 基于动态注册表遍历，自动适配所有已注册合约
     * 新增/移除的合约自动生效，无需修改此函数
     */
    function resetAllContractData() external onlyOwner {
        uint256 count = _registeredKeys.length;

        for (uint256 i = 0; i < count; i++) {
            address contractAddr = _addresses[_registeredKeys[i]];
            if (contractAddr != address(0)) {
                try IResetContractData(contractAddr).resetContractData() {
                    emit ContractResetSuccess(contractAddr);
                } catch {
                    emit ContractResetFailed(contractAddr);
                }
            }
        }

        emit AllContractDataReset(msg.sender, block.timestamp);
    }

    // ============ 内部核心辅助函数 ============

    /**
     * @dev 内部函数：设置合约地址并自动维护动态注册表
     * - 自动维护 _systemContracts 白名单（移除旧地址，添加新地址）
     * - 自动维护 _registeredKeys 列表（首次注册时自动添加）
     * - 防止重复 key 添加到 _registeredKeys
     * @param key 合约名称的 keccak256 哈希
     * @param value 合约地址
     */
    function _setContractAddress(bytes32 key, address value) internal {
        address oldValue = _addresses[key];

        // 从系统合约白名单中移除旧地址
        if (oldValue != address(0)) {
            _systemContracts[oldValue] = false;
        }
        // 将新地址加入系统合约白名单
        if (value != address(0)) {
            _systemContracts[value] = true;
        }

        _addresses[key] = value;

        // 如果是新 key，添加到注册列表
        if (_keyIndex[key] == 0 && value != address(0)) {
            _registeredKeys.push(key);
            _keyIndex[key] = _registeredKeys.length; // 1-based index
        }

        emit ContractAddressUpdated(key, value);
    }

    /**
     * @dev 内部函数：从动态注册表中移除合约
     * 使用 swap-and-pop 模式，O(1) 删除
     * @param key 要移除的合约 key
     */
    function _removeContractAddressInternal(bytes32 key) internal {
        address oldValue = _addresses[key];

        // 清理系统合约白名单
        if (oldValue != address(0)) {
            _systemContracts[oldValue] = false;
        }

        // 清理地址映射
        _addresses[key] = address(0);

        // 从注册列表中移除（swap-and-pop）
        uint256 idx = _keyIndex[key]; // 1-based
        uint256 lastIdx = _registeredKeys.length;

        if (idx != lastIdx) {
            // 不是最后一个元素，与最后一个交换
            bytes32 lastKey = _registeredKeys[lastIdx - 1];
            _registeredKeys[idx - 1] = lastKey;
            _keyIndex[lastKey] = idx;
        }
        _registeredKeys.pop();
        _keyIndex[key] = 0;

        emit ContractAddressRemoved(key);
    }
}
