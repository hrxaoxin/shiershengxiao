// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./AddressLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingLPReward is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IStakingLPReward {
    using SafeERC20 for IERC20;

    address public authorizer;
    
    RewardType public rewardType;
    
    uint256 public lpRewardPoolBalance;
    uint256 public tokenRewardPoolBalance;
    uint256 public bnbRewardPoolBalance;
    
    uint256 private _slippage = 1000;
    
    uint256 private _rewardRate = 100;
    uint256 private _maxRewardRate = 500;
    uint256 private _maxDailyRewardPercent = 100;
    uint256 private _rateStep = 10;
    
    uint256 private _todayStart;
    uint256 private _todayRewardAmount;
    uint256 private _todayIncomingTokens;
    
    uint256 public globalRewardPerWeight;
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    mapping(uint256 => mapping(address => uint256)) private _userRewardSnapshotWeight;
    
    uint256 public constant STAKING_REWARD_PRECISION = 1e18;
    uint256 public constant REWARD_PRECISION = 10000;
    
    uint256 public totalWeightedNFTs;

    error InvalidParam();
    error Unauthorized();
    error InsufficientLP();
    error InsufficientToken();
    error InsufficientBNB();
    error NoStakedNFTs();
    error SameRewardType();
    error ContractPaused();
    error AlreadyInitialized();

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizerAddress) external initializer {
        if (_authorizerAddress == address(0)) revert InvalidParam();
        
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        authorizer = _authorizerAddress;
        rewardType = RewardType.BNB;
        
        _slippage = 1000;
        _rewardRate = 100;
        _maxRewardRate = 500;
        _maxDailyRewardPercent = 100;
        _rateStep = 10;
        _todayStart = 0;
        _todayRewardAmount = 0;
        _todayIncomingTokens = 0;
        globalRewardPerWeight = 0;
        totalWeightedNFTs = 0;
        epoch = 1;
    }
    
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        if (authorizer == address(0)) revert Unauthorized();
        IAuthorizer auth = IAuthorizer(authorizer);
        if (!auth.isSystemContract(msg.sender)) revert Unauthorized();
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        if (_authorizerAddress == address(0)) revert InvalidParam();
        authorizer = _authorizerAddress;
    }

    function _getStakingLPAsset() private view returns (IStakingLPAsset) {
        address assetAddr = IAuthorizer(authorizer).getAddressByName(AddressLib.STAKING_LP_ASSET);
        return IStakingLPAsset(assetAddr);
    }

    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        if (amount == 0) revert InvalidParam();
        _getStakingLPAsset().recordIncomingBNB(amount);
    }

    function updateTotalWeight(uint256 _totalWeightedNFTs) external onlyOwnerOrAuthorizer {
        totalWeightedNFTs = _totalWeightedNFTs;
    }

    function syncUserWeight(address user, uint256 snapshotWeight) external onlyOwnerOrAuthorizer {
        _userRewardSnapshotWeight[epoch][user] = snapshotWeight;
    }

    function setRewardType(RewardType _rewardType) external onlyOwner {
        RewardType oldType = rewardType;
        if (oldType == _rewardType) {
            return;
        }
        
        IStakingLPAsset asset = _getStakingLPAsset();
        (uint256 lpBalance, uint256 tokenBalance, uint256 bnbBalance) = _getAssetBalances();
        
        if (oldType == RewardType.LP && _rewardType == RewardType.TOKEN) {
            if (lpBalance > 0) {
                uint256 converted = _redeemLPToToken(lpBalance);
                lpRewardPoolBalance -= lpBalance;
                if (converted > 0) {
                    tokenRewardPoolBalance += converted;
                }
            }
        } else if (oldType == RewardType.LP && _rewardType == RewardType.BNB) {
            if (lpBalance > 0) {
                uint256 converted = _redeemLPToWBNB(lpBalance);
                lpRewardPoolBalance -= lpBalance;
                if (converted > 0) {
                    bnbRewardPoolBalance += converted;
                }
            }
        } else if (oldType == RewardType.TOKEN && _rewardType == RewardType.LP) {
            if (tokenBalance > 0) {
                uint256 converted = _convertTokenToLP(tokenBalance);
                tokenRewardPoolBalance -= tokenBalance;
                if (converted > 0) {
                    lpRewardPoolBalance += converted;
                }
            }
        } else if (oldType == RewardType.TOKEN && _rewardType == RewardType.BNB) {
            if (tokenBalance > 0) {
                uint256 converted = _swapTokenToBNB(tokenBalance);
                tokenRewardPoolBalance -= tokenBalance;
                if (converted > 0) {
                    bnbRewardPoolBalance += converted;
                }
            }
        } else if (oldType == RewardType.BNB && _rewardType == RewardType.LP) {
            if (bnbBalance > 0) {
                uint256 converted = _convertBNBToLP(bnbBalance);
                bnbRewardPoolBalance -= bnbBalance;
                if (converted > 0) {
                    lpRewardPoolBalance += converted;
                }
            }
        } else if (oldType == RewardType.BNB && _rewardType == RewardType.TOKEN) {
            if (bnbBalance > 0) {
                uint256 converted = _swapBNBToToken(bnbBalance);
                bnbRewardPoolBalance -= bnbBalance;
                if (converted > 0) {
                    tokenRewardPoolBalance += converted;
                }
            }
        }
        
        rewardType = _rewardType;
        emit RewardTypeChanged(oldType, _rewardType);
    }

    function _getAssetBalances() internal view returns (uint256, uint256, uint256) {
        return (lpRewardPoolBalance, tokenRewardPoolBalance, bnbRewardPoolBalance);
    }

    function _redeemLPToToken(uint256 lpAmount) internal returns (uint256) {
        _getStakingLPAsset().migrateLP(0, 0, lpAmount);
        return lpAmount;
    }

    function _redeemLPToWBNB(uint256 lpAmount) internal returns (uint256) {
        _getStakingLPAsset().migrateLP(0, 0, lpAmount);
        return lpAmount;
    }

    function _convertTokenToLP(uint256 tokenAmount) internal returns (uint256) {
        _getStakingLPAsset().receiveToken(IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN), tokenAmount);
        return tokenAmount;
    }

    function _swapTokenToBNB(uint256 tokenAmount) internal returns (uint256) {
        return tokenAmount;
    }

    function _convertBNBToLP(uint256 bnbAmount) internal returns (uint256) {
        _getStakingLPAsset().recordIncomingBNB(bnbAmount);
        return bnbAmount;
    }

    function _swapBNBToToken(uint256 bnbAmount) internal returns (uint256) {
        return bnbAmount;
    }

    function claimLPReward() external nonReentrant whenNotPaused {
        address staking = IAuthorizer(authorizer).getAddressByName(AddressLib.STAKING);
        uint256 userWeight = IStaking(staking).userStakedWeight(msg.sender);
        if (userWeight == 0) revert NoStakedNFTs();

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            uint256 reward = bnbRewardPoolBalance * userWeight / totalWeightedNFTs;
            if (reward > 0 && reward <= bnbRewardPoolBalance) {
                bnbRewardPoolBalance -= reward;
                (bool success, ) = payable(msg.sender).call{value: reward}("");
                if (success) {
                    emit BNBRewardClaimed(msg.sender, reward);
                }
            }
            return;
        }

        uint256 currentEpoch = epoch;
        uint256 rewardBase = globalRewardPerWeight * userWeight;
        uint256 snapshotBase = _userRewardSnapshotWeight[currentEpoch][msg.sender];
        
        if (rewardBase <= snapshotBase) {
            return;
        }

        uint256 reward = (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
        
        if (currentType == RewardType.LP) {
            if (reward > lpRewardPoolBalance) revert InsufficientLP();
            lpRewardPoolBalance -= reward;
            _getStakingLPAsset().migrateLP(0, 0, reward);
            emit LPRewardClaimed(msg.sender, reward);
        } else if (currentType == RewardType.TOKEN) {
            if (reward > tokenRewardPoolBalance) revert InsufficientToken();
            tokenRewardPoolBalance -= reward;
            IERC20(IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN)).safeTransfer(msg.sender, reward);
            emit TokenRewardClaimed(msg.sender, reward);
        }

        _userRewardSnapshotWeight[currentEpoch][msg.sender] = globalRewardPerWeight;
    }

    function getPendingLPReward(address user) external view returns (uint256) {
        address staking = IAuthorizer(authorizer).getAddressByName(AddressLib.STAKING);
        uint256 userWeight = IStaking(staking).userStakedWeight(user);
        if (userWeight == 0) return 0;

        RewardType currentType = rewardType;
        
        if (currentType == RewardType.BNB) {
            return bnbRewardPoolBalance * userWeight / (totalWeightedNFTs + 1);
        }
        
        uint256 currentEpoch = epoch;
        uint256 rewardBase = globalRewardPerWeight * userWeight;
        uint256 snapshotBase = _userRewardSnapshotWeight[currentEpoch][user];
        
        if (rewardBase <= snapshotBase) {
            return 0;
        }
        
        return (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
    }

    function shouldCalculateDailyReward() public view returns (bool) {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        return currentDayStart > _todayStart;
    }

    function calculateDailyReward() external whenNotPaused {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart <= _todayStart) return;

        _todayStart = currentDayStart;
        _rewardRate = 100;

        RewardType currentType = rewardType;
        uint256 poolBalance;

        if (currentType == RewardType.LP) {
            poolBalance = lpRewardPoolBalance;
        } else if (currentType == RewardType.TOKEN) {
            poolBalance = tokenRewardPoolBalance;
        } else {
            poolBalance = bnbRewardPoolBalance;
        }

        if (poolBalance == 0 || totalWeightedNFTs == 0) {
            _todayRewardAmount = 0;
            _todayIncomingTokens = 0;
            return;
        }

        uint256 expectedDailyReward = poolBalance * _rewardRate / REWARD_PRECISION;

        if (expectedDailyReward > 0 && _todayIncomingTokens > expectedDailyReward) {
            uint256 multiple = _todayIncomingTokens / expectedDailyReward;
            uint256 steps = multiple - 1;
            uint256 maxSteps = (_maxRewardRate - _rewardRate) / _rateStep;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = _rewardRate + (steps * _rateStep);

            if (newRate != _rewardRate) {
                _rewardRate = newRate;
                emit RewardRateUpdated(_rewardRate);
            }
        }

        uint256 dailyReward = poolBalance * _rewardRate / REWARD_PRECISION;
        uint256 maxDailyReward = poolBalance * _maxDailyRewardPercent / 1000;

        if (dailyReward > maxDailyReward) {
            dailyReward = maxDailyReward;
        }

        if (dailyReward > 0) {
            uint256 increment = (dailyReward * STAKING_REWARD_PRECISION) / totalWeightedNFTs;
            globalRewardPerWeight += increment;
            _todayRewardAmount = dailyReward;

            if (currentType == RewardType.LP) {
                lpRewardPoolBalance -= dailyReward;
            } else if (currentType == RewardType.TOKEN) {
                tokenRewardPoolBalance -= dailyReward;
            } else {
                bnbRewardPoolBalance -= dailyReward;
            }

            emit DailyRewardCalculated(dailyReward, increment);
        } else {
            _todayRewardAmount = 0;
        }

        _todayIncomingTokens = 0;
    }

    function recordIncomingTokens(uint256 amount) external onlyOwnerOrAuthorizer {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;
        if (currentDayStart != _todayStart) {
            _todayStart = currentDayStart;
            _todayIncomingTokens = 0;
        }
        _todayIncomingTokens += amount;
    }

    function setRewardRate(uint256 __rewardRate) external onlyOwner {
        if (__rewardRate == 0 || __rewardRate > _maxRewardRate) revert InvalidParam();
        _rewardRate = __rewardRate;
        emit RewardRateUpdated(__rewardRate);
    }

    function setMaxRewardRate(uint256 __maxRewardRate) external onlyOwner {
        if (__maxRewardRate < _rewardRate) revert InvalidParam();
        _maxRewardRate = __maxRewardRate;
    }

    function setMaxDailyRewardPercent(uint256 __percent) external onlyOwner {
        if (__percent == 0 || __percent > 500) revert InvalidParam();
        _maxDailyRewardPercent = __percent;
    }

    function setRateStep(uint256 __rateStep) external onlyOwner {
        if (__rateStep == 0) revert InvalidParam();
        _rateStep = __rateStep;
    }

    function userRewardSnapshotWeight(address user) external view returns (uint256) {
        return _userRewardSnapshotWeight[epoch][user];
    }

    function addToRewardPool(uint256 amount, RewardType type_) external onlyOwnerOrAuthorizer {
        if (type_ == RewardType.LP) {
            lpRewardPoolBalance += amount;
        } else if (type_ == RewardType.TOKEN) {
            tokenRewardPoolBalance += amount;
        } else if (type_ == RewardType.BNB) {
            bnbRewardPoolBalance += amount;
        }

        if (totalWeightedNFTs > 0 && (type_ == RewardType.LP || type_ == RewardType.TOKEN)) {
            uint256 increment = (amount * STAKING_REWARD_PRECISION) / totalWeightedNFTs;
            globalRewardPerWeight += increment;
        }
    }

    function getPoolState() external view returns (
        uint256, uint256, uint256, uint256, uint256, uint256, RewardType,
        uint256, uint256, uint256, uint256, uint256, uint256, uint256
    ) {
        return (
            lpRewardPoolBalance,
            tokenRewardPoolBalance,
            bnbRewardPoolBalance,
            totalWeightedNFTs,
            globalRewardPerWeight,
            STAKING_REWARD_PRECISION,
            rewardType,
            _todayStart,
            _rewardRate,
            _maxRewardRate,
            _maxDailyRewardPercent,
            _rateStep,
            _todayRewardAmount,
            _todayIncomingTokens
        );
    }

    function setPoolState(
        uint256 lp, uint256 token, uint256 bnb,
        uint256 totalWeight, uint256 globalReward, uint256 todayStart,
        uint256 rewardRate, uint256 todayRewardAmount, uint256 todayIncomingTokens
    ) external onlyOwnerOrAuthorizer {
        lpRewardPoolBalance = lp;
        tokenRewardPoolBalance = token;
        bnbRewardPoolBalance = bnb;
        totalWeightedNFTs = totalWeight;
        globalRewardPerWeight = globalReward;
        _todayStart = todayStart;
        _rewardRate = rewardRate;
        _todayRewardAmount = todayRewardAmount;
        _todayIncomingTokens = todayIncomingTokens;
    }

    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        lpRewardPoolBalance = 0;
        tokenRewardPoolBalance = 0;
        bnbRewardPoolBalance = 0;
        globalRewardPerWeight = 0;
        totalWeightedNFTs = 0;
        _todayStart = 0;
        _todayRewardAmount = 0;
        _todayIncomingTokens = 0;
        _rewardRate = 100;
        _slippage = 1000;
        
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }

    receive() external payable {
        if (msg.value > 0) {
            bnbRewardPoolBalance += msg.value;
            if (totalWeightedNFTs > 0 && rewardType == RewardType.BNB) {
                uint256 increment = (msg.value * STAKING_REWARD_PRECISION) / totalWeightedNFTs;
                globalRewardPerWeight += increment;
            }
        }
    }
}