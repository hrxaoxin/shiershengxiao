// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

/**
 * @title Authorizer
 * @dev 权限管理合约，基于权重系统控制访问权限
 *
 * 权限系统：
 * 1. 每个用户有权重值
 * 2. 操作需要满足最小权重要求
 * 3. 支持批量更新权重
 *
 * 权重用途：
 * - 高级操作权限
 * - 分红权重计算
 * - 投票权重
 */
contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 用户权重映射
     */
    mapping(address => uint256) public weights;

    /**
     * @dev 总权重
     */
    uint256 public totalWeight;

    /**
     * @dev 管理员地址
     */
    address public admin;

    // 关联合约地址
    struct ContractAddresses {
        address tokenAddress;
        address usdtAddress;
        address mintModuleAddress;
        address upgradeModuleAddress;
        address priceOracleAddress;
        address battleAddress;
        address breedingAddress;
        address stakingAddress;
        address tokenStakingAddress;
        address rewardManagerAddress;
        address dividendManagerAddress;
        address poolManagerAddress;
        address tradingAddress;
        address arenaRankingAddress;
        address nftMintAddress;
        address nftMintDelegatorAddress;
        address nftUpdateAddress;
        address nftDataAddress;
        address tokenBurnerAddress;
        address weightManagerAddress;
        address battleHistoryAddress;
        address nftTradingAddress;
        address authorizerAddress;
        address feeReceiverAddress;
        address pancakeSwapPairAddress;
        address metadataContractAddress;
    }

    /**
     * @dev 存储的关联合约地址
     */
    ContractAddresses public contractAddresses;

    /**
     * @dev 关联合约地址设置事件
     */
    event ContractAddressesUpdated(ContractAddresses newAddresses);

    /**
     * @dev 初始化函数
     */
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        admin = msg.sender;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 权重事件
     */
    event WeightGranted(address indexed user, uint256 weight);
    event WeightRevoked(address indexed user);
    event WeightsUpdated(address[] users, uint256[] weights);

    /**
     * @dev 授予权限
     */
    function grantPermission(address user, uint256 weight) external onlyOwner {
        if (weights[user] == 0) {
            totalWeight += weight;
        } else {
            totalWeight = totalWeight - weights[user] + weight;
        }

        weights[user] = weight;
        emit WeightGranted(user, weight);
    }

    /**
     * @dev 撤销权限
     */
    function revokePermission(address user) external onlyOwner {
        totalWeight -= weights[user];
        weights[user] = 0;
        emit WeightRevoked(user);
    }

    /**
     * @dev 检查是否有权限
     */
    function hasPermission(address user, uint256 weightRequired) external view returns (bool) {
        return weights[user] >= weightRequired;
    }

    /**
     * @dev 获取用户权重
     */
    function getWeight(address user) external view returns (uint256) {
        return weights[user];
    }

    /**
     * @dev 获取总权重
     */
    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    /**
     * @dev 批量更新权重
     */
    function updateWeightsBatch(
        address[] calldata users,
        uint256[] calldata newWeights
    ) external onlyOwner {
        require(users.length == newWeights.length, "Authorizer: Length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            if (weights[users[i]] > 0) {
                totalWeight = totalWeight - weights[users[i]] + newWeights[i];
            } else {
                totalWeight += newWeights[i];
            }
            weights[users[i]] = newWeights[i];
        }

        emit WeightsUpdated(users, newWeights);
    }

    /**
     * @dev 设置管理员（向后兼容）
     */
    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    /**
     * @dev 一键设置所有关联合约地址并同步到各合约
     * @param addresses 包含所有关联合约地址的结构体
     */
    function setAllContracts(ContractAddresses calldata addresses) external onlyOwner {
        // 保存地址到当前合约
        contractAddresses = addresses;
        
        // 设置各合约的关联合约
        _setupAllContracts(addresses);
        
        emit ContractAddressesUpdated(addresses);
    }

    /**
     * @dev 内部函数：设置各合约的关联合约
     * @param addresses 包含所有关联合约地址的结构体
     */
    function _setupAllContracts(ContractAddresses calldata addresses) internal {
        // 设置 Battle 合约
        if (addresses.battleAddress != address(0)) {
            ISetNFTContract(addresses.battleAddress).setNFTContract(addresses.nftMintAddress);
        }
        
        // 设置 Breeding 合约
        if (addresses.breedingAddress != address(0)) {
            ISetNFTContract(addresses.breedingAddress).setNFTContract(addresses.nftMintAddress);
        }
        
        // 设置 Staking 合约
        if (addresses.stakingAddress != address(0)) {
            ISetRewardTokenContract(addresses.stakingAddress).setRewardTokenContract(addresses.tokenAddress);
        }
        
        // 设置 RewardManager 合约
        if (addresses.rewardManagerAddress != address(0)) {
            ISetDividendPool(addresses.rewardManagerAddress).setDividendPool(addresses.dividendManagerAddress);
            ISetNFTStakingPool(addresses.rewardManagerAddress).setNFTStakingPool(addresses.stakingAddress);
            ISetTokenStakingPool(addresses.rewardManagerAddress).setTokenStakingPool(addresses.tokenStakingAddress);
            ISetTokenContract(addresses.rewardManagerAddress).setTokenContract(addresses.tokenAddress);
            ISetArenaRewardPool(addresses.rewardManagerAddress).setArenaRewardPool(addresses.arenaRankingAddress);
        }
        
        // 设置 PriceOracle 合约
        if (addresses.priceOracleAddress != address(0)) {
            ISetTokenAddress(addresses.priceOracleAddress).setTokenAddress(addresses.tokenAddress);
            ISetUSDTAddress(addresses.priceOracleAddress).setUSDTAddress(addresses.usdtAddress);
        }
        
        // 设置 UpgradeModule 合约
        if (addresses.upgradeModuleAddress != address(0)) {
            ISetUSDTAddress(addresses.upgradeModuleAddress).setUSDTAddress(addresses.usdtAddress);
        }
        
        // 设置 NFTUpdate 合约
        if (addresses.nftUpdateAddress != address(0)) {
            ISetNFTContract(addresses.nftUpdateAddress).setNFTContract(addresses.nftMintAddress);
            ISetMetadataContract(addresses.nftUpdateAddress).setMetadataContract(addresses.metadataContractAddress);
            ISetTokenContract(addresses.nftUpdateAddress).setTokenContract(addresses.tokenAddress);
            ISetPancakeSwapPair(addresses.nftUpdateAddress).setPancakeSwapPair(addresses.pancakeSwapPairAddress);
        }
        
        // 设置 TokenBurner 合约
        if (addresses.tokenBurnerAddress != address(0)) {
            ISetNFTContract(addresses.tokenBurnerAddress).setNFTContract(addresses.nftMintAddress);
            ISetAuthorizedNFTContract(addresses.tokenBurnerAddress).setAuthorizedNFTContract(addresses.nftMintAddress);
            ISetTokenContract(addresses.tokenBurnerAddress).setTokenContract(addresses.tokenAddress);
        }
        
        // 设置 NFTMint 合约
        if (addresses.nftMintAddress != address(0)) {
            ISetTokenBurner(addresses.nftMintAddress).setTokenBurner(addresses.tokenBurnerAddress);
        }
        
        // 设置 WeightManager 合约
        if (addresses.weightManagerAddress != address(0)) {
            ISetNFTDataContract(addresses.weightManagerAddress).setNFTDataContract(addresses.nftDataAddress);
        }
        
        // 设置 BattleHistory 合约
        if (addresses.battleHistoryAddress != address(0)) {
            ISetBattleContract(addresses.battleHistoryAddress).setBattleContract(addresses.battleAddress);
        }
        
        // 设置 NFTTrading 合约
        if (addresses.nftTradingAddress != address(0)) {
            ISetFeeReceiver(addresses.nftTradingAddress).setFeeReceiver(addresses.feeReceiverAddress);
        }
        
        // 设置 ArenaRanking 合约
        if (addresses.arenaRankingAddress != address(0)) {
            ISetTokenContract(addresses.arenaRankingAddress).setTokenContract(addresses.tokenAddress);
            ISetRewardPool(addresses.arenaRankingAddress).setRewardPool(addresses.rewardManagerAddress);
        }
    }

    /**
     * @dev 单独设置关联合约地址（不触发同步）
     * @param addresses 包含所有关联合约地址的结构体
     */
    function setContractAddresses(ContractAddresses calldata addresses) external onlyOwner {
        contractAddresses = addresses;
        emit ContractAddressesUpdated(addresses);
    }

    /**
     * @dev 从当前存储的地址同步到各合约
     */
    function syncContractAddresses() external onlyOwner {
        _setupAllContracts(contractAddresses);
    }
}
