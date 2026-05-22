// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

import "./BattleLib.sol";
import "./BattleSkillData.sol";
import "./BattleHistory.sol";
import "./NFTDataType.sol";
import "./NFTData.sol";

contract Battle is Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    BattleSkillData public skillData;
    BattleHistory public battleHistory;
    NFTData public nftData;

    uint256 public battleCounter;
    uint256 public attackMultiplier;
    uint256 public defenseMultiplier;
    uint256 public randomMultiplier;

    event BattleCompleted(uint256 indexed battleId, uint256 indexed attackerId, uint256 indexed defenderId, bool attackerWon);

    function initialize(address _nftData, address _skillData, address _battleHistory) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        nftData = NFTData(_nftData);
        skillData = BattleSkillData(_skillData);
        battleHistory = BattleHistory(_battleHistory);
        attackMultiplier = 1;
        defenseMultiplier = 1;
        randomMultiplier = 30;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function battle(uint256 attackerTokenId, uint256 defenderTokenId) external nonReentrant returns (BattleLib.SingleBattleResult memory) {
        require(attackerTokenId != defenderTokenId, "E03");
        BattleLib.NFTStatus[] memory nftStatus = _buildStatus(attackerTokenId, defenderTokenId);
        BattleLib.SingleBattleResult memory result = BattleLib.battleCore(nftStatus, attackMultiplier, defenseMultiplier, randomMultiplier);
        battleCounter++;
        battleHistory.addBattle(battleCounter, result);
        emit BattleCompleted(battleCounter, attackerTokenId, defenderTokenId, result.attackerWon);
        return result;
    }

    function simulateBattle(uint256 attackerTokenId, uint256 defenderTokenId) external view returns (BattleLib.SingleBattleResult memory) {
        require(attackerTokenId != defenderTokenId, "E03");
        BattleLib.NFTStatus[] memory nftStatus = _buildStatus(attackerTokenId, defenderTokenId);
        return BattleLib.battleCoreSimulate(nftStatus, attackMultiplier, defenseMultiplier, randomMultiplier);
    }

    function _buildStatus(uint256 attackerTokenId, uint256 defenderTokenId) internal view returns (BattleLib.NFTStatus[] memory) {
        BattleLib.NFTStatus[] memory nftStatus = new BattleLib.NFTStatus[](2);
        nftStatus[0] = _buildSingleStatus(attackerTokenId);
        nftStatus[1] = _buildSingleStatus(defenderTokenId);
        return nftStatus;
    }

    function _buildSingleStatus(uint256 tokenId) internal view returns (BattleLib.NFTStatus memory) {
        NFTDataTypes.ZodiacType t = nftData.tokenType(tokenId);
        uint8 l = nftData.tokenLevel(tokenId);
        uint256 g = nftData.tokenGrowthValue(tokenId);
        
        uint256 elem = uint256(NFTDataTypes.getElement(t));
        uint256 zod = uint256(NFTDataTypes.getBaseZodiac(t));
        uint256 gen = uint256(NFTDataTypes.getGender(t));
        
        BattleLib.FullSkill memory s = skillData.getSkillByIndexes(elem, zod, gen);
        
        return BattleLib.NFTStatus({
            tokenId: tokenId,
            element: NFTDataTypes.ElementType(elem),
            zodiac: zod,
            gender: gen,
            level: l,
            attackValue: l * 60 * (1000 + g * 5) / 1000,
            defenseValue: l * 40 * (1000 + g * 6) / 1000,
            skillHash: s.nameHash,
            skillType: s.skillType,
            skillValue: s.value
        });
    }

    function getBattleHistoryById(uint256 battleId) external view returns (BattleLib.SingleBattleResult memory) {
        return battleHistory.getBattleHistoryById(battleId);
    }

    function setMultipliers(uint256 _attackMultiplier, uint256 _defenseMultiplier, uint256 _randomMultiplier) external onlyOwner {
        attackMultiplier = _attackMultiplier;
        defenseMultiplier = _defenseMultiplier;
        randomMultiplier = _randomMultiplier;
    }

    function setNFTContract(address _nft) external onlyOwner {
        nftData = NFTData(_nft);
    }
}
