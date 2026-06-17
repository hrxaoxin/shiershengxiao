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
 * @title BreedingCore
 * @dev NFT繁殖核心合约，负责处理NFT繁殖逻辑
 * 
 * 核心职责�?
 * 1. 繁殖配对创建：创建繁殖配对，锁定父母NFT
 * 2. 繁殖执行：生成子代NFT，继承父母属�?
 * 3. 冷却期管理：管理繁殖后的冷却时间
 * 4. 繁殖类型：支持自繁殖和市场繁殖两种模�?
 * 
 * 繁殖类型�?
 * - 自繁殖（BREEDING_TYPE_SELF = 0）：用户使用自己的两个NFT繁殖
 * - 市场繁殖（BREEDING_TYPE_MARKET = 1）：用户与市场上的NFT配对繁殖
 * 
 * 冷却期设置：
 * - 自繁殖冷却：12小时
 * - 市场繁殖冷却�?4小时
 * 
 * 费用设置�?
 * - 自繁殖费用：888代币
 * - 市场繁殖费用�?88代币
 * 
 * 繁殖流程�?
 * 1. 用户调用 breed() �?breedMarket() 创建繁殖配对
 * 2. 检查父母NFT是否满足条件（等�?=5、不在冷却期、未被锁定）
 * 3. 锁定父母NFT，扣除繁殖费�?
 * 4. 生成子代NFT，继承父母属性（生肖、属性、等级等�?
 * 5. 解锁父母NFT（进入冷却期�?
 * 6. 用户领取子代NFT
 * 
 * 属性遗传规则：
 * - 生肖：从父母中随机继�?
 * - 属性：从父母中随机继承，有概率变异
 * - 等级：子代等级为父母等级的平均值向下取�?
 * - 稀有度：根据父母稀有度计算，有概率提升
 * 
 * 与其他合约的交互�?
 * - NFTMint：铸造新的子代NFT
 * - Staking：检查NFT是否处于质押状�?
 * - TokenBurner：销毁繁殖费用代�?
 * 
 * 安全机制�?
 * - ReentrancyGuard：防止重入攻�?
 * - Pausable：可暂停所有繁殖操�?
 * - NFT锁定：繁殖期间锁定NFT防止转移
 * 
 * 权限控制�?
 * - onlyOwner：暂停合约、设置参数、紧急操�?
 * - onlyAuthorized：授权合约调�?
 */
contract BreedingCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using BreedingLib for *;

    /**
     * @dev 自繁殖冷却时�?
     */
    uint256 public selfBreedingCooldown = 12 hours;
    /**
     * @dev 市场繁殖冷却时间
     */
    uint256 public marketBreedingCooldown = 24 hours;
    /**
     * @dev 自繁殖费用（代币�?
     */
    uint256 public selfBreedingFee = 888 * 1e18;
    /**
     * @dev 市场繁殖费用（代币）
     */
    uint256 public marketBreedingFee = 888 * 1e18;
    /**
     * @dev 授权合约地址（Authorizer�? 通过此地址获取所有关联合约地址
     */
    address public authorizer;
    /**
     * @dev 黑洞地址（用于销毁NFT�?
     */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /**
     * @dev 自繁殖类�?
     */
    uint256 public constant BREEDING_TYPE_SELF = 0;
    /**
     * @dev 市场繁殖类型
     */
    uint256 public constant BREEDING_TYPE_MARKET = 1;
    /**
     * @dev 最大繁殖配对数�?
     */
    uint256 public constant MAX_BREEDING_PAIRS = 10000;

    /**
     * @dev 每日最大公共繁殖次�?
     */
    uint256 public maxDailyPublicBreedings = 5;
    /**
     * @dev 用户每日公共繁殖次数映射
     */
    mapping(address => uint256) public dailyPublicBreedings;
    /**
     * @dev 用户上次繁殖日期映射
     */
    mapping(address => uint256) public lastBreedingDay;

    /**
     * @dev 是否暂停繁殖
     */
    bool public paused;
    /**
     * @dev 暂停原因
     */
    string public pauseReason;

    /**
     * @dev 繁殖状态：进行�?
     */
    uint256 public constant BREEDING_STATUS_ACTIVE = 0;
    /**
     * @dev 繁殖状态：已完�?
     */
    uint256 public constant BREEDING_STATUS_COMPLETED = 1;
    /**
     * @dev 繁殖状态：已取�?
     */
    uint256 public constant BREEDING_STATUS_CANCELLED = 2;

    /**
     * @dev 繁殖配对结构�?
     * @param fatherId 父NFT ID
     * @param motherId 母NFT ID
     * @param maleOwner 父NFT所有�?
     * @param femaleOwner 母NFT所有�?
     * @param maleCoOwnerId 父NFT共同所有者ID
     * @param femaleCoOwnerId 母NFT共同所有者ID
     * @param startTime 繁殖开始时�?
     * @param breedingType 繁殖类型�?=自繁殖，1=市场繁殖�?
     * @param status 繁殖状�?
     * @param childId 子代NFT ID（雌性）
     * @param maleChildId 子代NFT ID（雄性）
     * @param rewardsClaimed 奖励是否已领�?
     * @param cancelledAt 取消时间（如果被取消�?
     */
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

    /**
     * @dev 繁殖配对映射
     */
    mapping(uint256 => BreedingPair) public breedingPairs;
    /**
     * @dev 繁殖配对计数�?
     */
    uint256 public breedingPairCount;
    /**
     * @dev NFT冷却时间映射
     */
    mapping(uint256 => uint256) public breedingCooldowns;
    /**
     * @dev NFT是否正在繁殖�?
     */
    mapping(uint256 => bool) public isNFTInActiveBreeding;
    /**
     * @dev 用户活跃繁殖订单ID列表
     */
    mapping(address => uint256[]) private _userActiveOrderIds;
    
    /**
     * @dev 用户所有繁殖订单ID列表（用于统计查询优化）
     */
    mapping(address => uint256[]) private _userAllOrderIds;
    /**
     * @dev 繁殖配对是否存在（防止重复）
     */
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
        require(!paused, "BC: Paused");
        _;
    }

    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "BC: Not authorized");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函�?
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "BC: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "BC: Invalid authorizer address");
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
        require(nftMintContract != address(0), "BC: NFT contract not set");
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
            require(breedingCooldowns[coOwnerId] <= block.timestamp, "BC: Co-owner cooldown");
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
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NFT contract not set");
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
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NFT contract not set");
        
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
        
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "BC: Level < 5");
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "BC: Diff zodiac");
        require((fatherType % 2) != (motherType % 2), "BC: Same gender");
        require(breedingCooldowns[fatherId] <= block.timestamp, "BC: Father cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "BC: Mother cooldown");
        require(!isNFTInActiveBreeding[fatherId], "BC: Father breeding");
        require(!isNFTInActiveBreeding[motherId], "BC: Mother breeding");
        require(!_breedingPairExists[fatherId][motherId] && !_breedingPairExists[motherId][fatherId], "BC: Pair already exists");
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
            require(tokenContract != address(0), "BC: Token contract not set");
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
            revert("BC: Father transfer failed");
        }
        // 权重同步：用户 -> 合约
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
                    revert("BC: Mother transfer failed and father recovery failed");
                }
            }
            if (fee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, fee);
            }
            revert("BC: Mother transfer failed");
        }
        // 权重同步：用户 -> 合约
        _syncWeightAfterTransfer(femaleOwner, address(this), motherId, nftMintContract);
    }

    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    function cancelBreeding(uint256 pairId) external nonReentrant whenNotPaused {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "BC: Pair not active");
        require(pair.childId == 0, "BC: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "BC: Not pair owner");
        
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NFT contract not set");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp < pair.startTime + cooldown, "BC: Cannot cancel after cooldown ended");

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
        
        // 记录原持有者用于权重同步
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
        require(pair.status == BREEDING_STATUS_ACTIVE, "BC: Pair not active");
        require(pair.childId == 0, "BC: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "BC: Not pair owner");
        
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NFT contract not set");

        IERC721Upgradeable nft721 = IERC721Upgradeable(nftMintContract);
        require(nft721.ownerOf(pair.fatherId) == address(this), "BC: Father NFT not held by contract");
        require(nft721.ownerOf(pair.motherId) == address(this), "BC: Mother NFT not held by contract");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "BC: Cooldown not ended");

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
        require(zodiacType > 0, "BC: Invalid child zodiac type");

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
        require(childId > 0, "BC: NFT mint failed");

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
        require(childIdForFemale > 0, "BC: Female child mint failed");

        uint256 childIdForMale = nft.mintForBreeding(pair.maleOwner, zodiacType, maleChildGrowth);
        require(childIdForMale > 0, "BC: Male child mint failed");

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

        // 记录原持有者用于权重同步
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
        require(fatherZodiac == motherZodiac, "BC: Parent zodiac mismatch");

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
        require(contractBalance >= fee, "BC: Insufficient balance for fee burn");
        
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
        require(cooldown > 0, "BC: Cooldown must be > 0"); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: Cooldown must be > 0"); 
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
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        INFTMint nftMint;
        if (nftMintContract != address(0)) {
            nftMint = INFTMint(nftMintContract);
        }
        
        uint256[] storage orderIds = _userAllOrderIds[user];
        totalPairs = 0;
        activePairs = 0;
        completedPairs = 0;
        claimablePairs = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            BreedingPair memory pair = breedingPairs[orderIds[i]];
            bool isRelated = (pair.maleOwner == user || pair.femaleOwner == user);
            if (!isRelated && nftMintContract != address(0)) {
                if (pair.maleCoOwnerId != 0 && nftMint.ownerOf(pair.maleCoOwnerId) == user) {
                    isRelated = true;
                }
                if (!isRelated && pair.femaleCoOwnerId != 0 && nftMint.ownerOf(pair.femaleCoOwnerId) == user) {
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
        address tokenContract = IAuthorizer(authorizer).getToken();
        require(tokenContract != address(0), "BC: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "BC: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    function emergencyWithdrawNFT(uint256 tokenId) external onlyOwner nonReentrant {
        address nftMintContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftMintContract != address(0), "BC: NFT contract not set");
        require(!isNFTInActiveBreeding[tokenId], "BC: NFT in active breeding");
        IERC721Upgradeable nft = IERC721Upgradeable(nftMintContract);
        address from = address(this);
        address to = owner();
        nft.safeTransferFrom(from, to, tokenId);
        _syncWeightAfterTransfer(from, to, tokenId, nftMintContract);
        emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenId);
    }

    /**
     * @dev 同步权重（NFT转移后调用）
     * @param from 原持有者
     * @param to 新持有者
     * @param tokenId NFT ID
     * @param nftContract NFT合约地址
     */
    function _syncWeightAfterTransfer(address from, address to, uint256 tokenId, address nftContract) internal {
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        if (nftDataContract != address(0)) {
            INFTDataInterface(nftDataContract).removeUserNFT(from, tokenId);
            INFTDataInterface(nftDataContract).addUserNFT(to, tokenId);
        }
        
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        if (dividendManager != address(0)) {
            IDividendManager(dividendManager).syncUserWeight(from);
            IDividendManager(dividendManager).syncUserWeight(to);
        }
    }

    receive() external payable {}
    fallback() external payable {}
}