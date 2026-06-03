// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract Battle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    struct NFTTraits {
        uint256 tokenId;
        uint8 level;
        uint8 element;
        uint8 power;
        uint8 growth;
        uint8 zodiac;
    }

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

    struct TeamState {
        NFTTraits[6] traits;
        uint256[6] hp;
        bool[6] alive;
        uint256[6] maxHp;
    }

    struct Skill {
        uint256 skillId;
        uint8 skillType;
        uint256 damage;
        uint256 cooldown;
        uint256 duration;
        bool isAoe;
    }

    BattleState[] public battleHistory;

    uint256 public constant MAX_ROUNDS = 50;
    uint256 public constant ZODIAC_COUNT = 12;
    uint256 public constant GENDER_COUNT = 2;
    uint256 public constant ELEMENT_COUNT = 5;
    uint256 public constant ZODIAC_TYPE_COUNT = ZODIAC_COUNT * GENDER_COUNT;
    uint256 public constant TOTAL_TYPE_COUNT = ELEMENT_COUNT * ZODIAC_TYPE_COUNT;
    uint256 public constant MAX_BATTLE_HISTORY = 1000;
    uint256 public constant MIN_GROWTH = 50;
    uint256 public constant GROWTH_RANGE = 51;
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant SKILL_USE_CHANCE_DENOMINATOR = 5;

    address public nftContract;
    address public authorizer;
    address public battleCaller;

    bool public paused;
    string public pauseReason;

    uint8 public constant ELEMENT_WATER = 0;
    uint8 public constant ELEMENT_WIND = 1;
    uint8 public constant ELEMENT_FIRE = 2;
    uint8 public constant ELEMENT_DARK = 3;
    uint8 public constant ELEMENT_LIGHT = 4;

    mapping(uint256 => Skill) public skills;

    event Paused(address account, string reason);
    event Unpaused(address account);
    event BattleStarted(
        uint256 indexed battleId,
        address indexed challenger,
        address indexed challenged,
        uint256[6] challengerTeam,
        uint256[6] challengedTeam
    );
    event BattleEnded(
        uint256 indexed battleId,
        uint8 winner
    );

    modifier whenNotPaused() {
        require(!paused, "Battle: Paused");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "Battle: Not authorized");
        _;
    }

    modifier onlyBattleCaller() {
        require(msg.sender == owner() || msg.sender == battleCaller, "Battle: Only authorized caller");
        _;
    }

    /**
     * @dev 初始化合约
     * @param _authorizer 授权器合约地址
     * @param _battleCaller 战斗调用者地址（通常是ArenaRanking合约）
     */
    function initialize(address _authorizer, address _battleCaller) external initializer {
        require(_authorizer != address(0), "Battle: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
        battleCaller = _battleCaller;
        _initSkills();
    }

    /**
     * @dev 重新初始化技能（仅所有者调用）
     */
    function reinitializeSkills() external onlyOwner {
        _initSkills();
    }

    /**
     * @dev 暂停合约
     * @param reason 暂停原因
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消暂停
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 设置授权器地址
     * @param a 新的授权器地址
     */
    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "Battle: Invalid authorizer address");
        authorizer = a;
    }

    function setBattleCaller(address _battleCaller) external onlyOwner {
        require(_battleCaller != address(0), "Battle: Invalid battle caller address");
        battleCaller = _battleCaller;
    }

    /**
     * @dev 授权升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "Battle: Invalid NFT contract address");
        nftContract = _nftContract;
    }

    /**
     * @dev 获取NFT属性
     * @param tokenId NFT ID
     * @return NFT属性结构体
     */
    function _getNFTTraits(uint256 tokenId) internal view returns (NFTTraits memory) {
        NFTTraits memory traits;
        traits.tokenId = tokenId;
        if (nftContract != address(0)) {
            (uint256 zodiacType, uint256 level, uint256 growth) = _getNFTData(tokenId);
            traits.level = uint8(level);
            traits.element = uint8(zodiacType / ZODIAC_TYPE_COUNT);
            traits.zodiac = uint8((zodiacType / GENDER_COUNT) % ZODIAC_COUNT);
            traits.growth = uint8(growth);
            traits.power = _calculatePower(traits.level, traits.growth);
        } else {
            uint256 zodiacType = tokenId % TOTAL_TYPE_COUNT;
            traits.level = uint8((zodiacType / ZODIAC_TYPE_COUNT) + 1);
            traits.element = uint8(zodiacType / ZODIAC_TYPE_COUNT);
            traits.zodiac = uint8((zodiacType / GENDER_COUNT) % ZODIAC_COUNT);
            traits.growth = uint8(MIN_GROWTH + (tokenId % GROWTH_RANGE));
            traits.power = _calculatePower(traits.level, traits.growth);
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
     * @dev 计算NFT战力
     * @param level 等级
     * @param growth 成长值
     * @return 战力值
     */
    function _calculatePower(uint256 level, uint256 growth) internal pure returns (uint8) {
        if (level == 0) return 0;
        uint256 basePower = level * 20;
        uint256 growthBonus = (level - 1) * growth * 2 / 100;
        return uint8(basePower + growthBonus);
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

        if (!isMockBattle) {
            require(nftContract != address(0), "Battle: NFT contract not set");
        }

        require(_validateTeam(challengerTeam), "Battle: Invalid challenger team");
        require(_validateTeam(challengedTeam), "Battle: Invalid challenged team");

        if (!isMockBattle) {
            require(challengedAddress != address(0), "Battle: Invalid challenged address");
        }

        if (!isMockBattle) {
            _requireNFTOwnership(challengerTeam);
            _requireNFTOwnershipForAddress(challengedTeam, challengedAddress);
        }

        if (challengerId != 0) {
            require(_isValidNFT(challengerId, isMockBattle), "Battle: Invalid challenger NFT");
            if (!isMockBattle) {
                require(INFTMint(nftContract).ownerOf(challengerId) == msg.sender, "Battle: Not owner of challenger NFT");
            }
        }
        if (!isMockBattle && challengedId != 0) {
            require(_isValidNFT(challengedId, false), "Battle: Invalid challenged NFT");
            require(INFTMint(nftContract).ownerOf(challengedId) == challengedAddress, "Battle: Not owner of challenged NFT");
        }

        if (battleHistory.length >= MAX_BATTLE_HISTORY) {
            for (uint256 i = 0; i < battleHistory.length - 1; i++) {
                battleHistory[i] = battleHistory[i + 1];
            }
            battleHistory.pop();
        }
        
        battleHistory.push(BattleState({
            battleId: battleHistory.length + 1,
            startTime: block.timestamp,
            status: 1,
            winner: 0,
            challengerId: challengerId,
            challengedId: challengedId,
            challenger: msg.sender,
            challenged: challengedAddress
        }));

        uint256 battleId = battleHistory.length;

        emit BattleStarted(battleId, msg.sender, challengedAddress, challengerTeam, challengedTeam);

        uint8 winner = _executeBattle(challengerTeam, challengedTeam, battleId);

        battleHistory[battleId - 1].winner = winner;
        battleHistory[battleId - 1].status = 2;

        emit BattleEnded(battleId, winner);

        return (true, winner);
    }

    /**
     * @dev 验证队伍所有权（指定地址）
     * @param team 队伍NFT数组（6个）
     * @param owner 所有权地址
     */
    function _requireNFTOwnershipForAddress(uint256[6] memory team, address owner) internal view {
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
        if (nftContract == address(0)) return false;
        (bool success, bytes memory data) = nftContract.staticcall(
            abi.encodeWithSignature("ownerOf(uint256)", tokenId)
        );
        return success && data.length >= 32 && abi.decode(data, (address)) != address(0);
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

        uint256[TEAM_SIZE] memory skillCooldown1;
        uint256[TEAM_SIZE] memory skillCooldown2;

        bool team1Alive = true;
        bool team2Alive = true;

        for (uint256 round = 0; round < MAX_ROUNDS && team1Alive && team2Alive; round++) {
            randomSeed++;

            for (uint i = 0; i < 6; i++) {
                if (skillCooldown1[i] > 0) skillCooldown1[i]--;
                if (skillCooldown2[i] > 0) skillCooldown2[i]--;
            }

            uint256[6] memory speedOrder1 = _getSpeedOrder(state1, randomSeed);
            uint256[6] memory speedOrder2 = _getSpeedOrder(state2, randomSeed + 1000);

            for (uint i = 0; i < 6; i++) {
                uint attackerIndex = speedOrder1[i];
                if (!state1.alive[attackerIndex] || !team1Alive) continue;
                
                NFTTraits memory attackerTrait = state1.traits[attackerIndex];
                uint256 skillKey = attackerTrait.element * ZODIAC_TYPE_COUNT + attackerTrait.zodiac;
                Skill memory skill = skills[skillKey];
                bool useSkill = skillCooldown1[attackerIndex] == 0 && (randomSeed % SKILL_USE_CHANCE_DENOMINATOR == 0 || _shouldUseSkill(state1, attackerIndex));
                
                if (useSkill && skill.skillId > 0) {
                    state2 = _applySkill(attackerTrait, state2, attackerIndex, skill);
                    skillCooldown1[attackerIndex] = skill.cooldown;
                } else {
                    uint defenderIndex = _findTarget(state2.alive, state2.traits, state2.hp);
                    if (defenderIndex == 6) {
                        team2Alive = false;
                        break;
                    }
                    uint damage = _calculateDamage(state1.traits[attackerIndex], state2.traits[defenderIndex], randomSeed + i);
                    state2.hp[defenderIndex] = state2.hp[defenderIndex] > damage ? state2.hp[defenderIndex] - damage : 0;
                    if (state2.hp[defenderIndex] == 0) {
                        state2.alive[defenderIndex] = false;
                        if (!_hasAnyAlive(state2.alive)) {
                            team2Alive = false;
                        }
                    }
                }
            }

            if (!team2Alive) break;

            for (uint i = 0; i < 6; i++) {
                uint attackerIndex = speedOrder2[i];
                if (!state2.alive[attackerIndex] || !team2Alive) continue;
                
                NFTTraits memory attackerTrait = state2.traits[attackerIndex];
                uint256 skillKey = attackerTrait.element * ZODIAC_TYPE_COUNT + attackerTrait.zodiac;
                Skill memory skill = skills[skillKey];
                bool useSkill = skillCooldown2[attackerIndex] == 0 && (randomSeed % 5 == 0 || _shouldUseSkill(state2, attackerIndex));
                
                if (useSkill && skill.skillId > 0) {
                    state1 = _applySkill(attackerTrait, state1, attackerIndex, skill);
                    skillCooldown2[attackerIndex] = skill.cooldown;
                } else {
                    uint defenderIndex = _findTarget(state1.alive, state1.traits, state1.hp);
                    if (defenderIndex == 6) {
                        team1Alive = false;
                        break;
                    }
                    uint damage = _calculateDamage(state2.traits[attackerIndex], state1.traits[defenderIndex], randomSeed + 1000 + i);
                    state1.hp[defenderIndex] = state1.hp[defenderIndex] > damage ? state1.hp[defenderIndex] - damage : 0;
                    if (state1.hp[defenderIndex] == 0) {
                        state1.alive[defenderIndex] = false;
                        if (!_hasAnyAlive(state1.alive)) {
                            team1Alive = false;
                        }
                    }
                }
            }
        }

        if (team1Alive && !team2Alive) return 1;
        if (team2Alive && !team1Alive) return 2;
        return 0;
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
     * @return 更新后的防守方状态
     */
    function _applySkill(NFTTraits memory attacker, TeamState memory defenderState, uint attackerIndex, Skill memory skill) internal view returns (TeamState memory) {
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
            targetIndex = skill.isAoe ? validTargetIndex : _findTarget(defenderState.alive, defenderState.traits, defenderState.hp);
            if (targetIndex >= 6) {
                targetIndex = validTargetIndex;
            }
            baseDamage = _calculateDamage(attacker, defenderState.traits[targetIndex], attackerIndex);
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
        uint256 growthBonus = ((traits.level - 1) * uint256(traits.growth) * 3) / 100;
        
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
        uint256 growthBonus = ((traits.level - 1) * uint256(traits.growth) * 20) / 100;
        return baseHp + levelBonus + growthBonus;
    }

    /**
     * @dev 生成随机种子 - 使用更安全的随机数生成方式
     * 结合多个链上数据源，增加预测难度
     * @param battleId 战斗ID
     * @return 随机种子
     */
    function _generateRandomSeed(uint256 battleId) internal view returns (uint256) {
        bytes32 entropy = keccak256(abi.encodePacked(
            battleId,
            block.timestamp,
            block.number,
            blockhash(block.number > 0 ? block.number - 1 : block.number),
            msg.sender,
            address(this),
            block.coinbase,
            block.prevrandao,
            gasleft(),
            tx.gasprice,
            block.basefee,
            uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, battleId)))
        ));
        
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
        uint256 battleId = block.timestamp % 1000 + 1;
        return _executeBattleCore(team1, team2, battleId);
    }

    /**
     * @dev 查找攻击目标（优先选择HP最低的目标）
     * @param alive 存活状态数组
     * @param traits 属性数组
     * @param currentHp 当前HP数组
     * @return 目标索引（6表示无目标）
     */
    function _findTarget(bool[6] memory alive, NFTTraits[6] memory traits, uint256[6] memory currentHp) internal pure returns (uint) {
        uint minHpIndex = 6;
        uint256 minHpPercent = type(uint256).max;
        
        for (uint i = 0; i < 6; i++) {
            if (alive[i]) {
                uint256 maxHp = _calculateMaxHP(traits[i]);
                uint256 currentHpPercent = (maxHp == 0) ? 0 : (currentHp[i] * 100) / maxHp;
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
        uint baseDamage = uint(attacker.level) * 30 + uint(attacker.power) * 3;

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

        uint256 defense = uint(defender.level) * 15 + uint(defender.power);
        uint256 reduction = (defense * 50) / (100 + defense);
        baseDamage = baseDamage * (100 - reduction) / 100;

        return baseDamage;
    }

    /**
     * @dev 验证队伍有效性（6个NFT都不为0）
     * @param team 队伍数组
     * @return 是否有效
     */
    function _validateTeam(uint256[6] memory team) internal pure returns (bool) {
        for (uint256 i = 0; i < 6; i++) {
            if (team[i] == 0) return false;
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
        
        uint256 battleId = block.timestamp % 1000 + 1;
        uint8 winner = _executeBattleView(attackerTeam, defenderTeam, battleId);
        
        return (true, winner);
    }

    /**
     * @dev 获取战斗日志数量
     * @return 战斗日志数量
     */
    function getBattleLogCount() external view returns (uint256) {
        return battleHistory.length;
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
        require(index < battleHistory.length, "Battle: Invalid index");
        BattleState memory battle = battleHistory[index];
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
        _setSkill(0, 1, 125, 3, 0, false); _setSkill(12, 6, 110, 4, 0, false);
        _setSkill(1, 0, 145, 5, 0, false); _setSkill(13, 8, 95, 4, 0, true);
        _setSkill(2, 0, 165, 5, 0, false); _setSkill(14, 5, 85, 4, 0, true);
        _setSkill(3, 0, 130, 3, 0, false); _setSkill(15, 2, 80, 3, 0, false);
        _setSkill(4, 3, 220, 6, 0, true); _setSkill(16, 8, 120, 5, 0, true);
        _setSkill(5, 7, 115, 4, 0, false); _setSkill(17, 6, 125, 4, 0, false);
        for (uint i = 6; i < 12; i++) {
            skills[i] = skills[i - 6];
            skills[i + 12] = skills[i + 6];
        }
    }

    /**
     * @dev 初始化风属性技能
     */
    function _initWindSkills() private {
        _setSkill(24, 1, 135, 3, 0, false); _setSkill(36, 6, 115, 4, 0, false);
        _setSkill(25, 0, 130, 5, 0, false); _setSkill(37, 8, 105, 4, 0, true);
        _setSkill(26, 0, 155, 5, 0, false); _setSkill(38, 5, 90, 4, 0, true);
        _setSkill(27, 0, 140, 3, 0, false); _setSkill(39, 2, 100, 3, 0, false);
        _setSkill(28, 3, 210, 6, 0, true); _setSkill(40, 8, 115, 5, 0, true);
        _setSkill(29, 7, 125, 4, 0, false); _setSkill(41, 6, 120, 4, 0, false);
        for (uint i = 30; i < 36; i++) {
            skills[i] = skills[i - 6];
            skills[i + 12] = skills[i + 6];
        }
    }

    /**
     * @dev 初始化火属性技能
     */
    function _initFireSkills() private {
        _setSkill(48, 1, 120, 3, 0, false); _setSkill(60, 6, 105, 4, 0, false);
        _setSkill(49, 0, 140, 5, 0, false); _setSkill(61, 8, 110, 4, 0, true);
        _setSkill(50, 0, 160, 5, 0, false); _setSkill(62, 5, 85, 4, 0, true);
        _setSkill(51, 0, 145, 3, 0, false); _setSkill(63, 2, 95, 3, 0, false);
        _setSkill(52, 3, 200, 6, 0, true); _setSkill(64, 8, 110, 5, 0, true);
        _setSkill(53, 7, 120, 4, 0, false); _setSkill(65, 6, 115, 4, 0, false);
        for (uint i = 54; i < 60; i++) {
            skills[i] = skills[i - 6];
            skills[i + 12] = skills[i + 6];
        }
    }

    /**
     * @dev 初始化暗属性技能
     */
    function _initDarkSkills() private {
        _setSkill(72, 1, 145, 3, 0, false); _setSkill(84, 6, 135, 4, 0, false);
        _setSkill(73, 0, 150, 5, 0, false); _setSkill(85, 8, 115, 4, 0, true);
        _setSkill(74, 0, 165, 5, 0, false); _setSkill(86, 5, 90, 4, 0, true);
        _setSkill(75, 0, 160, 3, 0, false); _setSkill(87, 2, 100, 3, 0, false);
        _setSkill(76, 3, 245, 6, 0, true); _setSkill(88, 8, 140, 5, 0, true);
        _setSkill(77, 7, 145, 4, 0, false); _setSkill(89, 6, 130, 4, 0, false);
        for (uint i = 78; i < 84; i++) {
            skills[i] = skills[i - 6];
            skills[i + 12] = skills[i + 6];
        }
    }

    /**
     * @dev 初始化光属性技能
     */
    function _initLightSkills() private {
        _setSkill(96, 1, 150, 3, 0, false); _setSkill(108, 6, 140, 4, 0, false);
        _setSkill(97, 0, 155, 5, 0, false); _setSkill(109, 8, 110, 4, 0, true);
        _setSkill(98, 0, 170, 5, 0, false); _setSkill(110, 5, 100, 4, 0, true);
        _setSkill(99, 0, 165, 3, 0, false); _setSkill(111, 2, 105, 3, 0, false);
        _setSkill(100, 3, 255, 6, 0, true); _setSkill(112, 8, 130, 5, 0, true);
        _setSkill(101, 7, 150, 4, 0, false); _setSkill(113, 6, 135, 4, 0, false);
        for (uint i = 102; i < 108; i++) {
            skills[i] = skills[i - 6];
            skills[i + 12] = skills[i + 6];
        }
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
}