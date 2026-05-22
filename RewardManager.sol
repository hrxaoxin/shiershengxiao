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
error NotOwner();
error NotOperator();
error NotAuthorized();
error PoolOverflow();
error Paused();
error NotPaused();
error RateLimited();

contract RewardManager is 
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    IDividendManager public dividendManager;
    IWeightManager public weightManager;
    IPoolManager public poolManager;
    
    address public nftDataContract;
    uint256 public operationCooldown = 1 seconds;
    mapping(address => uint256) public lastOperationTime;
    
    event RewardManagerInitialized(address indexed dividendManager, address indexed weightManager, address indexed poolManager);
    event DividendClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event HolderAdded(address indexed user, uint256 timestamp);
    event HolderRemoved(address indexed user, uint256 timestamp);
    
    function initialize(
        address _dividendManager,
        address _weightManager,
        address _poolManager,
        address _nftDataContract
    ) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        if (_dividendManager == address(0)) revert ZeroAddress();
        if (_weightManager == address(0)) revert ZeroAddress();
        if (_poolManager == address(0)) revert ZeroAddress();
        if (_nftDataContract == address(0)) revert ZeroAddress();
        
        dividendManager = IDividendManager(_dividendManager);
        weightManager = IWeightManager(_weightManager);
        poolManager = IPoolManager(_poolManager);
        nftDataContract = _nftDataContract;
        
        emit RewardManagerInitialized(_dividendManager, _weightManager, _poolManager);
    }
    
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    modifier onlyOperator() {
        bool isAuthorized = msg.sender == owner();
        if (!isAuthorized) revert NotOperator();
        _;
    }
    
    modifier rateLimited() {
        uint256 lastTime = lastOperationTime[msg.sender];
        if (block.timestamp < lastTime + operationCooldown) revert RateLimited();
        lastOperationTime[msg.sender] = block.timestamp;
        _;
    }
    
    function setDividendManager(address _dividendManager) external onlyOwner {
        if (_dividendManager == address(0)) revert ZeroAddress();
        dividendManager = IDividendManager(_dividendManager);
    }
    
    function setWeightManager(address _weightManager) external onlyOwner {
        if (_weightManager == address(0)) revert ZeroAddress();
        weightManager = IWeightManager(_weightManager);
    }
    
    function setPoolManager(address _poolManager) external onlyOwner {
        if (_poolManager == address(0)) revert ZeroAddress();
        poolManager = IPoolManager(_poolManager);
    }
    
    function setNFTDataContract(address _nftDataContract) external onlyOwner {
        if (_nftDataContract == address(0)) revert ZeroAddress();
        nftDataContract = _nftDataContract;
    }
    
    function setOperationCooldown(uint256 cooldown) external onlyOwner {
        operationCooldown = cooldown;
    }
    
    function depositDividend() external payable rateLimited {
        if (msg.value == 0) revert InvalidAmount();
        dividendManager.depositDividend{value: msg.value}();
    }
    
    function claimDividend() external nonReentrant whenNotPaused {
        dividendManager.claimDividend();
        emit DividendClaimed(msg.sender, 0, block.timestamp);
    }
    
    function createSnapshot() external onlyOwner returns (uint256) {
        return dividendManager.createSnapshot();
    }
    
    function finalizeSnapshot(uint256 snapshotId) external onlyOwner {
        dividendManager.finalizeSnapshot(snapshotId);
    }
    
    function claimDividendFromSnapshot(uint256 snapshotId) external nonReentrant whenNotPaused {
        dividendManager.claimDividendFromSnapshot(snapshotId);
    }
    
    function addHolder(address user) external onlyOperator returns (bool) {
        weightManager.addHolder(user);
        emit HolderAdded(user, block.timestamp);
        return true;
    }
    
    function removeHolder(address user) external onlyOperator {
        weightManager.removeHolder(user);
        emit HolderRemoved(user, block.timestamp);
    }
    
    function updateUserWeight(address user) external onlyOperator {
        weightManager.updateUserWeight(user);
    }
    
    function withdrawOwnerDividend() external onlyOwner {
        poolManager.withdrawOwnerDividend();
    }
    
    function withdrawNftStakingPool() external onlyOperator {
        poolManager.withdrawNftStakingPool();
    }
    
    function withdrawArenaPool() external onlyOperator {
        poolManager.withdrawArenaPool();
    }
    
    function withdrawTokenStakingPool() external onlyOperator {
        poolManager.withdrawTokenStakingPool();
    }
    
    function withdrawExtraFunds() external onlyOwner {
        poolManager.withdrawExtraFunds();
    }
    
    function getUserWeight(address user) external view returns (uint256) {
        return weightManager.getUserWeight(user);
    }
    
    function hasEligibility(address user) external view returns (bool) {
        return weightManager.hasEligibility(user);
    }
    
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        return dividendManager.calcUserDividend(user);
    }
    
    function getPoolDetails() external view returns (uint256, uint256, uint256, uint256) {
        return poolManager.getPoolDetails();
    }
    
    function getTotalPoolAmount() external view returns (uint256) {
        return poolManager.getTotalPoolAmount();
    }
    
    function getSnapshotCount() external view returns (uint256) {
        return dividendManager.getSnapshotCount();
    }
    
    function emergencyPause() external onlyOwner {
        _pause();
    }
    
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }
    
    function receiveEther() external payable {
    }
    
    receive() external payable {
    }
}