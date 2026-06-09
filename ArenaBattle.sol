// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "./NFTInterface.sol";

contract ArenaBattle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    address public rankingContract;
    address public battleContract;
    address public nftContract;
    address public arenaPlayerContract;
    
    uint256 public baseRewardPerWin = 100000000000000000; // 0.1 BNB
    
    uint256 public constant BATTLE_COOLDOWN = 30 seconds;
    uint256 public constant MAX_MOCK_RANKING = 100;
    uint256 public constant TEAM_SIZE = 6;
    uint256 public constant MOCK_ID_OFFSET = 10000;
    uint256 public constant MOCK_ID_MULTIPLIER = 1000;
    
    mapping(uint256 => uint256) public nftBattleLocked;
    mapping(address => uint256) public battleIdCounter;
    mapping(address => uint256) public lastBattleTime;
     
    event BattleExecuted(
        address indexed challenger,
        address indexed challenged,
        bool isVictory,
        uint256 battleId
    );

    modifier onlyAuthorized() {
        require(msg.sender == rankingContract, "ArenaBattle: Not authorized");
        _;
    }

    function initialize(address _rankingContract, address _battleContract, address _nftContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        rankingContract = _rankingContract;
        battleContract = _battleContract;
        nftContract = _nftContract;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRankingContract(address _rankingContract) external onlyOwner {
        rankingContract = _rankingContract;
    }

    function setBattleContract(address _battleContract) external onlyOwner {
        battleContract = _battleContract;
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        nftContract = _nftContract;
    }

    function setArenaPlayerContract(address _arenaPlayerContract) external onlyOwner {
        arenaPlayerContract = _arenaPlayerContract;
    }

    function setBaseRewardPerWin(uint256 _baseRewardPerWin) external onlyOwner {
        baseRewardPerWin = _baseRewardPerWin;
    }

    function executeMockBattle(
        uint256[6] calldata playerTeam,
        uint256 mockIndex
    ) external nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
        require(battleContract != address(0), "ArenaBattle: Battle contract not set");
        require(nftContract != address(0), "ArenaBattle: NFT contract not set");
        require(mockIndex < MAX_MOCK_RANKING, "ArenaBattle: Invalid mock player index");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaBattle: Battle cooldown");

        battleId = ++battleIdCounter[msg.sender];
        lastBattleTime[msg.sender] = block.timestamp;

        _validateTeam(playerTeam);

        uint256[6] memory mockTeam = _generateMockTeam(mockIndex);

        try IBattle(battleContract).challenge(
            playerTeam[0],
            (mockIndex + MOCK_ID_OFFSET) * MOCK_ID_MULTIPLIER,
            playerTeam,
            mockTeam,
            address(0)
        ) returns (bool success, uint256 result) {
            bool victory = result == 1;
            emit BattleExecuted(msg.sender, address(0), victory, battleId);
            return (success, result, battleId);
        } catch {
            revert("ArenaBattle: Battle failed");
        }
    }

    function executeRealBattle(
        address challengedPlayer,
        uint256[6] calldata playerTeam,
        uint256[6] calldata challengedTeam
    ) external nonReentrant whenNotPaused returns (bool success_, uint256 winner, uint256 battleId) {
        require(battleContract != address(0), "ArenaBattle: Battle contract not set");
        require(nftContract != address(0), "ArenaBattle: NFT contract not set");
        require(challengedPlayer != address(0), "ArenaBattle: Invalid challenged player");
        require(challengedPlayer != msg.sender, "ArenaBattle: Cannot challenge self");
        require(block.timestamp >= lastBattleTime[msg.sender] + BATTLE_COOLDOWN, "ArenaBattle: Battle cooldown");
        require(block.timestamp >= lastBattleTime[challengedPlayer] + BATTLE_COOLDOWN, "ArenaBattle: Target in battle cooldown");

        battleId = ++battleIdCounter[msg.sender];
        lastBattleTime[msg.sender] = block.timestamp;
        lastBattleTime[challengedPlayer] = block.timestamp;

        _validateTeam(playerTeam);
        _validateTeam(challengedTeam);

        try IBattle(battleContract).challenge(
            playerTeam[0],
            challengedTeam[0],
            playerTeam,
            challengedTeam,
            challengedPlayer
        ) returns (bool success, uint256 result) {
            bool victory = result == 1;
            emit BattleExecuted(msg.sender, challengedPlayer, victory, battleId);
            return (success, result, battleId);
        } catch {
            revert("ArenaBattle: Battle failed");
        }
    }

    function _validateTeam(uint256[6] memory team) internal view {
        require(nftContract != address(0), "ArenaBattle: NFT contract not set");
        INFT nft = INFT(nftContract);
        
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            uint256 tokenId = team[i];
            require(tokenId > 0, "ArenaBattle: Invalid token ID");
            address owner = nft.ownerOf(tokenId);
            require(owner == msg.sender, "ArenaBattle: NFT not owned");
        }
    }

    function _generateMockTeam(uint256 mockIndex) internal view returns (uint256[TEAM_SIZE] memory) {
        uint256[TEAM_SIZE] memory team;
        for (uint256 i = 0; i < TEAM_SIZE; i++) {
            team[i] = (uint256(keccak256(abi.encodePacked(mockIndex, i, block.timestamp))) % 1000000) + 1;
        }
        return team;
    }

    function _calculateTeamPower(uint256[6] memory team) internal view returns (uint256) {
        uint256 totalPower = 0;
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                uint256 level = INFTMint(nftContract).tokenLevel(team[i]);
                totalPower += level * 100;
            }
        }
        return totalPower;
    }

    function lockNFTsForBattle(uint256[6] calldata team, uint256 battleId) external onlyAuthorized {
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                nftBattleLocked[team[i]] = battleId;
            }
        }
    }

    function unlockNFTsFromBattle(uint256[6] memory team) external onlyAuthorized {
        for (uint256 i = 0; i < team.length; i++) {
            if (team[i] > 0) {
                nftBattleLocked[team[i]] = 0;
            }
        }
    }

    function isNFTLocked(uint256 tokenId) external view returns (bool) {
        return nftBattleLocked[tokenId] > 0;
    }

    function getBattleIdCounter(address player) external view returns (uint256) {
        return battleIdCounter[player];
    }

    function getLastBattleTime(address player) external view returns (uint256) {
        return lastBattleTime[player];
    }

    function simulateBattle(uint256[6] memory playerTeam, uint256 mockIndex) external view returns (bool) {
        uint256 playerPower = _calculateTeamPower(playerTeam);
        uint256 mockPower = (mockIndex % 1000) + 500;
        return playerPower > mockPower;
    }
}
