// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

error ZeroAddress();
error InvalidAmount();
error InvalidRatio();
error InvalidFee();
error NotOperator();
error InsufficientBalance();
error Overflow();

contract PoolManager is 
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    IPoolManager
{
    uint256 public constant BPS = 10000;
    
    struct Pools {
        uint128 ownerPool;
        uint128 nftStakingPool;
        uint128 arenaPool;
        uint128 tokenStakingPool;
    }
    
    Pools public pools;
    
    uint256 public ownerRatio;
    uint256 public nftStakingRatio;
    uint256 public arenaRatio;
    uint256 public tokenStakingRatio;
    uint256 public dividendRatio;
    
    uint256 public swapFeeRate;
    uint256 public dividendFeeRate;
    
    address public routerContract;
    address public wbnbContract;
    address public tokenContract;
    
    address public nftStakingContract;
    address public tokenStakingContract;
    address public arenaContract;
    address public rewardManager;
    
    event PoolDistributed(uint256 totalAmount, uint256 ownerAmount, uint256 stakingAmount, uint256 arenaAmount, uint256 tokenStakingAmount, uint256 timestamp);
    event PoolWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event TokenSwapped(uint256 amountIn, uint256 amountOut, uint256 timestamp);
    
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        
        ownerRatio = 500;
        nftStakingRatio = 2500;
        arenaRatio = 1500;
        tokenStakingRatio = 1000;
        dividendRatio = 4500;
        
        swapFeeRate = 30;
        dividendFeeRate = 100;
    }
    
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    modifier onlyOperator() {
        bool isAuthorized = msg.sender == rewardManager || msg.sender == owner();
        if (!isAuthorized) revert NotOperator();
        _;
    }
    
    function setRewardManager(address _rewardManager) external onlyOwner {
        if (_rewardManager == address(0)) revert ZeroAddress();
        rewardManager = _rewardManager;
    }
    
    function setRouterContract(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        routerContract = _router;
    }
    
    function setWbnbContract(address _wbnb) external onlyOwner {
        if (_wbnb == address(0)) revert ZeroAddress();
        wbnbContract = _wbnb;
    }
    
    function setTokenContract(address _token) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();
        tokenContract = _token;
    }
    
    function setNftStakingContract(address _nftStaking) external onlyOwner {
        if (_nftStaking == address(0)) revert ZeroAddress();
        nftStakingContract = _nftStaking;
    }
    
    function setTokenStakingContract(address _tokenStaking) external onlyOwner {
        if (_tokenStaking == address(0)) revert ZeroAddress();
        tokenStakingContract = _tokenStaking;
    }
    
    function setArenaContract(address _arena) external onlyOwner {
        if (_arena == address(0)) revert ZeroAddress();
        arenaContract = _arena;
    }
    
    function setRatios(
        uint256 _ownerRatio,
        uint256 _nftStakingRatio,
        uint256 _arenaRatio,
        uint256 _tokenStakingRatio,
        uint256 _dividendRatio
    ) external onlyOwner {
        if (_ownerRatio + _nftStakingRatio + _arenaRatio + _tokenStakingRatio + _dividendRatio != BPS) {
            revert InvalidRatio();
        }
        
        ownerRatio = _ownerRatio;
        nftStakingRatio = _nftStakingRatio;
        arenaRatio = _arenaRatio;
        tokenStakingRatio = _tokenStakingRatio;
        dividendRatio = _dividendRatio;
    }
    
    function setSwapFeeRate(uint256 _swapFeeRate) external onlyOwner {
        if (_swapFeeRate > 1000) revert InvalidFee();
        swapFeeRate = _swapFeeRate;
    }
    
    function setDividendFeeRate(uint256 _dividendFeeRate) external onlyOwner {
        if (_dividendFeeRate > 1000) revert InvalidFee();
        dividendFeeRate = _dividendFeeRate;
    }
    
    function deposit() external payable {
        if (msg.value == 0) revert InvalidAmount();
    }
    
    function _processPools(uint256 amount) internal {
        uint256 contractBalance = address(this).balance;
        if (contractBalance < amount) revert InsufficientBalance();
        
        uint256 ownerAmount = (amount * ownerRatio) / BPS;
        uint256 stakingAmount = (amount * nftStakingRatio) / BPS;
        uint256 arenaAmount = (amount * arenaRatio) / BPS;
        uint256 tokenStakingAmount = (amount * tokenStakingRatio) / BPS;
        uint256 dividendAmount = (amount * dividendRatio) / BPS;
        
        pools.ownerPool += uint128(ownerAmount);
        pools.nftStakingPool += uint128(stakingAmount);
        pools.arenaPool += uint128(arenaAmount);
        pools.tokenStakingPool += uint128(tokenStakingAmount);
        
        emit PoolDistributed(amount, ownerAmount, stakingAmount, arenaAmount, tokenStakingAmount, block.timestamp);
    }
    
    function withdrawOwnerDividend() external onlyOwner {
        uint256 amount = uint256(pools.ownerPool);
        if (amount == 0) revert InsufficientBalance();
        
        pools.ownerPool = 0;
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert InsufficientBalance();
        
        emit PoolWithdrawn(owner(), amount, block.timestamp);
    }
    
    function withdrawNftStakingPool() external onlyOperator {
        uint256 amount = uint256(pools.nftStakingPool);
        if (amount == 0) revert InsufficientBalance();
        
        pools.nftStakingPool = 0;
        
        (bool success, ) = payable(nftStakingContract).call{value: amount}("");
        if (!success) revert InsufficientBalance();
        
        emit PoolWithdrawn(nftStakingContract, amount, block.timestamp);
    }
    
    function withdrawArenaPool() external onlyOperator {
        uint256 amount = uint256(pools.arenaPool);
        if (amount == 0) revert InsufficientBalance();
        
        pools.arenaPool = 0;
        
        (bool success, ) = payable(arenaContract).call{value: amount}("");
        if (!success) revert InsufficientBalance();
        
        emit PoolWithdrawn(arenaContract, amount, block.timestamp);
    }
    
    function withdrawTokenStakingPool() external onlyOperator {
        uint256 amount = uint256(pools.tokenStakingPool);
        if (amount == 0) revert InsufficientBalance();
        
        pools.tokenStakingPool = 0;
        
        (bool success, ) = payable(tokenStakingContract).call{value: amount}("");
        if (!success) revert InsufficientBalance();
        
        emit PoolWithdrawn(tokenStakingContract, amount, block.timestamp);
    }
    
    function withdrawExtraFunds() external onlyOwner {
        uint256 totalPools = uint256(pools.ownerPool) + uint256(pools.nftStakingPool) + uint256(pools.arenaPool) + uint256(pools.tokenStakingPool);
        uint256 extraFunds = address(this).balance - totalPools;
        
        if (extraFunds == 0) revert InsufficientBalance();
        
        (bool success, ) = payable(owner()).call{value: extraFunds}("");
        if (!success) revert InsufficientBalance();
        
        emit PoolWithdrawn(owner(), extraFunds, block.timestamp);
    }
    
    function getTotalPoolAmount() external view returns (uint256) {
        return uint256(pools.ownerPool) + uint256(pools.nftStakingPool) + uint256(pools.arenaPool) + uint256(pools.tokenStakingPool);
    }
    
    function getPoolDetails() external view returns (uint256, uint256, uint256, uint256) {
        return (
            uint256(pools.ownerPool),
            uint256(pools.nftStakingPool),
            uint256(pools.arenaPool),
            uint256(pools.tokenStakingPool)
        );
    }
    
    function _tryAutoSwapAndStake(uint256 amount, address targetContract) internal {
        if (routerContract == address(0) || wbnbContract == address(0) || tokenContract == address(0)) {
            return;
        }
        
        uint256 feeAmount = (amount * swapFeeRate) / BPS;
        uint256 swapAmount = amount - feeAmount;
        
        bytes memory data = abi.encodeWithSignature(
            "swapExactETHForTokens(uint256,address[],address,uint256)",
            0,
            [wbnbContract, tokenContract],
            address(this),
            block.timestamp + 300
        );
        
        (bool success, ) = routerContract.call{value: swapAmount}(data);
        if (success) {
            uint256 tokenBalance = IERC20(tokenContract).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(tokenContract).transfer(targetContract, tokenBalance);
            }
            emit TokenSwapped(swapAmount, tokenBalance, block.timestamp);
        }
    }
    
    function receiveEther() external payable {
    }
    
    receive() external payable {
    }
}