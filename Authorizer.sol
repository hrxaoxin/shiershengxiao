// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

/**
 * @title Authorizer
 * @dev 合约授权管理器，负责管理系统中所有合约地址和权限控制
 *
 * 核心职责：
 * 1. 地址注册表：集中维护系统所有核心合约的地址，供其他合约查询
 * 2. 授权控制：通过 onlyAuthorized / onlyOwner 等修饰器，
 *    限定业务合约（铸造、战斗、交易、繁殖）可调用"受保护函数"
 * 3. 地址更新：当某个合约升级或迁移时，由 owner 更新注册表，
 *    所有依赖合约立即生效（无需逐个合约调用 setAddress）
 *
 * 注册的地址（每个地址通过 setXxxContract 形式的接口写入）：
 * - nftContract / nftMintAddress：ERC721 NFT 主合约（NFTMint）
 * - nftDataAddress：NFT 元数据合约（NFTData）
 * - nftUpdateAddress：NFT 升级合约（NFTUpdate）
 * - metadataAddress / mintModuleAddress / upgradeModuleAddress：铸造/升级模块地址
 * - priceOracleAddress：价格预言机合约（PriceOracle）
 * - battleAddress：战斗合约（Battle）
 * - breedingAddress：繁殖合约（Breeding）
 * - stakingAddress：NFT 质押合约（Staking）
 * - tokenStakingAddress：代币质押合约（TokenStaking）
 * - rewardManagerAddress：奖励管理器（RewardManager）
 * - dividendManagerAddress：分红管理器（DividendManager）
 * - poolManagerAddress：资金池管理器（PoolManager）
 * - arenaRankingAddress：竞技场排名合约（ArenaRanking）
 * - tradingAddress：交易市场合约（NFTTrading）
 * - tokenBurnerAddress：代币销毁合约（TokenBurner）
 * - feeReceiver：手续费接收地址（通常为 owner 或多签钱包）
 * - tokenAddress：游戏代币合约地址（ERC20）
 * - usdtAddress：USDT 稳定币地址
 * - pancakeSwapPair：PancakeSwap 流动池地址（用于价格验证）
 * - authorizer：本合约自身地址
 *
 * 权限模型：
 * - onlyOwner：可以更新任意地址（部署时的部署者或多签钱包）
 * - 授权业务合约：在业务合约内部通过 ISetXxx 接口写入地址时
 *   由其自身的 onlyOwner 或授权修饰器保护
 *
 * 使用示例（在业务合约中）：
 *   address public authorizer;
 *   modifier onlyBattleContract() {
 *       require(msg.sender == Authorizer(authorizer).battleAddress(),
 *           "only battle");
 *       _;
 *   }
 *
 * 安全注意：
 * - owner 应使用多签钱包或时间锁（Timelock），以防止单点故障
 * - 地址更新应在前端/后端广播前进行充分测试，错误地址可能导致系统瘫痪
 * - 建议在测试网完成全流程后再在主网设置最终地址
 *
 * 升级与治理：
 * - UUPS 可升级：未来可以扩展新的地址字段或引入角色权限（Role-Based Access Control）
 * - 所有状态均为 storage，代理升级后数据保留
 */
contract Authorizer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    bool public paused;
    string public pauseReason;

    /**
     * @struct ContractAddresses
     * @dev 系统合约地址结构体，集中管理所有核心合约地址
     * @param tokenAddress - 游戏代币合约地址
     * @param usdtAddress - USDT代币合约地址
     * @param mintModuleAddress - 铸造模块地址
     * @param upgradeModuleAddress - 升级模块地址
     * @param priceOracleAddress - 价格预言机地址
     * @param battleAddress - 战斗合约地址
     * @param breedingAddress - 繁殖合约地址
     * @param stakingAddress - NFT质押合约地址
     * @param tokenStakingAddress - 代币质押合约地址
     * @param rewardManagerAddress - 奖励管理器地址
     * @param dividendManagerAddress - 分红管理器地址
     * @param poolManagerAddress - 池管理器地址
     * @param tradingAddress - 交易模块地址
     * @param arenaRankingAddress - 竞技场排名合约地址
     * @param nftMintAddress - NFT铸造合约地址
     * @param nftMintDelegatorAddress - NFT铸造代理地址
     * @param nftUpdateAddress - NFT升级合约地址
     * @param nftDataAddress - NFT数据合约地址
     * @param tokenBurnerAddress - 代币销毁器地址
     * @param weightManagerAddress - 权重管理器地址
     * @param battleHistoryAddress - 战斗历史合约地址
     * @param nftTradingAddress - NFT交易合约地址
     * @param feeReceiverAddress - 费用接收地址
     * @param pancakeSwapPairAddress - PancakeSwap交易对地址
     * @param metadataContractAddress - 元数据合约地址
     */
    struct ContractAddresses {
        address tokenAddress;
        address usdtAddress;
        address mintModuleAddress;
        address upgradeModuleAddress;
        address priceOracleAddress;
        address battleAddress;
        address breedingCoreAddress;
        address breedingMarketAddress;
        address stakingAddress;
        address tokenStakingAddress;
        address rewardManagerAddress;
        address dividendManagerAddress;
        address poolManagerAddress;
        address tradingAddress;
        address arenaRankingAddress;
        address arenaRankingManagerAddress;
        address arenaRankingQueryAddress;
        address arenaRewardAddress;
        address arenaLeaderboardAddress;
        address arenaPlayerAddress;
        address arenaBattleAddress;
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

    event Paused(address account, string reason);
    event Unpaused(address account);

    /**
     * @dev 修饰器：确保合约未暂停
     */
    modifier whenNotPaused() {
        require(!paused, "Authorizer: Paused");
        _;
    }

    /**
     * @dev 暂停合约
     * @param reason - 暂停原因
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消暂停合约
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
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
    address public breedingCoreAddress;
    address public breedingMarketAddress;
    address public stakingAddress;
    address public tokenStakingAddress;
    address public rewardManagerAddress;
    address public dividendManagerAddress;
    address public poolManagerAddress;
    address public tradingAddress;
    address public arenaRankingAddress;
    address public arenaRankingManagerAddress;
    address public arenaRankingQueryAddress;
    address public arenaRewardAddress;
    address public arenaLeaderboardAddress;
    address public arenaPlayerAddress;
    address public arenaBattleAddress;
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
    event ContractSetupFailed(string contractName, string errorMessage);
    event ContractSetupSuccess(string contractName);

    /**
     * @dev 初始化函数，设置合约部署者为管理员
     */
    function initialize() external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        admin = msg.sender;
    }

    /**
     * @dev UUPS升级授权函数，仅允许合约所有者升级
     * @param newImplementation - 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    event WeightGranted(address indexed user, uint256 weight);
    event WeightRevoked(address indexed user);
    event WeightsUpdated(address[] users, uint256[] weights);

    /**
     * @dev 为用户授予权限权重
     * @param user - 用户地址
     * @param weight - 权限权重值
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
     * @dev 撤销用户的权限
     * @param user - 用户地址
     */
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

    /**
     * @dev 检查用户是否具有足够的权限
     * @param user - 用户地址
     * @param weightRequired - 所需权限权重
     * @return bool - 是否具有足够权限
     */
    function hasPermission(address user, uint256 weightRequired) external view returns (bool) {
        return weights[user] >= weightRequired;
    }

    /**
     * @dev 获取用户的权限权重
     * @param user - 用户地址
     * @return uint256 - 用户权限权重
     */
    function getWeight(address user) external view returns (uint256) {
        return weights[user];
    }

    /**
     * @dev 获取系统总权限权重
     * @return uint256 - 总权重
     */
    function getTotalWeight() external view returns (uint256) {
        return totalWeight;
    }

    /**
     * @dev 批量更新用户权限权重
     * @param users - 用户地址数组
     * @param newWeights - 新权重数组
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
     * @dev 设置管理员地址
     * @param _admin - 新管理员地址
     */
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Authorizer: Invalid admin address");
        admin = _admin;
    }

    /**
     * @dev 更新所有合约地址（立即生效）
     * @param _addresses - 新的合约地址配置
     */
    function setAllContracts(ContractAddresses calldata _addresses) external onlyOwner whenNotPaused {
        _setCoreAddresses(_addresses);
        _setNFTAddresses(_addresses);
        _setOtherAddresses(_addresses);

        _setupBattleAndBreeding(_addresses.battleAddress, _addresses.breedingCoreAddress, _addresses.breedingMarketAddress, _addresses.nftMintAddress);
        _setupStakingAndReward(_addresses.stakingAddress, _addresses.rewardManagerAddress, _addresses.dividendManagerAddress, _addresses.tokenStakingAddress, _addresses.tokenAddress, _addresses.arenaRankingAddress, _addresses.nftMintAddress);
        _setupPriceAndUpgrade(_addresses.priceOracleAddress, _addresses.upgradeModuleAddress, _addresses.tokenAddress, _addresses.usdtAddress);
        _setupNFTContracts(_addresses.nftUpdateAddress, _addresses.tokenBurnerAddress, _addresses.nftMintAddress, _addresses.metadataContractAddress, _addresses.pancakeSwapPairAddress);
        _setupOtherContracts(_addresses.weightManagerAddress, _addresses.battleHistoryAddress, _addresses.nftTradingAddress, _addresses.feeReceiverAddress, _addresses.arenaRankingAddress, _addresses.arenaRankingManagerAddress, _addresses.arenaRankingQueryAddress, _addresses.rewardManagerAddress, _addresses.arenaRewardAddress, _addresses.arenaLeaderboardAddress, _addresses.arenaPlayerAddress, _addresses.arenaBattleAddress);

        _emitContractAddressesUpdated();
    }

    /**
     * @dev 配置战斗和繁殖合约
     * @param _battleAddress - 战斗合约地址
     * @param _breedingCoreAddress - 繁殖核心合约地址
     * @param _breedingMarketAddress - 繁殖市场合约地址
     * @param _nftMintAddress - NFT铸造合约地址
     */
    function _setupBattleAndBreeding(
        address _battleAddress,
        address _breedingCoreAddress,
        address _breedingMarketAddress,
        address _nftMintAddress
    ) internal {
        if (_battleAddress != address(0)) {
            try ISetNFTContract(_battleAddress).setNFTContract(_nftMintAddress) {
                emit ContractSetupSuccess("Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Battle", reason);
            } catch {
                emit ContractSetupFailed("Battle", "Unknown error");
            }
        }
        if (_breedingCoreAddress != address(0)) {
            try ISetNFTContract(_breedingCoreAddress).setNFTContract(_nftMintAddress) {
                emit ContractSetupSuccess("BreedingCore-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingCore-NFT", reason);
            } catch {
                emit ContractSetupFailed("BreedingCore-NFT", "Unknown error");
            }
            
            try ISetTokenContract(_breedingCoreAddress).setTokenContract(tokenAddress) {
                emit ContractSetupSuccess("BreedingCore-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingCore-Token", reason);
            } catch {
                emit ContractSetupFailed("BreedingCore-Token", "Unknown error");
            }

            try IBreedingMarket(_breedingMarketAddress).setBreedingCore(_breedingCoreAddress) {
                emit ContractSetupSuccess("BreedingMarket-Core");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingMarket-Core", reason);
            } catch {
                emit ContractSetupFailed("BreedingMarket-Core", "Unknown error");
            }

            if (_nftMintAddress != address(0)) {
                try ISetBreedingContract(_nftMintAddress).setBreedingContract(_breedingCoreAddress) {
                    emit ContractSetupSuccess("NFTMint-Breeding");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTMint-Breeding", reason);
                } catch {
                    emit ContractSetupFailed("NFTMint-Breeding", "Unknown error");
                }
            }
        }
    }

    /**
     * @dev 配置质押和奖励相关合约
     * @param _stakingAddress - NFT质押合约地址
     * @param _rewardManagerAddress - 奖励管理器地址
     * @param _dividendManagerAddress - 分红管理器地址
     * @param _tokenStakingAddress - 代币质押合约地址
     * @param _tokenAddress - 游戏代币地址
     * @param _arenaRankingAddress - 竞技场排名合约地址
     * @param _nftMintAddress - NFT铸造合约地址
     */
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
            ISetRewardManagerContract(_dividendManagerAddress).setRewardManagerContract(_rewardManagerAddress);
        }
        if (_tokenStakingAddress != address(0)) {
            ISetTokenAddress(_tokenStakingAddress).setTokenAddress(_tokenAddress);
        }
        if (poolManagerAddress != address(0)) {
            ISetPoolManager(_rewardManagerAddress).setPoolManager(poolManagerAddress);
        }
    }

    /**
     * @dev 配置价格预言机和升级模块
     * @param _priceOracleAddress - 价格预言机地址
     * @param _upgradeModuleAddress - 升级模块地址
     * @param _tokenAddress - 游戏代币地址
     * @param _usdtAddress - USDT代币地址
     */
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
        }
    }

    /**
     * @dev 配置NFT相关合约
     * @param _nftUpdateAddress - NFT升级合约地址
     * @param _tokenBurnerAddress - 代币销毁器地址
     * @param _nftMintAddress - NFT铸造合约地址
     * @param _metadataContractAddress - 元数据合约地址
     * @param _pancakeSwapPairAddress - PancakeSwap交易对地址
     */
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
            if (dividendManagerAddress != address(0)) {
                ISetNFTUpdateContract(dividendManagerAddress).setNFTUpdateContract(_nftUpdateAddress);
            }
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

    /**
     * @dev 配置其他合约
     * @param _weightManagerAddress - 权重管理器地址
     * @param _battleHistoryAddress - 战斗历史合约地址
     * @param _nftTradingAddress - NFT交易合约地址
     * @param _feeReceiverAddress - 费用接收地址
     * @param _arenaRankingAddress - 竞技场排名合约地址
     * @param _rewardManagerAddress - 奖励管理器地址
     * @param _arenaRewardAddress - 竞技场奖励合约地址
     * @param _arenaLeaderboardAddress - 竞技场排行榜合约地址
     * @param _arenaPlayerAddress - 竞技场玩家合约地址
     * @param _arenaBattleAddress - 竞技场战斗合约地址
     */
    function _setupOtherContracts(
        address _weightManagerAddress,
        address _battleHistoryAddress,
        address _nftTradingAddress,
        address _feeReceiverAddress,
        address _arenaRankingAddress,
        address _arenaRankingManagerAddress,
        address _arenaRankingQueryAddress,
        address _rewardManagerAddress,
        address _arenaRewardAddress,
        address _arenaLeaderboardAddress,
        address _arenaPlayerAddress,
        address _arenaBattleAddress
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
        if (_arenaRankingManagerAddress != address(0)) {
            ISetTokenContract(_arenaRankingManagerAddress).setTokenContract(tokenAddress);
            ISetRewardPool(_arenaRankingManagerAddress).setRewardPool(_rewardManagerAddress);
            ISetBattleContract(_arenaRankingManagerAddress).setBattleContract(battleAddress);
            if (_arenaRewardAddress != address(0)) {
                ISetArenaRewardContract(_arenaRankingManagerAddress).setArenaRewardContract(_arenaRewardAddress);
            }
            if (_arenaLeaderboardAddress != address(0)) {
                ISetArenaLeaderboardContract(_arenaRankingManagerAddress).setArenaLeaderboardContract(_arenaLeaderboardAddress);
            }
            if (_arenaPlayerAddress != address(0)) {
                ISetArenaPlayerContract(_arenaRankingManagerAddress).setArenaPlayerContract(_arenaPlayerAddress);
            }
            if (_arenaBattleAddress != address(0)) {
                ISetArenaBattleContract(_arenaRankingManagerAddress).setArenaBattleContract(_arenaBattleAddress);
            }
        }
        if (_arenaRankingQueryAddress != address(0)) {
            if (_arenaRewardAddress != address(0)) {
                ISetArenaRewardContract(_arenaRankingQueryAddress).setArenaRewardContract(_arenaRewardAddress);
            }
            if (_arenaLeaderboardAddress != address(0)) {
                ISetArenaLeaderboardContract(_arenaRankingQueryAddress).setArenaLeaderboardContract(_arenaLeaderboardAddress);
            }
        }
        if (_arenaRewardAddress != address(0)) {
            ISetRankingContract(_arenaRewardAddress).setRankingContract(_arenaRankingManagerAddress != address(0) ? _arenaRankingManagerAddress : _arenaRankingAddress);
        }
        if (_arenaLeaderboardAddress != address(0)) {
            ISetRankingContract(_arenaLeaderboardAddress).setRankingContract(_arenaRankingManagerAddress != address(0) ? _arenaRankingManagerAddress : _arenaRankingAddress);
        }
        if (_arenaPlayerAddress != address(0)) {
            ISetRankingContract(_arenaPlayerAddress).setRankingContract(_arenaRankingManagerAddress != address(0) ? _arenaRankingManagerAddress : _arenaRankingAddress);
            ISetNFTContract(_arenaPlayerAddress).setNFTContract(nftMintAddress);
        }
        if (_arenaBattleAddress != address(0)) {
            ISetRankingContract(_arenaBattleAddress).setRankingContract(_arenaRankingManagerAddress != address(0) ? _arenaRankingManagerAddress : _arenaRankingAddress);
            ISetBattleContract(_arenaBattleAddress).setBattleContract(battleAddress);
            ISetNFTContract(_arenaBattleAddress).setNFTContract(nftMintAddress);
        }
    }

    /**
     * @dev 设置核心合约地址
     * @param _addresses - 合约地址配置
     */
    function _setCoreAddresses(ContractAddresses calldata _addresses) internal {
        tokenAddress = _addresses.tokenAddress;
        usdtAddress = _addresses.usdtAddress;
        battleAddress = _addresses.battleAddress;
        breedingCoreAddress = _addresses.breedingCoreAddress;
        breedingMarketAddress = _addresses.breedingMarketAddress;
        stakingAddress = _addresses.stakingAddress;
        rewardManagerAddress = _addresses.rewardManagerAddress;
        dividendManagerAddress = _addresses.dividendManagerAddress;
        priceOracleAddress = _addresses.priceOracleAddress;
        upgradeModuleAddress = _addresses.upgradeModuleAddress;
    }

    /**
     * @dev 设置NFT相关合约地址
     * @param _addresses - 合约地址配置
     */
    function _setNFTAddresses(ContractAddresses calldata _addresses) internal {
        nftUpdateAddress = _addresses.nftUpdateAddress;
        tokenBurnerAddress = _addresses.tokenBurnerAddress;
        nftMintAddress = _addresses.nftMintAddress;
        nftMintDelegatorAddress = _addresses.nftMintDelegatorAddress;
        weightManagerAddress = _addresses.weightManagerAddress;
        battleHistoryAddress = _addresses.battleHistoryAddress;
        nftTradingAddress = _addresses.nftTradingAddress;
        arenaRankingAddress = _addresses.arenaRankingAddress;
        arenaRankingManagerAddress = _addresses.arenaRankingManagerAddress;
        arenaRankingQueryAddress = _addresses.arenaRankingQueryAddress;
        arenaRewardAddress = _addresses.arenaRewardAddress;
        arenaLeaderboardAddress = _addresses.arenaLeaderboardAddress;
        arenaPlayerAddress = _addresses.arenaPlayerAddress;
        arenaBattleAddress = _addresses.arenaBattleAddress;
        tokenStakingAddress = _addresses.tokenStakingAddress;
    }

    /**
     * @dev 设置其他合约地址
     * @param _addresses - 合约地址配置
     */
    function _setOtherAddresses(ContractAddresses calldata _addresses) internal {
        mintModuleAddress = _addresses.mintModuleAddress;
        poolManagerAddress = _addresses.poolManagerAddress;
        tradingAddress = _addresses.tradingAddress;
        nftDataAddress = _addresses.nftDataAddress;
        feeReceiverAddress = _addresses.feeReceiverAddress;
        pancakeSwapPairAddress = _addresses.pancakeSwapPairAddress;
        metadataContractAddress = _addresses.metadataContractAddress;
    }

    /**
     * @dev 触发合约地址更新事件
     */
    function _emitContractAddressesUpdated() internal {
        address[] memory addrs = new address[](21);
        _fillAddressesPart1(addrs);
        _fillAddressesPart2(addrs);
        emit ContractAddressesUpdated(addrs);
    }

    /**
     * @dev 填充地址数组第一部分
     * @param addrs - 地址数组
     */
    function _fillAddressesPart1(address[] memory addrs) internal view {
        addrs[0] = tokenAddress;
        addrs[1] = usdtAddress;
        addrs[2] = battleAddress;
        addrs[3] = breedingCoreAddress;
        addrs[4] = breedingMarketAddress;
        addrs[5] = stakingAddress;
        addrs[6] = rewardManagerAddress;
        addrs[7] = dividendManagerAddress;
        addrs[8] = priceOracleAddress;
        addrs[9] = upgradeModuleAddress;
        addrs[10] = nftUpdateAddress;
    }

    /**
     * @dev 填充地址数组第二部分
     * @param addrs - 地址数组
     */
    function _fillAddressesPart2(address[] memory addrs) internal view {
        addrs[11] = tokenBurnerAddress;
        addrs[12] = nftMintAddress;
        addrs[13] = weightManagerAddress;
        addrs[14] = battleHistoryAddress;
        addrs[15] = nftTradingAddress;
        addrs[16] = arenaRankingAddress;
        addrs[17] = tokenStakingAddress;
        addrs[18] = feeReceiverAddress;
        addrs[19] = pancakeSwapPairAddress;
        addrs[20] = metadataContractAddress;
    }

    /**
     * @dev 同步所有合约地址配置（用于紧急修复）
     */
    function syncContractAddresses() external onlyOwner whenNotPaused {
        _setupBattleAndBreeding(battleAddress, breedingCoreAddress, breedingMarketAddress, nftMintAddress);
        _setupStakingAndReward(stakingAddress, rewardManagerAddress, dividendManagerAddress, tokenStakingAddress, tokenAddress, arenaRankingAddress, nftMintAddress);
        _setupPriceAndUpgrade(priceOracleAddress, upgradeModuleAddress, tokenAddress, usdtAddress);
        _setupNFTContracts(nftUpdateAddress, tokenBurnerAddress, nftMintAddress, metadataContractAddress, pancakeSwapPairAddress);
        _setupOtherContracts(weightManagerAddress, battleHistoryAddress, nftTradingAddress, feeReceiverAddress, arenaRankingAddress, arenaRankingManagerAddress, arenaRankingQueryAddress, rewardManagerAddress, arenaRewardAddress, arenaLeaderboardAddress, arenaPlayerAddress, arenaBattleAddress);
    }

    /**
     * @dev 接收 BNB - 防止用户误转 BNB 到本合约后永久锁定
     */
    receive() external payable {}

    /**
     * @dev Fallback 函数 - 处理未匹配的调用
     */
    fallback() external payable {}
}