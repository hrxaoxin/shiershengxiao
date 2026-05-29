// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

interface INFTMint {
    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function tokenGrowth(uint256 tokenId) external view returns (uint8);
}

contract Battle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
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

    BattleState[] public battleHistory;

    uint256 public baseBattleReward;
    uint256 public battleFeePercent;
    uint256 public constant MAX_ROUNDS = 50;
    uint256 public constant PRECISION = 10000;

    address public nftContract;
    address public authorizer;

    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
        _initWaterSkills();
        _initWindSkills();
        _initFireSkills();
        _initDarkSkills();
        _initLightSkills();
    }

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "Battle: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint8 public constant ELEMENT_WATER = 0;
    uint8 public constant ELEMENT_WIND = 1;
    uint8 public constant ELEMENT_FIRE = 2;
    uint8 public constant ELEMENT_DARK = 3;
    uint8 public constant ELEMENT_LIGHT = 4;

    event BattleStarted(
        uint256 indexed battleId,
        address indexed challenger,
        address indexed challenged,
        uint256[6] challengerTeam,
        uint256[6] challengedTeam
    );

    event BattleEnded(
        uint256 indexed battleId,
        uint8 winner,
        uint256 challengerReward,
        uint256 challengedReward
    );

    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "Battle: Invalid NFT contract address");
        nftContract = _nftContract;
    }

    function _getNFTTraits(uint256 tokenId) internal view returns (NFTTraits memory) {
        NFTTraits memory traits;
        traits.tokenId = tokenId;
        if (nftContract != address(0)) {
            (uint256 zodiacType, uint256 level, uint256 growth) = _getNFTData(tokenId);
            traits.level = uint8(level);
            traits.element = uint8(zodiacType / 24);
            traits.zodiac = uint8((zodiacType / 2) % 12);
            traits.growth = uint8(growth);
            traits.power = _calculatePower(traits.level, traits.growth);
        } else {
            uint256 zodiacType = tokenId % 120;
            traits.level = uint8((zodiacType / 24) + 1);
            traits.element = uint8(zodiacType / 24);
            traits.zodiac = uint8((zodiacType / 2) % 12);
            traits.growth = uint8(50 + (tokenId % 51));
            traits.power = _calculatePower(traits.level, traits.growth);
        }
        return traits;
    }

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

    function _calculatePower(uint256 level, uint256 growth) internal pure returns (uint8) {
        uint256 basePower = level * 20;
        uint256 growthBonus = (level - 1) * growth * 2 / 100;
        return uint8(basePower + growthBonus);
    }

    function _checkAdvantage(uint8 attackerElement, uint8 defenderElement) internal pure returns (bool) {
        if (attackerElement == ELEMENT_FIRE && defenderElement == ELEMENT_WIND) return true;
        if (attackerElement == ELEMENT_WIND && defenderElement == ELEMENT_WATER) return true;
        if (attackerElement == ELEMENT_WATER && defenderElement == ELEMENT_FIRE) return true;
        if (attackerElement == ELEMENT_LIGHT && defenderElement == ELEMENT_DARK) return true;
        if (attackerElement == ELEMENT_DARK && defenderElement == ELEMENT_LIGHT) return true;
        return false;
    }

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

    function challenge(
        uint256 challengerId,
        uint256 challengedId,
        uint256[6] calldata challengerTeam,
        uint256[6] calldata challengedTeam,
        address challengedAddress
    ) external returns (bool, uint256, uint256[] memory) {
        require(_validateTeam(challengerTeam), "Battle: Invalid challenger team");
        require(_validateTeam(challengedTeam), "Battle: Invalid challenged team");
        require(challengedAddress != address(0), "Battle: Invalid challenged address");

        _requireNFTOwnership(challengerTeam);
        _requireNFTOwnershipForAddress(challengedTeam, challengedAddress);

        if (challengerId != 0) {
            require(_isValidNFT(challengerId), "Battle: Invalid challenger NFT");
            require(INFTMint(nftContract).ownerOf(challengerId) == msg.sender, "Battle: Not owner of challenger NFT");
        }
        if (challengedId != 0) {
            require(_isValidNFT(challengedId), "Battle: Invalid challenged NFT");
            require(INFTMint(nftContract).ownerOf(challengedId) == challengedAddress, "Battle: Not owner of challenged NFT");
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

    function _isValidNFT(uint256 tokenId) internal view returns (bool) {
        if (nftContract == address(0)) return true;
        (bool success, bytes memory data) = nftContract.staticcall(
            abi.encodeWithSignature("ownerOf(uint256)", tokenId)
        );
        return success && data.length >= 32 && abi.decode(data, (address)) != address(0);
    }

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

        uint256[6] memory skillCooldown1;
        uint256[6] memory skillCooldown2;

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
                uint256 skillKey = attackerTrait.element * 24 + attackerTrait.zodiac;
                Skill memory skill = skills[skillKey];
                bool useSkill = skillCooldown1[attackerIndex] == 0 && (randomSeed % 5 == 0 || _shouldUseSkill(state1, attackerIndex));
                
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
                uint256 skillKey = attackerTrait.element * 24 + attackerTrait.zodiac;
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

    function _shouldUseSkill(TeamState memory state, uint attackerIndex) internal pure returns (bool) {
        uint256 hpPercent = (state.hp[attackerIndex] * 100) / state.maxHp[attackerIndex];
        return hpPercent < 50;
    }

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

    function _calculateSpeed(NFTTraits memory traits) internal pure returns (uint256) {
        uint256 baseSpeed = 60;
        uint256 levelBonus = uint256(traits.level) * 5;
        uint256 growthBonus = ((traits.level - 1) * uint256(traits.growth) * 3) / 100;
        
        uint256[12] memory zodiacSpeedBonus = [
            uint256(5), 25, 15, 5, 12, 8, 30, 20, 35, 5, 20, 22
        ];
        return baseSpeed + levelBonus + growthBonus + zodiacSpeedBonus[traits.zodiac];
    }

    function _calculateMaxHP(NFTTraits memory traits) internal pure returns (uint256) {
        uint256 baseHp = 100;
        uint256 levelBonus = uint256(traits.level) * 30;
        uint256 growthBonus = ((traits.level - 1) * uint256(traits.growth) * 20) / 100;
        return baseHp + levelBonus + growthBonus;
    }

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
        return _executeBattleCore(team1, team2, randomSeed);
    }

    function _executeBattleView(
        uint256[6] memory team1,
        uint256[6] memory team2,
        uint256 battleId
    ) internal view returns (uint8) {
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            battleId,
            block.timestamp,
            block.number
        )));
        return _executeBattleCore(team1, team2, randomSeed);
    }

    function simulateBattle(
        uint256[6] calldata team1,
        uint256[6] calldata team2
    ) external view returns (uint8) {
        uint256 battleId = block.timestamp % 1000 + 1;
        return _executeBattleCore(team1, team2, battleId);
    }

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

    function _hasAnyAlive(bool[6] memory alive) internal pure returns (bool) {
        for (uint i = 0; i < 6; i++) {
            if (alive[i]) return true;
        }
        return false;
    }

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

    function _validateTeam(uint256[6] memory team) internal pure returns (bool) {
        for (uint256 i = 0; i < 6; i++) {
            if (team[i] == 0) return false;
        }
        return true;
    }

    function battle(
        uint256[6] calldata attackerTeam,
        uint256[6] calldata defenderTeam
    ) external view returns (bool, uint256, uint256) {
        require(_validateTeam(attackerTeam), "Battle: Invalid attacker team");
        require(_validateTeam(defenderTeam), "Battle: Invalid defender team");
        
        uint256 battleId = block.timestamp % 1000 + 1;
        uint8 winner = _executeBattleView(attackerTeam, defenderTeam, battleId);
        
        uint256 attackerReward = winner == 1 ? baseBattleReward : 0;
        uint256 defenderReward = winner == 2 ? baseBattleReward : 0;
        
        return (true, winner, attackerReward);
    }

    function getBattleLogCount() external view returns (uint256) {
        return battleHistory.length;
    }

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

    function setBaseBattleReward(uint256 reward) external onlyOwner {
        baseBattleReward = reward;
    }

    function setBattleFeePercent(uint256 feePercent) external onlyOwner {
        require(feePercent <= 100, "Battle: Fee too high");
        battleFeePercent = feePercent;
    }

    function getBattleConstants() external pure returns (uint256, uint256) {
        return (MAX_ROUNDS, PRECISION);
    }

    struct Skill {
        uint256 skillId;
        uint8 skillType;
        uint256 damage;
        uint256 cooldown;
        uint256 duration;
        bool isAoe;
    }

    mapping(uint256 => Skill) public skills;

    function initSkills() external onlyOwner {
        _initWaterSkills();
        _initWindSkills();
        _initFireSkills();
        _initDarkSkills();
        _initLightSkills();
    }

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

    function _setSkill(uint256 tokenType, uint8 skillType, uint256 damage, uint256 cooldown, uint256 duration, bool isAoe) private {
        skills[tokenType] = Skill(tokenType, skillType, damage, cooldown, duration, isAoe);
    }

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