// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BreedingLib.sol";

contract BreedingCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using BreedingLib for *;

    uint256 public selfBreedingCooldown = 12 hours;
    uint256 public marketBreedingCooldown = 24 hours;
    uint256 public selfBreedingFee = 888 * 1e18;
    uint256 public marketBreedingFee = 888 * 1e18;
    address public nftMintContract;
    address public authorizer;
    address public tokenContract;
    address public stakingContract;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant BREEDING_TYPE_SELF = 0;
    uint256 public constant BREEDING_TYPE_MARKET = 1;
    uint256 public constant MAX_BREEDING_PAIRS = 10000;

    uint256 public maxDailyPublicBreedings = 5;
    mapping(address => uint256) public dailyPublicBreedings;
    mapping(address => uint256) public lastBreedingDay;

    bool public paused;
    string public pauseReason;

    uint256 public constant BREEDING_STATUS_ACTIVE = 0;
    uint256 public constant BREEDING_STATUS_COMPLETED = 1;
    uint256 public constant BREEDING_STATUS_CANCELLED = 2;

    struct BreedingPair {
        uint256 fatherId;
        uint256 motherId;
        address maleOwner;
        address femaleOwner;
        uint256 maleCoOwnerId;
        uint256 femaleCoOwnerId;
        uint256 startTime;
        uint256 breedingType;
        uint256 status;
        uint256 childId;
        uint256 maleChildId;
        bool rewardsClaimed;
        uint256 cancelledAt;
    }

    mapping(uint256 => BreedingPair) public breedingPairs;
    uint256 public breedingPairCount;
    mapping(uint256 => uint256) public breedingCooldowns;
    mapping(uint256 => bool) public isNFTInActiveBreeding;
    mapping(address => uint256[]) private _userActiveOrderIds;
    mapping(uint256 => mapping(uint256 => bool)) private _breedingPairExists;

    event BreedingPairCreated(uint256 indexed pairId, uint256 indexed fatherId, uint256 indexed motherId, uint256 breedingType);
    event BreedingCompleted(uint256 indexed pairId, uint256 indexed childId, uint256 zodiacType);
    event MaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    event FemaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    event CooldownUpdated(uint256 selfCooldown, uint256 marketCooldown);
    event BreedingFeeBurned(uint256 amount);
    event Paused(address indexed account, string reason);
    event Unpaused(address indexed account);
    event NFTContractSet(address indexed nftContract);
    event TokenContractSet(address indexed tokenContract);
    event EmergencyNFTLocked(uint256 indexed tokenId, address indexed owner);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);
    event BreedingCancelled(uint256 indexed pairId, uint256 fatherId, uint256 motherId, address indexed canceller);

    modifier whenNotPaused() {
        require(!paused, "BC: Paused");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "BC: Not authorized");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "BC: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "BC: Invalid authorizer address");
        authorizer = a;
    }

    function setStakingContract(address _stakingContract) external onlyOwner {
        require(_stakingContract != address(0), "BC: Invalid staking contract address");
        stakingContract = _stakingContract;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external nonReentrant whenNotPaused returns (uint256) {
        require(fatherId > 0, "BC: Invalid father");
        require(motherId > 0, "BC: Invalid mother");
        require(fatherId != motherId, "BC: Cannot self-breed");
        require(breedingPairCount < MAX_BREEDING_PAIRS, "BC: Max pairs");
        
        if (stakingContract != address(0)) {
            (address fatherStaker, , , , ) = IStaking(stakingContract).stakingInfo(fatherId);
            require(fatherStaker == address(0), "BC: Father staked");
            (address motherStaker, , , , ) = IStaking(stakingContract).stakingInfo(motherId);
            require(motherStaker == address(0), "BC: Mother staked");
        }

        INFTMint nft = INFTMint(nftMintContract);
        require(nft.ownerOf(fatherId) == msg.sender, "BC: Not father owner");
        require(nft.ownerOf(motherId) == msg.sender, "BC: Not mother owner");

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        if (coOwnerId > 0) {
            require(nft.ownerOf(coOwnerId) == msg.sender, "BC: Not co-owner");
            require(!isNFTInActiveBreeding[coOwnerId], "BC: Co-owner breeding");
            uint256 coOwnerType = nft.tokenType(coOwnerId);
            uint256 coOwnerZodiac = (coOwnerType / 2) % 12;
            require(coOwnerZodiac == (fatherType / 2) % 12, "BC: Co-owner zodiac");
        }

        return _breedCommon(
            fatherId, motherId, msg.sender, msg.sender,
            selfBreedingFee, selfBreedingCooldown,
            0
        );
    }

    function createMarketBreedingPairPublic(
        uint256 fatherId, uint256 motherId
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(fatherId > 0, "BC: Invalid father ID");
        require(motherId > 0, "BC: Invalid mother ID");
        require(fatherId != motherId, "BC: Cannot breed with self");
        
        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        address maleOwner = nft.ownerOf(fatherId);
        address femaleOwner = nft.ownerOf(motherId);
        
        require(maleOwner != femaleOwner, "BC: Diff owners");
        require(msg.sender == maleOwner || msg.sender == femaleOwner, "BC: Must be owner");
        
        BreedingLib.checkDailyBreedingLimit(msg.sender, dailyPublicBreedings, lastBreedingDay, maxDailyPublicBreedings);

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        require(nft721.isApprovedForAll(maleOwner, address(this)), "BC: Father not approved");
        require(nft721.isApprovedForAll(femaleOwner, address(this)), "BC: Mother not approved");

        uint256 pairId = _breedCommon(
            fatherId, motherId, maleOwner, femaleOwner,
            marketBreedingFee, marketBreedingCooldown,
            1
        );
        
        BreedingLib.updateDailyBreedingCount(msg.sender, dailyPublicBreedings, lastBreedingDay);
        BreedingLib.addActiveOrder(femaleOwner, pairId, _userActiveOrderIds);
        return pairId;
    }

    function _breedCommon(
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee, uint256 cooldown,
        uint256 breedingType
    ) internal returns (uint256 pairId) {
        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "BC: Level < 5");
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "BC: Diff zodiac");
        require((fatherType % 2) != (motherType % 2), "BC: Same gender");
        require(breedingCooldowns[fatherId] <= block.timestamp, "BC: Father cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "BC: Mother cooldown");
        require(!isNFTInActiveBreeding[fatherId], "BC: Father breeding");
        require(!isNFTInActiveBreeding[motherId], "BC: Mother breeding");
        require(nftMintContract != address(0), "BC: NFT contract not set");
        require(!_breedingPairExists[fatherId][motherId], "BC: Pair already exists");

        if (fee > 0) {
            require(tokenContract != address(0), "BC: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), fee), "BC: Fee transfer failed");
        }

        _breedingPairExists[fatherId][motherId] = true;
        breedingPairCount++;
        pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: 0, femaleCoOwnerId: 0, startTime: block.timestamp,
            breedingType: breedingType, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false,
            cancelledAt: 0
        });

        _transferBreedingNFTs(nft721, fatherId, motherId, maleOwner, femaleOwner, fee);

        isNFTInActiveBreeding[fatherId] = true;
        isNFTInActiveBreeding[motherId] = true;
        breedingCooldowns[fatherId] = block.timestamp + cooldown;
        breedingCooldowns[motherId] = block.timestamp + cooldown;
        BreedingLib.addActiveOrder(maleOwner, pairId, _userActiveOrderIds);
        emit BreedingPairCreated(pairId, fatherId, motherId, breedingType);
    }

    function _transferBreedingNFTs(
        IERC721Upgradeable nft,
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee
    ) internal {
        bool fatherTransferred = false;

        try nft.safeTransferFrom(maleOwner, address(this), fatherId) {
            fatherTransferred = true;
        } catch {
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert("BC: Father transfer failed");
        }

        try nft.safeTransferFrom(femaleOwner, address(this), motherId) {
        } catch {
            if (fatherTransferred) {
                try nft.safeTransferFrom(address(this), maleOwner, fatherId) {} 
                catch { emit EmergencyNFTLocked(fatherId, maleOwner); }
            }
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert("BC: Mother transfer failed");
        }
    }

    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    function cancelBreeding(uint256 pairId) external nonReentrant whenNotPaused {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "BC: Pair not active");
        require(pair.childId == 0, "BC: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "BC: Not pair owner");
        require(nftMintContract != address(0), "BC: NFT contract not set");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp < pair.startTime + cooldown, "BC: Cannot cancel after cooldown ended");

        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        
        pair.status = BREEDING_STATUS_CANCELLED;
        pair.cancelledAt = block.timestamp;
        
        isNFTInActiveBreeding[pair.fatherId] = false;
        isNFTInActiveBreeding[pair.motherId] = false;
        
        breedingCooldowns[pair.fatherId] = 0;
        breedingCooldowns[pair.motherId] = 0;

        BreedingLib.removeActiveOrder(pair.maleOwner, pairId, _userActiveOrderIds);
        BreedingLib.removeActiveOrder(pair.femaleOwner, pairId, _userActiveOrderIds);
        
        try nft721.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {
        } catch {
            emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
        }
        
        try nft721.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {
        } catch {
            emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
        }
        
        emit BreedingCancelled(pairId, pair.fatherId, pair.motherId, msg.sender);
    }

    function completeBreeding(uint256 pairId) external nonReentrant whenNotPaused returns (uint256, uint256) {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "BC: Pair not active");
        require(pair.childId == 0, "BC: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "BC: Not pair owner");
        require(nftMintContract != address(0), "BC: NFT contract not set");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "BC: Cooldown not ended");

        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        uint256 zodiacType = _getChildZodiacType(pair.fatherId, pair.motherId);
        require(zodiacType > 0, "BC: Invalid child zodiac type");

        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, pairId, tx.gasprice)));
        uint8 childGrowth = uint8((seed % 91) + 10);

        if (pair.breedingType == BREEDING_TYPE_SELF) {
            uint256 childId = nft.mintForBreeding(pair.femaleOwner, zodiacType, childGrowth);
            require(childId > 0, "BC: NFT mint failed");

            pair.childId = childId;
            pair.status = 1;
            isNFTInActiveBreeding[pair.fatherId] = false;
            isNFTInActiveBreeding[pair.motherId] = false;
            BreedingLib.removeActiveOrder(pair.maleOwner, pairId, _userActiveOrderIds);
            BreedingLib.removeActiveOrder(pair.femaleOwner, pairId, _userActiveOrderIds);

            _burnFee(pair.breedingType);

            try nft721.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {} catch { emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner); }
            try nft721.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {} catch { emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner); }

            emit BreedingCompleted(pairId, childId, zodiacType);
            return (childId, 0);
        } else {
            uint8 femaleChildGrowth = uint8((seed % 91) + 10);
            uint8 maleChildGrowth = uint8(((seed + 1000) % 91) + 10);

            uint256 childIdForFemale = nft.mintForBreeding(pair.femaleOwner, zodiacType, femaleChildGrowth);
            require(childIdForFemale > 0, "BC: Female child mint failed");

            uint256 childIdForMale = nft.mintForBreeding(pair.maleOwner, zodiacType, maleChildGrowth);
            require(childIdForMale > 0, "BC: Male child mint failed");

            pair.childId = childIdForFemale;
            pair.maleChildId = childIdForMale;
            pair.status = 1;
            isNFTInActiveBreeding[pair.fatherId] = false;
            isNFTInActiveBreeding[pair.motherId] = false;
            BreedingLib.removeActiveOrder(pair.maleOwner, pairId, _userActiveOrderIds);
            BreedingLib.removeActiveOrder(pair.femaleOwner, pairId, _userActiveOrderIds);

            _burnFee(pair.breedingType);

            try nft721.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {} catch { emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner); }
            try nft721.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {} catch { emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner); }

            emit BreedingCompleted(pairId, childIdForFemale, zodiacType);
            emit MaleChildGenerated(pairId, childIdForMale);
            emit FemaleChildGenerated(pairId, childIdForFemale);
            return (childIdForFemale, childIdForMale);
        }
    }

    function getBreedingInfo(uint256 pairId) external view returns (
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner,
        uint256 maleCoOwnerId,
        uint256 femaleCoOwnerId,
        uint256 startTime,
        uint256 breedingType,
        uint256 status,
        uint256 childId,
        uint256 maleChildId,
        bool rewardsClaimed
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        return (
            pair.fatherId,
            pair.motherId,
            pair.maleOwner,
            pair.femaleOwner,
            pair.maleCoOwnerId,
            pair.femaleCoOwnerId,
            pair.startTime,
            pair.breedingType,
            pair.status,
            pair.childId,
            pair.maleChildId,
            pair.rewardsClaimed
        );
    }

    function isInCooldown(uint256 tokenId) public view returns (bool) { 
        return breedingCooldowns[tokenId] > block.timestamp; 
    }

    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) { 
        return breedingCooldowns[tokenId]; 
    }

    function _getChildZodiacType(uint256 fatherId, uint256 motherId) internal view returns (uint256) {
        if (nftMintContract == address(0)) return 0;
        INFTMint nftMint = INFTMint(nftMintContract);
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "BC: Parent zodiac mismatch");

        uint256 seed = uint256(keccak256(abi.encodePacked(
            fatherId, 
            motherId, 
            block.timestamp,
            block.number,
            block.difficulty,
            tx.gasprice
        )));
        uint256 fatherElement = fatherType / 24;
        uint256 motherElement = motherType / 24;
        uint256 inheritedElement = (seed % 2 == 0) ? fatherElement : motherElement;
        uint256 inheritedGender = (seed / 2) % 2;
        return inheritedElement * 24 + fatherZodiac * 2 + inheritedGender;
    }

    function _burnFee(uint256 breedingType) internal {
        if (tokenContract == address(0)) return;
        uint256 fee = breedingType == BREEDING_TYPE_SELF ? selfBreedingFee : marketBreedingFee;
        if (fee == 0) return;
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= fee, "BC: Insufficient fee balance");
        require(token.transfer(BLACK_HOLE, fee), "BC: Fee burn transfer failed");
        emit BreedingFeeBurned(fee);
    }

    function setSelfBreedingFee(uint256 fee) external onlyOwner { 
        selfBreedingFee = fee; 
    }

    function setMarketBreedingFee(uint256 fee) external onlyOwner { 
        marketBreedingFee = fee; 
    }

    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: Cooldown must be > 0"); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: Cooldown must be > 0"); 
        marketBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function setNFTContract(address _nftContract) external onlyAuthorized { 
        require(_nftContract != address(0), "BC: Invalid NFT contract address"); 
        nftMintContract = _nftContract; 
        emit NFTContractSet(nftMintContract); 
    }

    function setTokenContract(address _tokenContract) external onlyAuthorized { 
        require(_tokenContract != address(0), "BC: Invalid token contract address"); 
        tokenContract = _tokenContract; 
        emit TokenContractSet(_tokenContract); 
    }

    function getUserActiveOrders(address user) external view returns (uint256[] memory) {
        uint256[] storage orderIds = _userActiveOrderIds[user];
        uint256 activeCount = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (breedingPairs[orderIds[i]].status == BREEDING_STATUS_ACTIVE) {
                activeCount++;
            }
        }
        uint256[] memory result = new uint256[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (breedingPairs[orderIds[i]].status == BREEDING_STATUS_ACTIVE) {
                result[idx] = orderIds[i];
                idx++;
            }
        }
        return result;
    }

    function getNFTBreedingCooldown(uint256 tokenId) public view returns (uint256 remainingCooldown) {
        if (breedingCooldowns[tokenId] == 0) {
            return 0;
        }
        if (block.timestamp >= breedingCooldowns[tokenId]) {
            return 0;
        }
        return breedingCooldowns[tokenId] - block.timestamp;
    }

    function getUserBreedingStats(address user) external view returns (
        uint256 totalPairs,
        uint256 activePairs,
        uint256 completedPairs,
        uint256 claimablePairs
    ) {
        uint256 pairCount = breedingPairCount;
        totalPairs = 0;
        activePairs = 0;
        completedPairs = 0;
        claimablePairs = 0;

        for (uint256 i = 1; i <= pairCount; i++) {
            BreedingPair memory pair = breedingPairs[i];
            bool isRelated = (pair.maleOwner == user || pair.femaleOwner == user);
            if (pair.maleCoOwnerId != 0) {
                if (INFTMint(nftMintContract).ownerOf(pair.maleCoOwnerId) == user) {
                    isRelated = true;
                }
            }
            if (pair.femaleCoOwnerId != 0) {
                if (INFTMint(nftMintContract).ownerOf(pair.femaleCoOwnerId) == user) {
                    isRelated = true;
                }
            }

            if (isRelated) {
                totalPairs++;
                if (pair.status == 0) {
                    activePairs++;
                } else if (pair.status == 1) {
                    completedPairs++;
                    if (!pair.rewardsClaimed) {
                        claimablePairs++;
                    }
                }
            }
        }
    }

    function getBreedingPairWithCooldown(uint256 pairId) external view returns (
        uint256 fatherId,
        uint256 motherId,
        uint256 fatherCooldown,
        uint256 motherCooldown,
        uint256 remainingTime,
        uint256 status
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        fatherId = pair.fatherId;
        motherId = pair.motherId;
        fatherCooldown = getNFTBreedingCooldown(pair.fatherId);
        motherCooldown = getNFTBreedingCooldown(pair.motherId);
        status = pair.status;

        if (pair.status == 0) {
            if (pair.startTime > 0) {
                uint256 breedingDuration = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
                if (block.timestamp >= pair.startTime + breedingDuration) {
                    remainingTime = 0;
                } else {
                    remainingTime = pair.startTime + breedingDuration - block.timestamp;
                }
            } else {
                remainingTime = 0;
            }
        } else {
            remainingTime = 0;
        }
    }

    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "BC: Amount must be > 0");
        require(amount <= address(this).balance, "BC: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "BC: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "BC: Amount must be > 0");
        require(tokenContract != address(0), "BC: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "BC: Insufficient token balance");
        require(token.transfer(owner(), amount), "BC: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawNFT(uint256 tokenId) external onlyOwner nonReentrant {
        require(nftMintContract != address(0), "BC: NFT contract not set");
        require(!isNFTInActiveBreeding[tokenId], "BC: NFT in active breeding");
        IERC721Upgradeable nft = IERC721Upgradeable(nftMintContract);
        nft.safeTransferFrom(address(this), owner(), tokenId);
        emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenId);
    }

    receive() external payable {}
    fallback() external payable {}
}