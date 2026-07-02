// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BreedingLib.sol";

contract BreedingExecutor is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IBreedingExecutor {
    using SafeERC20 for IERC20;
    using BreedingLib for *;

    address public authorizer;

    uint256 public constant BREEDING_TYPE_SELF = 0;
    uint256 public constant BREEDING_TYPE_MARKET = 1;

    uint256 public constant BREEDING_STATUS_ACTIVE = 0;
    uint256 public constant BREEDING_STATUS_COMPLETED = 1;
    uint256 public constant BREEDING_STATUS_CANCELLED = 2;

    uint256 public constant MAX_BREEDING_PAIRS = 10000;

    error AuthorizerNotSet();
    error InvalidAuthorizer();
    error NFTContractNotSet();
    error TokenContractNotSet();
    error InvalidFatherId();
    error InvalidMotherId();
    error CannotSelfBreed();
    error FatherStaked();
    error MotherStaked();
    error NotFatherOwner();
    error NotMotherOwner();
    error NotCoOwner();
    error CoOwnerBreeding();
    error CoOwnerOnCooldown();
    error CoOwnerZodiacMismatch();
    error InvalidFatherId2();
    error InvalidMotherId2();
    error CannotBreedSame();
    error DifferentOwnersRequired();
    error MustBeOwner();
    error FatherNotApproved();
    error MotherNotApproved();
    error LevelBelow5();
    error DifferentZodiac();
    error SameGender();
    error FatherOnCooldown();
    error MotherOnCooldown();
    error FatherBreeding();
    error MotherBreeding();
    error PairAlreadyExists();
    error PairNotActive();
    error AlreadyCompleted();
    error NotPairOwner();
    error CannotCancelCompleted();
    error FatherNotHeld();
    error MotherNotHeld();
    error CooldownNotEnded();
    error InvalidChildType();
    error MaxBreedingPairs();
    error FatherTransferFailed();
    error MotherTransferFailed();
    error MotherTransferFailedWithRevert();
    error ChildMintFailed();
    error FemaleChildMintFailed();
    error MaleChildMintFailed();
    error ParentZodiacMismatch();

    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        if (authorizer == address(0)) revert AuthorizerNotSet();
        IAuthorizer auth = IAuthorizer(authorizer);
        if (!auth.isSystemContract(msg.sender)) revert AuthorizerNotSet();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authorizerAddress) external initializer {
        if (_authorizerAddress == address(0)) revert InvalidAuthorizer();
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        if (_authorizerAddress == address(0)) revert InvalidAuthorizer();
        authorizer = _authorizerAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _getBreedingCore() internal view returns (IBreedingCoreState) {
        address breedingCore = IAuthorizer(authorizer).getAddressByName("breedingCore");
        if (breedingCore == address(0)) revert AuthorizerNotSet();
        return IBreedingCoreState(breedingCore);
    }

    function createSelfBreedingPair(address caller, uint256 fatherId, uint256 motherId, uint256 coOwnerId) external nonReentrant returns (uint256) {
        IBreedingCoreState core = _getBreedingCore();
        uint256 currentEpoch = core.epoch();
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        address stakingContract = IAuthorizer(authorizer).getAddressByName("staking");
        if (nftMintContract == address(0)) revert NFTContractNotSet();
        if (fatherId == 0) revert InvalidFatherId();
        if (motherId == 0) revert InvalidMotherId();
        if (fatherId == motherId) revert CannotSelfBreed();
        if (core.breedingPairCount(currentEpoch) >= MAX_BREEDING_PAIRS) revert MaxBreedingPairs();
        
        if (stakingContract != address(0)) {
            (address fatherStaker, , , , ) = IStaking(stakingContract).stakingInfo(fatherId);
            if (fatherStaker != address(0)) revert FatherStaked();
            (address motherStaker, , , , ) = IStaking(stakingContract).stakingInfo(motherId);
            if (motherStaker != address(0)) revert MotherStaked();
        }

        INFTMint nft = INFTMint(nftMintContract);
        if (nft.ownerOf(fatherId) != caller) revert NotFatherOwner();
        if (nft.ownerOf(motherId) != caller) revert NotMotherOwner();

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        if (coOwnerId > 0) {
            if (nft.ownerOf(coOwnerId) != caller) revert NotCoOwner();
            if (core.isNFTInActiveBreeding(currentEpoch, coOwnerId)) revert CoOwnerBreeding();
            if (core.breedingCooldowns(currentEpoch, coOwnerId) > block.timestamp) revert CoOwnerOnCooldown();
            uint256 coOwnerType = nft.tokenType(coOwnerId);
            uint256 coOwnerZodiac = (coOwnerType / 2) % 12;
            if (coOwnerZodiac != (fatherType / 2) % 12) revert CoOwnerZodiacMismatch();
        }

        return _breedCommon(
            fatherId, motherId, caller, caller,
            core.selfBreedingFee(), core.selfBreedingCooldown(),
            0
        );
    }

    function createMarketBreedingPairPublic(address caller, uint256 fatherId, uint256 motherId) external nonReentrant returns (uint256) {
        IBreedingCoreState core = _getBreedingCore();
        uint256 currentEpoch = core.epoch();
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        if (nftMintContract == address(0)) revert NFTContractNotSet();
        if (fatherId == 0) revert InvalidFatherId2();
        if (motherId == 0) revert InvalidMotherId2();
        if (fatherId == motherId) revert CannotBreedSame();
        
        INFTMint nft = INFTMint(nftMintContract);
        address maleOwner = nft.ownerOf(fatherId);
        address femaleOwner = nft.ownerOf(motherId);
        
        if (maleOwner == femaleOwner) revert DifferentOwnersRequired();
        if (caller != maleOwner && caller != femaleOwner) revert MustBeOwner();

        _checkDailyBreedingLimit(caller, currentEpoch, core);

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);

        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        if (!nft721.isApprovedForAll(maleOwner, address(this))) revert FatherNotApproved();
        if (!nft721.isApprovedForAll(femaleOwner, address(this))) revert MotherNotApproved();

        uint256 pairId = _breedCommon(
            fatherId, motherId, maleOwner, femaleOwner,
            core.marketBreedingFee(), core.marketBreedingCooldown(),
            1
        );

        _updateDailyBreedingCount(caller, currentEpoch, core);

        core.addActiveOrder(currentEpoch, femaleOwner, pairId);
        return pairId;
    }

    function _checkDailyBreedingLimit(address caller, uint256 currentEpoch, IBreedingCoreState core) private {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 userLastDay = core.getLastBreedingDay(currentEpoch, caller);
        uint256 userDailyCount = core.getDailyPublicBreedings(currentEpoch, caller);
        
        if (userLastDay != currentDay) {
            userDailyCount = 0;
        }
        if (userDailyCount >= core.maxDailyPublicBreedings()) revert MustBeOwner();
    }

    function _updateDailyBreedingCount(address caller, uint256 currentEpoch, IBreedingCoreState core) private {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 userLastDay = core.getLastBreedingDay(currentEpoch, caller);
        
        if (userLastDay != currentDay) {
            core.setDailyPublicBreeding(currentEpoch, caller, 1);
            core.setLastBreedingDay(currentEpoch, caller, currentDay);
        } else {
            uint256 userDailyCount = core.getDailyPublicBreedings(currentEpoch, caller);
            core.setDailyPublicBreeding(currentEpoch, caller, userDailyCount + 1);
        }
    }

    function _breedCommon(
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee, uint256 cooldown,
        uint256 breedingType
    ) internal returns (uint256 pairId) {
        IBreedingCoreState core = _getBreedingCore();
        uint256 currentEpoch = core.epoch();
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        if (nftMintContract == address(0)) revert NFTContractNotSet();
        
        INFTMint nft = INFTMint(nftMintContract);
        _validateBreedingPair(nft, fatherId, motherId, currentEpoch, core);

        core.setBreedingPairExists(currentEpoch, fatherId, motherId, true);
        core.setBreedingPairExists(currentEpoch, motherId, fatherId, true);
        
        uint256 newCount = core.breedingPairCount(currentEpoch) + 1;
        core.setBreedingPairCount(currentEpoch, newCount);
        pairId = newCount;
        
        _createBreedingPair(pairId, fatherId, motherId, maleOwner, femaleOwner, breedingType, currentEpoch, core);
        _finalizeBreedTransaction(nftMintContract, fatherId, motherId, maleOwner, femaleOwner, fee, cooldown, pairId, currentEpoch, core);
        
        emit BreedingPairCreated(pairId, fatherId, motherId, breedingType);
    }

    function _validateBreedingPair(INFTMint nft, uint256 fatherId, uint256 motherId, uint256 currentEpoch, IBreedingCoreState core) private view {
        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        
        if (nft.tokenLevel(fatherId) < 5 || nft.tokenLevel(motherId) < 5) revert LevelBelow5();
        if ((fatherType / 2) % 12 != (motherType / 2) % 12) revert DifferentZodiac();
        if ((fatherType % 2) == (motherType % 2)) revert SameGender();
        if (core.breedingCooldowns(currentEpoch, fatherId) > block.timestamp) revert FatherOnCooldown();
        if (core.breedingCooldowns(currentEpoch, motherId) > block.timestamp) revert MotherOnCooldown();
        if (core.isNFTInActiveBreeding(currentEpoch, fatherId)) revert FatherBreeding();
        if (core.isNFTInActiveBreeding(currentEpoch, motherId)) revert MotherBreeding();
        if (core.get_breedingPairExists(currentEpoch, fatherId, motherId) || core.get_breedingPairExists(currentEpoch, motherId, fatherId)) revert PairAlreadyExists();
    }

    function _createBreedingPair(
        uint256 pairId, uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner, uint256 breedingType, uint256 currentEpoch, IBreedingCoreState core
    ) private {
        BreedingLib.BreedingPairData memory data = BreedingLib.BreedingPairData({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: 0, femaleCoOwnerId: 0, startTime: block.timestamp,
            breedingType: breedingType, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false,
            cancelledAt: 0
        });
        core.setBreedingPair(currentEpoch, pairId, data);
    }

    function _finalizeBreedTransaction(
        address nftMintContract,
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee, uint256 cooldown,
        uint256 pairId, uint256 currentEpoch, IBreedingCoreState core
    ) private {
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        
        _transferBreedingNFTs(nft721, fatherId, motherId, maleOwner, femaleOwner, fee, tokenContract);

        if (fee > 0) {
            if (tokenContract == address(0)) revert TokenContractNotSet();
            IERC20(tokenContract).safeTransferFrom(msg.sender, address(_getBreedingCore()), fee);
        }

        core.setNFTInActiveBreeding(currentEpoch, fatherId, true);
        core.setNFTInActiveBreeding(currentEpoch, motherId, true);
        core.setBreedingCooldown(currentEpoch, fatherId, block.timestamp + cooldown);
        core.setBreedingCooldown(currentEpoch, motherId, block.timestamp + cooldown);
        core.addActiveOrder(currentEpoch, maleOwner, pairId);
        core.addAllOrder(currentEpoch, maleOwner, pairId);
        if (maleOwner != femaleOwner) {
            core.addAllOrder(currentEpoch, femaleOwner, pairId);
        }
    }

    function _transferBreedingNFTs(
        IERC721Upgradeable nft,
        uint256 fatherId, uint256 motherId,
        address maleOwner, address femaleOwner,
        uint256 fee, address tokenContract
    ) internal {
        bool fatherTransferred = false;
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");

        try nft.safeTransferFrom(maleOwner, address(_getBreedingCore()), fatherId) {
            fatherTransferred = true;
        } catch {
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert FatherTransferFailed();
        }
        _syncWeightAfterTransfer(maleOwner, address(_getBreedingCore()), fatherId, nftMintContract);

        try nft.safeTransferFrom(femaleOwner, address(_getBreedingCore()), motherId) {
        } catch {
            if (fatherTransferred) {
                bool revertOnFailure = false;
                try nft.safeTransferFrom(address(_getBreedingCore()), maleOwner, fatherId) {
                    _syncWeightAfterTransfer(address(_getBreedingCore()), maleOwner, fatherId, nftMintContract);
                } catch {
                    emit EmergencyNFTLocked(fatherId, maleOwner);
                    revertOnFailure = true;
                }
                if (revertOnFailure) {
                    revert MotherTransferFailedWithRevert();
                }
            }
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert MotherTransferFailed();
        }
        _syncWeightAfterTransfer(femaleOwner, address(_getBreedingCore()), motherId, nftMintContract);
    }

    function cancelBreeding(address caller, uint256 pairId) external nonReentrant {
        IBreedingCoreState core = _getBreedingCore();
        uint256 currentEpoch = core.epoch();
        BreedingLib.BreedingPairData memory pair = core.breedingPairs(currentEpoch, pairId);
        if (pair.status != BREEDING_STATUS_ACTIVE) revert PairNotActive();
        if (pair.childId != 0) revert AlreadyCompleted();
        if (caller != pair.maleOwner && caller != pair.femaleOwner) revert NotPairOwner();
        
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        if (nftMintContract == address(0)) revert NFTContractNotSet();

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? core.selfBreedingCooldown() : core.marketBreedingCooldown();
        if (block.timestamp >= pair.startTime + cooldown) revert CannotCancelCompleted();

        INFTMint nft = INFTMint(nftMintContract);
        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        
        pair.status = BREEDING_STATUS_CANCELLED;
        core.setBreedingPairExists(currentEpoch, pair.fatherId, pair.motherId, false);
        core.setBreedingPairExists(currentEpoch, pair.motherId, pair.fatherId, false);
        pair.cancelledAt = block.timestamp;
        
        core.setNFTInActiveBreeding(currentEpoch, pair.fatherId, false);
        core.setNFTInActiveBreeding(currentEpoch, pair.motherId, false);
        
        core.setBreedingCooldown(currentEpoch, pair.fatherId, 0);
        core.setBreedingCooldown(currentEpoch, pair.motherId, 0);

        core.removeActiveOrder(currentEpoch, pair.maleOwner, pairId);
        core.removeActiveOrder(currentEpoch, pair.femaleOwner, pairId);
        
        address fatherOwner = pair.maleOwner;
        address motherOwner = pair.femaleOwner;
        
        try nft721.safeTransferFrom(address(core), pair.maleOwner, pair.fatherId) {
        } catch {
            emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
        }
        _syncWeightAfterTransfer(address(core), fatherOwner, pair.fatherId, nftMintContract);
        
        try nft721.safeTransferFrom(address(core), pair.femaleOwner, pair.motherId) {
        } catch {
            emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
        }
        _syncWeightAfterTransfer(address(core), motherOwner, pair.motherId, nftMintContract);
        
        uint256 fee = pair.breedingType == BREEDING_TYPE_SELF ? core.selfBreedingFee() : core.marketBreedingFee();
        if (fee > 0) {
            address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
            if (tokenContract != address(0)) {
                IERC20(tokenContract).safeTransferFrom(address(core), caller, fee);
            }
        }
        
        emit BreedingCancelled(pairId, pair.fatherId, pair.motherId, caller);
    }

    function completeBreeding(address caller, uint256 pairId) external nonReentrant returns (uint256, uint256) {
        IBreedingCoreState core = _getBreedingCore();
        uint256 currentEpoch = core.epoch();
        BreedingLib.BreedingPairData memory pair = core.breedingPairs(currentEpoch, pairId);
        if (pair.status != BREEDING_STATUS_ACTIVE) revert PairNotActive();
        if (pair.childId != 0) revert AlreadyCompleted();
        if (caller != pair.maleOwner && caller != pair.femaleOwner) revert NotPairOwner();
        
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");
        if (nftMintContract == address(0)) revert NFTContractNotSet();

        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        if (nft721.ownerOf(pair.fatherId) != address(core)) revert FatherNotHeld();
        if (nft721.ownerOf(pair.motherId) != address(core)) revert MotherNotHeld();

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? core.selfBreedingCooldown() : core.marketBreedingCooldown();
        if (block.timestamp < pair.startTime + cooldown) revert CooldownNotEnded();

        return _processCompleteBreeding(pairId, pair, nftMintContract, nft721, currentEpoch, core);
    }

    function _processCompleteBreeding(
        uint256 pairId,
        BreedingLib.BreedingPairData memory pair,
        address nftMintContract,
        IERC721Upgradeable nft721,
        uint256 currentEpoch,
        IBreedingCoreState core
    ) private returns (uint256, uint256) {
        INFTMint nft = INFTMint(nftMintContract);

        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            block.prevrandao,
            pairId,
            tx.gasprice,
            pair.maleOwner
        )));
        
        uint256 zodiacType = _getChildZodiacType(nft, pair.fatherId, pair.motherId, seed);
        if (zodiacType == 0) revert InvalidChildType();

        if (pair.breedingType == BREEDING_TYPE_SELF) {
            return _completeSelfBreeding(pairId, nft, nft721, pair, zodiacType, seed, currentEpoch, core);
        } else {
            return _completeMarketBreeding(pairId, nft, nft721, pair, zodiacType, seed, currentEpoch, core);
        }
    }

    function _completeSelfBreeding(
        uint256 pairId,
        INFTMint nft,
        IERC721Upgradeable nft721,
        BreedingLib.BreedingPairData memory pair,
        uint256 zodiacType,
        uint256 seed,
        uint256 currentEpoch,
        IBreedingCoreState core
    ) private returns (uint256, uint256) {
        uint8 childGrowth = uint8((seed % 91) + 10);
        uint256 childId = nft.mintForBreeding(pair.femaleOwner, zodiacType, childGrowth);
        if (childId == 0) revert ChildMintFailed();

        pair.childId = childId;
        pair.status = 1;
        core.setBreedingPair(currentEpoch, pairId, pair);
        
        _finalizeBreeding(pairId, pair, nft721, currentEpoch, core);
        
        emit BreedingCompleted(pairId, childId, zodiacType);
        return (childId, 0);
    }

    function _completeMarketBreeding(
        uint256 pairId,
        INFTMint nft,
        IERC721Upgradeable nft721,
        BreedingLib.BreedingPairData memory pair,
        uint256 zodiacType,
        uint256 seed,
        uint256 currentEpoch,
        IBreedingCoreState core
    ) private returns (uint256, uint256) {
        (uint256 childIdForFemale, uint256 childIdForMale) = _mintMarketBreedingChildren(
            nft, pair.femaleOwner, pair.maleOwner, zodiacType, seed
        );

        pair.childId = childIdForFemale;
        pair.maleChildId = childIdForMale;
        pair.status = 1;
        core.setBreedingPair(currentEpoch, pairId, pair);
        
        _finalizeBreeding(pairId, pair, nft721, currentEpoch, core);
        
        emit BreedingCompleted(pairId, childIdForFemale, zodiacType);
        emit MaleChildGenerated(pairId, childIdForMale);
        emit FemaleChildGenerated(pairId, childIdForFemale);
        return (childIdForFemale, childIdForMale);
    }

    function _mintMarketBreedingChildren(
        INFTMint nft,
        address femaleOwner,
        address maleOwner,
        uint256 zodiacType,
        uint256 seed
    ) private returns (uint256 childIdForFemale, uint256 childIdForMale) {
        uint8 femaleChildGrowth = uint8((seed % 91) + 10);
        uint8 maleChildGrowth = uint8(((seed >> 32) % 91) + 10);
        childIdForFemale = nft.mintForBreeding(femaleOwner, zodiacType, femaleChildGrowth);
        if (childIdForFemale == 0) revert FemaleChildMintFailed();
        childIdForMale = nft.mintForBreeding(maleOwner, zodiacType, maleChildGrowth);
        if (childIdForMale == 0) revert MaleChildMintFailed();
    }

    function _finalizeBreeding(
        uint256 pairId,
        BreedingLib.BreedingPairData memory pair,
        IERC721Upgradeable nft721,
        uint256 currentEpoch,
        IBreedingCoreState core
    ) private {
        core.setBreedingPairExists(currentEpoch, pair.fatherId, pair.motherId, false);
        core.setBreedingPairExists(currentEpoch, pair.motherId, pair.fatherId, false);
        core.setNFTInActiveBreeding(currentEpoch, pair.fatherId, false);
        core.setNFTInActiveBreeding(currentEpoch, pair.motherId, false);
        core.removeActiveOrder(currentEpoch, pair.maleOwner, pairId);
        core.removeActiveOrder(currentEpoch, pair.femaleOwner, pairId);

        _burnFee(pair.breedingType, core);

        address fatherOwner = pair.maleOwner;
        address motherOwner = pair.femaleOwner;
        address nftMintContract = IAuthorizer(authorizer).getAddressByName("nftMintCore");

        try nft721.safeTransferFrom(address(core), pair.maleOwner, pair.fatherId) {} catch { emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner); }
        _syncWeightAfterTransfer(address(core), fatherOwner, pair.fatherId, nftMintContract);
        try nft721.safeTransferFrom(address(core), pair.femaleOwner, pair.motherId) {} catch { emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner); }
        _syncWeightAfterTransfer(address(core), motherOwner, pair.motherId, nftMintContract);
    }

    function _getChildZodiacType(INFTMint nftMint, uint256 fatherId, uint256 motherId, uint256 randomSeed) internal view returns (uint256) {
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        if (fatherZodiac != motherZodiac) revert ParentZodiacMismatch();

        return BreedingLib.calculateChildZodiacType(INFTMint(nftMint), fatherId, motherId, randomSeed, block.timestamp, msg.sender);
    }

    function _burnFee(uint256 breedingType, IBreedingCoreState core) internal {
        address tokenContract = IAuthorizer(authorizer).getAddressByName("token");
        require(tokenContract != address(0), "BC: TNS");
        uint256 fee = breedingType == 0 ? core.selfBreedingFee() : core.marketBreedingFee();
        if (fee == 0) return;

        IERC20 token = IERC20(tokenContract);
        uint256 contractBalance = token.balanceOf(address(core));
        require(contractBalance >= fee, "BC: IBFB");

        token.safeTransferFrom(address(core), address(0x000000000000000000000000000000000000dEaD), fee);
        emit BreedingFeeBurned(fee);
    }

    function _syncWeightAfterTransfer(address from, address to, uint256 tokenId, address nftContract) internal {
        BreedingLib.syncWeightAfterTransfer(authorizer, from, to, tokenId);
    }

    event BreedingPairCreated(uint256 indexed pairId, uint256 indexed fatherId, uint256 indexed motherId, uint256 breedingType);
    event BreedingCompleted(uint256 indexed pairId, uint256 indexed childId, uint256 zodiacType);
    event MaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    event FemaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    event BreedingFeeBurned(uint256 amount);
    event BreedingCancelled(uint256 indexed pairId, uint256 fatherId, uint256 motherId, address indexed canceller);
    event EmergencyNFTLocked(uint256 indexed tokenId, address indexed owner);
}