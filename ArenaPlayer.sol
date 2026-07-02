﻿// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";
import "./AddressLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ArenaPlayer
 * @dev 竞技场玩家合约，管理玩家的 NFT 质押、战斗队伍和挑战次数
 * 
 * 核心职责：
 * 1. NFT 质押管理：玩家质押 NFT 用于竞技场战斗
 * 2. 战斗队伍配置：设置和清除玩家的战斗队伍
 * 3. 挑战次数管理：跟踪玩家的每日挑战次数，支持充值
 * 4. 模拟玩家生成：生成用于 PvE 战斗的模拟对手队伍
 * 
 * 与其他合约的交互：
 * - ArenaRanking / ArenaRankingManager：战斗发起时验证 NFT 所有权
 * - NFT 合约：验证 NFT 所有权，管理 NFT 转移
 * 
 * 挑战机制：
 * - 每日免费挑战次数：默认 3 次
 * - 充值挑战次数：每次 3 次（代币支付）
 * - 每日重置：挑战次数每天重置
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有操作
 * - NFT 所有权验证：确保质押的 NFT 属于调用者
 * 
 * 权限控制：
 * - onlyOwner：暂停合约、设置参数
 * - onlyAuthorized：质押、解除质押、设置队伍
 */
contract ArenaPlayer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IERC721Receiver {
    using SafeERC20 for IERC20;
    
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    
    /**
     * @dev 最大队伍大小（NFT 数量）
     */
    uint256 public constant MAX_TEAM_SIZE = 6;
    /**
     * @dev 模拟玩家索引偏移量
     */
    uint256 public constant MOCK_PLAYER_INDEX_OFFSET = 1000000;
    /**
     * @dev 每日免费挑战次数
     */
    uint256 public constant DAILY_ATTEMPTS = 3;
    /**
     * @dev 充值成本（代币，wei单位）
     */
    uint256 public rechargeCost = 1 * 10**18; // 1 代币
    
    /**
     * @dev 玩家战斗队伍映射
     */
    mapping(uint256 => mapping(address => uint256[])) public playerBattleTeams;
    /**
     * @dev NFT 质押所有者映射
     */
    mapping(uint256 => mapping(uint256 => address)) internal _nftStakedOwner;
    /**
     * @dev 用户质押的 NFT 列表
     */
    mapping(uint256 => mapping(address => uint256[])) public userStakedNFTs;
    /**
     * @dev 玩家上次战斗时间
     */
    mapping(uint256 => mapping(address => uint256)) public playerLastBattleTime;
    /**
     * @dev 玩家剩余挑战次数
     */
    mapping(uint256 => mapping(address => uint256)) public playerRemainingAttempts;
    /**
     * @dev 玩家上次重置时间
     */
    mapping(uint256 => mapping(address => uint256)) public playerLastResetTime;
    
    /**
     * @dev 每次充值获得的挑战次数
     */
    uint256 public rechargeAttempts;
    
    /**
     * @dev 纪元版本号，用于快速重置合约数据（循环复用，MAX_EPOCHS次后回到0）
     */
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;
    
    /**
     * @dev 战斗队伍设置事件
     */
    event BattleTeamSet(address indexed player, uint256[6] tokenIds);
    /**
     * @dev 战斗队伍清除事件
     */
    event BattleTeamCleared(address indexed player);
    /**
     * @dev NFT 质押事件
     */
    event NFTsStaked(address indexed player, uint256[] tokenIds);
    /**
     * @dev NFT 解除质押事件
     */
    event NFTsUnstaked(address indexed player, uint256[] tokenIds);
    /**
     * @dev 挑战次数充值事件
     */
    event ChallengeAttemptsRecharged(address indexed player, uint256 attempts);
    /**
     * @dev 模拟队伍生成事件
     */
    event MockTeamGenerated(address indexed player, uint256[6] team);

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     * @param oldEpoch 重置前的纪元号
     * @param newEpoch 重置后的纪元号
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        require(authorizer != address(0), "ArenaPlayer: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "ArenaPlayer: Not authorized");
        _;
    }

    /// @dev 构造函数：禁用初始化器，防止实现合约被直接部署后被初始化攻击
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(
        address _authorizerAddress
    ) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        authorizer = _authorizerAddress;
        
        rechargeCost = 1 * 10**18;
        rechargeAttempts = 3;
        epoch = 1;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "ArenaPlayer: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev UUPS 升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev ERC721安全转账接收函数
     * @return bytes4 接收接口ID
     * @notice 允许合约接收NFT质押
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        return 0x150b7a02;
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 内部函数：重置玩家挑战次数
     * @param player 玩家地址
     * @notice 将玩家剩余挑战次数重置为每日默认值
     */
    function _resetAttempts(address player) internal {
        uint256 currentEpoch = _currentEpoch();
        playerLastResetTime[currentEpoch][player] = block.timestamp;
        playerRemainingAttempts[currentEpoch][player] = DAILY_ATTEMPTS;
    }

    function _checkAndResetAttempts(address player) internal {
        uint256 currentEpoch = _currentEpoch();
        if (playerLastResetTime[currentEpoch][player] == 0 || block.timestamp > playerLastResetTime[currentEpoch][player] + 24 hours) {
            _resetAttempts(player);
        }
    }

    /**
     * @dev 质押NFT
     * @param tokenIds NFT ID数组（最多6个）
     * @notice 玩家质押NFT用于竞技场战斗，质押后NFT转移到合约地址
     */
    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaPlayer: Invalid tokenIds count");
        
        uint256 currentEpoch = _currentEpoch();
        address nftContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_MINT_CORE);
        require(nftContract != address(0), "ArenaPlayer: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaPlayer: Invalid token ID");
            require(_nftStakedOwner[currentEpoch][tokenId] == address(0), "ArenaPlayer: NFT already staked in this contract");
            require(nft.ownerOf(tokenId) == msg.sender, "ArenaPlayer: Not owner of token");
            require(nft.isApprovedForAll(msg.sender, address(this)), "ArenaPlayer: Contract not approved for transfer");
            
            nft.safeTransferFrom(msg.sender, address(this), tokenId);
            _nftStakedOwner[currentEpoch][tokenId] = msg.sender;
            userStakedNFTs[currentEpoch][msg.sender].push(tokenId);
        }
        
        _syncWeightAfterStake(msg.sender, tokenIds);
        
        emit NFTsStaked(msg.sender, tokenIds);
    }

    /**
     * @dev 解除质押NFT
     * @param tokenIds NFT ID数组
     * @notice 玩家解除质押NFT，如果解除后无质押NFT则清空战斗队伍
     */
    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        uint256 currentEpoch = _currentEpoch();
        address nftContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_MINT_CORE);
        require(nftContract != address(0), "ArenaPlayer: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        bool shouldClearTeam = false;
        uint256[] storage team = playerBattleTeams[currentEpoch][msg.sender];
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaPlayer: Invalid token ID");
            require(_nftStakedOwner[currentEpoch][tokenId] != address(0), "ArenaPlayer: NFT not staked");
            require(_nftStakedOwner[currentEpoch][tokenId] == msg.sender, "ArenaPlayer: Not owner of staked NFT");
            
            for (uint256 j = 0; j < team.length; j++) {
                if (team[j] == tokenId) {
                    shouldClearTeam = true;
                    break;
                }
            }
            
            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            _nftStakedOwner[currentEpoch][tokenId] = address(0);
            
            uint256[] storage stakedList = userStakedNFTs[currentEpoch][msg.sender];
            for (uint256 j = 0; j < stakedList.length; j++) {
                if (stakedList[j] == tokenId) {
                    stakedList[j] = stakedList[stakedList.length - 1];
                    stakedList.pop();
                    break;
                }
            }
        }
        
        if (shouldClearTeam || userStakedNFTs[currentEpoch][msg.sender].length == 0) {
            delete playerBattleTeams[currentEpoch][msg.sender];
        }
        
        _syncWeightAfterUnstake(msg.sender, tokenIds);
        
        emit NFTsUnstaked(msg.sender, tokenIds);
    }

    function setBattleTeam(uint256[6] calldata tokenIds) external nonReentrant whenNotPaused {
        uint256 currentEpoch = _currentEpoch();
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaPlayer: Invalid token ID");
            require(_nftStakedOwner[currentEpoch][tokenId] == msg.sender, "ArenaPlayer: NFT not staked or not owner");
            
            for (uint256 j = i + 1; j < 6; j++) {
                require(tokenIds[j] != tokenId, "ArenaPlayer: Duplicate token in team");
            }
        }
        
        uint256[] memory teamArray = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            teamArray[i] = tokenIds[i];
        }
        playerBattleTeams[currentEpoch][msg.sender] = teamArray;
        
        emit BattleTeamSet(msg.sender, tokenIds);
    }

    function clearBattleTeam() external nonReentrant {
        uint256 currentEpoch = _currentEpoch();
        delete playerBattleTeams[currentEpoch][msg.sender];
        emit BattleTeamCleared(msg.sender);
    }

    /**
     * @dev 获取用户质押的NFT列表
     * @param user 用户地址
     * @return NFT ID数组
     */
    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        require(user != address(0), "ArenaPlayer: Invalid user address");
        uint256 currentEpoch = _currentEpoch();
        return userStakedNFTs[currentEpoch][user];
    }

    function getPlayerBattleTeam(address player) external view returns (uint256[] memory) {
        uint256 currentEpoch = _currentEpoch();
        return playerBattleTeams[currentEpoch][player];
    }

    function nftStakedOwner(uint256 tokenId) external view returns (address) {
        uint256 currentEpoch = _currentEpoch();
        return _nftStakedOwner[currentEpoch][tokenId];
    }

    function rechargeChallengeAttempts() external nonReentrant whenNotPaused {
        address arenaRankingManager = IAuthorizer(authorizer).getAddressByName(AddressLib.ARENA_RANKING_MANAGER);
        require(IArenaRanking(arenaRankingManager).currentSeasonId() > 0, "ArenaPlayer: No active season");
        
        _checkAndResetAttempts(msg.sender);
        
        address tokenContract = IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN);
        require(tokenContract != address(0), "ArenaPlayer: Token contract not set");
        
        IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), rechargeCost);

        uint256 currentEpoch = _currentEpoch();
        uint256 newAttempts = rechargeAttempts;
        playerRemainingAttempts[currentEpoch][msg.sender] += newAttempts;

        emit ChallengeAttemptsRecharged(msg.sender, newAttempts);
    }

    /**
     * @dev 获取玩家剩余挑战次数
     * @param player 玩家地址
     * @return 剩余挑战次数
     */
    function getRemainingAttempts(address player) external view returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        if (playerLastResetTime[currentEpoch][player] == 0) {
            return DAILY_ATTEMPTS;
        }
        if (block.timestamp > playerLastResetTime[currentEpoch][player] + 24 hours) {
            return DAILY_ATTEMPTS;
        }
        return playerRemainingAttempts[currentEpoch][player];
    }

    /**
     * @dev 获取玩家挑战状态
     * @param player 玩家地址
     * @return remainingAttempts 剩余挑战次数, lastBattleTime 上次战斗时间, hasTeam 是否有战斗队伍
     */
    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    ) {
        uint256 currentEpoch = _currentEpoch();
        remainingAttempts = playerRemainingAttempts[currentEpoch][player];
        lastBattleTime = playerLastBattleTime[currentEpoch][player];
        hasTeam = playerBattleTeams[currentEpoch][player].length > 0;
    }

    function setRechargeCost(uint256 _rechargeCost) external onlyOwner {
        rechargeCost = _rechargeCost;
    }

    function setRechargeAttempts(uint256 _rechargeAttempts) external onlyOwner {
        require(_rechargeAttempts > 0, "ArenaPlayer: Recharge attempts must be greater than 0");
        rechargeAttempts = _rechargeAttempts;
    }

    /**
     * @dev 更新玩家战斗时间
     * @param player 玩家地址
     * @param timestamp 时间戳
     * @notice 仅限owner或authorizer调用
     */
    function updatePlayerBattleTime(address player, uint256 timestamp) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        playerLastBattleTime[currentEpoch][player] = timestamp;
    }

    function updatePlayerAttempts(address player, uint256 attempts) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        playerRemainingAttempts[currentEpoch][player] = attempts;
    }

    function updatePlayerResetTime(address player, uint256 timestamp) external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        playerLastResetTime[currentEpoch][player] = timestamp;
    }

    function decrementAttempts(address player) external onlyOwnerOrAuthorizer returns (uint256) {
        _checkAndResetAttempts(player);
        uint256 currentEpoch = _currentEpoch();
        require(playerRemainingAttempts[currentEpoch][player] > 0, "ArenaPlayer: No remaining attempts");
        playerRemainingAttempts[currentEpoch][player]--;
        return playerRemainingAttempts[currentEpoch][player];
    }

    /**
     * @dev 生成模拟队伍
     * @param seed 随机种子
     * @return 模拟队伍（6个NFT ID）
     * @notice 根据种子生成确定性的模拟玩家队伍
     */
    function generateMockTeam(uint256 seed) external view returns (uint256[6] memory) {
        uint256[6] memory team;
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = (uint256(keccak256(abi.encodePacked(seed, i, block.timestamp))) % 1000000) + 1;
            team[i] = tokenId;
        }
        return team;
    }

    function isNFTStaked(uint256 tokenId) external view returns (bool) {
        uint256 currentEpoch = _currentEpoch();
        return _nftStakedOwner[currentEpoch][tokenId] != address(0);
    }

    /**
     * @dev 获取NFT质押所有者
     * @param tokenId NFT ID
     * @return 质押所有者地址
     */
    function getNFTStakedOwner(uint256 tokenId) external view returns (address) {
        uint256 currentEpoch = _currentEpoch();
        return _nftStakedOwner[currentEpoch][tokenId];
    }

    /**
     * @dev 质押后同步权重数据
     * @param user 用户地址
     * @param tokenIds 质押的NFT ID列表
     */
    function _syncWeightAfterStake(address user, uint256[] calldata tokenIds) internal {
        address nftDataContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_DATA);
        address weightManager = IAuthorizer(authorizer).getAddressByName(AddressLib.WEIGHT_MANAGER);
        address dividendManager = IAuthorizer(authorizer).getAddressByName(AddressLib.DIVIDEND_MANAGER);
        
        // 从用户NFT列表中移除质押的NFT
        if (nftDataContract != address(0)) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                try INFTDataInterface(nftDataContract).removeUserNFT(user, tokenIds[i]) {
                    // 成功
                } catch {
                    // 忽略错误，不影响主流程
                }
            }
        }
        
        // 同步用户权重 - WeightManager
        if (weightManager != address(0)) {
            try IWeightManager(weightManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略错误，不影响主流程
            }
        }
        
        // 同步用户权重 - DividendManager
        if (dividendManager != address(0)) {
            try IDividendManager(dividendManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略错误，不影响主流程
            }
        }
    }

    /**
     * @dev 解除质押后同步权重数据
     * @param user 用户地址
     * @param tokenIds 解除质押的NFT ID列表
     */
    function _syncWeightAfterUnstake(address user, uint256[] calldata tokenIds) internal {
        address nftDataContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_DATA);
        address weightManager = IAuthorizer(authorizer).getAddressByName(AddressLib.WEIGHT_MANAGER);
        address dividendManager = IAuthorizer(authorizer).getAddressByName(AddressLib.DIVIDEND_MANAGER);
        
        // 将解除质押的NFT添加回用户列表
        if (nftDataContract != address(0)) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                try INFTDataInterface(nftDataContract).addUserNFT(user, tokenIds[i]) {
                    // 成功
                } catch {
                    // 忽略错误，不影响主流程
                }
            }
        }
        
        // 同步用户权重 - WeightManager
        if (weightManager != address(0)) {
            try IWeightManager(weightManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略错误，不影响主流程
            }
        }
        
        // 同步用户权重 - DividendManager
        if (dividendManager != address(0)) {
            try IDividendManager(dividendManager).syncUserWeight(user) {
                // 成功
            } catch {
                // 忽略错误，不影响主流程
            }
        }
    }

    /**
     * @dev 重置合约数据
     * @notice 清空玩家战斗队伍和质押NFT数据，仅owner或authorizer可调用
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        rechargeCost = 1 * 10**18;
        rechargeAttempts = 3;
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}