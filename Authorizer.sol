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
     * 
     * 分类说明：
     * 1. 代币合约：tokenAddress, usdtAddress
     * 2. NFT铸造相关：nftMintCoreAddress, nftMintBatchAddress, nftMintMetadataAddress
     * 3. NFT升级和数据：nftUpdateAddress, nftDataAddress
     * 4. 代币销毁和交易：tokenBurnerAddress, nftTradingAddress, nftBuybackAddress
     * 5. 质押相关：stakingAddress, tokenStakingAddress
     * 6. 奖励和分红：rewardManagerAddress, dividendManagerAddress, poolManagerAddress
     * 7. 价格预言机：priceOracleAddress
     * 8. 战斗相关：battleAddress, battleSkillDataAddress, battleHistoryAddress
     * 9. 繁殖相关：breedingCoreAddress, breedingMarketAddress
     * 10. 权重管理：weightManagerAddress
     * 11. 竞技场相关：arenaRankingManagerAddress, arenaRankingQueryAddress, arenaRewardAddress, arenaLeaderboardAddress, arenaPlayerAddress, arenaBattleAddress
     * 12. 其他：feeReceiverAddress, pancakeSwapRouterAddress
     */
    struct ContractAddresses {
        // ========== 代币合约 ==========
        address tokenAddress;              // 游戏代币合约地址（ERC20）
        address usdtAddress;               // USDT代币合约地址
        
        // ========== NFT铸造相关合约 ==========
        address nftMintCoreAddress;        // NFT铸造核心合约地址（NFTMintCore）
        address nftMintBatchAddress;       // NFT批量铸造合约地址（NFTMintBatch）
        address nftMintMetadataAddress;    // NFT元数据合约地址（NFTMintMetadata）
        
        // ========== NFT升级和数据合约 ==========
        address nftUpdateAddress;          // NFT升级合约地址（NFTUpdate）
        address nftDataAddress;            // NFT数据合约地址（NFTData）
        
        // ========== 代币销毁和交易合约 ==========
        address tokenBurnerAddress;        // 代币销毁合约地址（TokenBurner）
        address nftTradingAddress;         // NFT交易合约地址（NFTTrading）
        address nftBuybackAddress;         // NFT回购合约地址（NFTBuyback）
        
        // ========== 质押相关合约 ==========
        address stakingAddress;            // NFT质押合约地址（Staking）
        address tokenStakingAddress;       // 代币质押合约地址（TokenStaking）
        
        // ========== 奖励和分红合约 ==========
        address rewardManagerAddress;      // 奖励管理合约地址（RewardManager）
        address dividendManagerAddress;    // 分红管理合约地址（DividendManager）
        address poolManagerAddress;        // 资金池管理合约地址（PoolManager）
        
        // ========== 价格预言机 ==========
        address priceOracleAddress;        // 价格预言机合约地址（PriceOracle）
        
        // ========== 战斗相关合约 ==========
        address battleAddress;             // 战斗合约地址（Battle）
        address battleSkillDataAddress;    // 战斗技能数据合约地址（BattleSkillData）
        address battleHistoryAddress;      // 战斗历史合约地址（BattleHistory）
        
        // ========== 繁殖相关合约 ==========
        address breedingCoreAddress;       // 繁殖核心合约地址（BreedingCore）
        address breedingMarketAddress;     // 繁殖市场合约地址（BreedingMarket）
        
        // ========== 权重管理合约 ==========
        address weightManagerAddress;      // 权重管理合约地址（WeightManager）
        
        // ========== 竞技场相关合约 ==========
        address arenaRankingManagerAddress; // 竞技场排名管理合约地址（ArenaRankingManager）
        address arenaRankingQueryAddress;   // 竞技场排名查询合约地址（ArenaRankingQuery）
        address arenaRewardAddress;         // 竞技场奖励合约地址（ArenaReward）
        address arenaLeaderboardAddress;    // 竞技场排行榜合约地址（ArenaLeaderboard）
        address arenaPlayerAddress;         // 竞技场玩家合约地址（ArenaPlayer）
        address arenaBattleAddress;         // 竞技场战斗合约地址（ArenaBattle）
        
        // ========== 其他地址 ==========
        address feeReceiverAddress;        // 费用接收地址
        address pancakeSwapRouterAddress;  // PancakeSwap路由器地址
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

    // ========== 代币合约 ==========
    address public tokenAddress;              // 游戏代币合约地址（ERC20）
    address public usdtAddress;               // USDT代币合约地址
    
    // ========== NFT铸造相关合约 ==========
    address public nftMintCoreAddress;        // NFT铸造核心合约地址（NFTMintCore）
    address public nftMintBatchAddress;       // NFT批量铸造合约地址（NFTMintBatch）
    address public nftMintMetadataAddress;    // NFT元数据合约地址（NFTMintMetadata）
    
    // ========== NFT升级和数据合约 ==========
    address public nftUpdateAddress;          // NFT升级合约地址（NFTUpdate）
    address public nftDataAddress;            // NFT数据合约地址（NFTData）
    
    // ========== 代币销毁和交易合约 ==========
    address public tokenBurnerAddress;        // 代币销毁合约地址（TokenBurner）
    address public nftTradingAddress;         // NFT交易合约地址（NFTTrading）
    address public nftBuybackAddress;         // NFT回购合约地址（NFTBuyback）
    
    // ========== 质押相关合约 ==========
    address public stakingAddress;            // NFT质押合约地址（Staking）
    address public tokenStakingAddress;       // 代币质押合约地址（TokenStaking）
    
    // ========== 奖励和分红合约 ==========
    address public rewardManagerAddress;      // 奖励管理合约地址（RewardManager）
    address public dividendManagerAddress;    // 分红管理合约地址（DividendManager）
    address public poolManagerAddress;        // 资金池管理合约地址（PoolManager）
    
    // ========== 价格预言机 ==========
    address public priceOracleAddress;        // 价格预言机合约地址（PriceOracle）
    
    // ========== 战斗相关合约 ==========
    address public battleAddress;             // 战斗合约地址（Battle）
    address public battleSkillDataAddress;    // 战斗技能数据合约地址（BattleSkillData）
    address public battleHistoryAddress;      // 战斗历史合约地址（BattleHistory）
    
    // ========== 繁殖相关合约 ==========
    address public breedingCoreAddress;       // 繁殖核心合约地址（BreedingCore）
    address public breedingMarketAddress;     // 繁殖市场合约地址（BreedingMarket）
    
    // ========== 权重管理合约 ==========
    address public weightManagerAddress;      // 权重管理合约地址（WeightManager）
    
    // ========== 竞技场相关合约 ==========
    address public arenaRankingManagerAddress; // 竞技场排名管理合约地址（ArenaRankingManager）
    address public arenaRankingQueryAddress;   // 竞技场排名查询合约地址（ArenaRankingQuery）
    address public arenaRewardAddress;         // 竞技场奖励合约地址（ArenaReward）
    address public arenaLeaderboardAddress;    // 竞技场排行榜合约地址（ArenaLeaderboard）
    address public arenaPlayerAddress;         // 竞技场玩家合约地址（ArenaPlayer）
    address public arenaBattleAddress;         // 竞技场战斗合约地址（ArenaBattle）
    
    // ========== 其他地址 ==========
    address public feeReceiverAddress;        // 费用接收地址
    address public pancakeSwapRouterAddress;  // PancakeSwap路由器地址

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
        _setArenaAddresses(_addresses);
        _setOtherAddresses(_addresses);

        _setupBattleAndBreeding(_addresses.battleAddress, _addresses.breedingCoreAddress, _addresses.breedingMarketAddress, _addresses.nftMintCoreAddress, _addresses.stakingAddress);
        _setupStakingAndReward(_addresses.stakingAddress, _addresses.rewardManagerAddress, _addresses.dividendManagerAddress, _addresses.tokenStakingAddress, _addresses.tokenAddress, _addresses.arenaRankingManagerAddress, _addresses.nftMintCoreAddress, _addresses.nftBuybackAddress, _addresses.nftUpdateAddress, _addresses.tokenBurnerAddress);
        _setupPriceAndUpgrade(_addresses.priceOracleAddress, _addresses.nftUpdateAddress, _addresses.tokenAddress, _addresses.usdtAddress);
        _setupNFTContracts(_addresses.nftUpdateAddress, _addresses.tokenBurnerAddress, _addresses.nftMintCoreAddress, _addresses.nftMintMetadataAddress, _addresses.pancakeSwapRouterAddress);
        _setupOtherContracts(_addresses.weightManagerAddress, _addresses.battleHistoryAddress, _addresses.battleSkillDataAddress, _addresses.nftTradingAddress, _addresses.feeReceiverAddress, _addresses.arenaRankingManagerAddress, _addresses.arenaRankingQueryAddress, _addresses.rewardManagerAddress, _addresses.arenaRewardAddress, _addresses.arenaLeaderboardAddress, _addresses.arenaPlayerAddress, _addresses.arenaBattleAddress);

        _emitContractAddressesUpdated();
    }

    /**
     * @dev 配置战斗和繁殖合约
     * @param _battleAddress - 战斗合约地址
     * @param _breedingCoreAddress - 繁殖核心合约地址
     * @param _breedingMarketAddress - 繁殖市场合约地址
     * @param _nftMintAddress - NFT铸造合约地址
     * @param _stakingAddress - NFT质押合约地址
     */
    function _setupBattleAndBreeding(
        address _battleAddress,
        address _breedingCoreAddress,
        address _breedingMarketAddress,
        address _nftMintAddress,
        address _stakingAddress
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

            // 设置BreedingCore的Staking合约地址
            if (_stakingAddress != address(0)) {
                try ISetStakingContract(_breedingCoreAddress).setStakingContract(_stakingAddress) {
                    emit ContractSetupSuccess("BreedingCore-Staking");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("BreedingCore-Staking", reason);
                } catch {
                    emit ContractSetupFailed("BreedingCore-Staking", "Unknown error");
                }
            }

            try IBreedingMarket(_breedingMarketAddress).setBreedingCore(_breedingCoreAddress) {
                emit ContractSetupSuccess("BreedingMarket-Core");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BreedingMarket-Core", reason);
            } catch {
                emit ContractSetupFailed("BreedingMarket-Core", "Unknown error");
            }

            // 设置BreedingMarket的NFT合约地址
            if (_nftMintAddress != address(0)) {
                try ISetNFTContract(_breedingMarketAddress).setNFTContract(_nftMintAddress) {
                    emit ContractSetupSuccess("BreedingMarket-NFT");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("BreedingMarket-NFT", reason);
                } catch {
                    emit ContractSetupFailed("BreedingMarket-NFT", "Unknown error");
                }
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
        // 设置Staking的Breeding合约地址
        if (_stakingAddress != address(0) && _breedingCoreAddress != address(0)) {
            try ISetBreedingContract(_stakingAddress).setBreedingContract(_breedingCoreAddress) {
                emit ContractSetupSuccess("Staking-Breeding");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Staking-Breeding", reason);
            } catch {
                emit ContractSetupFailed("Staking-Breeding", "Unknown error");
            }
        }
    }

    /**
     * @dev 配置质押和奖励相关合约
     * @param _stakingAddress - NFT质押合约地址
     * @param _rewardManagerAddress - 奖励管理合约地址
     * @param _dividendManagerAddress - 分红管理合约地址
     * @param _tokenStakingAddress - 代币质押合约地址
     * @param _tokenAddress - 游戏代币合约地址
     * @param _arenaRankingManagerAddress - 竞技场排名管理合约地址
     * @param _nftMintCoreAddress - NFT铸造核心合约地址
     */
    function _setupStakingAndReward(
        address _stakingAddress,
        address _rewardManagerAddress,
        address _dividendManagerAddress,
        address _tokenStakingAddress,
        address _tokenAddress,
        address _arenaRankingManagerAddress,
        address _nftMintCoreAddress,
        address _nftBuybackAddress,
        address _nftUpdateAddress,
        address _tokenBurnerAddress
    ) internal {
        if (_stakingAddress != address(0)) {
            ISetRewardTokenContract(_stakingAddress).setRewardTokenContract(_tokenAddress);
            ISetNFTContract(_stakingAddress).setNFTContract(_nftMintCoreAddress);
        }
        if (_rewardManagerAddress != address(0)) {
            ISetDividendPool(_rewardManagerAddress).setDividendPool(_dividendManagerAddress);
            ISetNFTStakingPool(_rewardManagerAddress).setNFTStakingPool(_stakingAddress);
            ISetTokenStakingPool(_rewardManagerAddress).setTokenStakingPool(_tokenStakingAddress);
            ISetTokenContract(_rewardManagerAddress).setTokenContract(_tokenAddress);
            ISetArenaRewardPool(_rewardManagerAddress).setArenaRewardPool(_arenaRankingManagerAddress);
            if (_nftBuybackAddress != address(0)) {
                ISetNFTBuybackPool(_rewardManagerAddress).setNFTBuybackPool(_nftBuybackAddress);
            }
        }
        if (_dividendManagerAddress != address(0)) {
            ISetTokenContract(_dividendManagerAddress).setTokenContract(_tokenAddress);
            ISetRewardManagerContract(_dividendManagerAddress).setRewardManagerContract(_rewardManagerAddress);
        }
        if (_tokenStakingAddress != address(0)) {
            ISetTokenAddress(_tokenStakingAddress).setTokenAddress(_tokenAddress);
        }
        if (poolManagerAddress != address(0)) {
            try ISetPoolManager(_rewardManagerAddress).setPoolManager(poolManagerAddress) {
                emit ContractSetupSuccess("RewardManager-PoolManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-PoolManager", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-PoolManager", "Unknown error");
            }
        }
        // 初始化NFT回购销毁合约
        if (_nftBuybackAddress != address(0)) {
            try ISetNFTContract(_nftBuybackAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("NFTBuyback-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTBuyback-NFT", reason);
            } catch {
                emit ContractSetupFailed("NFTBuyback-NFT", "Unknown error");
            }
            try ISetTokenContract(_nftBuybackAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("NFTBuyback-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTBuyback-Token", reason);
            } catch {
                emit ContractSetupFailed("NFTBuyback-Token", "Unknown error");
            }
            if (_tokenBurnerAddress != address(0)) {
                try INFTBuyback(_nftBuybackAddress).setTokenBurnerContract(_tokenBurnerAddress) {
                    emit ContractSetupSuccess("NFTBuyback-TokenBurner");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTBuyback-TokenBurner", reason);
                } catch {
                    emit ContractSetupFailed("NFTBuyback-TokenBurner", "Unknown error");
                }
            }
            if (_nftUpdateAddress != address(0)) {
                try INFTBuyback(_nftBuybackAddress).setNFTUpdateContract(_nftUpdateAddress) {
                    emit ContractSetupSuccess("NFTBuyback-NFTUpdate");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTBuyback-NFTUpdate", reason);
                } catch {
                    emit ContractSetupFailed("NFTBuyback-NFTUpdate", "Unknown error");
                }
            }
            if (nftDataAddress != address(0)) {
                try INFTBuyback(_nftBuybackAddress).setNFTDataContract(nftDataAddress) {
                    emit ContractSetupSuccess("NFTBuyback-NFTData");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTBuyback-NFTData", reason);
                } catch {
                    emit ContractSetupFailed("NFTBuyback-NFTData", "Unknown error");
                }
            }
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
     * @param _tokenBurnerAddress - 代币销毁合约地址
     * @param _nftMintCoreAddress - NFT铸造核心合约地址
     * @param _nftMintMetadataAddress - NFT元数据合约地址
     * @param _pancakeSwapRouterAddress - PancakeSwap路由器地址
     */
    function _setupNFTContracts(
        address _nftUpdateAddress,
        address _tokenBurnerAddress,
        address _nftMintCoreAddress,
        address _nftMintMetadataAddress,
        address _pancakeSwapRouterAddress
    ) internal {
        if (_nftUpdateAddress != address(0)) {
            ISetNFTContract(_nftUpdateAddress).setNFTContract(_nftMintCoreAddress);
            ISetMetadataContract(_nftUpdateAddress).setMetadataContract(_nftMintMetadataAddress);
            ISetTokenContract(_nftUpdateAddress).setTokenContract(tokenAddress);
            ISetPancakeSwapPair(_nftUpdateAddress).setPancakeSwapPair(_pancakeSwapRouterAddress);
            if (dividendManagerAddress != address(0)) {
                ISetNFTUpdateContract(dividendManagerAddress).setNFTUpdateContract(_nftUpdateAddress);
            }
        }
        if (_tokenBurnerAddress != address(0)) {
            ISetNFTContract(_tokenBurnerAddress).setNFTContract(_nftMintCoreAddress);
            ISetAuthorizedNFTContract(_tokenBurnerAddress).setAuthorizedNFTContract(_nftMintCoreAddress);
            ISetTokenContract(_tokenBurnerAddress).setTokenContract(tokenAddress);
        }
        if (_nftMintCoreAddress != address(0)) {
            ISetTokenBurner(_nftMintCoreAddress).setTokenBurnerContract(_tokenBurnerAddress);
            // 设置NFTMintCore的Breeding合约地址
            if (breedingCoreAddress != address(0)) {
                try ISetBreedingContract(_nftMintCoreAddress).setBreedingContract(breedingCoreAddress) {
                    emit ContractSetupSuccess("NFTMintCore-Breeding");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("NFTMintCore-Breeding", reason);
                } catch {
                    emit ContractSetupFailed("NFTMintCore-Breeding", "Unknown error");
                }
            }
        }
    }

    /**
     * @dev 配置其他合约
     * @param _weightManagerAddress - 权重管理合约地址
     * @param _battleHistoryAddress - 战斗历史合约地址
     * @param _battleSkillDataAddress - 战斗技能数据合约地址
     * @param _nftTradingAddress - NFT交易合约地址
     * @param _feeReceiverAddress - 费用接收地址
     * @param _arenaRankingManagerAddress - 竞技场排名管理合约地址
     * @param _arenaRankingQueryAddress - 竞技场排名查询合约地址
     * @param _rewardManagerAddress - 奖励管理合约地址
     * @param _arenaRewardAddress - 竞技场奖励合约地址
     * @param _arenaLeaderboardAddress - 竞技场排行榜合约地址
     * @param _arenaPlayerAddress - 竞技场玩家合约地址
     * @param _arenaBattleAddress - 竞技场战斗合约地址
     */
    function _setupOtherContracts(
        address _weightManagerAddress,
        address _battleHistoryAddress,
        address _battleSkillDataAddress,
        address _nftTradingAddress,
        address _feeReceiverAddress,
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
        if (_battleSkillDataAddress != address(0)) {
            // BattleSkillData 不需要额外配置
        }
        if (_nftTradingAddress != address(0)) {
            ISetNFTContract(_nftTradingAddress).setNFTContract(nftMintCoreAddress);
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
            ISetRankingContract(_arenaRewardAddress).setRankingContract(_arenaRankingManagerAddress);
        }
        if (_arenaLeaderboardAddress != address(0)) {
            ISetRankingContract(_arenaLeaderboardAddress).setRankingContract(_arenaRankingManagerAddress);
        }
        if (_arenaPlayerAddress != address(0)) {
            ISetRankingContract(_arenaPlayerAddress).setRankingContract(_arenaRankingManagerAddress);
            ISetNFTContract(_arenaPlayerAddress).setNFTContract(nftMintCoreAddress);
        }
        if (_arenaBattleAddress != address(0)) {
            ISetRankingContract(_arenaBattleAddress).setRankingContract(_arenaRankingManagerAddress);
            ISetBattleContract(_arenaBattleAddress).setBattleContract(battleAddress);
            ISetNFTContract(_arenaBattleAddress).setNFTContract(nftMintCoreAddress);
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
        battleSkillDataAddress = _addresses.battleSkillDataAddress;
        breedingCoreAddress = _addresses.breedingCoreAddress;
        breedingMarketAddress = _addresses.breedingMarketAddress;
        stakingAddress = _addresses.stakingAddress;
        tokenStakingAddress = _addresses.tokenStakingAddress;
        rewardManagerAddress = _addresses.rewardManagerAddress;
        dividendManagerAddress = _addresses.dividendManagerAddress;
        poolManagerAddress = _addresses.poolManagerAddress;
        priceOracleAddress = _addresses.priceOracleAddress;
    }

    /**
     * @dev 设置NFT相关合约地址
     * @param _addresses - 合约地址配置
     */
    function _setNFTAddresses(ContractAddresses calldata _addresses) internal {
        nftMintCoreAddress = _addresses.nftMintCoreAddress;
        nftMintBatchAddress = _addresses.nftMintBatchAddress;
        nftMintMetadataAddress = _addresses.nftMintMetadataAddress;
        nftUpdateAddress = _addresses.nftUpdateAddress;
        nftDataAddress = _addresses.nftDataAddress;
        tokenBurnerAddress = _addresses.tokenBurnerAddress;
        nftTradingAddress = _addresses.nftTradingAddress;
        nftBuybackAddress = _addresses.nftBuybackAddress;
        weightManagerAddress = _addresses.weightManagerAddress;
        battleHistoryAddress = _addresses.battleHistoryAddress;
    }

    /**
     * @dev 设置竞技场相关合约地址
     * @param _addresses - 合约地址配置
     */
    function _setArenaAddresses(ContractAddresses calldata _addresses) internal {
        arenaRankingManagerAddress = _addresses.arenaRankingManagerAddress;
        arenaRankingQueryAddress = _addresses.arenaRankingQueryAddress;
        arenaRewardAddress = _addresses.arenaRewardAddress;
        arenaLeaderboardAddress = _addresses.arenaLeaderboardAddress;
        arenaPlayerAddress = _addresses.arenaPlayerAddress;
        arenaBattleAddress = _addresses.arenaBattleAddress;
    }

    /**
     * @dev 设置其他地址
     * @param _addresses - 合约地址配置
     */
    function _setOtherAddresses(ContractAddresses calldata _addresses) internal {
        feeReceiverAddress = _addresses.feeReceiverAddress;
        pancakeSwapRouterAddress = _addresses.pancakeSwapRouterAddress;
    }

    /**
     * @dev 触发合约地址更新事件
     */
    function _emitContractAddressesUpdated() internal {
        address[] memory addrs = new address[](22);
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
        addrs[2] = nftMintCoreAddress;
        addrs[3] = nftMintBatchAddress;
        addrs[4] = nftMintMetadataAddress;
        addrs[5] = nftUpdateAddress;
        addrs[6] = nftDataAddress;
        addrs[7] = tokenBurnerAddress;
        addrs[8] = nftTradingAddress;
        addrs[9] = nftBuybackAddress;
        addrs[10] = stakingAddress;
    }

    /**
     * @dev 填充地址数组第二部分
     * @param addrs - 地址数组
     */
    function _fillAddressesPart2(address[] memory addrs) internal view {
        addrs[11] = tokenStakingAddress;
        addrs[12] = rewardManagerAddress;
        addrs[13] = dividendManagerAddress;
        addrs[14] = poolManagerAddress;
        addrs[15] = priceOracleAddress;
        addrs[16] = battleAddress;
        addrs[17] = battleSkillDataAddress;
        addrs[18] = battleHistoryAddress;
        addrs[19] = breedingCoreAddress;
        addrs[20] = breedingMarketAddress;
        addrs[21] = weightManagerAddress;
    }

    /**
     * @dev 同步所有合约地址配置（用于紧急修复）
     */
    function syncContractAddresses() external onlyOwner whenNotPaused {
        _setupBattleAndBreeding(battleAddress, breedingCoreAddress, breedingMarketAddress, nftMintCoreAddress, stakingAddress);
        _setupStakingAndReward(stakingAddress, rewardManagerAddress, dividendManagerAddress, tokenStakingAddress, tokenAddress, arenaRankingManagerAddress, nftMintCoreAddress, nftBuybackAddress, nftUpdateAddress, tokenBurnerAddress);
        _setupPriceAndUpgrade(priceOracleAddress, nftUpdateAddress, tokenAddress, usdtAddress);
        _setupNFTContracts(nftUpdateAddress, tokenBurnerAddress, nftMintCoreAddress, nftMintMetadataAddress, pancakeSwapRouterAddress);
        _setupOtherContracts(weightManagerAddress, battleHistoryAddress, battleSkillDataAddress, nftTradingAddress, feeReceiverAddress, arenaRankingManagerAddress, arenaRankingQueryAddress, rewardManagerAddress, arenaRewardAddress, arenaLeaderboardAddress, arenaPlayerAddress, arenaBattleAddress);
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