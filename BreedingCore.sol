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

/**
 * @title BreedingCore - NFT繁殖核心合约
 * @dev 支持自繁殖和市场繁殖两种模式
 */
contract BreedingCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using BreedingLib for *;

    uint256 public selfBreedingCooldown = 12 hours;
    uint256 public marketBreedingCooldown = 24 hours;
    uint256 public selfBreedingFee = 888 * 1e18;
    uint256 public marketBreedingFee = 888 * 1e18;
    address public authorizer;
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
    mapping(address => uint256[]) private _userAllOrderIds;
    mapping(uint256 => mapping(uint256 => bool)) private _breedingPairExists;

    event BreedingPairCreated(uint256 indexed pairId, uint256 indexed fatherId, uint256 indexed motherId, uint256 breedingType);
    event BreedingCompleted(uint256 indexed pairId, uint256 indexed childId, uint256 zodiacType);
    event MaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    event FemaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    event CooldownUpdated(uint256 selfCooldown, uint256 marketCooldown);
    event BreedingFeeBurned(uint256 amount);
    event Paused(address indexed account, string reason);
    event Unpaused(address indexed account);
    event EmergencyNFTLocked(uint256 indexed tokenId, address indexed owner);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);
    event BreedingCancelled(uint256 indexed pairId, uint256 fatherId, uint256 motherId, address indexed canceller);

    modifier whenNotPaused() {
        require(!paused, "BC: P");
        _;
    }

    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "BC: NA");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "BC: IA");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "BC: IA");
        authorizer = _authorizerAddress;
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
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        address stakingContract = IAuthorizer(authorizer).getStaking();
        require(nftMintContract != address(0), "BC: NCS");
        require(fatherId > 0, "BC: IF");
        require(motherId > 0, "BC: IM");
        require(fatherId != motherId, "BC: CSB");
        require(breedingPairCount < MAX_BREEDING_PAIRS, "BC: MP");
        
        if (stakingContract != address(0)) {
            (address fatherStaker, , , , ) = IStaking(stakingContract).stakingInfo(fatherId);
            require(fatherStaker == address(0), "BC: FS");
            (address motherStaker, , , , ) = IStaking(stakingContract).stakingInfo(motherId);
            require(motherStaker == address(0), "BC: MS");
        }

        INFTMint nft = INFTMint(nftMintContract);
        require(nft.ownerOf(fatherId) == msg.sender, "BC: NFO");
        require(nft.ownerOf(motherId) == msg.sender, "BC: NMO");

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        if (coOwnerId > 0) {
            require(nft.ownerOf(coOwnerId) == msg.sender, "BC: NCO");
            require(!isNFTInActiveBreeding[coOwnerId], "BC: COB");
            require(breedingCooldowns[coOwnerId] <= block.timestamp, "BC: COC");
            uint256 coOwnerType = nft.tokenType(coOwnerId);
            uint256 coOwnerZodiac = (coOwnerType / 2) % 12;
            require(coOwnerZodiac == (fatherType / 2) % 12, "BC: COZ");
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
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NCS");
        require(fatherId > 0, "BC: IFID");
        require(motherId > 0, "BC: IMID");
        require(fatherId != motherId, "BC: CBS");
        
        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        address maleOwner = nft.ownerOf(fatherId);
        address femaleOwner = nft.ownerOf(motherId);
        
        require(maleOwner != femaleOwner, "BC: DO");
        require(msg.sender == maleOwner || msg.sender == femaleOwner, "BC: MO");
        
        BreedingLib.checkDailyBreedingLimit(msg.sender, dailyPublicBreedings, lastBreedingDay, maxDailyPublicBreedings);

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        require(nft721.isApprovedForAll(maleOwner, address(this)), "BC: FNA");
        require(nft721.isApprovedForAll(femaleOwner, address(this)), "BC: MNA");

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
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NCS");
        
        INFTMint nft = INFTMint(nftMintContract);
        _validateBreedingPair(nft, fatherId, motherId);

        _breedingPairExists[fatherId][motherId] = true;
        _breedingPairExists[motherId][fatherId] = true;
        breedingPairCount++;
        pairId = breedingPairCount;
        
        _createBreedingPair(pairId, fatherId, motherId, maleOwner, femaleOwner, breedingType);
        _finalizeBreedTransaction(nftMintContract, fatherId, motherId, maleOwner, femaleOwner, fee, cooldown, pairId);
        
        emit BreedingPairCreated(pairId, fatherId, motherId, breedingType);
    }

    function _validateBreedingPair(INFTMint nft, uint256 fatherId, uint256 motherId) private view {
        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "BC: L5");
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "BC: DZ");
        require((fatherType % 2) != (motherType % 2), "BC: SG");
        require(breedingCooldowns[fatherId] <= block.timestamp, "BC: FC");
        require(breedingCooldowns[motherId] <= block.timestamp, "BC: MC");
        require(!isNFTInActiveBreeding[fatherId], "BC: FB");
        require(!isNFTInActiveBreeding[motherId], "BC: MB");
        require(!_breedingPairExists[fatherId][motherId] && !_breedingPairExists[motherId][fatherId], "BC: PAE");
    }

    function _createBreedingPair(
        uint256 pairId, uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner, uint256 breedingType
    ) private {
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: 0, femaleCoOwnerId: 0, startTime: block.timestamp,
            breedingType: breedingType, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false,
            cancelledAt: 0
        });
    }

    function _finalizeBreedTransaction(
        address nftMintContract,
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee, uint256 cooldown,
        uint256 pairId
    ) private {
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        address tokenContract = IAuthorizer(authorizer).getToken();
        
        _transferBreedingNFTs(nft721, fatherId, motherId, maleOwner, femaleOwner, fee, tokenContract);

        if (fee > 0) {
            require(tokenContract != address(0), "BC: TNS");
            IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), fee);
        }

        isNFTInActiveBreeding[fatherId] = true;
        isNFTInActiveBreeding[motherId] = true;
        breedingCooldowns[fatherId] = block.timestamp + cooldown;
        breedingCooldowns[motherId] = block.timestamp + cooldown;
        BreedingLib.addActiveOrder(maleOwner, pairId, _userActiveOrderIds);
        _userAllOrderIds[maleOwner].push(pairId);
        if (maleOwner != femaleOwner) {
            _userAllOrderIds[femaleOwner].push(pairId);
        }
    }

    function _transferBreedingNFTs(
        IERC721Upgradeable nft,
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee, address tokenContract
    ) internal {
        bool fatherTransferred = false;
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();

        try nft.safeTransferFrom(maleOwner, address(this), fatherId) {
            fatherTransferred = true;
        } catch {
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert("BC: FTF");
        }
        _syncWeightAfterTransfer(maleOwner, address(this), fatherId, nftMintContract);

        try nft.safeTransferFrom(femaleOwner, address(this), motherId) {
        } catch {
            if (fatherTransferred) {
                bool revertOnFailure = false;
                try nft.safeTransferFrom(address(this), maleOwner, fatherId) {
                    _syncWeightAfterTransfer(address(this), maleOwner, fatherId, nftMintContract);
                } catch {
                    emit EmergencyNFTLocked(fatherId, maleOwner);
                    revertOnFailure = true;
                }
                if (revertOnFailure) {
                    revert("BC: MTF2");
                }
            }
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert("BC: MTF");
        }
        _syncWeightAfterTransfer(femaleOwner, address(this), motherId, nftMintContract);
    }

    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    function cancelBreeding(uint256 pairId) external nonReentrant whenNotPaused {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "BC: PNA");
        require(pair.childId == 0, "BC: AC");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "BC: NPO");
        
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NCS");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp < pair.startTime + cooldown, "BC: CCC");

        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        
        pair.status = BREEDING_STATUS_CANCELLED;
        _breedingPairExists[pair.fatherId][pair.motherId] = false;
        _breedingPairExists[pair.motherId][pair.fatherId] = false;
        pair.cancelledAt = block.timestamp;
        
        isNFTInActiveBreeding[pair.fatherId] = false;
        isNFTInActiveBreeding[pair.motherId] = false;
        
        breedingCooldowns[pair.fatherId] = 0;
        breedingCooldowns[pair.motherId] = 0;

        BreedingLib.removeActiveOrder(pair.maleOwner, pairId, _userActiveOrderIds);
        BreedingLib.removeActiveOrder(pair.femaleOwner, pairId, _userActiveOrderIds);
        
        address fatherOwner = pair.maleOwner;
        address motherOwner = pair.femaleOwner;
        
        try nft721.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {
        } catch {
            emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
        }
        _syncWeightAfterTransfer(address(this), fatherOwner, pair.fatherId, nftMintContract);
        
        try nft721.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {
        } catch {
            emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
        }
        _syncWeightAfterTransfer(address(this), motherOwner, pair.motherId, nftMintContract);
        
        emit BreedingCancelled(pairId, pair.fatherId, pair.motherId, msg.sender);
    }

    function completeBreeding(uint256 pairId) external nonReentrant whenNotPaused returns (uint256, uint256) {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "BC: PNA");
        require(pair.childId == 0, "BC: AC");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "BC: NPO");
        
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NCS");

        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        require(nft721.ownerOf(pair.fatherId) == address(this), "BC: FNH");
        require(nft721.ownerOf(pair.motherId) == address(this), "BC: MNH");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "BC: CNE");

        INFTMint nft = INFTMint(nftMintContract);

        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            block.prevrandao,
            pairId,
            tx.gasprice,
            msg.sender
        )));
        
        uint256 zodiacType = _getChildZodiacType(nft, pair.fatherId, pair.motherId, seed);
        require(zodiacType > 0, "BC: ICT");

        if (pair.breedingType == BREEDING_TYPE_SELF) {
            return _completeSelfBreeding(pairId, nft, nft721, pair, zodiacType, seed);
        } else {
            return _completeMarketBreeding(pairId, nft, nft721, pair, zodiacType, seed);
        }
    }

    function _completeSelfBreeding(
        uint256 pairId,
        INFTMint nft,
        IERC721Upgradeable nft721,
        BreedingPair storage pair,
        uint256 zodiacType,
        uint256 seed
    ) private returns (uint256, uint256) {
        uint8 childGrowth = uint8((seed % 91) + 10);
        uint256 childId = nft.mintForBreeding(pair.femaleOwner, zodiacType, childGrowth);
        require(childId > 0, "BC: NMF");

        pair.childId = childId;
        pair.status = 1;
        
        _finalizeBreeding(pairId, pair, nft721);
        
        emit BreedingCompleted(pairId, childId, zodiacType);
        return (childId, 0);
    }

    function _completeMarketBreeding(
        uint256 pairId,
        INFTMint nft,
        IERC721Upgradeable nft721,
        BreedingPair storage pair,
        uint256 zodiacType,
        uint256 seed
    ) private returns (uint256, uint256) {
        uint8 femaleChildGrowth = uint8((seed % 91) + 10);
        uint8 maleChildGrowth = uint8(((seed >> 32) % 91) + 10);

        uint256 childIdForFemale = nft.mintForBreeding(pair.femaleOwner, zodiacType, femaleChildGrowth);
        require(childIdForFemale > 0, "BC: FCMF");

        uint256 childIdForMale = nft.mintForBreeding(pair.maleOwner, zodiacType, maleChildGrowth);
        require(childIdForMale > 0, "BC: MCMF");

        pair.childId = childIdForFemale;
        pair.maleChildId = childIdForMale;
        pair.status = 1;
        
        _finalizeBreeding(pairId, pair, nft721);
        
        emit BreedingCompleted(pairId, childIdForFemale, zodiacType);
        emit MaleChildGenerated(pairId, childIdForMale);
        emit FemaleChildGenerated(pairId, childIdForFemale);
        return (childIdForFemale, childIdForMale);
    }

    function _finalizeBreeding(
        uint256 pairId,
        BreedingPair storage pair,
        IERC721Upgradeable nft721
    ) private {
        _breedingPairExists[pair.fatherId][pair.motherId] = false;
        _breedingPairExists[pair.motherId][pair.fatherId] = false;
        isNFTInActiveBreeding[pair.fatherId] = false;
        isNFTInActiveBreeding[pair.motherId] = false;
        BreedingLib.removeActiveOrder(pair.maleOwner, pairId, _userActiveOrderIds);
        BreedingLib.removeActiveOrder(pair.femaleOwner, pairId, _userActiveOrderIds);

        _burnFee(pair.breedingType);

        address fatherOwner = pair.maleOwner;
        address motherOwner = pair.femaleOwner;
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();

        try nft721.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {} catch { emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner); }
        _syncWeightAfterTransfer(address(this), fatherOwner, pair.fatherId, nftMintContract);
        try nft721.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {} catch { emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner); }
        _syncWeightAfterTransfer(address(this), motherOwner, pair.motherId, nftMintContract);
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

    function _getChildZodiacType(INFTMint nftMint, uint256 fatherId, uint256 motherId, uint256 randomSeed) internal view returns (uint256) {
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "BC: PZM");

        uint256 seed = uint256(keccak256(abi.encodePacked(
            fatherId, 
            motherId, 
            randomSeed,
            block.timestamp,
            block.number,
            block.prevrandao,
            tx.gasprice,
            msg.sender
        )));
        uint256 fatherElement = fatherType / 24;
        uint256 motherElement = motherType / 24;
        uint256 inheritedElement = (seed % 2 == 0) ? fatherElement : motherElement;
        uint256 inheritedGender = (seed / 2) % 2;
        return inheritedElement * 24 + fatherZodiac * 2 + inheritedGender;
    }

    function _burnFee(uint256 breedingType) internal {
        address tokenContract = IAuthorizer(authorizer).getToken();
        if (tokenContract == address(0)) return;
        uint256 fee = breedingType == BREEDING_TYPE_SELF ? selfBreedingFee : marketBreedingFee;
        if (fee == 0) return;
        IERC20 token = IERC20(tokenContract);
        
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= fee, "BC: IBFB");
        
        token.safeTransfer(BLACK_HOLE, fee);
        emit BreedingFeeBurned(fee);
    }

    function setSelfBreedingFee(uint256 fee) external onlyOwner { 
        selfBreedingFee = fee; 
    }

    function setMarketBreedingFee(uint256 fee) external onlyOwner { 
        marketBreedingFee = fee; 
    }

    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: CM0"); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: CM0"); 
        marketBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function getUserActiveOrders(address user) external view returns (uint256[] memory) {
        uint256[] storage orderIds = _userActiveOrderIds[user];
        uint256 length = orderIds.length;
        uint256[] memory result = new uint256[](length);
        uint256 idx = 0;
        for (uint256 i = 0; i < length; i++) {
            if (breedingPairs[orderIds[i]].status == BREEDING_STATUS_ACTIVE) {
                result[idx] = orderIds[i];
                idx++;
            }
        }
        assembly {
            mstore(result, idx)
        }
        return result;
    }

    function getUserBreedingStats(address user) external view returns (
        uint256 totalPairs,
        uint256 activePairs,
        uint256 completedPairs,
        uint256 claimablePairs
    ) {
        uint256[] storage orderIds = _userAllOrderIds[user];
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        
        for (uint256 i = 0; i < orderIds.length; i++) {
            BreedingPair memory pair = breedingPairs[orderIds[i]];
            bool isRelated = (pair.maleOwner == user || pair.femaleOwner == user);
            if (!isRelated && nftMintContract != address(0)) {
                INFTMint nftMint = INFTMint(nftMintContract);
                if (pair.maleCoOwnerId != 0 && nftMint.ownerOf(pair.maleCoOwnerId) == user) isRelated = true;
                if (!isRelated && pair.femaleCoOwnerId != 0 && nftMint.ownerOf(pair.femaleCoOwnerId) == user) isRelated = true;
            }

            if (isRelated) {
                totalPairs++;
                if (pair.status == 0) activePairs++;
                else if (pair.status == 1) {
                    completedPairs++;
                    if (!pair.rewardsClaimed) claimablePairs++;
                }
            }
        }
    }

    function getBreedingPairWithCooldown(uint256 pairId) external view returns (
        uint256 fatherId, uint256 motherId, uint256 fatherCooldown,
        uint256 motherCooldown, uint256 remainingTime, uint256 status
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        fatherId = pair.fatherId;
        motherId = pair.motherId;
        fatherCooldown = breedingCooldowns[pair.fatherId];
        motherCooldown = breedingCooldowns[pair.motherId];
        status = pair.status;
        remainingTime = 0;
        if (pair.status == 0 && pair.startTime > 0) {
            uint256 endTime = pair.startTime + (pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown);
            if (block.timestamp < endTime) remainingTime = endTime - block.timestamp;
        }
    }

    function emergencyWithdraw(uint256 tokenType, uint256 tokenIdOrAmount, uint256 amount) external onlyOwner nonReentrant {
        if (tokenType == 0) {
            require(tokenIdOrAmount > 0, "BC: A0");
            require(tokenIdOrAmount <= address(this).balance, "BC: IS");
            (bool success, ) = payable(owner()).call{value: tokenIdOrAmount}("");
            require(success, "BC: BF");
            emit EmergencyBNBWithdrawn(msg.sender, owner(), tokenIdOrAmount);
        } else if (tokenType == 1) {
            require(amount > 0, "BC: A0");
            address tokenContract = IAuthorizer(authorizer).getToken();
            require(tokenContract != address(0), "BC: TNS");
            IERC20 token = IERC20(tokenContract);
            require(token.balanceOf(address(this)) >= amount, "BC: IS");
            token.safeTransfer(owner(), amount);
            emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
        } else {
            address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
            require(nftMintContract != address(0), "BC: NCS");
            require(!isNFTInActiveBreeding[tokenIdOrAmount], "BC: NB");
            IERC721Upgradeable(nftMintContract).safeTransferFrom(address(this), owner(), tokenIdOrAmount);
            BreedingLib.syncWeightAfterTransfer(authorizer, address(this), owner(), tokenIdOrAmount);
            emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenIdOrAmount);
        }
    }

    function _syncWeightAfterTransfer(address from, address to, uint256 tokenId, address nftContract) internal {
        BreedingLib.syncWeightAfterTransfer(authorizer, from, to, tokenId);
    }

    receive() external payable {}
    fallback() external payable {}
}