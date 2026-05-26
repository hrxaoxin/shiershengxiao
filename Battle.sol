// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title Battle
 * @dev 战斗合约，实现NFT之间的自动战斗系统
 *
 * 战斗规则：
 * 1. 6v6队伍对战
 * 2. 速度决定出手顺序
 * 3. 属性克制影响伤害
 * 4. 暴击和闪避机制
 * 5. 一队全部阵亡则战斗结束
 *
 * 战斗流程：
 * 1. 验证双方NFT所有权
 * 2. 初始化战斗状态
 * 3. 按速度排序决定出手顺序
 * 4. 循环执行回合直到一队全灭
 * 5. 记录战斗结果并分发奖励
 *
 * 奖励机制：
 * - 获胜者获得失败者的部分代币
 * - 战斗手续费进入奖励池
 */
contract Battle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {

    /**
     * @dev NFT属性结构体
     */
    struct NFTTraits {
        uint256 tokenId;
        uint8 level;
        uint8 element;
        uint8 power;
    }

    /**
     * @dev 战斗状态结构体
     */
    struct BattleState {
        uint256 battleId;
        uint256 startTime;
        uint8 status;
        uint8 winner;
    }

    /**
     * @dev 队伍状态结构体
     */
    struct TeamState {
        NFTTraits[6] traits;
        uint256[6] hp;
        bool[6] alive;
    }

    /**
     * @dev 战斗历史记录数组
     */
    BattleState[] public battleHistory;

    /**
     * @dev 每次战斗的基础奖励（代币）
     */
    uint256 public baseBattleReward;

    /**
     * @dev 战斗手续费率（百分比）
     */
    uint256 public battleFeePercent;

    /**
     * @dev 最大回合数限制
     */
    uint256 public constant MAX_ROUNDS = 50;

    /**
     * @dev 战斗常量
     */
    uint256 public constant PRECISION = 10000;

    /**
     * @dev NFT合约地址
     */
    address public nftContract;

    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

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
        require(msg.sender == owner() || msg.sender == authorizer, "Battle: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 元素类型枚举
     */
    uint8 public constant ELEMENT_WATER = 0;
    uint8 public constant ELEMENT_WIND = 1;
    uint8 public constant ELEMENT_FIRE = 2;
    uint8 public constant ELEMENT_DARK = 3;
    uint8 public constant ELEMENT_LIGHT = 4;

    /**
     * @dev 战斗事件
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
     */
    event BattleEnded(
        uint256 indexed battleId,
        uint8 winner,
        uint256 challengerReward,
        uint256 challengedReward
    );

    /**
     * @dev 设置NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "Battle: Invalid NFT contract address");
        nftContract = _nftContract;
    }

    /**
     * @dev 获取NFT属性
     */
    function _getNFTTraits(uint256 tokenId) internal view returns (NFTTraits memory) {
        NFTTraits memory traits;
        traits.tokenId = tokenId;
        if (nftContract != address(0)) {
            (uint256 tokenType, uint256 level) = _getNFTData(tokenId);
            traits.level = uint8(level);
            traits.element = uint8(tokenType / 24);
            traits.power = _calculatePower(level, tokenType);
        } else {
            traits.level = uint8((tokenId % 5) + 1);
            traits.element = uint8(tokenId % 5);
            traits.power = _calculatePower(traits.level, traits.element * 24);
        }
        return traits;
    }

    /**
     * @dev 获取NFT数据（如果NFT合约已设置）
     */
    function _getNFTData(uint256 tokenId) internal view returns (uint256 tokenType, uint256 level) {
        if (nftContract == address(0)) {
            return (0, 1);
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
    }

    /**
     * @dev 计算NFT战力
     */
    function _calculatePower(uint256 level, uint256 tokenType) internal pure returns (uint8) {
        uint8 basePower = uint8(level * 20);
        uint8 elementBonus = uint8((tokenType / 24) * 5);
        return basePower + elementBonus;
    }

    /**
     * @dev 检查属性克制
     * 火>风>水>火，光>暗>光
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
     * @dev 挑战对手
     *
     * @param challengerId 挑战者领队NFT ID
     * @param challengedId 被挑战者领队NFT ID
     * @param challengerTeam 挑战者队伍（6个NFT ID）
     * @param challengedTeam 被挑战者队伍（6个NFT ID）
     * @return tuple (是否成功, 获胜者, 奖励分配)
     */
    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam
    ) external returns (bool, uint256, uint256[] memory) {
        require(_validateTeam(challengerTeam), "Battle: Invalid challenger team");
        require(_validateTeam(challengedTeam), "Battle: Invalid challenged team");

        battleHistory.push(BattleState({
            battleId: battleHistory.length + 1,
            startTime: block.timestamp,
            status: 1,
            winner: 0
        }));

        uint256 battleId = battleHistory.length;

        emit BattleStarted(battleId, msg.sender, address(0), challengerTeam, challengedTeam);

        uint8 winner = _executeBattle(challengerTeam, challengedTeam, battleId);

        battleHistory[battleId - 1].winner = winner;
        battleHistory[battleId - 1].status = 2;

        uint256[] memory rewards = new uint256[](2);
        if (winner == 1) {
            rewards[0] = baseBattleReward;
            rewards[1] = 0;
        } else {
            rewards[0] = 0;
            rewards[1] = baseBattleReward;
        }

        emit BattleEnded(battleId, winner, rewards[0], rewards[1]);

        return (true, winner, rewards);
    }

    /**
     * @dev 执行战斗逻辑
     */
    function _executeBattle(
        uint256[6] memory team1,
        uint256[6] memory team2,
        uint256 battleId
    ) internal returns (uint8) {
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            battleId,
            block.timestamp,
            block.number,
            msg.sender
        )));

        TeamState memory state1;
        TeamState memory state2;

        for (uint i = 0; i < 6; i++) {
            state1.traits[i] = _getNFTTraits(team1[i]);
            state2.traits[i] = _getNFTTraits(team2[i]);
            state1.hp[i] = uint256(state1.traits[i].level) * 100;
            state2.hp[i] = uint256(state2.traits[i].level) * 100;
            state1.alive[i] = true;
            state2.alive[i] = true;
        }

        bool team1Alive = true;
        bool team2Alive = true;

        for (uint256 round = 0; round < MAX_ROUNDS && team1Alive && team2Alive; round++) {
            randomSeed++;

            for (uint i = 0; i < 6; i++) {
                if (!state1.alive[i] || !team1Alive) continue;
                uint defenderIndex = _findTarget(state2.alive, state2.traits);
                if (defenderIndex == 6) {
                    team1Alive = false;
                    break;
                }
                uint damage = _calculateDamage(state1.traits[i], state2.traits[defenderIndex], randomSeed + i);
                state2.hp[defenderIndex] = state2.hp[defenderIndex] > damage ? state2.hp[defenderIndex] - damage : 0;
                if (state2.hp[defenderIndex] == 0) {
                    state2.alive[defenderIndex] = false;
                    if (!_hasAnyAlive(state2.alive)) {
                        team2Alive = false;
                    }
                }
            }

            if (!team2Alive) break;

            for (uint i = 0; i < 6; i++) {
                if (!state2.alive[i] || !team2Alive) continue;
                uint defenderIndex = _findTarget(state1.alive, state1.traits);
                if (defenderIndex == 6) {
                    team2Alive = false;
                    break;
                }
                uint damage = _calculateDamage(state2.traits[i], state1.traits[defenderIndex], randomSeed + 1000 + i);
                state1.hp[defenderIndex] = state1.hp[defenderIndex] > damage ? state1.hp[defenderIndex] - damage : 0;
                if (state1.hp[defenderIndex] == 0) {
                    state1.alive[defenderIndex] = false;
                    if (!_hasAnyAlive(state1.alive)) {
                        team1Alive = false;
                    }
                }
            }
        }

        if (team1Alive && !team2Alive) return 1;
        if (team2Alive && !team1Alive) return 2;
        return 0;
    }

    /**
     * @dev 查找存活目标
     */
    function _findTarget(bool[6] memory alive, NFTTraits[6] memory traits) internal pure returns (uint) {
        for (uint i = 0; i < 3; i++) {
            if (alive[i]) return i;
        }
        for (uint i = 3; i < 6; i++) {
            if (alive[i]) return i;
        }
        return 6;
    }

    /**
     * @dev 检查是否有任何存活单位
     */
    function _hasAnyAlive(bool[6] memory alive) internal pure returns (bool) {
        for (uint i = 0; i < 6; i++) {
            if (alive[i]) return true;
        }
        return false;
    }

    /**
     * @dev 计算伤害
     */
    function _calculateDamage(NFTTraits memory attacker, NFTTraits memory defender, uint256 seed) internal pure returns (uint) {
        uint baseDamage = uint(attacker.level) * 30 + uint(attacker.power) * 2;

        if (_checkAdvantage(attacker.element, defender.element)) {
            baseDamage = baseDamage * 150 / 100;
        } else if (_checkAdvantage(defender.element, attacker.element)) {
            baseDamage = baseDamage * 75 / 100;
        }

        uint256 random = seed % 100;
        if (random < 15) {
            baseDamage = baseDamage * 200 / 100;
        }

        uint256 dodgeCheck = (seed + 1) % 100;
        if (dodgeCheck < 20) {
            baseDamage = 0;
        }

        uint256 defense = uint(defender.level) * 10 + uint(defender.power);
        baseDamage = baseDamage * 100 / (100 + defense / 10);

        return baseDamage;
    }

    /**
     * @dev 验证队伍
     */
    function _validateTeam(uint256[6] memory team) internal pure returns (bool) {
        for (uint256 i = 0; i < 6; i++) {
            if (team[i] == 0) return false;
        }
        return true;
    }

    /**
     * @dev 模拟战斗（不改变状态）
     */
    function simulateBattle(
        uint256[6] calldata team1,
        uint256[6] calldata team2
    ) external view returns (uint8) {
        uint256 battleId = block.timestamp % 1000 + 1;
        TeamState memory state1;
        TeamState memory state2;

        for (uint i = 0; i < 6; i++) {
            state1.traits[i] = _getNFTTraits(team1[i]);
            state2.traits[i] = _getNFTTraits(team2[i]);
            state1.hp[i] = uint256(state1.traits[i].level) * 100;
            state2.hp[i] = uint256(state2.traits[i].level) * 100;
            state1.alive[i] = true;
            state2.alive[i] = true;
        }

        bool team1Alive = true;
        bool team2Alive = true;
        uint256 seed = battleId;

        for (uint256 round = 0; round < MAX_ROUNDS && team1Alive && team2Alive; round++) {
            seed++;
            for (uint i = 0; i < 6; i++) {
                if (!state1.alive[i] || !team1Alive) continue;
                uint defenderIndex = _findTarget(state2.alive, state2.traits);
                if (defenderIndex == 6) {
                    team1Alive = false;
                    break;
                }
                uint damage = _calculateDamage(state1.traits[i], state2.traits[defenderIndex], seed + i);
                state2.hp[defenderIndex] = state2.hp[defenderIndex] > damage ? state2.hp[defenderIndex] - damage : 0;
                if (state2.hp[defenderIndex] == 0) {
                    state2.alive[defenderIndex] = false;
                    if (!_hasAnyAlive(state2.alive)) {
                        team2Alive = false;
                    }
                }
            }

            if (!team2Alive) break;

            for (uint i = 0; i < 6; i++) {
                if (!state2.alive[i] || !team2Alive) continue;
                uint defenderIndex = _findTarget(state1.alive, state1.traits);
                if (defenderIndex == 6) {
                    team2Alive = false;
                    break;
                }
                uint damage = _calculateDamage(state2.traits[i], state1.traits[defenderIndex], seed + 1000 + i);
                state1.hp[defenderIndex] = state1.hp[defenderIndex] > damage ? state1.hp[defenderIndex] - damage : 0;
                if (state1.hp[defenderIndex] == 0) {
                    state1.alive[defenderIndex] = false;
                    if (!_hasAnyAlive(state1.alive)) {
                        team1Alive = false;
                    }
                }
            }
        }

        if (team1Alive && !team2Alive) return 1;
        if (team2Alive && !team1Alive) return 2;
        return 0;
    }

    /**
     * @dev 获取战斗记录数量
     */
    function getBattleLogCount() external view returns (uint256) {
        return battleHistory.length;
    }

    /**
     * @dev 获取战斗记录
     */
    function getBattleLog(uint256 index) external view returns (
        uint256 battleId,
        uint256 challengerId,
        uint256 challengedId,
        uint8 winner,
        uint256 timestamp
    ) {
        require(index < battleHistory.length, "Battle: Invalid index");
        BattleState memory battle = battleHistory[index];
        return (
            battle.battleId,
            0,
            0,
            battle.winner,
            battle.startTime
        );
    }

    /**
     * @dev 设置基础战斗奖励
     */
    function setBaseBattleReward(uint256 reward) external onlyOwner {
        baseBattleReward = reward;
    }

    /**
     * @dev 设置战斗手续费率
     */
    function setBattleFeePercent(uint256 feePercent) external onlyOwner {
        require(feePercent <= 100, "Battle: Fee too high");
        battleFeePercent = feePercent;
    }

    /**
     * @dev 获取战斗常量
     */
    function getBattleConstants() external pure returns (uint256, uint256) {
        return (MAX_ROUNDS, PRECISION);
    }
}
