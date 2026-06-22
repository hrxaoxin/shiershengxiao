// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title BattleHistory
 * @dev 战斗历史记录合约，记录所有战斗的结果和详情
 *
 * 核心职责：
 * 1. 战斗记录存储：记录每一场战斗的双方、使用的 NFT 队伍、战斗结果、得分
 * 2. 历史查询接口：供前端查询玩家历史战绩（可按玩家、按赛季、按时间分页查询）
 * 3. 排行榜数据来源：为 ArenaRanking 提供胜场/败场/积分统计依据
 *
 * 战斗记录数据结构（基于 BattleLib.SingleBattleResult）：
 * - battleId：战斗唯一 ID（从 1 自增）
 * - timestamp：战斗发生时间（秒）
 * - player1 / player2：双方玩家地址
 * - team1 / team2：双方使用的 NFT 队伍 ID 数组
 * - result：战斗结果（TEAM1_WIN / TEAM2_WIN / DRAW）
 * - score1 / score2：双方得分（用于排名积分）
 *
 * 存储设计：
 * - battleHistory[battleId] 存 SingleBattleResult 完整记录
 * - battleCount：当前总战斗数（也是下一个要分配的 battleId）
 * - earliestBattleId：最早可见 ID（环形缓冲区清理时使用）
 * - battleIdToIndex / indexToBattleId：索引映射，支持分页查询
 * - MAX_BATTLE_RECORDS = 10000：限制总记录数，防止存储无限膨胀
 *
 * 写入权限（严格保护，防止伪造历史）：
 * - onlyBattleContract：仅 Battle 合约可以通过 addBattle(...) 写入
 * - 其他合约或外部调用均不可篡改历史记录
 *
 * 典型查询流程：
 * 1. 前端展示"我的战斗记录"：调用 getBattlesByPlayer(player, page, pageSize)
 * 2. 前端展示"赛季排行榜"：ArenaRanking 调用 getBattlesBySeason(seasonId)
 * 3. 前端查看具体战斗：调用 getBattleDetail(battleId) 展示队伍与得分
 *
 * 与其他合约的联动：
 * - Battle.sol：战斗结束后调用 addBattle 写入历史
 * - ArenaRanking.sol：读取战斗统计，计算玩家积分和排名
 * - WeightManager.sol：胜场数可用于权重加成（可选功能）
 *
 * 性能优化：
 * - 使用环形缓冲区（circular buffer）限制总记录数
 * - 超出 MAX_BATTLE_RECORDS 时覆盖最旧的记录
 * - 前端应将结果缓存，避免频繁链上读取
 *
 * 安全限制：
 * - onlyBattleContract 修饰器防止外部篡改
 * - owner 可设置 authorizer 以支持多合约写入（未来扩展）
 * - Pausable：紧急情况下可暂停写入
 *
 * 升级与治理：
 * - UUPS 可升级，未来可扩展更多字段（如战斗回放、技能触发日志）
 */
contract BattleHistory is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 授权合约地址（Authorizer）- 通过此地址获取所有关联合约地址
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
        address battleContract = IAuthorizer(authorizer).getBattle();
        require(msg.sender == battleContract, "BattleHistory: Only battle contract");
        _;
    }

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "BattleHistory: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizerAddress;
    }

    /**
     * @dev UUPS升级授权
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "BattleHistory: Invalid authorizer address");
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
        require(auth.isSystemContract(msg.sender), "BattleHistory: Not authorized");
        _;
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
            // 索引从1开始，0表示未分配
            // 修复：当 battleId 未分配时，正确计算新索引
            if (battleCount == 0) {
                newIndex = 1;
            } else {
                newIndex = (battleCount % MAX_BATTLE_RECORDS) + 1;
                // 防止新索引与现有索引冲突
                if (newIndex == 0) newIndex = 1;
            }
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

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}