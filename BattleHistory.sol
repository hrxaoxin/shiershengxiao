// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

contract BattleHistory is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    address public battleContract;
    address public authorizer;

    mapping(uint256 => BattleLib.SingleBattleResult) public battleHistory;

    modifier onlyBattleContract() {
        require(msg.sender == battleContract, "Only battle contract");
        _;
    }

    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "BattleHistory: Not authorized");
        _;
    }

    function setBattleContract(address _battleContract) external onlyAuthorized {
        require(_battleContract != address(0), "BattleHistory: Invalid battle contract address");
        battleContract = _battleContract;
    }

    function addBattle(uint256 battleId, BattleLib.SingleBattleResult calldata result) external onlyBattleContract {
        battleHistory[battleId] = result;
    }

    function getBattleHistoryById(uint256 battleId) external view returns (BattleLib.SingleBattleResult memory) {
        return battleHistory[battleId];
    }
}
