// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./AddressLib.sol";
import "./StakingLPLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingLPAsset is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IStakingLPAsset {
    using SafeERC20 for IERC20;

    address public authorizer;
    
    uint256 private _slippage = 1000;

    error InvalidParam();
    error Unauthorized();
    error SLP_BNBTransferFailed();

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
        _slippage = 1000;
    }

    function _getStakingLPReward() private view returns (IStakingLPReward) {
        address rewardAddr = IAuthorizer(authorizer).getAddressByName(AddressLib.STAKING_LP_REWARD);
        return IStakingLPReward(rewardAddr);
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

    function recordIncomingBNB(uint256 amount) external onlyOwnerOrAuthorizer {
        _recordIncomingBNB(amount);
    }

    function _recordIncomingBNB(uint256 amount) internal {
        if (amount == 0) revert InvalidParam();
        
        IStakingLPReward reward = _getStakingLPReward();
        RewardType currentType = reward.rewardType();
        
        if (currentType == RewardType.LP) {
            uint256 lpAmount = StakingLPLib.convertBNBToLP(IAuthorizer(authorizer), amount);
            if (lpAmount > 0) {
                reward.addToRewardPool(lpAmount, RewardType.LP);
            }
        } else if (currentType == RewardType.TOKEN) {
            uint256 tokenAmount = StakingLPLib.swapBNBToToken(IAuthorizer(authorizer), amount);
            if (tokenAmount > 0) {
                reward.addToRewardPool(tokenAmount, RewardType.TOKEN);
            }
        } else {
            reward.addToRewardPool(amount, RewardType.BNB);
        }
    }

    function receiveToken(address token, uint256 amount) external onlyOwnerOrAuthorizer {
        if (token == address(0)) revert InvalidParam();
        if (amount == 0) revert InvalidParam();
        
        IBEP20(token).transferFrom(msg.sender, address(this), amount);
        
        IStakingLPReward reward = _getStakingLPReward();
        RewardType currentType = reward.rewardType();
        
        address wbnb = IAuthorizer(authorizer).getAddressByName(AddressLib.WBNB);
        address mainToken = IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN);

        if (token == wbnb) {
            if (currentType == RewardType.LP) {
                IWBNB(wbnb).withdraw(amount);
                uint256 lpAmount = StakingLPLib.convertBNBToLP(IAuthorizer(authorizer), amount);
                if (lpAmount > 0) {
                    reward.addToRewardPool(lpAmount, RewardType.LP);
                }
            } else if (currentType == RewardType.TOKEN) {
                uint256 tokenAmount = StakingLPLib.swapWBNBToToken(IAuthorizer(authorizer), amount);
                if (tokenAmount > 0) {
                    reward.addToRewardPool(tokenAmount, RewardType.TOKEN);
                }
            } else {
                IWBNB(wbnb).withdraw(amount);
                reward.addToRewardPool(amount, RewardType.BNB);
            }
        } else if (token == mainToken) {
            if (currentType == RewardType.LP) {
                uint256 lpAmount = StakingLPLib.convertTokenToLP(IAuthorizer(authorizer), amount);
                if (lpAmount > 0) {
                    reward.addToRewardPool(lpAmount, RewardType.LP);
                }
            } else if (currentType == RewardType.TOKEN) {
                reward.addToRewardPool(amount, RewardType.TOKEN);
            } else {
                uint256 bnbAmount = StakingLPLib.swapTokenToBNB(IAuthorizer(authorizer), amount);
                if (bnbAmount > 0) {
                    reward.addToRewardPool(bnbAmount, RewardType.BNB);
                }
            }
        } else {
            uint256 bnbAmount = StakingLPLib.swapTokenToBNB(IAuthorizer(authorizer), amount);
            if (bnbAmount > 0) {
                _getStakingLPReward().addToRewardPool(bnbAmount, RewardType.BNB);
            }
        }
    }

    function compoundFees() external onlyOwner whenNotPaused {
        StakingLPLib.compoundFees(IAuthorizer(authorizer));
        emit FeesCompounded(0);
    }

    function migrateLP(uint8 oldDexType, uint8 newDexType, uint256 lpAmount) public onlyOwner nonReentrant whenNotPaused returns (uint256) {
        return _migrateLPInternal(oldDexType, newDexType, lpAmount);
    }

    function _migrateLPInternal(uint8 oldDexType, uint8 newDexType, uint256 lpAmount) private returns (uint256) {
        IStakingLPReward reward = _getStakingLPReward();
        StakingLPLib.RewardPoolState memory state = StakingLPLib.RewardPoolState({
            lpRewardPoolBalance: reward.lpRewardPoolBalance(),
            tokenRewardPoolBalance: 0,
            bnbRewardPoolBalance: 0,
            totalWeightedNFTs: 0,
            globalRewardPerWeight: 0,
            stakingRewardPrecision: 0,
            rewardType: RewardType.LP,
            todayStart: 0,
            rewardRate: 0,
            maxRewardRate: 0,
            maxDailyRewardPercent: 0,
            rateStep: 0,
            todayRewardAmount: 0,
            todayIncomingTokens: 0,
            rewardPrecision: 0
        });
        
        uint256 newLPAmount;
        (state, newLPAmount) = StakingLPLib.migrateLP(state, IAuthorizer(authorizer), oldDexType, newDexType, lpAmount);
        _updatePoolState(reward, state);
        
        emit LPMigrated(oldDexType, newDexType, lpAmount, newLPAmount);
        return newLPAmount;
    }

    function _updatePoolState(IStakingLPReward reward, StakingLPLib.RewardPoolState memory state) private {
        reward.setPoolState(
            state.lpRewardPoolBalance,
            state.tokenRewardPoolBalance,
            state.bnbRewardPoolBalance,
            state.totalWeightedNFTs,
            state.globalRewardPerWeight,
            state.todayStart,
            state.rewardRate,
            state.todayRewardAmount,
            state.todayIncomingTokens
        );
    }

    function emergencyWithdrawWBNB(uint256 amount) external onlyOwner nonReentrant {
        StakingLPLib.emergencyWithdrawWBNB(IAuthorizer(authorizer), amount);
        emit EmergencyWBNBWithdrawn(msg.sender, owner(), amount);
    }

    function setSlippage(uint256 __slippage) external onlyOwner {
        if (__slippage == 0 || __slippage > 10000) revert InvalidParam();
        _slippage = __slippage;
    }

    function withdrawToken(address token, address to) external onlyOwner {
        if (token == address(0)) revert InvalidParam();
        if (to == address(0)) revert InvalidParam();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
        }
    }

    function withdrawBNB(address to) external onlyOwner {
        if (to == address(0)) revert InvalidParam();
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(to).call{value: balance}("");
            if (!success) revert SLP_BNBTransferFailed();
        }
    }

    function redeemLPToUser(uint256 lpAmount, address user) external onlyOwnerOrAuthorizer {
        StakingLPLib.redeemLPToUser(IAuthorizer(authorizer), lpAmount, user);
    }

    receive() external payable {
        if (msg.value > 0) {
            _recordIncomingBNB(msg.value);
        }
    }
}