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

    // ========== 单独设置各合约地址（方便单独测试） ==========
    function setTokenAddress(address _tokenAddress) external onlyOwner {
        tokenAddress = _tokenAddress;
    }

    function setUsdtAddress(address _usdtAddress) external onlyOwner {
        usdtAddress = _usdtAddress;
    }

    function setNFTMintCoreAddress(address _nftMintCoreAddress) external onlyOwner {
        nftMintCoreAddress = _nftMintCoreAddress;
    }

    function setNFTMintBatchAddress(address _nftMintBatchAddress) external onlyOwner {
        nftMintBatchAddress = _nftMintBatchAddress;
    }

    function setNFTMintMetadataAddress(address _nftMintMetadataAddress) external onlyOwner {
        nftMintMetadataAddress = _nftMintMetadataAddress;
    }

    function setNFTUpdateAddress(address _nftUpdateAddress) external onlyOwner {
        nftUpdateAddress = _nftUpdateAddress;
    }

    function setNFTDataAddress(address _nftDataAddress) external onlyOwner {
        nftDataAddress = _nftDataAddress;
    }

    function setTokenBurnerAddress(address _tokenBurnerAddress) external onlyOwner {
        tokenBurnerAddress = _tokenBurnerAddress;
    }

    function setNFTTradingAddress(address _nftTradingAddress) external onlyOwner {
        nftTradingAddress = _nftTradingAddress;
    }

    function setNFTBuybackAddress(address _nftBuybackAddress) external onlyOwner {
        nftBuybackAddress = _nftBuybackAddress;
    }

    function setStakingAddress(address _stakingAddress) external onlyOwner {
        stakingAddress = _stakingAddress;
    }

    function setTokenStakingAddress(address _tokenStakingAddress) external onlyOwner {
        tokenStakingAddress = _tokenStakingAddress;
    }

    function setRewardManagerAddress(address _rewardManagerAddress) external onlyOwner {
        rewardManagerAddress = _rewardManagerAddress;
    }

    function setDividendManagerAddress(address _dividendManagerAddress) external onlyOwner {
        dividendManagerAddress = _dividendManagerAddress;
    }

    function setPoolManagerAddress(address _poolManagerAddress) external onlyOwner {
        poolManagerAddress = _poolManagerAddress;
    }

    function setPriceOracleAddress(address _priceOracleAddress) external onlyOwner {
        priceOracleAddress = _priceOracleAddress;
    }

    function setBattleAddress(address _battleAddress) external onlyOwner {
        battleAddress = _battleAddress;
    }

    function setBattleSkillDataAddress(address _battleSkillDataAddress) external onlyOwner {
        battleSkillDataAddress = _battleSkillDataAddress;
    }

    function setBattleHistoryAddress(address _battleHistoryAddress) external onlyOwner {
        battleHistoryAddress = _battleHistoryAddress;
    }

    function setBreedingCoreAddress(address _breedingCoreAddress) external onlyOwner {
        breedingCoreAddress = _breedingCoreAddress;
    }

    function setBreedingMarketAddress(address _breedingMarketAddress) external onlyOwner {
        breedingMarketAddress = _breedingMarketAddress;
    }

    function setWeightManagerAddress(address _weightManagerAddress) external onlyOwner {
        weightManagerAddress = _weightManagerAddress;
    }

    function setArenaRankingManagerAddress(address _arenaRankingManagerAddress) external onlyOwner {
        arenaRankingManagerAddress = _arenaRankingManagerAddress;
    }

    function setArenaRankingQueryAddress(address _arenaRankingQueryAddress) external onlyOwner {
        arenaRankingQueryAddress = _arenaRankingQueryAddress;
    }

    function setArenaRewardAddress(address _arenaRewardAddress) external onlyOwner {
        arenaRewardAddress = _arenaRewardAddress;
    }

    function setArenaLeaderboardAddress(address _arenaLeaderboardAddress) external onlyOwner {
        arenaLeaderboardAddress = _arenaLeaderboardAddress;
    }

    function setArenaPlayerAddress(address _arenaPlayerAddress) external onlyOwner {
        arenaPlayerAddress = _arenaPlayerAddress;
    }

    function setArenaBattleAddress(address _arenaBattleAddress) external onlyOwner {
        arenaBattleAddress = _arenaBattleAddress;
    }

    function setFeeReceiverAddress(address _feeReceiverAddress) external onlyOwner {
        feeReceiverAddress = _feeReceiverAddress;
    }

    function setPancakeSwapRouterAddress(address _pancakeSwapRouterAddress) external onlyOwner {
        pancakeSwapRouterAddress = _pancakeSwapRouterAddress;
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


        setupBattleAndBreeding(_addresses.battleAddress, _addresses.breedingCoreAddress, _addresses.breedingMarketAddress, _addresses.nftMintCoreAddress, _addresses.stakingAddress);
        setupStakingAndReward(_addresses.stakingAddress, _addresses.rewardManagerAddress, _addresses.dividendManagerAddress, _addresses.tokenStakingAddress, _addresses.tokenAddress, _addresses.arenaRankingManagerAddress, _addresses.nftMintCoreAddress, _addresses.nftBuybackAddress, _addresses.nftUpdateAddress, _addresses.tokenBurnerAddress);
        setupPriceAndUpgrade(_addresses.priceOracleAddress, _addresses.nftUpdateAddress, _addresses.tokenAddress, _addresses.usdtAddress);
        setupNFTContracts(_addresses.nftUpdateAddress, _addresses.tokenBurnerAddress, _addresses.nftMintCoreAddress, _addresses.nftMintMetadataAddress, _addresses.pancakeSwapRouterAddress);
        setupOtherContracts(_addresses.weightManagerAddress, _addresses.battleHistoryAddress, _addresses.battleSkillDataAddress, _addresses.nftTradingAddress, _addresses.feeReceiverAddress, _addresses.arenaRankingManagerAddress, _addresses.arenaRankingQueryAddress, _addresses.rewardManagerAddress, _addresses.arenaRewardAddress, _addresses.arenaLeaderboardAddress, _addresses.arenaPlayerAddress, _addresses.arenaBattleAddress);

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
    function setupBattleAndBreeding(
        address _battleAddress,
        address _breedingCoreAddress,
        address _breedingMarketAddress,
        address _nftMintAddress,
        address _stakingAddress
    ) external onlyOwner {
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
    function setupStakingAndReward(
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
    ) external onlyOwner {
        if (_stakingAddress != address(0)) {
            try ISetRewardTokenContract(_stakingAddress).setRewardTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("Staking-RewardToken");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Staking-RewardToken", reason);
            } catch {
                emit ContractSetupFailed("Staking-RewardToken", "Unknown error");
            }
            try ISetNFTContract(_stakingAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("Staking-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("Staking-NFT", reason);
            } catch {
                emit ContractSetupFailed("Staking-NFT", "Unknown error");
            }
        }
        if (_rewardManagerAddress != address(0)) {
            try ISetDividendPool(_rewardManagerAddress).setDividendPool(_dividendManagerAddress) {
                emit ContractSetupSuccess("RewardManager-DividendPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-DividendPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-DividendPool", "Unknown error");
            }
            try ISetNFTStakingPool(_rewardManagerAddress).setNFTStakingPool(_stakingAddress) {
                emit ContractSetupSuccess("RewardManager-NFTStakingPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-NFTStakingPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-NFTStakingPool", "Unknown error");
            }
            try ISetTokenStakingPool(_rewardManagerAddress).setTokenStakingPool(_tokenStakingAddress) {
                emit ContractSetupSuccess("RewardManager-TokenStakingPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-TokenStakingPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-TokenStakingPool", "Unknown error");
            }
            try ISetTokenContract(_rewardManagerAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("RewardManager-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-Token", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-Token", "Unknown error");
            }
            try ISetArenaRewardPool(_rewardManagerAddress).setArenaRewardPool(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("RewardManager-ArenaRewardPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("RewardManager-ArenaRewardPool", reason);
            } catch {
                emit ContractSetupFailed("RewardManager-ArenaRewardPool", "Unknown error");
            }
            if (_nftBuybackAddress != address(0)) {
                try ISetNFTBuybackPool(_rewardManagerAddress).setNFTBuybackPool(_nftBuybackAddress) {
                    emit ContractSetupSuccess("RewardManager-NFTBuybackPool");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("RewardManager-NFTBuybackPool", reason);
                } catch {
                    emit ContractSetupFailed("RewardManager-NFTBuybackPool", "Unknown error");
                }
            }
        }
        if (_dividendManagerAddress != address(0)) {
            try ISetTokenContract(_dividendManagerAddress).setTokenContract(_tokenAddress) {
                emit ContractSetupSuccess("DividendManager-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("DividendManager-Token", reason);
            } catch {
                emit ContractSetupFailed("DividendManager-Token", "Unknown error");
            }
            try ISetRewardManagerContract(_dividendManagerAddress).setRewardManagerContract(_rewardManagerAddress) {
                emit ContractSetupSuccess("DividendManager-RewardManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("DividendManager-RewardManager", reason);
            } catch {
                emit ContractSetupFailed("DividendManager-RewardManager", "Unknown error");
            }
        }
        if (_tokenStakingAddress != address(0)) {
            try ISetTokenAddress(_tokenStakingAddress).setTokenAddress(_tokenAddress) {
                emit ContractSetupSuccess("TokenStaking-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenStaking-Token", reason);
            } catch {
                emit ContractSetupFailed("TokenStaking-Token", "Unknown error");
            }
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
    function setupPriceAndUpgrade(
        address _priceOracleAddress,
        address _upgradeModuleAddress,
        address _tokenAddress,
        address _usdtAddress
    ) external onlyOwner {
        if (_priceOracleAddress != address(0)) {
            try ISetTokenAddress(_priceOracleAddress).setTokenAddress(_tokenAddress) {
                emit ContractSetupSuccess("PriceOracle-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("PriceOracle-Token", reason);
            } catch {
                emit ContractSetupFailed("PriceOracle-Token", "Unknown error");
            }
            try ISetUSDTAddress(_priceOracleAddress).setUSDTAddress(_usdtAddress) {
                emit ContractSetupSuccess("PriceOracle-USDT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("PriceOracle-USDT", reason);
            } catch {
                emit ContractSetupFailed("PriceOracle-USDT", "Unknown error");
            }
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
    function setupNFTContracts(
        address _nftUpdateAddress,
        address _tokenBurnerAddress,
        address _nftMintCoreAddress,
        address _nftMintMetadataAddress,
        address _pancakeSwapRouterAddress
    ) external onlyOwner {
        if (_nftUpdateAddress != address(0)) {
            try ISetNFTContract(_nftUpdateAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("NFTUpdate-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-NFT", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-NFT", "Unknown error");
            }
            try ISetMetadataContract(_nftUpdateAddress).setMetadataContract(_nftMintMetadataAddress) {
                emit ContractSetupSuccess("NFTUpdate-Metadata");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-Metadata", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-Metadata", "Unknown error");
            }
            try ISetTokenContract(_nftUpdateAddress).setTokenContract(tokenAddress) {
                emit ContractSetupSuccess("NFTUpdate-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-Token", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-Token", "Unknown error");
            }
            try ISetPancakeSwapPair(_nftUpdateAddress).setPancakeSwapPair(_pancakeSwapRouterAddress) {
                emit ContractSetupSuccess("NFTUpdate-PancakeSwapPair");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTUpdate-PancakeSwapPair", reason);
            } catch {
                emit ContractSetupFailed("NFTUpdate-PancakeSwapPair", "Unknown error");
            }
            if (dividendManagerAddress != address(0)) {
                try ISetNFTUpdateContract(dividendManagerAddress).setNFTUpdateContract(_nftUpdateAddress) {
                    emit ContractSetupSuccess("DividendManager-NFTUpdate");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("DividendManager-NFTUpdate", reason);
                } catch {
                    emit ContractSetupFailed("DividendManager-NFTUpdate", "Unknown error");
                }
            }
        }
        if (_tokenBurnerAddress != address(0)) {
            try ISetNFTContract(_tokenBurnerAddress).setNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("TokenBurner-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenBurner-NFT", reason);
            } catch {
                emit ContractSetupFailed("TokenBurner-NFT", "Unknown error");
            }
            try ISetAuthorizedNFTContract(_tokenBurnerAddress).setAuthorizedNFTContract(_nftMintCoreAddress) {
                emit ContractSetupSuccess("TokenBurner-AuthorizedNFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenBurner-AuthorizedNFT", reason);
            } catch {
                emit ContractSetupFailed("TokenBurner-AuthorizedNFT", "Unknown error");
            }
            try ISetTokenContract(_tokenBurnerAddress).setTokenContract(tokenAddress) {
                emit ContractSetupSuccess("TokenBurner-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("TokenBurner-Token", reason);
            } catch {
                emit ContractSetupFailed("TokenBurner-Token", "Unknown error");
            }
        }
        if (_nftMintCoreAddress != address(0)) {
            try ISetTokenBurner(_nftMintCoreAddress).setTokenBurnerContract(_tokenBurnerAddress) {
                emit ContractSetupSuccess("NFTMintCore-TokenBurner");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTMintCore-TokenBurner", reason);
            } catch {
                emit ContractSetupFailed("NFTMintCore-TokenBurner", "Unknown error");
            }
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
    function setupOtherContracts(
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
    ) external onlyOwner {
        if (_weightManagerAddress != address(0)) {
            try ISetNFTDataContract(_weightManagerAddress).setNFTDataContract(nftDataAddress) {
                emit ContractSetupSuccess("WeightManager-NFTData");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("WeightManager-NFTData", reason);
            } catch {
                emit ContractSetupFailed("WeightManager-NFTData", "Unknown error");
            }
        }
        if (_battleHistoryAddress != address(0)) {
            try ISetBattleContract(_battleHistoryAddress).setBattleContract(battleAddress) {
                emit ContractSetupSuccess("BattleHistory-Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("BattleHistory-Battle", reason);
            } catch {
                emit ContractSetupFailed("BattleHistory-Battle", "Unknown error");
            }
        }
        if (_battleSkillDataAddress != address(0)) {
            // BattleSkillData 不需要额外配置
        }
        if (_nftTradingAddress != address(0)) {
            try ISetNFTContract(_nftTradingAddress).setNFTContract(nftMintCoreAddress) {
                emit ContractSetupSuccess("NFTTrading-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTTrading-NFT", reason);
            } catch {
                emit ContractSetupFailed("NFTTrading-NFT", "Unknown error");
            }
            try ISetFeeReceiver(_nftTradingAddress).setFeeReceiver(_feeReceiverAddress) {
                emit ContractSetupSuccess("NFTTrading-FeeReceiver");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("NFTTrading-FeeReceiver", reason);
            } catch {
                emit ContractSetupFailed("NFTTrading-FeeReceiver", "Unknown error");
            }
        }
        if (_arenaRankingManagerAddress != address(0)) {
            try ISetTokenContract(_arenaRankingManagerAddress).setTokenContract(tokenAddress) {
                emit ContractSetupSuccess("ArenaRankingManager-Token");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingManager-Token", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingManager-Token", "Unknown error");
            }
            try ISetRewardPool(_arenaRankingManagerAddress).setRewardPool(_rewardManagerAddress) {
                emit ContractSetupSuccess("ArenaRankingManager-RewardPool");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingManager-RewardPool", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingManager-RewardPool", "Unknown error");
            }
            try ISetBattleContract(_arenaRankingManagerAddress).setBattleContract(battleAddress) {
                emit ContractSetupSuccess("ArenaRankingManager-Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaRankingManager-Battle", reason);
            } catch {
                emit ContractSetupFailed("ArenaRankingManager-Battle", "Unknown error");
            }
            if (_arenaRewardAddress != address(0)) {
                try ISetArenaRewardContract(_arenaRankingManagerAddress).setArenaRewardContract(_arenaRewardAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaReward");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaReward", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaReward", "Unknown error");
                }
            }
            if (_arenaLeaderboardAddress != address(0)) {
                try ISetArenaLeaderboardContract(_arenaRankingManagerAddress).setArenaLeaderboardContract(_arenaLeaderboardAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaLeaderboard");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaLeaderboard", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaLeaderboard", "Unknown error");
                }
            }
            if (_arenaPlayerAddress != address(0)) {
                try ISetArenaPlayerContract(_arenaRankingManagerAddress).setArenaPlayerContract(_arenaPlayerAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaPlayer");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaPlayer", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaPlayer", "Unknown error");
                }
            }
            if (_arenaBattleAddress != address(0)) {
                try ISetArenaBattleContract(_arenaRankingManagerAddress).setArenaBattleContract(_arenaBattleAddress) {
                    emit ContractSetupSuccess("ArenaRankingManager-ArenaBattle");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaBattle", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingManager-ArenaBattle", "Unknown error");
                }
            }
        }
        if (_arenaRankingQueryAddress != address(0)) {
            if (_arenaRewardAddress != address(0)) {
                try ISetArenaRewardContract(_arenaRankingQueryAddress).setArenaRewardContract(_arenaRewardAddress) {
                    emit ContractSetupSuccess("ArenaRankingQuery-ArenaReward");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaReward", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaReward", "Unknown error");
                }
            }
            if (_arenaLeaderboardAddress != address(0)) {
                try ISetArenaLeaderboardContract(_arenaRankingQueryAddress).setArenaLeaderboardContract(_arenaLeaderboardAddress) {
                    emit ContractSetupSuccess("ArenaRankingQuery-ArenaLeaderboard");
                } catch Error(string memory reason) {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaLeaderboard", reason);
                } catch {
                    emit ContractSetupFailed("ArenaRankingQuery-ArenaLeaderboard", "Unknown error");
                }
            }
        }
        if (_arenaRewardAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaRewardAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaReward-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaReward-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaReward-ArenaRankingManager", "Unknown error");
            }
        }
        if (_arenaLeaderboardAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaLeaderboardAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaLeaderboard-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaLeaderboard-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaLeaderboard-ArenaRankingManager", "Unknown error");
            }
        }
        if (_arenaPlayerAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaPlayerAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaPlayer-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaPlayer-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaPlayer-ArenaRankingManager", "Unknown error");
            }
            try ISetNFTContract(_arenaPlayerAddress).setNFTContract(nftMintCoreAddress) {
                emit ContractSetupSuccess("ArenaPlayer-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaPlayer-NFT", reason);
            } catch {
                emit ContractSetupFailed("ArenaPlayer-NFT", "Unknown error");
            }
        }
        if (_arenaBattleAddress != address(0)) {
            try ISetArenaRankingManagerContract(_arenaBattleAddress).setArenaRankingManagerContract(_arenaRankingManagerAddress) {
                emit ContractSetupSuccess("ArenaBattle-ArenaRankingManager");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-ArenaRankingManager", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-ArenaRankingManager", "Unknown error");
            }
            try ISetBattleContract(_arenaBattleAddress).setBattleContract(battleAddress) {
                emit ContractSetupSuccess("ArenaBattle-Battle");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-Battle", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-Battle", "Unknown error");
            }
            try ISetNFTContract(_arenaBattleAddress).setNFTContract(nftMintCoreAddress) {
                emit ContractSetupSuccess("ArenaBattle-NFT");
            } catch Error(string memory reason) {
                emit ContractSetupFailed("ArenaBattle-NFT", reason);
            } catch {
                emit ContractSetupFailed("ArenaBattle-NFT", "Unknown error");
            }
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