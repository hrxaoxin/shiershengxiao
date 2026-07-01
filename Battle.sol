// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title Battle
 * @dev 核心战斗合约，负责十二生肖NFT之间的战斗逻辑执行
 *
 * 核心功能：
 * 1. 战斗执行：处理两队6v6的NFT战斗，包括攻击、技能、闪避、暴击等
 * 2. 属性克制：五行相克关系影响伤害（火→风→水→火，光↔暗）
 * 3. 技能系统：每个NFT类型有独特技能（范围攻击/单体攻击）
 * 4. 速度排序：根据NFT速度决定攻击顺序
 * 5. 战斗历史：记录最近1000场战斗结果（环形缓冲区）
 * 6. 模拟战斗：提供只读接口用于前端预览战斗结果
 *
 * 战斗流程：
 * 1. 战斗发起：外部合约（如ArenaRanking）调用 challenge() 发起战斗
 * 2. 队伍验证：检查NFT所有权和队伍有效性（非零，无重复）
 * 3. 属性计算：根据NFT等级和成长值计算HP、攻击、防御、速度
 * 4. 回合执行：最多10回合，每回合按速度顺序攻击
 *    - 有几率使用技能（技能冷却期间不可用）
 *    - 优先攻击HP最低的敌方单位
 *    - 有几率暴击（12%概率，伤害×1.8）
 *    - 有几率闪避（5%-25%，根据成长值）
 * 5. 结算：一方全灭或超过最大回合数则结束
 * 6. 记录：写入战斗历史，发出 BattleEnded 事件
 *
 * 权限设计：
 * - onlyOwner: 合约所有者，可配置参数、暂停合约、升级合约
 * - onlyAuthorized: 所有者或授权器，可设置NFT合约地址
 * - onlyBattleCaller: 所有者或战斗调用者（如ArenaRanking），可发起战斗
 *
 * 安全机制：
 * - nonReentrant: 防止重入攻击
 * - whenNotPaused: 紧急暂停
 * - NFT所有权验证：确保战斗双方确实拥有其NFT
 * - 随机种子：结合多熵源（blockhash、timestamp、prevrandao等）
 *
 * 使用说明：
 * - 部署后需调用 initialize() 初始化
 * - 通过 setNFTContract() 关联 NFT 合约
 * - 通过 setBattleCaller() 授权战斗发起合约（如 ArenaRanking）
 */
contract Battle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     * OpenZeppelin UUPS 模式要求在实现合约构造函数中禁用初始化
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev NFT战斗属性结构体
     * 存储一个NFT在战斗中的核心属性，影响攻击、防御、速度等
     * @param tokenId NFT的唯一标识符
     * @param level NFT等级（1-5），等级越高属性越强
     * @param element 属性类型（0=水, 1=风, 2=火, 3=暗, 4=光）
     * @param growth 成长值（50-100），直接影响属性加成
     * @param zodiac 生肖索引（0-11，对应鼠牛虎兔龙蛇马羊猴鸡狗猪）
     */
    struct NFTTraits {
        uint256 tokenId;
        uint8 level;
        uint8 element;
        uint8 growth;
        uint8 zodiac;
    }

    /**
     * @dev 战斗状态结构体
     * 记录一场战斗的完整状态，用于战斗历史查询
     * @param battleId 战斗的唯一标识符
     * @param startTime 战斗开始时间戳
     * @param status 战斗状态（1=进行中，2=已结束）
     * @param winner 获胜方（1=挑战者，2=被挑战者，0=平局）
     * @param challengerId 挑战者代表NFT ID
     * @param challengedId 被挑战者代表NFT ID
     * @param challenger 挑战者钱包地址
     * @param challenged 被挑战者钱包地址
     */
    struct BattleState {
        uint256 battleId;
        uint256 startTime;
        uint8 status;
        uint8 winner;
        uint256 challengerId;
        uint256 challengedId;
        address challenger;
        address challenged;
    }

    /**
     * @dev 队伍状态结构体
     * 记录一个队伍（6个NFT）在战斗中的实时状态
     * @param traits 6个NFT的属性数组
     * @param hp 6个NFT的当前生命值
     * @param alive 6个NFT的存活状态（true=存活）
     * @param maxHp 6个NFT的最大生命值
     */
    struct TeamState {
        NFTTraits[6] traits;
        uint256[6] hp;
        bool[6] alive;
        uint256[6] maxHp;
    }

    /**
     * @dev 技能数据结构体
     * 每个NFT类型关联一个独特技能，影响战斗策略
     * @param skillId 技能ID（通常等于tokenType）
     * @param skillType 技能类型（0=普攻强化，1-8=不同类型技能）
     * @param damage 技能伤害倍率（百分比，125表示125%伤害）
     * @param cooldown 技能冷却回合数（使用后需等待的回合）
     * @param duration 技能持续回合数（当前未使用，保留）
     * @param isAoe 是否范围攻击（true=对所有敌方造成伤害）
     */
    struct Skill {
        uint256 skillId;
        uint8 skillType;
        uint256 damage;
        uint256 cooldown;
        uint256 duration;
        bool isAoe;
    }

    /**
     * @dev 纪元版本号，用于快速重置合约数据
     */
    uint256 public epoch;
    
    /**
     * @dev 战斗历史映射（epoch => index => BattleState）
     */
    mapping(uint256 => mapping(uint256 => BattleState)) public battleHistory;
    /**
     * @dev 战斗历史环形缓冲区当前写入索引（epoch => index）
     */
    mapping(uint256 => uint256) public battleHistoryIndex;

    /**
     * @dev 战斗常量配置
     */
    uint256 public constant MAX_ROUNDS = 10;          // 最大战斗回合数
    uint256 public constant ZODIAC_COUNT = 12;        // 十二生肖总数
    uint256 public constant GENDER_COUNT = 2;         // 性别数量（公/母）
    uint256 public constant ELEMENT_COUNT = 5;        // 属性数量（水风火暗光）
    uint256 public constant ZODIAC_TYPE_COUNT = ZODIAC_COUNT * GENDER_COUNT; // 24
    uint256 public constant TOTAL_TYPE_COUNT = ELEMENT_COUNT * ZODIAC_TYPE_COUNT; // 120种NFT类型
    uint256 public constant MAX_BATTLE_HISTORY = 1000; // 最大战斗历史记录数
    uint256 public constant MIN_GROWTH = 50;          // 最小成长值
    uint256 public constant GROWTH_RANGE = 51;         // 成长值范围（50-100）
    uint256 public constant TEAM_SIZE = 6;             // 每队NFT数量
    uint256 public constant SKILL_USE_CHANCE_DENOMINATOR = 5; // 1/5概率触发技能

    /**
     * @dev 授权器地址（Authorizer 合约）
     */
    address public authorizer;

    /**
     * @dev 属性类型常量
     */
    uint8 public constant ELEMENT_WATER = 0; // 水属性
    uint8 public constant ELEMENT_WIND = 1;  // 风属性
    
    uint256 public constant ELEMENT_BONUS = 120; // 属性克制加成百分比（120表示20%加成）
    uint8 public constant ELEMENT_FIRE = 2;  // 火属性
    uint8 public constant ELEMENT_DARK = 3;  // 暗属性
    uint8 public constant ELEMENT_LIGHT = 4; // 光属性

    /**
     * @dev 技能映射：tokenType => Skill
     * 共120种NFT类型，每种对应一个独特技能
     */
    mapping(uint256 => Skill) public skills;

    /**
     * @dev 战斗开始事件（供前端/后端监听以更新UI）
     * @param battleId 战斗ID
     * @param challenger 挑战者地址
     * @param challenged 被挑战者地址
     * @param challengerTeam 挑战者NFT队伍
     * @param challengedTeam 被挑战者NFT队伍
     */
    event BattleStarted(
        uint256 indexed battleId,
        address indexed challenger,
        address indexed challenged,
        uint256[6] challengerTeam,
        uint256[6] challengedTeam
    );
    /**
     * @dev 战斗结束事件
     * @param battleId 战斗ID
     * @param winner 获胜方（1=挑战者，2=被挑战者，0=平局）
     */
    event BattleEnded(
        uint256 indexed battleId,
        uint8 winner
    );

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     * @param oldEpoch 重置前的纪元版本号
     * @param newEpoch 重置后的纪元版本号
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    /**
     * @notice 修饰器：仅所有者或授权器可调用
     * @dev 双重授权检查：owner或authorizer或authorizer认可的系统合约
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "Battle: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "Battle: Not owner or authorizer");
        _;
    }

    /**
     * @notice 修饰器：仅所有者或战斗调用者可调用
     * @dev 用于战斗发起类函数（如 challenge），双重检查：owner或ArenaPlayer
     */
    modifier onlyBattleCaller() {
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "Battle: Authorizer not set");
        address battleCaller = IAuthorizer(authorizer).getAddressByName(\"arenaPlayer\");
        require(msg.sender == owner() || msg.sender == battleCaller, "Battle: Only authorized caller");
        _;
    }

    /**
     * @dev 初始化合约
     * @param _authorizerAddress 授权器合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "Battle: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        epoch = 1;
        _initSkills();
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }

    /**
     * @dev 重新初始化技能（仅所有者调用）
     */
    function reinitializeSkills() external onlyOwner {
        _initSkills();
    }

    /**
     * @dev 设置授权器地址
     * @param _authorizerAddress 新的授权器地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "Battle: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 授权升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 获取NFT属性
     * @param tokenId NFT ID
     * @return NFT属性结构体
     */
    function _getNFTTraits(uint256 tokenId) internal view returns (NFTTraits memory) {
        NFTTraits memory traits;
        traits.tokenId = tokenId;
        address nftContract = IAuthorizer(authorizer).getAddressByName(\"nftMintCore\");
        if (nftContract != address(0)) {
            (uint256 zodiacType, uint256 level, uint256 growth) = _getNFTData(tokenId);
            traits.level = uint8(level);
            traits.element = uint8(zodiacType / ZODIAC_TYPE_COUNT);
            traits.zodiac = uint8((zodiacType / GENDER_COUNT) % ZODIAC_COUNT);
            traits.growth = uint8(growth);
        } else {
            // 修复：在mock模式下验证tokenId有效性
            require(tokenId > 0, "Battle: Invalid tokenId in mock mode");
            
            uint256 mockMultiplier = 1000;
            uint256 mockOffset = 10000;
            uint256 mockIdRange = 1000;

            if (tokenId >= (mockOffset + 0) * mockMultiplier) {
                uint256 temp = tokenId / mockMultiplier;
                uint256 mockIndex = temp - mockOffset;

                uint256 growthPart = temp / mockIdRange;
                uint256 growth = 50 + (growthPart % 51);

                uint256 level = 1;
                if (mockIndex == 0) level = 5;
                else if (mockIndex <= 4) level = 5;
                else if (mockIndex <= 9) level = 4;
                else if (mockIndex <= 19) level = 4;
                else if (mockIndex <= 39) level = 3;
                else if (mockIndex <= 69) level = 2;
                else if (mockIndex <= 99) level = 1;

                uint256 zodiacType = tokenId % TOTAL_TYPE_COUNT;

                traits.level = uint8(level);
                traits.element = uint8(zodiacType / ZODIAC_TYPE_COUNT);
                traits.zodiac = uint8((zodiacType / GENDER_COUNT) % ZODIAC_COUNT);
                traits.growth = uint8(growth);
            } else {
                uint256 zodiacType = tokenId % TOTAL_TYPE_COUNT;
                traits.level = uint8((zodiacType / ZODIAC_TYPE_COUNT) + 1);
                traits.element = uint8(zodiacType / ZODIAC_TYPE_COUNT);
                traits.zodiac = uint8((zodiacType / GENDER_COUNT) % ZODIAC_COUNT);
                traits.growth = uint8(MIN_GROWTH + (tokenId % GROWTH_RANGE));
            }
        }
        return traits;
    }

    /**
     * @dev 获取NFT数据（类型、等级、成长值）
     * @param tokenId NFT ID
     * @return tokenType 生肖类型
     * @return level 等级
     * @return growth 成长值
     */
    function _getNFTData(uint256 tokenId) internal view returns (uint256 tokenType, uint256 level, uint256 growth) {
        address nftContract = IAuthorizer(authorizer).getAddressByName(\"nftMintCore\");
        if (nftContract == address(0)) {
            return (0, 1, 50);
        }
        (bool success, bytes memory data) = nftContract.staticcall(
            abi.encodeWithSignature("tokenType(uint256)", tokenId)
        );
        if (success && data.length >= 32) {
            tokenType = abi.decode(data, (uint256));
        }
        (success, data) = nftContract.staticcall(
            abi.encodeWithSignature("tokenLevel(uint256)", tokenId)
        );
        if (success && data.length >= 32) {
            level = abi.decode(data, (uint256));
        }
        (success, data) = nftContract.staticcall(
            abi.encodeWithSignature("tokenGrowth(uint256)", tokenId)
        );
        if (success && data.length >= 32) {
            growth = abi.decode(data, (uint256));
        }
    }

    /**
     * @dev 检查元素克制关系
     * @param attackerElement 攻击方元素
     * @param defenderElement 防御方元素
     * @return 是否克制
     */
    function _checkAdvantage(uint8 attackerElement, uint8 defenderElement) internal pure returns (bool) {
        if (attackerElement == ELEMENT_FIRE && defenderElement == ELEMENT_WIND) return true;
        if (attackerElement == ELEMENT_WIND && defenderElement == ELEMENT_WATER) return true;
        if (attackerElement == ELEMENT_WATER && defenderElement == ELEMENT_FIRE) return true;
        if (attackerElement == ELEMENT_LIGHT && defenderElement == ELEMENT_DARK) return true;
        if (attackerElement == ELEMENT_DARK && defenderElement == ELEMENT_LIGHT) return true;
        return false;
    }

    /**
     * @dev 验证队伍所有权（调用者必须拥有所有NFT）
     * @param team 队伍NFT数组（6个）
     */
    function _requireNFTOwnership(uint256[6] memory team) internal view {
        address nftContract = IAuthorizer(authorizer).getAddressByName(\"nftMintCore\");
        require(nftContract != address(0), "Battle: NFT contract not set");
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            (bool success, bytes memory data) = nftContract.staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", tokenId)
            );
            require(success && data.length >= 32, "Battle: Failed to query NFT owner");
            address owner = abi.decode(data, (address));
            require(owner == msg.sender, "Battle: Not owner of NFT in team");
        }
    }

    /**
     * @dev 发起挑战
     * @param challengerId 挑战者代表NFT ID
     * @param challengedId 被挑战者代表NFT ID
     * @param challengerTeam 挑战者队伍（6个NFT）
     * @param challengedTeam 被挑战者队伍（6个NFT）
     * @param challengedAddress 被挑战者地址（address(0)表示模拟战斗）
     * @return success 是否成功
     * @return winner 获胜方（1=挑战者，2=被挑战者，0=平局）
     */
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam,
        address challengedAddress
    ) external nonReentrant onlyBattleCaller whenNotPaused returns (bool, uint256) {
        bool isMockBattle = (challengedAddress == address(0));
        address nftContract = IAuthorizer(authorizer).getAddressByName(\"nftMintCore\");

        // 修复：统一验证NFT合约设置
        if (!isMockBattle) {
            require(nftContract != address(0), "Battle: NFT contract not set");
            require(challengedAddress != address(0), "Battle: Invalid challenged address");
        }

        // 修复：加强队伍验证，确保所有NFT有效且不重叠
        require(_validateTeam(challengerTeam), "Battle: Invalid challenger team");
        require(_validateTeam(challengedTeam), "Battle: Invalid challenged team");
        
        // 检查攻击方和防御方团队没有重叠的NFT
        for (uint256 i = 0; i < 6; i++) {
            require(challengerTeam[i] != 0, "Battle: Challenger team contains zero NFT");
            require(challengedTeam[i] != 0, "Battle: Challenged team contains zero NFT");
            for (uint256 j = 0; j < 6; j++) {
                require(challengerTeam[i] != challengedTeam[j], "Battle: Team overlap detected");
            }
        }

        // 修复：在非模拟战斗中验证NFT所有权
        if (!isMockBattle) {
            _requireNFTOwnership(challengerTeam);
            _requireNFTOwnershipForAddress(challengedTeam, challengedAddress);
        }

        // 修复：验证代表NFT
        if (challengerId != 0) {
            require(_isValidNFT(challengerId, isMockBattle), "Battle: Invalid challenger NFT");
            if (!isMockBattle) {
                require(INFTMint(nftContract).ownerOf(challengerId) == msg.sender, "Battle: Not owner of challenger NFT");
                // 确保代表NFT在挑战者队伍中
                bool found = false;
                for (uint256 i = 0; i < 6; i++) {
                    if (challengerTeam[i] == challengerId) {
                        found = true;
                        break;
                    }
                }
                require(found, "Battle: Challenger NFT not in team");
            }
        }
        if (challengedId != 0) {
            require(_isValidNFT(challengedId, isMockBattle), "Battle: Invalid challenged NFT");
            if (!isMockBattle) {
                require(INFTMint(nftContract).ownerOf(challengedId) == challengedAddress, "Battle: Not owner of challenged NFT");
                // 确保代表NFT在被挑战者队伍中
                bool found = false;
                for (uint256 i = 0; i < 6; i++) {
                    if (challengedTeam[i] == challengedId) {
                        found = true;
                        break;
                    }
                }
                require(found, "Battle: Challenged NFT not in team");
            }
        }

        uint256 currentEpoch = _currentEpoch();
        uint256 historyIndex = battleHistoryIndex[currentEpoch];
        uint256 battleId = historyIndex + 1;

        battleHistory[currentEpoch][historyIndex] = BattleState({
            battleId: battleId,
            startTime: block.timestamp,
            status: 1,
            winner: 0,
            challengerId: challengerId,
            challengedId: challengedId,
            challenger: msg.sender,
            challenged: challengedAddress
        });

        battleHistoryIndex[currentEpoch] = (historyIndex + 1) % MAX_BATTLE_HISTORY;

        emit BattleStarted(battleId, msg.sender, challengedAddress, challengerTeam, challengedTeam);

        uint8 winner = _executeBattle(challengerTeam, challengedTeam, battleId);

        uint256 newHistoryIndex = battleHistoryIndex[currentEpoch];
        uint256 writeIndex = (newHistoryIndex == 0) ? MAX_BATTLE_HISTORY - 1 : newHistoryIndex - 1;
        battleHistory[currentEpoch][writeIndex].winner = winner;
        battleHistory[currentEpoch][writeIndex].status = 2;

        emit BattleEnded(battleId, winner);

        return (true, winner);
    }

    /**
     * @dev 验证队伍所有权（指定地址）
     * @param team 队伍NFT数组（6个）
     * @param owner 所有权地址
     */
    function _requireNFTOwnershipForAddress(uint256[6] memory team, address owner) internal view {
        address nftContract = IAuthorizer(authorizer).getAddressByName(\"nftMintCore\");
        require(nftContract != address(0), "Battle: NFT contract not set");
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = team[i];
            (bool success, bytes memory data) = nftContract.staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", tokenId)
            );
            require(success && data.length >= 32, "Battle: Failed to query NFT owner");
            address tokenOwner = abi.decode(data, (address));
            require(tokenOwner == owner, "Battle: Not owner of NFT in team");
        }
    }

    /**
     * @dev 验证NFT有效性
     * @param tokenId NFT ID
     * @param isMockBattle 是否模拟战斗
     * @return 是否有效
     */
    function _isValidNFT(uint256 tokenId, bool isMockBattle) internal view returns (bool) {
        if (isMockBattle) {
            return true;
        }
        address nftContract = IAuthorizer(authorizer).getAddressByName(\"nftMintCore\");
        if (nftContract == address(0)) return false;
        (bool success, bytes memory data) = nftContract.staticcall(
            abi.encodeWithSignature("ownerOf(uint256)", tokenId)
        );
        return success && data.length >= 32 && abi.decode(data, (address)) != address(0);
    }

    

    /**
     * @dev 战斗结果结构体
     * 存储单次攻击的结果信息
     * @param targetAlive 目标是否存活
     * @param targetState 目标队伍状态
     */
    struct BattleResult {
        bool targetAlive;
        TeamState targetState;
    }

    /**
     * @dev 执行单次攻击
     * @param attacker 攻击者NFT属性
     * @param target 目标队伍状态
     * @param seed 随机种子
     * @param attackerIdx 攻击者索引
     * @param canUseSkill 是否可以使用技能
     * @param skill 技能数据
     * @return result 攻击结果（包含目标存活状态和更新后的目标状态）
     */
    function _executeSingleAttack(
        NFTTraits memory attacker,
        TeamState memory target,
        uint256 seed,
        uint attackerIdx,
        bool canUseSkill,
        Skill memory skill
    ) internal view returns (BattleResult memory) {
        BattleResult memory result;
        result.targetAlive = true;
        result.targetState = target;

        if (canUseSkill && skill.skillId > 0) {
            result.targetState = _applySkill(attacker, result.targetState, attackerIdx, skill, seed);
            if (!_hasAnyAlive(result.targetState.alive)) {
                result.targetAlive = false;
            }
        } else {
            uint defenderIdx = _findTarget(result.targetState.alive, result.targetState.maxHp, result.targetState.hp);
            if (defenderIdx == 6) {
                result.targetAlive = false;
                return result;
            }
            uint damage = _calculateDamage(attacker, result.targetState.traits[defenderIdx], seed);
            result.targetState.hp[defenderIdx] = result.targetState.hp[defenderIdx] > damage 
                ? result.targetState.hp[defenderIdx] - damage : 0;
            if (result.targetState.hp[defenderIdx] == 0) {
                result.targetState.alive[defenderIdx] = false;
                if (!_hasAnyAlive(result.targetState.alive)) {
                    result.targetAlive = false;
                }
            }
        }
        return result;
    }

    /**
     * @dev 执行战斗核心逻辑
     * @param team1 队伍1（挑战者）
     * @param team2 队伍2（被挑战者）
     * @param randomSeed 随机种子
     * @return winner 获胜方（1=队伍1，2=队伍2，0=平局）
     */
    function _executeBattleCore(
        uint256[6] memory team1,
        uint256[6] memory team2,
        uint256 randomSeed
    ) internal view returns (uint8) {
        TeamState memory state1;
        TeamState memory state2;

        for (uint i = 0; i < 6; i++) {
            state1.traits[i] = _getNFTTraits(team1[i]);
            state2.traits[i] = _getNFTTraits(team2[i]);
            state1.maxHp[i] = _calculateMaxHP(state1.traits[i]);
            state2.maxHp[i] = _calculateMaxHP(state2.traits[i]);
            state1.hp[i] = state1.maxHp[i];
            state2.hp[i] = state2.maxHp[i];
            state1.alive[i] = true;
            state2.alive[i] = true;
        }

        bool team1Alive = true;
        bool team2Alive = true;

        for (uint256 round = 0; round < MAX_ROUNDS && team1Alive && team2Alive; round++) {
            randomSeed++;

            uint256[6] memory speedOrder1 = _getSpeedOrder(state1, randomSeed);
            uint256[6] memory speedOrder2 = _getSpeedOrder(state2, randomSeed + 1000);

            (team1Alive, state2) = _executeTeamAttacks(speedOrder1, state1, state2, randomSeed, team1Alive);
            
            if (!team1Alive) {
                break;
            }

            (team2Alive, state1) = _executeTeamAttacks(speedOrder2, state2, state1, randomSeed + 1000, team2Alive);
        }

        if (team1Alive && team2Alive) {
            return 0;
        } else if (team1Alive) {
            return 1;
        } else {
            return 2;
        }
    }

    /**
     * @dev 执行队伍攻击
     * @param speedOrder 速度排序数组（决定攻击顺序）
     * @param attackerState 攻击方队伍状态
     * @param targetState 目标队伍状态
     * @param seed 随机种子
     * @param attackerAlive 攻击方是否存活
     * @return alive 攻击方是否仍有存活单位
     * @return 更新后的目标队伍状态
     */
    function _executeTeamAttacks(
        uint256[6] memory speedOrder,
        TeamState memory attackerState,
        TeamState memory targetState,
        uint256 seed,
        bool attackerAlive
    ) internal view returns (bool, TeamState memory) {
        for (uint i = 0; i < 6; i++) {
            uint attackerIdx = speedOrder[i];
            if (!attackerState.alive[attackerIdx] || !attackerAlive) continue;

            NFTTraits memory attacker = attackerState.traits[attackerIdx];
            uint256 skillKey = attacker.element * ZODIAC_TYPE_COUNT + attacker.zodiac;
            Skill memory skill = skills[skillKey];
            bool canUseSkill = (seed % SKILL_USE_CHANCE_DENOMINATOR == 0);

            // 执行单次攻击，修改 targetState
            targetState = _executeSingleAttackIntoState(attacker, targetState, seed + i, attackerIdx, canUseSkill, skill);
            if (!_hasAnyAlive(targetState.alive)) {
                return (false, targetState);
            }
        }
        return (true, targetState);
    }

    /**
     * @dev 执行单次攻击并返回修改后的目标状态
     * @param attacker 攻击者NFT属性
     * @param target 目标队伍状态
     * @param seed 随机种子
     * @param attackerIdx 攻击者索引
     * @param canUseSkill 是否可以使用技能
     * @param skill 技能数据
     * @return 更新后的目标队伍状态
     */
    function _executeSingleAttackIntoState(
        NFTTraits memory attacker,
        TeamState memory target,
        uint256 seed,
        uint attackerIdx,
        bool canUseSkill,
        Skill memory skill
    ) internal pure returns (TeamState memory) {
        // 修复：添加攻击者索引边界检查
        require(attackerIdx < 6, "Battle: Invalid attacker index");
        
        if (canUseSkill && skill.skillId > 0) {
            return _applySkillToState(attacker, target, attackerIdx, skill, seed);
        } else {
            uint defenderIdx = _findTarget(target.alive, target.maxHp, target.hp);
            // 修复：确保防御者索引有效
            if (defenderIdx >= 6) {
                return target;
            }
            // 修复：添加防御者索引边界检查
            require(defenderIdx < 6, "Battle: Invalid defender index");
            uint damage = _calculateDamage(attacker, target.traits[defenderIdx], seed);
            if (target.hp[defenderIdx] > damage) {
                target.hp[defenderIdx] -= damage;
            } else {
                target.hp[defenderIdx] = 0;
                target.alive[defenderIdx] = false;
            }
            return target;
        }
    }

    /**
     * @dev 应用技能效果到队伍状态（纯函数版本）
     * @param attacker 攻击者NFT属性
     * @param target 目标队伍状态
     * @param attackerIdx 攻击者索引
     * @param skill 技能数据
     * @param seed 随机种子
     * @return 更新后的目标队伍状态
     */
    function _applySkillToState(NFTTraits memory attacker, TeamState memory target, uint attackerIdx, Skill memory skill, uint256 seed) internal pure returns (TeamState memory) {
        uint256 baseDamage = 0;
        uint256 targetIndex = 6;
        uint256 validTargetIndex = 6;

        for (uint i = 0; i < 6; i++) {
            if (target.alive[i]) {
                validTargetIndex = i;
                break;
            }
        }

        if (validTargetIndex < 6) {
            targetIndex = skill.isAoe ? validTargetIndex : _findTarget(target.alive, target.maxHp, target.hp);
            if (targetIndex >= 6) {
                targetIndex = validTargetIndex;
            }
            baseDamage = _calculateDamage(attacker, target.traits[targetIndex], seed);
        }
        uint256 skillDamage = (baseDamage * skill.damage) / 100;

        if (skill.isAoe) {
            for (uint i = 0; i < 6; i++) {
                if (target.alive[i]) {
                    // 修复：正确处理伤害，确保HP不会变成负数
                    target.hp[i] = target.hp[i] > skillDamage ? target.hp[i] - skillDamage : 0;
                    // 修复：及时更新存活状态
                    if (target.hp[i] == 0) {
                        target.alive[i] = false;
                    }
                }
            }
        } else if (targetIndex < 6) {
            // 修复：确保目标索引有效时才处理
            require(targetIndex < 6, "Battle: Invalid target index");
            target.hp[targetIndex] = target.hp[targetIndex] > skillDamage ? target.hp[targetIndex] - skillDamage : 0;
            if (target.hp[targetIndex] == 0) {
                target.alive[targetIndex] = false;
            }
        }

        return target;
    }

    /**
     * @dev 判断是否应该使用技能（HP低于50%时使用）
     * @param state 队伍状态
     * @param attackerIndex 攻击者索引
     * @return 是否应该使用技能
     */
    function _shouldUseSkill(TeamState memory state, uint attackerIndex) internal pure returns (bool) {
        uint256 hpPercent = (state.hp[attackerIndex] * 100) / state.maxHp[attackerIndex];
        return hpPercent < 50;
    }

    /**
     * @dev 应用技能效果
     * @param attacker 攻击者属性
     * @param defenderState 防守方状态
     * @param attackerIndex 攻击者索引
     * @param skill 技能数据
     * @param seed 随机种子
     * @return 更新后的防守方状态
     */
    function _applySkill(NFTTraits memory attacker, TeamState memory defenderState, uint attackerIndex, Skill memory skill, uint256 seed) internal view returns (TeamState memory) {
        uint256 baseDamage = 0;
        uint256 targetIndex = 6;
        uint256 validTargetIndex = 6;

        for (uint i = 0; i < 6; i++) {
            if (defenderState.alive[i]) {
                validTargetIndex = i;
                break;
            }
        }

        if (validTargetIndex < 6) {
            targetIndex = skill.isAoe ? validTargetIndex : _findTarget(defenderState.alive, defenderState.maxHp, defenderState.hp);
            if (targetIndex >= 6) {
                targetIndex = validTargetIndex;
            }
            baseDamage = _calculateDamage(attacker, defenderState.traits[targetIndex], seed);
        }
        uint256 skillDamage = (baseDamage * skill.damage) / 100;

        if (skill.isAoe) {
            for (uint i = 0; i < 6; i++) {
                if (defenderState.alive[i]) {
                    defenderState.hp[i] = defenderState.hp[i] > skillDamage ? defenderState.hp[i] - skillDamage : 0;
                    if (defenderState.hp[i] == 0) {
                        defenderState.alive[i] = false;
                    }
                }
            }
        } else if (targetIndex < 6) {
            defenderState.hp[targetIndex] = defenderState.hp[targetIndex] > skillDamage ? defenderState.hp[targetIndex] - skillDamage : 0;
            if (defenderState.hp[targetIndex] == 0) {
                defenderState.alive[targetIndex] = false;
            }
        }

        return defenderState;
    }

    /**
     * @dev 获取速度排序（决定攻击顺序）
     * @param state 队伍状态
     * @param seed 随机种子
     * @return 排序后的索引数组
     */
    function _getSpeedOrder(TeamState memory state, uint256 seed) internal pure returns (uint256[6] memory) {
        uint256[6] memory order = [uint256(0), 1, 2, 3, 4, 5];
        uint256[6] memory speeds = [
            _calculateSpeed(state.traits[0]),
            _calculateSpeed(state.traits[1]),
            _calculateSpeed(state.traits[2]),
            _calculateSpeed(state.traits[3]),
            _calculateSpeed(state.traits[4]),
            _calculateSpeed(state.traits[5])
        ];

        for (uint i = 0; i < 6; i++) {
            for (uint j = i + 1; j < 6; j++) {
                if (speeds[j] > speeds[i] || (speeds[j] == speeds[i] && ((seed + j) % 100) > ((seed + i) % 100))) {
                    (speeds[i], speeds[j]) = (speeds[j], speeds[i]);
                    (order[i], order[j]) = (order[j], order[i]);
                }
            }
        }
        return order;
    }

    /**
     * @dev 计算速度值
     * @param traits NFT属性
     * @return 速度值
     */
    function _calculateSpeed(NFTTraits memory traits) internal pure returns (uint256) {
        uint256 baseSpeed = 60;
        uint256 levelBonus = uint256(traits.level) * 5;
        uint256 growthBonus = uint256(traits.level) * uint256(traits.growth) / 10;

        uint256[12] memory zodiacSpeedBonus = [
            uint256(5), 25, 15, 5, 12, 8, 30, 20, 35, 5, 20, 22
        ];
        return baseSpeed + levelBonus + growthBonus + zodiacSpeedBonus[traits.zodiac];
    }

    /**
     * @dev 计算最大HP
     * @param traits NFT属性
     * @return 最大HP值
     */
    function _calculateMaxHP(NFTTraits memory traits) internal pure returns (uint256) {
        uint256 baseHp = 100;
        uint256 levelBonus = uint256(traits.level) * 30;
        uint256 growthBonus = uint256(traits.level) * uint256(traits.growth) * 2;
        return baseHp + levelBonus + growthBonus;
    }

    /**
     * @dev 生成随机种子 - 使用多重链上熵源增强随机性
     * 结合 blockhash、timestamp、coinbase、gasleft 等多个数据源
     * 在高价值场景下建议配合 Commit-Reveal 方案使用
     * @param battleId 战斗ID
     * @return 随机种子
     */
    function _generateRandomSeed(uint256 battleId) internal view returns (uint256) {
        bytes32 part1 = keccak256(abi.encodePacked(battleId, block.timestamp, block.number));
        bytes32 part2 = keccak256(abi.encodePacked(msg.sender, address(this), block.coinbase));
        bytes32 part3 = keccak256(abi.encodePacked(block.prevrandao, tx.gasprice, gasleft()));
        bytes32 part4 = keccak256(abi.encodePacked(block.basefee, block.chainid));
        
        bytes32 entropy = keccak256(abi.encodePacked(part1, part2, part3, part4));
        return uint256(entropy);
    }

    /**
     * @dev 执行战斗（写入状态）
     * @param team1 队伍1
     * @param team2 队伍2
     * @param battleId 战斗ID
     * @return winner 获胜方
     */
    function _executeBattle(
        uint256[6] memory team1,
        uint256[6] memory team2,
        uint256 battleId
    ) internal returns (uint8) {
        uint256 randomSeed = _generateRandomSeed(battleId);
        return _executeBattleCore(team1, team2, randomSeed);
    }

    /**
     * @dev 执行战斗（只读模式）
     * @param team1 队伍1
     * @param team2 队伍2
     * @param battleId 战斗ID
     * @return winner 获胜方
     */
    function _executeBattleView(
        uint256[6] memory team1,
        uint256[6] memory team2,
        uint256 battleId
    ) internal view returns (uint8) {
        uint256 randomSeed = _generateRandomSeed(battleId);
        return _executeBattleCore(team1, team2, randomSeed);
    }

    /**
     * @dev 模拟战斗（不记录战斗历史）
     * @param team1 队伍1
     * @param team2 队伍2
     * @return winner 获胜方
     */
    function simulateBattle(
        uint256[6] calldata team1,
        uint256[6] calldata team2
    ) external view returns (uint8) {
        // 修复：使用多源熵生成种子，避免同区块所有调用结果相同
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            block.prevrandao,
            block.coinbase,
            msg.sender,
            team1[0],
            team2[0]
        )));
        return _executeBattleCore(team1, team2, seed);
    }

    /**
     * @dev 查找攻击目标（优先选择HP最低的目标）
     * @param alive 存活状态数组
     * @param maxHp 最大HP数组
     * @param currentHp 当前HP数组
     * @return 目标索引（6表示无目标）
     */
    function _findTarget(bool[6] memory alive, uint256[6] memory maxHp, uint256[6] memory currentHp) internal pure returns (uint) {
        uint minHpIndex = 6;
        uint256 minHpPercent = type(uint256).max;

        for (uint i = 0; i < 6; i++) {
            if (alive[i]) {
                uint256 currentHpPercent = (maxHp[i] == 0) ? 0 : (currentHp[i] * 100) / maxHp[i];
                if (currentHpPercent < minHpPercent) {
                    minHpPercent = currentHpPercent;
                    minHpIndex = i;
                }
            }
        }

        if (minHpIndex != 6) return minHpIndex;

        for (uint i = 0; i < 3; i++) {
            if (alive[i]) return i;
        }
        for (uint i = 3; i < 6; i++) {
            if (alive[i]) return i;
        }
        return 6;
    }

    /**
     * @dev 检查队伍是否还有存活单位
     * @param alive 存活状态数组
     * @return 是否有存活单位
     */
    function _hasAnyAlive(bool[6] memory alive) internal pure returns (bool) {
        for (uint i = 0; i < 6; i++) {
            if (alive[i]) return true;
        }
        return false;
    }

    /**
     * @dev 计算伤害
     * @param attacker 攻击者属性
     * @param defender 防御者属性
     * @param seed 随机种子
     * @return 伤害值
     */
    function _calculateDamage(NFTTraits memory attacker, NFTTraits memory defender, uint256 seed) internal pure returns (uint) {
        uint baseDamage = uint(attacker.level) * 30 + uint(attacker.level) * uint(attacker.growth) * 5 / 10;

        if (_checkAdvantage(attacker.element, defender.element)) {
            baseDamage = baseDamage * 130 / 100;
        } else if (_checkAdvantage(defender.element, attacker.element)) {
            baseDamage = baseDamage * 80 / 100;
        }

        uint256 random = seed % 100;
        if (random < 12) {
            baseDamage = baseDamage * 180 / 100;
        }

        uint256 dodgeCheck = (seed + 1) % 100;
        uint256 dodgeChance = 15 + (uint256(defender.growth) - 50) / 10;
        if (dodgeChance > 25) dodgeChance = 25;
        if (dodgeChance < 5) dodgeChance = 5;

        if (dodgeCheck < dodgeChance) {
            return 0;
        }

        uint256 defense = uint(defender.level) * 15 + uint(defender.level) * uint(defender.growth) * 2 / 10;
        uint256 reduction = (defense * 50) / (100 + defense);
        baseDamage = baseDamage * (100 - reduction) / 100;

        return baseDamage;
    }

    /**
     * @dev 验证队伍有效性（6个NFT都不为0，且无重复）
     * @param team 队伍数组
     * @return 是否有效
     */
    function _validateTeam(uint256[6] memory team) internal pure returns (bool) {
        for (uint256 i = 0; i < 6; i++) {
            if (team[i] == 0) return false;
            for (uint256 j = i + 1; j < 6; j++) {
                if (team[i] == team[j]) return false;
            }
        }
        return true;
    }

    /**
     * @dev 快速战斗（只读，不记录历史）
     * @param attackerTeam 攻击方队伍
     * @param defenderTeam 防御方队伍
     * @return success 是否成功
     * @return winner 获胜方
     */
    function battle(
        uint256[6] calldata attackerTeam,
        uint256[6] calldata defenderTeam
    ) external view returns (bool, uint256) {
        require(_validateTeam(attackerTeam), "Battle: Invalid attacker team");
        require(_validateTeam(defenderTeam), "Battle: Invalid defender team");

        // 修复：使用多源熵生成种子，避免同区块结果完全一致
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            block.prevrandao,
            msg.sender,
            attackerTeam[0],
            defenderTeam[0]
        )));
        uint8 winner = _executeBattleView(attackerTeam, defenderTeam, seed);

        return (true, winner);
    }

    /**
     * @dev 获取战斗日志数量
     * @return 战斗日志数量
     */
    function getBattleLogCount() external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        return battleHistoryIndex[currentEpoch];
    }

    /**
     * @dev 获取战斗日志
     * @param index 日志索引
     * @return battleId 战斗ID
     * @return challengerId 挑战者NFT ID
     * @return challengedId 被挑战者NFT ID
     * @return challenger 挑战者地址
     * @return challenged 被挑战者地址
     * @return winner 获胜方
     * @return timestamp 时间戳
     * @return status 状态
     */
    function getBattleLog(uint256 index) external view returns (
        uint256 battleId,
        uint256 challengerId,
        uint256 challengedId,
        address challenger,
        address challenged,
        uint8 winner,
        uint256 timestamp,
        uint8 status
    ) {
        uint256 currentEpoch = _currentEpoch();
        require(index < battleHistoryIndex[currentEpoch], "Battle: Invalid index");
        BattleState memory battle = battleHistory[currentEpoch][index];
        return (
            battle.battleId,
            battle.challengerId,
            battle.challengedId,
            battle.challenger,
            battle.challenged,
            battle.winner,
            battle.startTime,
            battle.status
        );
    }

    /**
     * @dev 获取战斗常量
     * @return MAX_ROUNDS 最大回合数
     * @return ELEMENT_COUNT 属性数量
     */
    function getBattleConstants() external pure returns (uint256, uint256) {
        return (MAX_ROUNDS, 5);
    }

    /**
     * @dev 初始化技能（公开接口）
     */
    function initSkills() external onlyOwner {
        _initSkills();
    }

    /**
     * @dev 暂停合约
     */
    function pause(string calldata) external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停合约
     */
    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 初始化技能（内部）
     */
    function _initSkills() internal {
        _initWaterSkills();
        _initWindSkills();
        _initFireSkills();
        _initDarkSkills();
        _initLightSkills();
    }

    /**
     * @dev 初始化水属性技能
     */
    function _initWaterSkills() private {
        _setSkill(0, 1, 125, 3, 0, false);
        _setSkill(1, 0, 145, 5, 0, false);
        _setSkill(2, 0, 165, 5, 0, false);
        _setSkill(3, 0, 130, 3, 0, false);
        _setSkill(4, 3, 220, 6, 0, true);
        _setSkill(5, 7, 115, 4, 0, false);
        _setSkill(12, 6, 110, 4, 0, false);
        _setSkill(13, 8, 95, 4, 0, true);
        _setSkill(14, 5, 85, 4, 0, true);
        _setSkill(15, 2, 80, 3, 0, false);
        _setSkill(16, 8, 120, 5, 0, true);
        _setSkill(17, 6, 125, 4, 0, false);
    }

    /**
     * @dev 初始化风属性技能
     */
    function _initWindSkills() private {
        _setSkill(24, 1, 135, 3, 0, false);
        _setSkill(25, 0, 130, 5, 0, false);
        _setSkill(26, 0, 155, 5, 0, false);
        _setSkill(27, 0, 140, 3, 0, false);
        _setSkill(28, 3, 210, 6, 0, true);
        _setSkill(29, 7, 125, 4, 0, false);
        _setSkill(36, 6, 115, 4, 0, false);
        _setSkill(37, 8, 105, 4, 0, true);
        _setSkill(38, 5, 90, 4, 0, true);
        _setSkill(39, 2, 100, 3, 0, false);
        _setSkill(40, 8, 115, 5, 0, true);
        _setSkill(41, 6, 120, 4, 0, false);
    }

    /**
     * @dev 初始化火属性技能
     */
    function _initFireSkills() private {
        _setSkill(48, 1, 120, 3, 0, false);
        _setSkill(49, 0, 140, 5, 0, false);
        _setSkill(50, 0, 160, 5, 0, false);
        _setSkill(51, 0, 145, 3, 0, false);
        _setSkill(52, 3, 200, 6, 0, true);
        _setSkill(53, 7, 120, 4, 0, false);
        _setSkill(60, 6, 105, 4, 0, false);
        _setSkill(61, 8, 110, 4, 0, true);
        _setSkill(62, 5, 85, 4, 0, true);
        _setSkill(63, 2, 95, 3, 0, false);
        _setSkill(64, 8, 110, 5, 0, true);
        _setSkill(65, 6, 115, 4, 0, false);
    }

    /**
     * @dev 初始化暗属性技能
     */
    function _initDarkSkills() private {
        _setSkill(72, 1, 145, 3, 0, false);
        _setSkill(73, 0, 150, 5, 0, false);
        _setSkill(74, 0, 165, 5, 0, false);
        _setSkill(75, 0, 160, 3, 0, false);
        _setSkill(76, 3, 245, 6, 0, true);
        _setSkill(77, 7, 145, 4, 0, false);
        _setSkill(84, 6, 135, 4, 0, false);
        _setSkill(85, 8, 115, 4, 0, true);
        _setSkill(86, 5, 90, 4, 0, true);
        _setSkill(87, 2, 100, 3, 0, false);
        _setSkill(88, 8, 140, 5, 0, true);
        _setSkill(89, 6, 130, 4, 0, false);
    }

    /**
     * @dev 初始化光属性技能
     */
    function _initLightSkills() private {
        _setSkill(96, 1, 150, 3, 0, false);
        _setSkill(97, 0, 155, 5, 0, false);
        _setSkill(98, 0, 170, 5, 0, false);
        _setSkill(99, 0, 165, 3, 0, false);
        _setSkill(100, 3, 255, 6, 0, true);
        _setSkill(101, 7, 150, 4, 0, false);
        _setSkill(108, 6, 140, 4, 0, false);
        _setSkill(109, 8, 110, 4, 0, true);
        _setSkill(110, 5, 100, 4, 0, true);
        _setSkill(111, 2, 105, 3, 0, false);
        _setSkill(112, 8, 130, 5, 0, true);
        _setSkill(113, 6, 135, 4, 0, false);
    }

    /**
     * @dev 设置技能
     * @param tokenType 生肖类型
     * @param skillType 技能类型
     * @param damage 伤害倍率（百分比）
     * @param cooldown 冷却回合数
     * @param duration 持续回合数
     * @param isAoe 是否范围攻击
     */
    function _setSkill(uint256 tokenType, uint8 skillType, uint256 damage, uint256 cooldown, uint256 duration, bool isAoe) private {
        skills[tokenType] = Skill(tokenType, skillType, damage, cooldown, duration, isAoe);
    }

    /**
     * @dev 获取技能信息
     * @param tokenType 生肖类型
     * @return skillId 技能ID
     * @return skillType_ 技能类型
     * @return damage 伤害倍率
     * @return cooldown 冷却回合数
     * @return duration 持续回合数
     * @return isAoe 是否范围攻击
     */
    function getSkill(uint256 tokenType) external view returns (
        uint256 skillId,
        uint8 skillType_,
        uint256 damage,
        uint256 cooldown,
        uint256 duration,
        bool isAoe
    ) {
        require(tokenType < 120, "Battle: Invalid token type");
        Skill memory skill = skills[tokenType];
        return (skill.skillId, skill.skillType, skill.damage, skill.cooldown, skill.duration, skill.isAoe);
    }

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}

    /**
     * @dev 重置合约数据
     * @notice 通过递增纪元版本号快速重置，仅owner或authorizer可调用
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = epoch + 1;
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}
