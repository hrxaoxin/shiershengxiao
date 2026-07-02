// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "./NFTInterface.sol";
import "./AddressLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BreedingLib.sol";

contract BreedingCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using BreedingLib for *;

    uint256 public selfBreedingCooldown;
    uint256 public marketBreedingCooldown;
    uint256 public selfBreedingFee;
    uint256 public marketBreedingFee;
    address public authorizer;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    uint256 public constant MAX_EPOCHS = 50;
    uint256 public epoch;

    mapping(uint256 => address) public stuckNFTs;

    uint256 public constant BREEDING_TYPE_SELF = 0;
    uint256 public constant BREEDING_TYPE_MARKET = 1;

    uint256 public maxDailyPublicBreedings;
    mapping(uint256 => mapping(address => uint256)) private _dailyPublicBreedings;
    mapping(uint256 => mapping(address => uint256)) private _lastBreedingDay;

    bool public paused;
    string public pauseReason;

    uint256 public constant BREEDING_STATUS_ACTIVE = 0;
    uint256 public constant BREEDING_STATUS_COMPLETED = 1;
    uint256 public constant BREEDING_STATUS_CANCELLED = 2;

    mapping(uint256 => mapping(uint256 => BreedingLib.BreedingPairData)) public breedingPairs;
    mapping(uint256 => uint256) public breedingPairCount;
    mapping(uint256 => mapping(uint256 => uint256)) public breedingCooldowns;
    mapping(uint256 => mapping(uint256 => bool)) public isNFTInActiveBreeding;
    mapping(uint256 => mapping(address => uint256[])) private _userActiveOrderIds;
    mapping(uint256 => mapping(address => uint256[])) private _userAllOrderIds;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => bool))) private _breedingPairExists;

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
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    error ContractPaused();
    error AuthorizerNotSet();
    error NotAuthorized();
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
    error CooldownMustBePositive();
    error PairNotActive();
    error AlreadyCompleted();
    error NotPairOwner();
    error CannotCancelCompleted();
    error FatherNotHeld();
    error MotherNotHeld();
    error CooldownNotEnded();
    error InvalidChildType();
    error MaxBreedingPairs();
    error AmountZero();
    error InsufficientBalance();
    error BNBTransferFailed();
    error NFTBreeding();
    error InvalidTo();
    error NotNftHolder();
    error FatherTransferFailed();
    error MotherTransferFailed();
    error MotherTransferFailedWithRevert();
    error ChildMintFailed();
    error FemaleChildMintFailed();
    error MaleChildMintFailed();
    error ParentZodiacMismatch();
    error ActiveBreedingPairs();
    error OnlyExecutor();

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        if (authorizer == address(0)) revert AuthorizerNotSet();
        IAuthorizer auth = IAuthorizer(authorizer);
        if (!auth.isSystemContract(msg.sender)) revert NotAuthorized();
        _;
    }

    modifier onlyBreedingExecutor() {
        address breedingExecutor = IAuthorizer(authorizer).getAddressByName(AddressLib.BREEDING_EXECUTOR);
        if (msg.sender != breedingExecutor) revert OnlyExecutor();
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
        epoch = 1;
    }
    
    function _currentEpoch() internal view returns (uint256) {
        return epoch;
    }

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        if (_authorizerAddress == address(0)) revert InvalidAuthorizer();
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
        address breedingExecutor = IAuthorizer(authorizer).getAddressByName(AddressLib.BREEDING_EXECUTOR);
        if (breedingExecutor == address(0)) revert AuthorizerNotSet();
        return IBreedingExecutor(breedingExecutor).createSelfBreedingPair(msg.sender, fatherId, motherId, coOwnerId);
    }

    function createMarketBreedingPairPublic(uint256 fatherId, uint256 motherId) external nonReentrant whenNotPaused returns (uint256) {
        address breedingExecutor = IAuthorizer(authorizer).getAddressByName(AddressLib.BREEDING_EXECUTOR);
        if (breedingExecutor == address(0)) revert AuthorizerNotSet();
        return IBreedingExecutor(breedingExecutor).createMarketBreedingPairPublic(msg.sender, fatherId, motherId);
    }

    function completeBreeding(uint256 pairId) external nonReentrant whenNotPaused returns (uint256, uint256) {
        address breedingExecutor = IAuthorizer(authorizer).getAddressByName(AddressLib.BREEDING_EXECUTOR);
        if (breedingExecutor == address(0)) revert AuthorizerNotSet();
        return IBreedingExecutor(breedingExecutor).completeBreeding(msg.sender, pairId);
    }

    function cancelBreeding(uint256 pairId) external nonReentrant whenNotPaused {
        address breedingExecutor = IAuthorizer(authorizer).getAddressByName(AddressLib.BREEDING_EXECUTOR);
        if (breedingExecutor == address(0)) revert AuthorizerNotSet();
        IBreedingExecutor(breedingExecutor).cancelBreeding(msg.sender, pairId);
    }

    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    function setSelfBreedingFee(uint256 fee) external onlyOwner { 
        selfBreedingFee = fee; 
    }

    function setMarketBreedingFee(uint256 fee) external onlyOwner { 
        marketBreedingFee = fee; 
    }

    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { 
        if (cooldown == 0) revert CooldownMustBePositive(); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        if (cooldown == 0) revert CooldownMustBePositive(); 
        marketBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function getBreedingInfo(uint256 pairId) external view returns (BreedingLib.BreedingPairData memory) {
        uint256 currentEpoch = _currentEpoch();
        return BreedingLib.getBreedingPairData(breedingPairs, currentEpoch, pairId);
    }

    function isInCooldown(uint256 tokenId) public view returns (bool) { 
        uint256 currentEpoch = _currentEpoch();
        return breedingCooldowns[currentEpoch][tokenId] > block.timestamp; 
    }

    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) { 
        uint256 currentEpoch = _currentEpoch();
        return breedingCooldowns[currentEpoch][tokenId]; 
    }

    function getDailyPublicBreedings(uint256 epoch, address user) external view returns (uint256) {
        return _dailyPublicBreedings[epoch][user];
    }

    function getLastBreedingDay(uint256 epoch, address user) external view returns (uint256) {
        return _lastBreedingDay[epoch][user];
    }

    function getUserActiveOrders(address user) external view returns (uint256[] memory) {
        uint256 currentEpoch = _currentEpoch();
        return BreedingLib.getUserActiveOrders(_userActiveOrderIds, breedingPairs, currentEpoch, user, BREEDING_STATUS_ACTIVE);
    }

    function getUserBreedingStats(address user) external view returns (
        uint256 totalPairs,
        uint256 activePairs,
        uint256 completedPairs,
        uint256 claimablePairs
    ) {
        uint256 currentEpoch = _currentEpoch();
        address nftMintContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_MINT_CORE);
        return BreedingLib.getUserBreedingStats(_userAllOrderIds, breedingPairs, currentEpoch, user, nftMintContract);
    }

    function getBreedingPairWithCooldown(uint256 pairId) external view returns (
        uint256 fatherId, uint256 motherId, uint256 fatherCooldown,
        uint256 motherCooldown, uint256 remainingTime, uint256 status
    ) {
        uint256 currentEpoch = _currentEpoch();
        BreedingLib.BreedingPairData memory pair = breedingPairs[currentEpoch][pairId];
        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        fatherCooldown = breedingCooldowns[currentEpoch][pair.fatherId];
        motherCooldown = breedingCooldowns[currentEpoch][pair.motherId];
        remainingTime = 0;
        if (pair.status == 0 && pair.startTime > 0) {
            uint256 endTime = pair.startTime + cooldown;
            if (block.timestamp < endTime) {
                remainingTime = endTime - block.timestamp;
            }
        }
        fatherId = pair.fatherId;
        motherId = pair.motherId;
        status = pair.status;
    }

    function emergencyWithdraw(uint256 tokenType, uint256 tokenIdOrAmount, uint256 amount) external onlyOwner nonReentrant {
        uint256 currentEpoch = _currentEpoch();
        if (tokenType == 0) {
            if (tokenIdOrAmount == 0) revert AmountZero();
            if (tokenIdOrAmount > address(this).balance) revert InsufficientBalance();
            (bool success, ) = payable(owner()).call{value: tokenIdOrAmount}("");
            if (!success) revert BNBTransferFailed();
            emit EmergencyBNBWithdrawn(msg.sender, owner(), tokenIdOrAmount);
        } else if (tokenType == 1) {
            if (amount == 0) revert AmountZero();
            address tokenContract = IAuthorizer(authorizer).getAddressByName(AddressLib.TOKEN);
            if (tokenContract == address(0)) revert TokenContractNotSet();
            IERC20 token = IERC20(tokenContract);
            if (token.balanceOf(address(this)) < amount) revert InsufficientBalance();
            token.safeTransfer(owner(), amount);
            emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
        } else {
            address nftMintContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_MINT_CORE);
            if (nftMintContract == address(0)) revert NFTContractNotSet();
            if (isNFTInActiveBreeding[currentEpoch][tokenIdOrAmount]) revert NFTBreeding();
            IERC721Upgradeable(nftMintContract).safeTransferFrom(address(this), owner(), tokenIdOrAmount);
            BreedingLib.syncWeightAfterTransfer(authorizer, address(this), owner(), tokenIdOrAmount);
            emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenIdOrAmount);
        }
    }

    function recoverStuckNFT(uint256 tokenId, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidTo();
        uint256 currentEpoch = _currentEpoch();
        address nftMintContract = IAuthorizer(authorizer).getAddressByName(AddressLib.NFT_MINT_CORE);
        if (nftMintContract == address(0)) revert NFTContractNotSet();
        IERC721Upgradeable nft = IERC721Upgradeable(nftMintContract);
        if (nft.ownerOf(tokenId) != address(this)) revert NotNftHolder();
        if (isNFTInActiveBreeding[currentEpoch][tokenId]) revert NFTBreeding();
        nft.safeTransferFrom(address(this), to, tokenId);
        _syncWeightAfterTransfer(address(this), to, tokenId, nftMintContract);
    }

    function _syncWeightAfterTransfer(address from, address to, uint256 tokenId, address nftContract) internal {
        BreedingLib.syncWeightAfterTransfer(authorizer, from, to, tokenId);
    }

    receive() external payable {}
    fallback() external payable {}

    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 currentEpoch = _currentEpoch();
        if (breedingPairCount[currentEpoch] != 0) revert ActiveBreedingPairs();
        uint256 oldEpoch = epoch;
        epoch = (epoch + 1) % MAX_EPOCHS;
        paused = false;
        pauseReason = "";
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }

    function get_userActiveOrderIds(uint256 currentEpoch, address user) external view onlyBreedingExecutor returns (uint256[] memory) {
        return _userActiveOrderIds[currentEpoch][user];
    }

    function get_userAllOrderIds(uint256 currentEpoch, address user) external view onlyBreedingExecutor returns (uint256[] memory) {
        return _userAllOrderIds[currentEpoch][user];
    }

    function get_breedingPairExists(uint256 currentEpoch, uint256 fatherId, uint256 motherId) external view onlyBreedingExecutor returns (bool) {
        return _breedingPairExists[currentEpoch][fatherId][motherId];
    }

    function setBreedingPair(uint256 currentEpoch, uint256 pairId, BreedingLib.BreedingPairData calldata data) external onlyBreedingExecutor {
        breedingPairs[currentEpoch][pairId] = data;
    }

    function setBreedingPairCount(uint256 currentEpoch, uint256 count) external onlyBreedingExecutor {
        breedingPairCount[currentEpoch] = count;
    }

    function setBreedingCooldown(uint256 currentEpoch, uint256 tokenId, uint256 cooldown) external onlyBreedingExecutor {
        breedingCooldowns[currentEpoch][tokenId] = cooldown;
    }

    function setNFTInActiveBreeding(uint256 currentEpoch, uint256 tokenId, bool active) external onlyBreedingExecutor {
        isNFTInActiveBreeding[currentEpoch][tokenId] = active;
    }

    function setDailyPublicBreeding(uint256 currentEpoch, address user, uint256 count) external onlyBreedingExecutor {
        _dailyPublicBreedings[currentEpoch][user] = count;
    }

    function setLastBreedingDay(uint256 currentEpoch, address user, uint256 day) external onlyBreedingExecutor {
        _lastBreedingDay[currentEpoch][user] = day;
    }

    function addActiveOrder(uint256 currentEpoch, address user, uint256 pairId) external onlyBreedingExecutor {
        BreedingLib.addActiveOrder(user, pairId, _userActiveOrderIds[currentEpoch]);
    }

    function removeActiveOrder(uint256 currentEpoch, address user, uint256 pairId) external onlyBreedingExecutor {
        BreedingLib.removeActiveOrder(user, pairId, _userActiveOrderIds[currentEpoch]);
    }

    function addAllOrder(uint256 currentEpoch, address user, uint256 pairId) external onlyBreedingExecutor {
        _userAllOrderIds[currentEpoch][user].push(pairId);
    }

    function setBreedingPairExists(uint256 currentEpoch, uint256 fatherId, uint256 motherId, bool exists) external onlyBreedingExecutor {
        _breedingPairExists[currentEpoch][fatherId][motherId] = exists;
    }
}