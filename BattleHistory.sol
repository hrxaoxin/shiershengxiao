// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BattleLib.sol";

contract BattleHistory {
    address public owner;
    address public battleContract;

    mapping(uint256 => BattleLib.SingleBattleResult) public battleHistory;

    modifier onlyBattleContract() {
        require(msg.sender == battleContract, "Only battle contract");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setBattleContract(address _battleContract) external onlyOwner {
        battleContract = _battleContract;
    }

    function addBattle(uint256 battleId, BattleLib.SingleBattleResult calldata result) external onlyBattleContract {
        battleHistory[battleId] = result;
    }

    function getBattleHistoryById(uint256 battleId) external view returns (BattleLib.SingleBattleResult memory) {
        return battleHistory[battleId];
    }
}
