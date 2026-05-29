// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

// ============ 接口定义 ============

interface ISetNFTContract {
    function setNFTContract(address _nftContract) external;
}

interface ISetRewardTokenContract {
    function setRewardTokenContract(address _tokenContract) external;
}

interface ISetDividendPool {
    function setDividendPool(address _dividendManager) external;
}

interface ISetNFTStakingPool {
    function setNFTStakingPool(address _stakingAddress) external;
}

interface ISetTokenStakingPool {
    function setTokenStakingPool(address _tokenStakingAddress) external;
}

interface ISetTokenContract {
    function setTokenContract(address _tokenContract) external;
}

interface ISetArenaRewardPool {
    function setArenaRewardPool(address _arenaRankingAddress) external;
}

interface ISetTokenAddress {
    function setTokenAddress(address _tokenContract) external;
}

interface ISetUSDTAddress {
    function setUSDTAddress(address _usdtAddress) external;
}

interface ISetMetadataContract {
    function setMetadataContract(address _metadataAddress) external;
}

interface ISetPancakeSwapPair {
    function setPancakeSwapPair(address _pairAddress) external;
}

interface ISetAuthorizedNFTContract {
    function setAuthorizedNFTContract(address _nftContract) external;
}

interface ISetTokenBurner {
    function setTokenBurner(address _tokenBurner) external;
}

interface ISetNFTDataContract {
    function setNFTDataContract(address _nftDataAddress) external;
}

interface ISetBattleContract {
    function setBattleContract(address _battleAddress) external;
}

interface ISetFeeReceiver {
    function setFeeReceiver(address _feeReceiver) external;
}

interface ISetRewardPool {
    function setRewardPool(address _rewardPool) external;
}

interface ISetPoolManager {
    function setPoolManager(address _poolManager) external;
}

contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
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
        address feeReceiverAddress;
        address pancakeSwapPairAddress;
        address metadataContractAddress;
    }

    mapping(address => uint256) public weights;
    uint256 public totalWeight;
    address public admin;

    address public tokenAddress;
    address public usdtAddress;
    address public mintModuleAddress;
    address public upgradeModuleAddress;
    address public priceOracleAddress;
    address public battleAddress;
    address public breedingAddress;
    address public stakingAddress;
    address public tokenStakingAddress;
    address public rewardManagerAddress;
    address public dividendManagerAddress;
    address public poolManagerAddress;
    address public tradingAddress;
    address public arenaRankingAddress;
    address public nftMintAddress;
    address public nftMintDelegatorAddress;
    address public nftUpdateAddress;
    address public nftDataAddress;
    address public tokenBurnerAddress;
    address public weightManagerAddress;
    address public battleHistoryAddress;
    address public nftTradingAddress;
    address public feeReceiverAddress;
    address public pancakeSwapPairAddress;
    address public metadataContractAddress;

    event ContractAddressesUpdated(address[] addresses);

    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        admin = msg.sender;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    event WeightGranted(address indexed user, uint256 weight);
    event WeightRevoked(address indexed user);
    event WeightsUpdated(address[] users, uint256[] weights);

    function grantPermission(address user, uint256 weight) external onlyOwner {
        if (weights[user] == 0) {
            totalWeight += weight;
        } else {
            totalWeight = totalWeight - weights[user] + weight;
        }
        weights[user] = weight;
        emit WeightGranted(user, weight);
    }

    function revokePermission(address user) external onlyOwner {
        uint256 w = weights[user];
        require(w > 0, "Authorizer: No permission to revoke");
        if (w >= totalWeight) {
            totalWeight = 0;
        } else {
            totalWeight -= w;
        }
        weights[user] = 0;
        emit WeightRevoked(user);
    }

    function hasPermission(address user, uint256 weightRequired) external view returns (bool) {
        return weights[user] >= weightRequired;
    }

    function getWeight(address user) external view returns (uint256) {
        return weights[user];
    }

    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

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

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    function setAllContracts(ContractAddresses calldata _addresses) external onlyOwner {
        _setCoreAddresses(_addresses);
        _setNFTAddresses(_addresses);
        _setOtherAddresses(_addresses);

        _setupBattleAndBreeding(_addresses.battleAddress, _addresses.breedingAddress, _addresses.nftMintAddress);
        _setupStakingAndReward(_addresses.stakingAddress, _addresses.rewardManagerAddress, _addresses.dividendManagerAddress, _addresses.tokenStakingAddress, _addresses.tokenAddress, _addresses.arenaRankingAddress, _addresses.nftMintAddress);
        _setupPriceAndUpgrade(_addresses.priceOracleAddress, _addresses.upgradeModuleAddress, _addresses.tokenAddress, _addresses.usdtAddress);
        _setupNFTContracts(_addresses.nftUpdateAddress, _addresses.tokenBurnerAddress, _addresses.nftMintAddress, _addresses.metadataContractAddress, _addresses.pancakeSwapPairAddress);
        _setupOtherContracts(_addresses.weightManagerAddress, _addresses.battleHistoryAddress, _addresses.nftTradingAddress, _addresses.feeReceiverAddress, _addresses.arenaRankingAddress, _addresses.rewardManagerAddress);

        _emitContractAddressesUpdated();
    }

    function _setupBattleAndBreeding(
        address _battleAddress,
        address _breedingAddress,
        address _nftMintAddress
    ) internal {
        if (_battleAddress != address(0)) {
            ISetNFTContract(_battleAddress).setNFTContract(_nftMintAddress);
        }
        if (_breedingAddress != address(0)) {
            ISetNFTContract(_breedingAddress).setNFTContract(_nftMintAddress);
            ISetTokenContract(_breedingAddress).setTokenContract(tokenAddress);
        }
    }

    function _setupStakingAndReward(
        address _stakingAddress,
        address _rewardManagerAddress,
        address _dividendManagerAddress,
        address _tokenStakingAddress,
        address _tokenAddress,
        address _arenaRankingAddress,
        address _nftMintAddress
    ) internal {
        if (_stakingAddress != address(0)) {
            ISetRewardTokenContract(_stakingAddress).setRewardTokenContract(_tokenAddress);
            ISetNFTContract(_stakingAddress).setNFTContract(_nftMintAddress);
        }
        if (_rewardManagerAddress != address(0)) {
            ISetDividendPool(_rewardManagerAddress).setDividendPool(_dividendManagerAddress);
            ISetNFTStakingPool(_rewardManagerAddress).setNFTStakingPool(_stakingAddress);
            ISetTokenStakingPool(_rewardManagerAddress).setTokenStakingPool(_tokenStakingAddress);
            ISetTokenContract(_rewardManagerAddress).setTokenContract(_tokenAddress);
            ISetArenaRewardPool(_rewardManagerAddress).setArenaRewardPool(_arenaRankingAddress);
        }
        if (_dividendManagerAddress != address(0)) {
            ISetTokenContract(_dividendManagerAddress).setTokenContract(_tokenAddress);
        }
        if (poolManagerAddress != address(0)) {
            ISetPoolManager(_rewardManagerAddress).setPoolManager(poolManagerAddress);
        }
        if (_tokenStakingAddress != address(0)) {
            ISetTokenAddress(_tokenStakingAddress).setTokenAddress(_tokenAddress);
        }
    }

    function _setupPriceAndUpgrade(
        address _priceOracleAddress,
        address _upgradeModuleAddress,
        address _tokenAddress,
        address _usdtAddress
    ) internal {
        if (_priceOracleAddress != address(0)) {
            ISetTokenAddress(_priceOracleAddress).setTokenAddress(_tokenAddress);
            ISetUSDTAddress(_priceOracleAddress).setUSDTAddress(_usdtAddress);
        }
        if (_upgradeModuleAddress != address(0)) {
            ISetUSDTAddress(_upgradeModuleAddress).setUSDTAddress(_usdtAddress);
        }
    }

    function _setupNFTContracts(
        address _nftUpdateAddress,
        address _tokenBurnerAddress,
        address _nftMintAddress,
        address _metadataContractAddress,
        address _pancakeSwapPairAddress
    ) internal {
        if (_nftUpdateAddress != address(0)) {
            ISetNFTContract(_nftUpdateAddress).setNFTContract(_nftMintAddress);
            ISetMetadataContract(_nftUpdateAddress).setMetadataContract(_metadataContractAddress);
            ISetTokenContract(_nftUpdateAddress).setTokenContract(tokenAddress);
            ISetPancakeSwapPair(_nftUpdateAddress).setPancakeSwapPair(_pancakeSwapPairAddress);
        }
        if (_tokenBurnerAddress != address(0)) {
            ISetNFTContract(_tokenBurnerAddress).setNFTContract(_nftMintAddress);
            ISetAuthorizedNFTContract(_tokenBurnerAddress).setAuthorizedNFTContract(_nftMintAddress);
            ISetTokenContract(_tokenBurnerAddress).setTokenContract(tokenAddress);
        }
        if (_nftMintAddress != address(0)) {
            ISetTokenBurner(_nftMintAddress).setTokenBurner(_tokenBurnerAddress);
        }
    }

    function _setupOtherContracts(
        address _weightManagerAddress,
        address _battleHistoryAddress,
        address _nftTradingAddress,
        address _feeReceiverAddress,
        address _arenaRankingAddress,
        address _rewardManagerAddress
    ) internal {
        if (_weightManagerAddress != address(0)) {
            ISetNFTDataContract(_weightManagerAddress).setNFTDataContract(nftDataAddress);
        }
        if (_battleHistoryAddress != address(0)) {
            ISetBattleContract(_battleHistoryAddress).setBattleContract(battleAddress);
        }
        if (_nftTradingAddress != address(0)) {
            ISetNFTContract(_nftTradingAddress).setNFTContract(nftMintAddress);
            ISetFeeReceiver(_nftTradingAddress).setFeeReceiver(_feeReceiverAddress);
        }
        if (_arenaRankingAddress != address(0)) {
            ISetTokenContract(_arenaRankingAddress).setTokenContract(tokenAddress);
            ISetRewardPool(_arenaRankingAddress).setRewardPool(_rewardManagerAddress);
            ISetBattleContract(_arenaRankingAddress).setBattleContract(battleAddress);
        }
    }

    function setContractAddresses(ContractAddresses calldata _addresses) external onlyOwner {
        _setCoreAddresses(_addresses);
        _setNFTAddresses(_addresses);
        _setOtherAddresses(_addresses);
        _emitContractAddressesUpdated();
    }

    function _setCoreAddresses(ContractAddresses calldata _addresses) internal {
        tokenAddress = _addresses.tokenAddress;
        usdtAddress = _addresses.usdtAddress;
        battleAddress = _addresses.battleAddress;
        breedingAddress = _addresses.breedingAddress;
        stakingAddress = _addresses.stakingAddress;
        rewardManagerAddress = _addresses.rewardManagerAddress;
        dividendManagerAddress = _addresses.dividendManagerAddress;
        priceOracleAddress = _addresses.priceOracleAddress;
        upgradeModuleAddress = _addresses.upgradeModuleAddress;
    }

    function _setNFTAddresses(ContractAddresses calldata _addresses) internal {
        nftUpdateAddress = _addresses.nftUpdateAddress;
        tokenBurnerAddress = _addresses.tokenBurnerAddress;
        nftMintAddress = _addresses.nftMintAddress;
        nftMintDelegatorAddress = _addresses.nftMintDelegatorAddress;
        weightManagerAddress = _addresses.weightManagerAddress;
        battleHistoryAddress = _addresses.battleHistoryAddress;
        nftTradingAddress = _addresses.nftTradingAddress;
        arenaRankingAddress = _addresses.arenaRankingAddress;
        tokenStakingAddress = _addresses.tokenStakingAddress;
    }

    function _setOtherAddresses(ContractAddresses calldata _addresses) internal {
        mintModuleAddress = _addresses.mintModuleAddress;
        poolManagerAddress = _addresses.poolManagerAddress;
        tradingAddress = _addresses.tradingAddress;
        nftDataAddress = _addresses.nftDataAddress;
        feeReceiverAddress = _addresses.feeReceiverAddress;
        pancakeSwapPairAddress = _addresses.pancakeSwapPairAddress;
        metadataContractAddress = _addresses.metadataContractAddress;
    }

    function _emitContractAddressesUpdated() internal {
        address[] memory addrs = new address[](20);
        _fillAddressesPart1(addrs);
        _fillAddressesPart2(addrs);
        emit ContractAddressesUpdated(addrs);
    }

    function _fillAddressesPart1(address[] memory addrs) internal view {
        addrs[0] = tokenAddress;
        addrs[1] = usdtAddress;
        addrs[2] = battleAddress;
        addrs[3] = breedingAddress;
        addrs[4] = stakingAddress;
        addrs[5] = rewardManagerAddress;
        addrs[6] = dividendManagerAddress;
        addrs[7] = priceOracleAddress;
        addrs[8] = upgradeModuleAddress;
        addrs[9] = nftUpdateAddress;
    }

    function _fillAddressesPart2(address[] memory addrs) internal view {
        addrs[10] = tokenBurnerAddress;
        addrs[11] = nftMintAddress;
        addrs[12] = weightManagerAddress;
        addrs[13] = battleHistoryAddress;
        addrs[14] = nftTradingAddress;
        addrs[15] = arenaRankingAddress;
        addrs[16] = tokenStakingAddress;
        addrs[17] = feeReceiverAddress;
        addrs[18] = pancakeSwapPairAddress;
        addrs[19] = metadataContractAddress;
    }

    function syncContractAddresses() external onlyOwner {
        _setupBattleAndBreeding(battleAddress, breedingAddress, nftMintAddress);
        _setupStakingAndReward(stakingAddress, rewardManagerAddress, dividendManagerAddress, tokenStakingAddress, tokenAddress, arenaRankingAddress, nftMintAddress);
        _setupPriceAndUpgrade(priceOracleAddress, upgradeModuleAddress, tokenAddress, usdtAddress);
        _setupNFTContracts(nftUpdateAddress, tokenBurnerAddress, nftMintAddress, metadataContractAddress, pancakeSwapPairAddress);
        _setupOtherContracts(weightManagerAddress, battleHistoryAddress, nftTradingAddress, feeReceiverAddress, arenaRankingAddress, rewardManagerAddress);
    }
}
