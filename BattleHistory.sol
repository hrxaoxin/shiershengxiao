// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title BattleHistory
 * @dev 战斗历史记录合约，记录所有战斗的结果和详情
 *
 * 功能：
 * 1. 存储战斗记录（战斗ID => 战斗结果）
 * 2. 仅允许战斗合约写入记录
 * 3. 提供战斗记录查询接口
 *
 * 战斗记录包含：
 * - 战斗ID
 * - 战斗时间戳
 * - 双方玩家地址
 * - 双方NFT队伍
 * - 战斗结果
 * - 双方得分
 */
contract BattleHistory is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 战斗合约地址
     * 只有战斗合约可以添加战斗记录
     */
    address public battleContract;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 战斗历史映射
     * battleId => SingleBattleResult
     */
    mapping(uint256 => BattleLib.SingleBattleResult) public battleHistory;
    
    /**
     * @dev 最大战斗记录数限制（默认10000条）
     */
    uint256 public constant MAX_BATTLE_RECORDS = 10000;
    
    /**
     * @dev 当前战斗记录总数
     */
    uint256 public battleCount;
    
    /**
     * @dev 最早的战斗ID（用于环形缓冲区）
     */
    uint256 public earliestBattleId;
    
    /**
     * @dev battleId到索引的映射（用于快速查找）
     */
    mapping(uint256 => uint256) public battleIdToIndex;
    
    /**
     * @dev 索引到battleId的映射（用于环形缓冲区）
     */
    mapping(uint256 => uint256) public indexToBattleId;

    /**
     * @dev 仅允许战斗合约调用的修饰器
     */
    modifier onlyBattleContract() {
        require(msg.sender == battleContract, "BattleHistory: Only battle contract");
        _;
    }

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS升级授权
     * @param newImplementation 新实现合约地址
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
        require(msg.sender == owner() || msg.sender == authorizer, "BattleHistory: Not authorized");
        _;
    }

    /**
     * @dev 设置战斗合约地址
     * @param _battleContract 战斗合约地址
     */
    function setBattleContract(address _battleContract) external onlyAuthorized {
        require(_battleContract != address(0), "BattleHistory: Invalid battle contract address");
        battleContract = _battleContract;
    }

    /**
     * @dev 添加战斗记录
     * @param battleId 战斗ID
     * @param result 战斗结果
     */
    function addBattle(uint256 battleId, BattleLib.SingleBattleResult calldata result) external onlyBattleContract {
        if (battleCount >= MAX_BATTLE_RECORDS) {
            uint256 oldestIndex = battleIdToIndex[earliestBattleId];
            delete battleHistory[earliestBattleId];
            delete battleIdToIndex[earliestBattleId];
            
            uint256 nextEarliestId = indexToBattleId[(oldestIndex + 1) % MAX_BATTLE_RECORDS];
            if (nextEarliestId > 0) {
                earliestBattleId = nextEarliestId;
            }
        } else {
            battleCount++;
        }
        
        uint256 newIndex = battleIdToIndex[battleId];
        if (newIndex == 0) {
            newIndex = battleCount % MAX_BATTLE_RECORDS;
        }
        
        battleHistory[battleId] = result;
        battleIdToIndex[battleId] = newIndex;
        indexToBattleId[newIndex] = battleId;
        
        if (battleCount == 1 || battleId < earliestBattleId) {
            earliestBattleId = battleId;
        }
    }

    /**
     * @dev 根据战斗ID获取战斗记录
     * @param battleId 战斗ID
     * @return SingleBattleResult 战斗结果
     */
    function getBattleHistoryById(uint256 battleId) external view returns (BattleLib.SingleBattleResult memory) {
        return battleHistory[battleId];
    }
}
