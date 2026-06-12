// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";

/**
 * @title ArenaPlayer
 * @dev 竞技场玩家合约，管理玩家�?NFT 质押、战斗队伍和挑战次数
 * 
 * 核心职责�?
 * 1. NFT 质押管理：玩家质�?NFT 用于竞技场战�?
 * 2. 战斗队伍配置：设置和清除玩家的战斗队�?
 * 3. 挑战次数管理：跟踪玩家的每日挑战次数，支持充�?
 * 4. 模拟玩家生成：生成用�?PvE 战斗的模拟对手队�?
 * 
 * 与其他合约的交互�?
 * - ArenaRanking / ArenaRankingManager：战斗发起时验证 NFT 所有权
 * - NFT 合约：验�?NFT 所有权，管�?NFT 转移
 * 
 * 挑战机制�?
 * - 每日免费挑战次数：默�?3 �?
 * - 充值挑战次数：每次 3 次（代币支付�?
 * - 每日重置：挑战次数每天重�?
 * 
 * 安全机制�?
 * - ReentrancyGuard：防止重入攻�?
 * - Pausable：可暂停所有操�?
 * - NFT 所有权验证：确保质押的 NFT 属于调用�?
 * 
 * 权限控制�?
 * - onlyOwner：暂停合约、设置参�?
 * - onlyAuthorized：质�?解除质押、设置队�?
 */
contract ArenaPlayer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /**
     * @dev 排名合约地址
     */
    address public rankingContract;
    /**
     * @dev NFT 合约地址
     */
    address public nftContract;
    /**
     * @dev 授权合约地址
     */
    address public authorizer;
    
    /**
     * @dev 最大队伍大小（NFT 数量�?
     */
    uint256 public constant MAX_TEAM_SIZE = 6;
    /**
     * @dev 模拟玩家索引偏移�?
     */
    uint256 public constant MOCK_PLAYER_INDEX_OFFSET = 1000000;
    
    /**
     * @dev 最大充值次数限�?
     */
    uint256 public maxRechargeAttempts = 5;
    /**
     * @dev 充值成本（BNB�?
     */
    uint256 public rechargeCost = 1000000000000000000; // 1 BNB
    
    /**
     * @dev 玩家战斗队伍映射
     */
    mapping(address => uint256[]) public playerBattleTeams;
    /**
     * @dev NFT 质押所有者映�?
     */
    mapping(uint256 => address) public nftStakedOwner;
    /**
     * @dev 用户质押�?NFT 列表
     */
    mapping(address => uint256[]) public userStakedNFTs;
    /**
     * @dev 玩家上次战斗时间
     */
    mapping(address => uint256) public playerLastBattleTime;
    /**
     * @dev 玩家剩余挑战次数
     */
    mapping(address => uint256) public playerRemainingAttempts;
    /**
     * @dev 玩家上次重置时间
     */
    mapping(address => uint256) public playerLastResetTime;
    /**
     * @dev 玩家充值次�?
     */
    mapping(address => uint256) public rechargeCount;
    
    /**
     * @dev 每日挑战次数默认�?
     */
    uint256 public constant DAILY_ATTEMPTS = 3;
    /**
     * @dev 每次充值获得的挑战次数
     */
    uint256 public constant RECHARGE_ATTEMPTS = 3;
    /**
     * @dev 充值挑战次数的成本（代币）
     */
    uint256 public constant RECHARGE_COST = 888;
    
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
     * @dev 挑战次数充值事�?
     */
    event ChallengeAttemptsRecharged(address indexed player, uint256 attempts);
    /**
     * @dev 模拟队伍生成事件
     */
    event MockTeamGenerated(address indexed player, uint256[6] team);

    /**
     * @dev 授权检查修饰器
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == rankingContract, "ArenaPlayer: Not authorized");
        _;
    }

    /**
     * @dev 初始化函�?
     * @param _rankingContract 排名合约地址
     * @param _nftContract NFT 合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _rankingContract, address _nftContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        rankingContract = _rankingContract;
        nftContract = _nftContract;
        authorizer = _authorizer;
    }
    
    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaPlayer: Invalid authorizer address");
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS 升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
     * @dev 设置排名合约地址
     * @param _rankingContract 排名合约地址
     */
    function setRankingContract(address _rankingContract) external onlyOwnerOrAuthorizer {
        rankingContract = _rankingContract;
    }

    /**
     * @dev 设置 NFT 合约地址
     * @param _nftContract NFT 合约地址
     */
    function setNFTContract(address _nftContract) external onlyOwnerOrAuthorizer {
        nftContract = _nftContract;
    }

    /**
     * @dev 内部函数：重置玩家的挑战次数
     * @param player 玩家地址
     */
    function _resetAttempts(address player) internal {
        playerLastResetTime[player] = block.timestamp;
        playerRemainingAttempts[player] = DAILY_ATTEMPTS;
    }

    function _checkAndResetAttempts(address player) internal {
        if (playerLastResetTime[player] == 0 || block.timestamp > playerLastResetTime[player] + 24 hours) {
            _resetAttempts(player);
            rechargeCount[player] = 0;
        }
    }

    function stakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(tokenIds.length > 0 && tokenIds.length <= 6, "ArenaPlayer: Invalid tokenIds count");
        require(nftContract != address(0), "ArenaPlayer: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaPlayer: Invalid token ID");
            // 检查NFT是否已被其他合约质押
            require(nftStakedOwner[tokenId] == address(0), "ArenaPlayer: NFT already staked in this contract");
            // 检查是否在其他质押合约中（需要上层合约配合检查）
            require(nft.ownerOf(tokenId) == msg.sender, "ArenaPlayer: Not owner of token");
            require(nft.isApprovedForAll(msg.sender, address(this)), "ArenaPlayer: Contract not approved for transfer");
            
            nft.safeTransferFrom(msg.sender, address(this), tokenId);
            nftStakedOwner[tokenId] = msg.sender;
            userStakedNFTs[msg.sender].push(tokenId);
        }
        
        emit NFTsStaked(msg.sender, tokenIds);
    }

    function unstakeNFTs(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(nftContract != address(0), "ArenaPlayer: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        bool shouldClearTeam = false;
        uint256[] storage team = playerBattleTeams[msg.sender];
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaPlayer: Invalid token ID");
            require(nftStakedOwner[tokenId] != address(0), "ArenaPlayer: NFT not staked");
            require(nftStakedOwner[tokenId] == msg.sender, "ArenaPlayer: Not owner of staked NFT");
            
            for (uint256 j = 0; j < team.length; j++) {
                if (team[j] == tokenId) {
                    shouldClearTeam = true;
                    break;
                }
            }
            
            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            nftStakedOwner[tokenId] = address(0);
            
            uint256[] storage stakedList = userStakedNFTs[msg.sender];
            for (uint256 j = 0; j < stakedList.length; j++) {
                if (stakedList[j] == tokenId) {
                    stakedList[j] = stakedList[stakedList.length - 1];
                    stakedList.pop();
                    break;
                }
            }
        }
        
        if (shouldClearTeam || userStakedNFTs[msg.sender].length == 0) {
            delete playerBattleTeams[msg.sender];
        }
        
        emit NFTsUnstaked(msg.sender, tokenIds);
    }

    function setBattleTeam(uint256[6] calldata tokenIds) external nonReentrant whenNotPaused {
        require(nftContract != address(0), "ArenaPlayer: NFT contract not set");
        
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "ArenaPlayer: Invalid token ID");
            require(nftStakedOwner[tokenId] == msg.sender, "ArenaPlayer: NFT not staked or not owner");
            
            for (uint256 j = i + 1; j < 6; j++) {
                require(tokenIds[j] != tokenId, "ArenaPlayer: Duplicate token in team");
            }
        }
        
        uint256[] memory teamArray = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            teamArray[i] = tokenIds[i];
        }
        playerBattleTeams[msg.sender] = teamArray;
        
        emit BattleTeamSet(msg.sender, tokenIds);
    }

    function clearBattleTeam() external nonReentrant {
        delete playerBattleTeams[msg.sender];
        emit BattleTeamCleared(msg.sender);
    }

    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        require(user != address(0), "ArenaPlayer: Invalid user address");
        return userStakedNFTs[user];
    }

    function getPlayerBattleTeam(address player) external view returns (uint256[] memory) {
        return playerBattleTeams[player];
    }

    function rechargeChallengeAttempts() external payable nonReentrant whenNotPaused {
        require(IArenaRanking(rankingContract).currentSeasonId() > 0, "ArenaPlayer: No active season");
        
        _checkAndResetAttempts(msg.sender);
        require(rechargeCount[msg.sender] < maxRechargeAttempts, "ArenaPlayer: Max recharge attempts reached");
        // 修复：校�?msg.value >= rechargeCost，恢复付费充值机�?
        require(msg.value >= rechargeCost, "ArenaPlayer: Insufficient BNB for recharge");
        
        // 退还多�?BNB
        if (msg.value > rechargeCost) {
            (bool refundOk, ) = payable(msg.sender).call{value: msg.value - rechargeCost}("");
            require(refundOk, "ArenaPlayer: Refund failed");
        }

        uint256 newAttempts = RECHARGE_ATTEMPTS;
        playerRemainingAttempts[msg.sender] += newAttempts;
        rechargeCount[msg.sender]++;

        emit ChallengeAttemptsRecharged(msg.sender, newAttempts);
    }

    function getRemainingAttempts(address player) external view returns (uint256) {
        if (playerLastResetTime[player] == 0) {
            return DAILY_ATTEMPTS;
        }
        if (block.timestamp > playerLastResetTime[player] + 24 hours) {
            return DAILY_ATTEMPTS;
        }
        return playerRemainingAttempts[player];
    }

    function getPlayerChallengeStatus(address player) external view returns (
        uint256 remainingAttempts,
        uint256 lastBattleTime,
        bool hasTeam
    ) {
        remainingAttempts = playerRemainingAttempts[player];
        lastBattleTime = playerLastBattleTime[player];
        hasTeam = playerBattleTeams[player].length > 0;
    }

    function setMaxRechargeAttempts(uint256 _maxRechargeAttempts) external onlyOwner {
        maxRechargeAttempts = _maxRechargeAttempts;
    }

    function setRechargeCost(uint256 _rechargeCost) external onlyOwner {
        rechargeCost = _rechargeCost;
    }

    function updatePlayerBattleTime(address player, uint256 timestamp) external onlyOwnerOrAuthorizer {
        playerLastBattleTime[player] = timestamp;
    }

    function updatePlayerAttempts(address player, uint256 attempts) external onlyOwnerOrAuthorizer {
        playerRemainingAttempts[player] = attempts;
    }

    function updatePlayerResetTime(address player, uint256 timestamp) external onlyOwnerOrAuthorizer {
        playerLastResetTime[player] = timestamp;
    }

    function generateMockTeam(uint256 seed) external view returns (uint256[6] memory) {
        uint256[6] memory team;
        for (uint256 i = 0; i < 6; i++) {
            uint256 tokenId = (uint256(keccak256(abi.encodePacked(seed, i, block.timestamp))) % 1000000) + 1;
            team[i] = tokenId;
        }
        return team;
    }

    function isNFTStaked(uint256 tokenId) external view returns (bool) {
        return nftStakedOwner[tokenId] != address(0);
    }

    function getNFTStakedOwner(uint256 tokenId) external view returns (address) {
        return nftStakedOwner[tokenId];
    }
}
