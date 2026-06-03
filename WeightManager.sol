// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

error ZeroAddress();
error InvalidAmount();
error NotOperator();

contract WeightManager is
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "WeightManager: Paused");
        _;
    }

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    address public nftDataContract;
    address public authorizer;
    uint256 public minOwnerWeight;
    uint256 public ownerWeight;
    
    mapping(address => uint256) public userWeight;
    mapping(address => uint256) public cachedUserWeight;
    mapping(address => uint256) public cachedWeightTimestamp;
    uint256 public weightCacheDuration = 5 minutes;
    
    mapping(address => address) public eligibleUserPrev;
    mapping(address => address) public eligibleUserNext;
    mapping(address => bool) public inEligibleList;
    address public eligibleUserHead;
    address public eligibleUserTail;
    
    event UserWeightUpdated(address indexed user, uint256 oldWeight, uint256 newWeight, uint256 timestamp);
    event TotalWeightUpdated(uint256 oldWeight, uint256 newWeight, uint256 timestamp);
    
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        minOwnerWeight = 0;
        ownerWeight = 0;
        authorizer = _authorizer;
    }
    
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "WeightManager: Not authorized");
        _;
    }
    
    modifier onlyOperator() {
        bool isAuthorized = msg.sender == owner();
        if (!isAuthorized) revert NotOperator();
        _;
    }
    
    function setNFTDataContract(address _nftDataContract) external onlyAuthorized {
        if (_nftDataContract == address(0)) revert ZeroAddress();
        nftDataContract = _nftDataContract;
    }
    
    function setMinOwnerWeight(uint256 _minWeight) external onlyOwner {
        if (_minWeight == 0) revert InvalidAmount();
        minOwnerWeight = _minWeight;
        if (ownerWeight < minOwnerWeight) {
            ownerWeight = minOwnerWeight;
        }
    }
    
    function setOwnerWeight(uint256 _w) external onlyOwner {
        if (_w < minOwnerWeight) revert InvalidAmount();
        ownerWeight = _w;
    }
    
    function _calcUserWeight(address user) internal view returns (uint256) {
        if (user == owner()) return ownerWeight;
        if (nftDataContract == address(0)) return 0;
        
        INFTDataInterface m = INFTDataInterface(nftDataContract);
        return m.calcUserWeight(user);
    }
    
    function getUserWeight(address user) external view returns (uint256) {
        if (user == owner()) return ownerWeight;
        
        if (cachedWeightTimestamp[user] + weightCacheDuration >= block.timestamp) {
            return cachedUserWeight[user];
        }
        
        return _calcUserWeight(user);
    }
    
    function refreshUserWeightCache(address user) external onlyOperator {
        if (nftDataContract == address(0)) return;
        
        INFTDataInterface nftData = INFTDataInterface(nftDataContract);
        if (user == owner()) return;
        
        uint256 weight = nftData.calcUserWeight(user);
        cachedUserWeight[user] = weight;
        cachedWeightTimestamp[user] = block.timestamp;
    }
    
    function batchUpdateUserWeight(address[] calldata users) external onlyOperator whenNotPaused {
        require(users.length <= 100, "WeightManager: Batch size too large");
        uint256 count = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                _updateUserWeight(users[i]);
                count++;
            }
        }
        emit BatchWeightUpdateCompleted(msg.sender, count);
    }

    function getUserWeightHistory(address user) external view returns (WeightSnapshot[] memory) {
        return weightSnapshots[user];
    }

    event BatchWeightUpdateCompleted(address indexed operator, uint256 count);

    function setWeightCacheDuration(uint256 duration) external onlyOwner {
        weightCacheDuration = duration;
    }
    
    function clearUserWeightCache(address user) external onlyOperator {
        delete cachedUserWeight[user];
        delete cachedWeightTimestamp[user];
    }
    
    function _hasEligibility(address user) internal view returns (bool) {
        uint256 w = getUserWeight(user);
        return w >= minOwnerWeight;
    }
    
    function hasEligibility(address user) external view returns (bool) {
        return _hasEligibility(user);
    }
    
    function _updateUserWeight(address user) internal {
        uint256 oldWeight = userWeight[user];
        uint256 newWeight = _calcUserWeight(user);
        
        if (oldWeight != newWeight) {
            userWeight[user] = newWeight;
            cachedUserWeight[user] = newWeight;
            cachedWeightTimestamp[user] = block.timestamp;
            emit UserWeightUpdated(user, oldWeight, newWeight, block.timestamp);
        }
        
        _manageEligibleList(user);
    }
    
    function updateUserWeight(address user) external onlyOperator whenNotPaused {
        _updateUserWeight(user);
    }
    
    function _manageEligibleList(address user) internal {
        bool isEligible = _hasEligibility(user);
        bool wasInList = inEligibleList[user];
        
        if (isEligible && !wasInList) {
            _addToEligibleList(user);
        } else if (!isEligible && wasInList) {
            _removeFromEligibleList(user);
        }
    }
    
    function _addToEligibleList(address user) internal {
        if (eligibleUserTail == address(0)) {
            eligibleUserHead = user;
            eligibleUserTail = user;
            eligibleUserPrev[user] = address(0);
            eligibleUserNext[user] = address(0);
        } else {
            eligibleUserNext[eligibleUserTail] = user;
            eligibleUserPrev[user] = eligibleUserTail;
            eligibleUserNext[user] = address(0);
            eligibleUserTail = user;
        }
        inEligibleList[user] = true;
    }
    
    function _removeFromEligibleList(address user) internal {
        address prev = eligibleUserPrev[user];
        address next = eligibleUserNext[user];
        
        if (prev != address(0)) {
            eligibleUserNext[prev] = next;
        } else {
            eligibleUserHead = next;
        }
        
        if (next != address(0)) {
            eligibleUserPrev[next] = prev;
        } else {
            eligibleUserTail = prev;
        }
        
        delete eligibleUserPrev[user];
        delete eligibleUserNext[user];
        inEligibleList[user] = false;
    }
    
    function addHolder(address user) external onlyOperator whenNotPaused returns (bool) {
        _updateUserWeight(user);
        return true;
    }
    
    function removeHolder(address user) external onlyOperator whenNotPaused {
        uint256 oldWeight = userWeight[user];
        if (oldWeight > 0) {
            userWeight[user] = 0;
            _manageEligibleList(user);
            emit UserWeightUpdated(user, oldWeight, 0, block.timestamp);
        }
    }
}