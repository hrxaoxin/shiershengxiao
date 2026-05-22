// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

error ZeroAddress();
error InvalidAmount();
error NoDividend();
error NoEligibility();
error ZeroWeight();
error InsufficientBalance();
error Overflow();
error InvalidSnapshot();
error DuplicateEntry();

contract DividendManager is 
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IDividendManager
{
    uint256 public dividendPool;
    uint256 public totalDistributed;
    uint256 public totalWeight;
    uint256 public minOwnerWeight;
    uint256 public ownerWeight;
    
    mapping(address => uint256) public claimedDividend;
    mapping(address => uint256) public userWeight;
    mapping(address => uint256) public precisionAcc;
    mapping(address => uint256) public precisionAccumulationCount;
    
    struct DividendSnapshot {
        uint256 snapshotId;
        uint256 timestamp;
        uint256 totalWeight;
        uint256 dividendPool;
        mapping(address => uint256) userWeights;
        mapping(address => uint256) claimedAmounts;
        bool isFinalized;
    }
    
    DividendSnapshot[] public dividendSnapshots;
    uint256 public activeSnapshotId;
    mapping(address => uint256) public lastClaimedSnapshotId;
    uint256 public snapshotInterval = 24 hours;
    
    event DividendClaimed(address indexed user, uint256 amount, uint256 precision, uint256 timestamp);
    event DividendDeposited(uint256 amount, address indexed sender, uint256 timestamp);
    event DividendSnapshotCreated(uint256 snapshotId, uint256 timestamp);
    event DividendSnapshotFinalized(uint256 snapshotId, uint256 timestamp);
    event DividendClaimedFromSnapshot(address indexed user, uint256 snapshotId, uint256 amount, uint256 timestamp);
    
    function initialize(address rewardManager) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }
    
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    modifier onlyOperator() {
        bool isAuthorized = msg.sender == owner();
        if (!isAuthorized) revert NoEligibility();
        _;
    }
    
    function depositDividend() external payable {
        if (msg.value == 0) revert InvalidAmount();
        dividendPool += msg.value;
        emit DividendDeposited(msg.value, msg.sender, block.timestamp);
    }
    
    function claimDividend() external nonReentrant whenNotPaused {
        address user = msg.sender;
        uint256 userW = user == owner() ? ownerWeight : userWeight[user];
        
        if (userW == 0) revert ZeroWeight();
        if (totalWeight == 0 || dividendPool == 0) revert NoDividend();
        
        uint256 contractBalance = address(this).balance;
        if (contractBalance < dividendPool) revert InsufficientBalance();
        
        uint256 baseReward;
        uint256 carryOver;
        
        if (dividendPool > type(uint256).max / userW) revert Overflow();
        uint256 totalDiv = dividendPool * userW;
        baseReward = totalDiv / totalWeight;
        carryOver = totalDiv % totalWeight;
        
        uint256 accumulated = precisionAcc[user] + carryOver;
        uint256 additionalReward = accumulated / totalWeight;
        carryOver = accumulated % totalWeight;
        
        if (baseReward > dividendPool) revert InvalidAmount();
        if (additionalReward > dividendPool - baseReward) revert InvalidAmount();
        
        baseReward += additionalReward;
        
        if (baseReward == 0) revert NoDividend();
        if (baseReward > dividendPool) revert InvalidAmount();
        
        precisionAcc[user] = carryOver;
        precisionAccumulationCount[user] += 1;
        
        if (precisionAccumulationCount[user] >= 1000) {
            precisionAcc[user] = carryOver / 10;
            precisionAccumulationCount[user] = 0;
        }
        
        unchecked {
            dividendPool -= baseReward;
            claimedDividend[user] += baseReward;
            totalDistributed += baseReward;
        }
        
        emit DividendClaimed(user, baseReward, precisionAcc[user], block.timestamp);
        
        (bool success, ) = payable(user).call{value: baseReward}("");
        if (!success) revert InsufficientBalance();
    }
    
    function createSnapshot() external onlyOwner returns (uint256) {
        uint256 snapshotId = dividendSnapshots.length;
        DividendSnapshot storage snapshot = dividendSnapshots.push();
        snapshot.snapshotId = snapshotId;
        snapshot.timestamp = block.timestamp;
        snapshot.totalWeight = totalWeight;
        snapshot.dividendPool = dividendPool;
        snapshot.isFinalized = false;
        
        activeSnapshotId = snapshotId;
        emit DividendSnapshotCreated(snapshotId, block.timestamp);
        return snapshotId;
    }
    
    function finalizeSnapshot(uint256 snapshotId) external onlyOwner {
        if (snapshotId >= dividendSnapshots.length) revert InvalidSnapshot();
        DividendSnapshot storage snapshot = dividendSnapshots[snapshotId];
        if (snapshot.isFinalized) revert DuplicateEntry();
        
        snapshot.isFinalized = true;
        emit DividendSnapshotFinalized(snapshotId, block.timestamp);
    }
    
    function claimDividendFromSnapshot(uint256 snapshotId) external nonReentrant whenNotPaused {
        if (snapshotId >= dividendSnapshots.length) revert InvalidSnapshot();
        DividendSnapshot storage snapshot = dividendSnapshots[snapshotId];
        if (!snapshot.isFinalized) revert InvalidSnapshot();
        
        address user = msg.sender;
        uint256 userW = snapshot.userWeights[user];
        if (userW == 0) revert ZeroWeight();
        
        uint256 claimed = snapshot.claimedAmounts[user];
        if (claimed > 0) revert DuplicateEntry();
        
        uint256 totalW = snapshot.totalWeight;
        if (totalW == 0 || snapshot.dividendPool == 0) revert NoDividend();
        
        uint256 baseReward = (snapshot.dividendPool * userW) / totalW;
        if (baseReward == 0) revert NoDividend();
        
        snapshot.claimedAmounts[user] = baseReward;
        lastClaimedSnapshotId[user] = snapshotId;
        
        emit DividendClaimedFromSnapshot(user, snapshotId, baseReward, block.timestamp);
        
        (bool success, ) = payable(user).call{value: baseReward}("");
        if (!success) revert InsufficientBalance();
    }
    
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        uint256 totalW = totalWeight;
        if (totalW == 0 || dividendPool == 0) return (0, precisionAcc[user]);
        
        uint256 userW = user == owner() ? ownerWeight : userWeight[user];
        if (userW == 0) return (0, precisionAcc[user]);
        
        uint256 baseReward = (dividendPool * userW) / totalW;
        uint256 carryOver = (dividendPool * userW) % totalW;
        uint256 accumulated = precisionAcc[user] + carryOver;
        uint256 additionalReward = accumulated / totalW;
        
        return (baseReward + additionalReward, accumulated % totalW);
    }
    
    function getUserWeightInSnapshot(uint256 snapshotId, address user) external view returns (uint256) {
        if (snapshotId >= dividendSnapshots.length) revert InvalidSnapshot();
        return dividendSnapshots[snapshotId].userWeights[user];
    }
    
    function getUserDividendInSnapshot(uint256 snapshotId, address user) external view returns (uint256) {
        if (snapshotId >= dividendSnapshots.length) revert InvalidSnapshot();
        DividendSnapshot storage snapshot = dividendSnapshots[snapshotId];
        
        uint256 userW = snapshot.userWeights[user];
        if (userW == 0 || snapshot.totalWeight == 0 || snapshot.dividendPool == 0) {
            return 0;
        }
        
        return (snapshot.dividendPool * userW) / snapshot.totalWeight;
    }
    
    function getSnapshotCount() external view returns (uint256) {
        return dividendSnapshots.length;
    }
    
    function setSnapshotInterval(uint256 interval) external onlyOwner {
        if (interval == 0) revert InvalidAmount();
        snapshotInterval = interval;
    }
    
    function emergencyPause() external onlyOwner {
        _pause();
    }
    
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }
    
    function updateUserWeight(address user, uint256 oldWeight, uint256 newWeight) external onlyOperator {
        if (oldWeight > newWeight) {
            uint256 diff = oldWeight - newWeight;
            if (totalWeight < diff) revert Overflow();
            totalWeight -= diff;
        } else {
            if (totalWeight > type(uint256).max - (newWeight - oldWeight)) revert Overflow();
            totalWeight += (newWeight - oldWeight);
        }
        userWeight[user] = newWeight;
    }
    
    function setOwnerWeight(uint256 weight) external onlyOwner {
        uint256 oldWeight = ownerWeight;
        if (oldWeight > weight) {
            totalWeight -= oldWeight - weight;
        } else {
            totalWeight += weight - oldWeight;
        }
        ownerWeight = weight;
    }
    
    function setMinOwnerWeight(uint256 minWeight) external onlyOwner {
        minOwnerWeight = minWeight;
    }
}