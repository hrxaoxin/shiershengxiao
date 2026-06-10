// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";

contract ArenaPlayer is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    address public rankingContract;
    address public nftContract;
    address public authorizer;
    
    uint256 public constant MAX_TEAM_SIZE = 6;
    uint256 public constant MOCK_PLAYER_INDEX_OFFSET = 1000000;
    
    uint256 public maxRechargeAttempts = 5;
    uint256 public rechargeCost = 1000000000000000000; // 1 BNB
    
    mapping(address => uint256[]) public playerBattleTeams;
    mapping(uint256 => address) public nftStakedOwner;
    mapping(address => uint256[]) public userStakedNFTs;
    mapping(address => uint256) public playerLastBattleTime;
    mapping(address => uint256) public playerRemainingAttempts;
    mapping(address => uint256) public playerLastResetTime;
    mapping(address => uint256) public rechargeCount;
    
    uint256 public constant DAILY_ATTEMPTS = 3;
    uint256 public constant RECHARGE_ATTEMPTS = 3;
    uint256 public constant RECHARGE_COST = 888;
    
    event BattleTeamSet(address indexed player, uint256[6] tokenIds);
    event BattleTeamCleared(address indexed player);
    event NFTsStaked(address indexed player, uint256[] tokenIds);
    event NFTsUnstaked(address indexed player, uint256[] tokenIds);
    event ChallengeAttemptsRecharged(address indexed player, uint256 attempts);
    event MockTeamGenerated(address indexed player, uint256[6] team);

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer || msg.sender == rankingContract, "ArenaPlayer: Not authorized");
        _;
    }

    function initialize(address _rankingContract, address _nftContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        rankingContract = _rankingContract;
        nftContract = _nftContract;
        authorizer = _authorizer;
    }
    
    function setAuthorizer(address _authorizer) external onlyOwner {
        require(_authorizer != address(0), "ArenaPlayer: Invalid authorizer address");
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRankingContract(address _rankingContract) external onlyAuthorized {
        rankingContract = _rankingContract;
    }

    function setNFTContract(address _nftContract) external onlyAuthorized {
        nftContract = _nftContract;
    }

    function _resetAttempts(address player) internal {
        playerLastResetTime[player] = block.timestamp;
        playerRemainingAttempts[player] = DAILY_ATTEMPTS;
    }

    function _checkAndResetAttempts(address player) internal {
        if (block.timestamp > playerLastResetTime[player] + 24 hours) {
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
            require(nft.ownerOf(tokenId) == msg.sender, "ArenaPlayer: Not owner of token");
            require(nftStakedOwner[tokenId] == address(0), "ArenaPlayer: NFT already staked");
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

    function rechargeChallengeAttempts() external nonReentrant whenNotPaused {
        require(IArenaRanking(rankingContract).currentSeasonId() > 0, "ArenaPlayer: No active season");

        uint256 newAttempts = RECHARGE_ATTEMPTS;
        _checkAndResetAttempts(msg.sender);
        
        playerRemainingAttempts[msg.sender] += newAttempts;
        rechargeCount[msg.sender]++;

        emit ChallengeAttemptsRecharged(msg.sender, newAttempts);
    }

    function getRemainingAttempts(address player) external view returns (uint256) {
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

    function updatePlayerBattleTime(address player, uint256 timestamp) external onlyAuthorized {
        playerLastBattleTime[player] = timestamp;
    }

    function updatePlayerAttempts(address player, uint256 attempts) external onlyAuthorized {
        playerRemainingAttempts[player] = attempts;
    }

    function updatePlayerResetTime(address player, uint256 timestamp) external onlyAuthorized {
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
