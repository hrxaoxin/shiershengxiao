// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./LPLib.sol";
import "./ArenaRewardLPLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract ArenaRewardLP is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using ArenaRewardLPLib for ArenaRewardLPLib.RewardPool;
    using SafeERC20 for IERC20;
    
    address public authorizer;
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    ArenaRewardLPLib.RewardPool private _pool;
    uint256[44] private __gap;

    event LPRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event TokenRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event BNBRewardClaimed(address user, uint256 seasonId, uint256 amount);
    event LPAddedToPool(uint256 amount);
    event TokenAddedToPool(uint256 amount);
    event BNBAddedToPool(uint256 amount);
    event RewardTypeChanged(RewardType oldType, RewardType newType);
    event DailyRewardCalculated(uint256 dailyReward);
    event RewardRateUpdated(uint256 rewardRate);

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     * @param oldEpoch 重置前的纪元版本号
     * @param newEpoch 重置后的纪元版本号
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "ArenaRewardLP: Invalid authorizer");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
        epoch = 1;
        _pool.rewardType = RewardType.BNB;
        _pool.rewardRate = 100;
        _pool.maxRewardRate = 500;
        _pool.maxDailyRewardPercent = 100;
        _pool.rateStep = 10;
        _pool.rewardPrecision = 10000;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        require(authorizer != address(0), "ArenaRewardLP: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaRewardLP: Not authorized");
        _;
    }

    receive() external payable {
        if (msg.value > 0) {
            _pool.processIncomingBNB(IAuthorizer(authorizer), msg.value);
        }
    }

    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        require(amount > 0, "ArenaRewardLP: Amount must be > 0");
        _pool.processIncomingBNB(IAuthorizer(authorizer), amount);
    }

    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        require(token != address(0), "ArenaRewardLP: Invalid token address");
        require(amount > 0, "ArenaRewardLP: Amount must be > 0");
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        _pool.processIncomingToken(IAuthorizer(authorizer), token, amount);
    }

    function receiveMultipleTokens(address[] calldata tokens, uint256[] calldata amounts) external onlyOwnerOrAuthorizer {
        require(tokens.length == amounts.length, "ArenaRewardLP: Arrays length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IBEP20(tokens[i]).transferFrom(msg.sender, address(this), amounts[i]);
                _pool.processIncomingToken(IAuthorizer(authorizer), tokens[i], amounts[i]);
            }
        }
    }

    function setRewardType(RewardType _rewardType) external onlyOwner {
        RewardType oldType = _pool.rewardType;
        if (oldType == _rewardType) {
            return;
        }
        _pool.convertPoolAssets(IAuthorizer(authorizer), oldType, _rewardType);
        _pool.rewardType = _rewardType;
        emit RewardTypeChanged(oldType, _rewardType);
    }

    function compoundFees() external onlyOwner {
        LPLib.compoundFees(IAuthorizer(authorizer));
    }

    function claimLPReward(uint256 seasonId) external nonReentrant whenNotPaused returns (uint256) {
        address arenaReward = IAuthorizer(authorizer).getAddressByName(\"arenaReward\");
        uint256 reward = IArenaReward(arenaReward).getPendingRewardsByPlayer(msg.sender, seasonId);
        return _pool.claimReward(IAuthorizer(authorizer), msg.sender, seasonId, reward, arenaReward);
    }

    function getPendingLPReward(address user, uint256 seasonId) external view returns (uint256) {
        address arenaReward = IAuthorizer(authorizer).getAddressByName(\"arenaReward\");
        return _pool.getPendingReward(user, seasonId, arenaReward);
    }

    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        LPLib.emergencyWithdrawWBNB(IAuthorizer(authorizer), amount);
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaRewardLP: Invalid authorizer");
        authorizer = _authorizerAddress;
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0 && _rewardRate <= _pool.maxRewardRate, "ArenaRewardLP: Invalid reward rate");
        _pool.rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        require(_maxRewardRate >= _pool.rewardRate, "ArenaRewardLP: Max rate must be >= current rate");
        _pool.maxRewardRate = _maxRewardRate;
    }

    function setMaxDailyRewardPercent(uint256 _percent) external onlyOwner {
        require(_percent > 0 && _percent <= 500, "ArenaRewardLP: Invalid percent");
        _pool.maxDailyRewardPercent = _percent;
    }

    function shouldCalculateDailyReward() external view returns (bool) {
        return _pool.shouldCalculateDailyReward();
    }

    function calculateDailyReward() external whenNotPaused {
        _pool.calculateDailyReward();
    }

    function recordIncomingTokens(uint256 amount) external onlyOwnerOrAuthorizer {
        _pool.recordIncomingTokens(amount);
    }

    function setRateStep(uint256 _rateStep) external onlyOwner {
        require(_rateStep > 0, "ArenaRewardLP: Step must be > 0");
        _pool.rateStep = _rateStep;
    }

    function withdrawToken(address token, address to) external onlyOwner {
        require(token != address(0), "ArenaRewardLP: Invalid token");
        require(to != address(0), "ArenaRewardLP: Invalid recipient");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
        }
    }

    function withdrawBNB(address to) external onlyOwner {
        require(to != address(0), "ArenaRewardLP: Invalid recipient");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(to).call{value: balance}("");
            require(success, "ArenaRewardLP: BNB transfer failed");
        }
    }

    /**
     * @dev 重置合约数据
     * @notice 通过递增纪元版本号快速重置，仅owner或authorizer可调用
     * @dev 注意：奖励池余额（LP/Token/BNB）代表真实资产，不会随epoch重置而丢失
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        
        _pool.rewardType = RewardType.BNB;
        _pool.rewardRate = 100;
        _pool.maxRewardRate = 500;
        _pool.maxDailyRewardPercent = 100;
        _pool.rateStep = 10;
        _pool.rewardPrecision = 10000;
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}
