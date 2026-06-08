// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Breeding
 * @dev NFT繁殖合约，管理十二生肖NFT的配对、繁殖和子代产出流程
 *
 * 核心功能：
 * 1. 自主繁殖（Self Breeding）：玩家使用自己持有的2个NFT进行繁殖
 *    - 需消耗 888 代币作为繁殖费用
 *    - 冷却时间 12 小时
 *    - 产出 1 个子代NFT，归繁殖者所有
 *
 * 2. 市场繁殖（Market Breeding）：玩家与其他玩家的NFT配对繁殖
 *    - 需消耗 888 代币作为繁殖费用
 *    - 冷却时间 24 小时
 *    - 产出 2 个子代NFT，父母双方各获得 1 个
 *    - 每个玩家每天最多参与 5 次市场繁殖
 *
 * 3. 繁殖市场上架/下架：玩家可以将NFT上架到繁殖市场供他人配对
 *
 * 繁殖规则：
 * - 父母NFT必须达到 5 级以上
 * - 父母NFT必须为同一生肖（如都是鼠）
 * - 父母NFT必须为不同性别（一公一母）
 * - 父母NFT不能在质押或其他繁殖中
 * - 父母NFT需过冷却期才能再次繁殖
 *
 * 子代遗传规则：
 * - 生肖：继承父母的生肖（必须相同）
 * - 属性：50% 概率继承父亲属性，50% 概率继承母亲属性
 * - 性别：随机
 * - 成长值：随机（10-100）
 *
 * 费用机制：
 * - 繁殖费用在完成繁殖后转入黑洞地址永久销毁（通缩机制）
 * - 如繁殖被取消，费用不会退还（用于防刷）
 *
 * 安全机制：
 * - nonReentrant：防止重入攻击
 * - whenNotPaused：紧急暂停功能
 * - NFT所有权验证：确保调用者有权使用NFT进行繁殖
 * - 冷却期控制：防止高频繁殖刷NFT
 * - try-catch转账：防止单方NFT转账失败导致状态不一致
 *
 * 典型流程：
 * 1. 用户调用 createSelfBreedingPair() 创建自主繁殖对（质押父母NFT + 支付费用）
 * 2. 等待冷却期结束
 * 3. 用户调用 completeBreeding() 产出子代NFT并取回父母NFT
 * 4. 或在冷却期内调用 cancelBreeding() 取消繁殖（退还父母，不退还费用）
 */
contract Breeding is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     * OpenZeppelin UUPS 模式要求在实现合约构造函数中禁用初始化
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 自主繁殖冷却时间（默认12小时）
     * 繁殖对创建后需要等待此时间才能完成并产出子代
     */
    uint256 public selfBreedingCooldown = 12 hours;
    /**
     * @dev 市场繁殖冷却时间（默认24小时）
     * 市场繁殖冷却时间较长，防止高频跨玩家配对刷NFT
     */
    uint256 public marketBreedingCooldown = 24 hours;
    /**
     * @dev 自主繁殖费用（单位：代币，含18位小数，默认888代币）
     * 完成繁殖后此费用转入黑洞地址永久销毁
     */
    uint256 public selfBreedingFee = 888 * 1e18;
    /**
     * @dev 市场繁殖费用（单位：代币，含18位小数，默认888代币）
     * 完成繁殖后此费用转入黑洞地址永久销毁
     */
    uint256 public marketBreedingFee = 888 * 1e18;
    /**
     * @dev NFT铸造合约地址（ERC721），用于查询NFT所有者、等级、类型
     */
    address public nftMintContract;
    /**
     * @dev 授权器合约地址，用于 onlyAuthorized 修饰器的权限检查
     */
    address public authorizer;
    /**
     * @dev 代币合约地址（ERC20），用于收取和销毁繁殖费用
     */
    address public tokenContract;
    /**
     * @dev 质押合约地址（可选），用于检查NFT是否在质押中
     */
    address public stakingContract;
    /**
     * @dev 黑洞地址：转入此地址的代币将永久不可访问（通缩机制）
     */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    /**
     * @dev 繁殖类型常量：自主繁殖（使用自己的两个NFT）
     */
    uint256 public constant BREEDING_TYPE_SELF = 0;
    /**
     * @dev 繁殖类型常量：市场繁殖（使用自己和他人的NFT）
     */
    uint256 public constant BREEDING_TYPE_MARKET = 1;
    /**
     * @dev 系统支持的最大活跃繁殖对数量（防无限增长）
     */
    uint256 public constant MAX_BREEDING_PAIRS = 10000;

    /**
     * @dev 每个玩家每日最大市场繁殖次数（防刷）
     */
    uint256 public maxDailyPublicBreedings = 5;
    /**
     * @dev 用户每日市场繁殖次数记录（地址 => 当日次数）
     */
    mapping(address => uint256) public dailyPublicBreedings;
    /**
     * @dev 用户上次繁殖的日期标识（用于每日重置计数）
     */
    mapping(address => uint256) public lastBreedingDay;

    /**
     * @dev 合约暂停标志（true=已暂停，所有用户操作被禁止）
     */
    bool public paused;
    /**
     * @dev 合约暂停原因（记录在事件中便于追踪）
     */
    string public pauseReason;

    /**
     * @dev 繁殖状态常量：进行中（已创建配对，等待冷却结束）
     */
    uint256 public constant BREEDING_STATUS_ACTIVE = 0;
    /**
     * @dev 繁殖状态常量：已完成（已产出子代NFT）
     */
    uint256 public constant BREEDING_STATUS_COMPLETED = 1;
    /**
     * @dev 繁殖状态常量：已取消（用户在冷却期内主动取消）
     */
    uint256 public constant BREEDING_STATUS_CANCELLED = 2;

    /**
     * @dev 繁殖配对结构体
     *
     * 存储一个繁殖对的完整信息，包括父母NFT、所有者、状态、子代等
     * @param fatherId 父亲NFT的ID
     * @param motherId 母亲NFT的ID
     * @param maleOwner 父亲NFT所有者地址
     * @param femaleOwner 母亲NFT所有者地址
     * @param maleCoOwnerId 父方共同所有者NFT ID（可选，用于多NFT持有场景）
     * @param femaleCoOwnerId 母方共同所有者NFT ID（可选）
     * @param startTime 繁殖开始时间戳（决定冷却结束时间）
     * @param breedingType 繁殖类型（0=自主繁殖，1=市场繁殖）
     * @param status 繁殖状态（0=进行中，1=已完成，2=已取消）
     * @param childId 子代NFT ID（母方获得，自主繁殖时唯一子代）
     * @param maleChildId 子代NFT ID（父方获得，仅市场繁殖时产生）
     * @param rewardsClaimed 奖励是否已领取（保留字段，当前未使用）
     * @param cancelledAt 取消时间戳（状态为已取消时记录）
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
     * @dev 市场上架结构体
     *
     * 记录一个NFT在繁殖市场的上架状态
     * @param tokenId 上架的NFT ID
     * @param owner 上架者地址
     * @param listTime 上架时间戳
     * @param isActive 是否活跃上架中
     */
    struct MarketListing { 
        uint256 tokenId; 
        address owner; 
        uint256 listTime; 
        bool isActive; 
    }

    /**
     * @dev 繁殖配对映射：pairId => BreedingPair
     * pairId 从 1 开始递增
     */
    mapping(uint256 => BreedingPair) public breedingPairs;
    /**
     * @dev 当前繁殖配对总数（等于最大的pairId）
     */
    uint256 public breedingPairCount;
    /**
     * @dev NFT冷却时间映射：tokenId => 冷却结束时间戳
     * 繁殖完成后NFT进入冷却期，期间不可再次繁殖
     */
    mapping(uint256 => uint256) public breedingCooldowns;
    /**
     * @dev NFT是否在活跃繁殖中的映射：tokenId => bool
     * 防止同一个NFT同时参与多个繁殖配对
     */
    mapping(uint256 => bool) public isNFTInActiveBreeding;
    /**
     * @dev 市场上架信息映射：tokenId => MarketListing
     */
    mapping(uint256 => MarketListing) public marketListings;
    /**
     * @dev 所有历史上架过的NFT ID数组
     */
    uint256[] public listedTokenIds;
    /**
     * @dev 当前活跃上架的NFT ID数组
     */
    uint256[] public activeListedTokenIds;
    /**
     * @dev 用户活跃繁殖对索引：地址 => pairId数组
     * 用于前端快速查询用户的活跃繁殖对，避免遍历所有配对
     */
    mapping(address => uint256[]) private _userActiveOrderIds;

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
    event MarketListingCreated(uint256 indexed tokenId, address indexed owner);
    event MarketListingRemoved(uint256 indexed tokenId, address indexed owner);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);

    modifier whenNotPaused() {
        require(!paused, "Breeding: Paused");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Not authorized");
        _;
    }

    /**
     * @dev 初始化合约
     * @param _authorizer 授权器合约地址
     */
    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "Breeding: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    /**
     * @dev 设置授权器地址
     * @param a 新的授权器地址
     */
    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "Breeding: Invalid authorizer address");
        authorizer = a;
    }

    function setStakingContract(address _stakingContract) external onlyOwner {
        require(_stakingContract != address(0), "Breeding: Invalid staking contract address");
        stakingContract = _stakingContract;
    }

    /**
     * @dev 授权升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 暂停合约
     * @param reason 暂停原因
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消暂停
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 创建自己的NFT繁殖对（玩家用自己的两个NFT繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param coOwnerId 共同所有者NFT ID（可选）
     * @return pairId 繁殖对ID
     */
    function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external nonReentrant whenNotPaused returns (uint256) {
        require(fatherId > 0, "Breeding: Invalid father ID");
        require(motherId > 0, "Breeding: Invalid mother ID");
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(!isNFTInActiveBreeding[fatherId], "Breeding: Father already in breeding");
        require(!isNFTInActiveBreeding[motherId], "Breeding: Mother already in breeding");
        require(breedingPairCount < MAX_BREEDING_PAIRS, "Breeding: Max pairs limit reached");
        
        // 检查 NFT 是否正在质押中
        if (stakingContract != address(0)) {
            (address fatherStaker, , , , ) = IStaking(stakingContract).stakingInfo(fatherId);
            require(fatherStaker == address(0), "Breeding: Father is staked");
            (address motherStaker, , , , ) = IStaking(stakingContract).stakingInfo(motherId);
            require(motherStaker == address(0), "Breeding: Mother is staked");
        }
        
        INFTMint nft = INFTMint(nftMintContract);

        require(nft.ownerOf(fatherId) == msg.sender, "Breeding: Not father owner");
        require(nft.ownerOf(motherId) == msg.sender, "Breeding: Not mother owner");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "Breeding: Different zodiac");
        require((fatherType % 2) != (motherType % 2), "Breeding: Same gender");

        require(breedingCooldowns[fatherId] <= block.timestamp, "Breeding: Father in cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "Breeding: Mother in cooldown");

        if (coOwnerId > 0) {
            require(nft.ownerOf(coOwnerId) == msg.sender, "Breeding: Not co-owner owner");
            require(!isNFTInActiveBreeding[coOwnerId], "Breeding: Co-owner already in breeding");
            uint256 coOwnerType = nft.tokenType(coOwnerId);
            uint256 coOwnerZodiac = (coOwnerType / 2) % 12;
            require(coOwnerZodiac == (fatherType / 2) % 12, "Breeding: Co-owner zodiac mismatch");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: msg.sender, femaleOwner: msg.sender,
            maleCoOwnerId: coOwnerId, femaleCoOwnerId: coOwnerId, startTime: block.timestamp,
            breedingType: 0, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false,
            cancelledAt: 0
        });

        bool fatherTransferred = false;
        bool motherTransferred = false;

        try nft.safeTransferFrom(msg.sender, address(this), fatherId) {
            fatherTransferred = true;
        } catch {
            revert("Breeding: Father NFT transfer failed");
        }
        
        try nft.safeTransferFrom(msg.sender, address(this), motherId) {
            motherTransferred = true;
        } catch {
            if (fatherTransferred) {
                try nft.safeTransferFrom(address(this), msg.sender, fatherId) {
                } catch {
                    emit EmergencyNFTLocked(fatherId, msg.sender);
                }
            }
            revert("Breeding: Mother NFT transfer failed");
        }

        if (selfBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            try IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), selfBreedingFee) {
            } catch {
                if (fatherTransferred) {
                    try nft.safeTransferFrom(address(this), msg.sender, fatherId) {
                    } catch {
                        emit EmergencyNFTLocked(fatherId, msg.sender);
                    }
                }
                if (motherTransferred) {
                    try nft.safeTransferFrom(address(this), msg.sender, motherId) {
                    } catch {
                        emit EmergencyNFTLocked(motherId, msg.sender);
                    }
                }
                revert("Breeding: Fee transfer failed");
            }
        }
        
        isNFTInActiveBreeding[fatherId] = true;
        isNFTInActiveBreeding[motherId] = true;
        breedingCooldowns[fatherId] = block.timestamp + selfBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + selfBreedingCooldown;
        _addActiveOrder(msg.sender, pairId);
        emit BreedingPairCreated(pairId, fatherId, motherId, 0);
        return pairId;
    }

    /**
     * @dev 创建公开市场繁殖对（玩家与其他玩家的NFT繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @return pairId 繁殖对ID
     */
    function createMarketBreedingPairPublic(
        uint256 fatherId, uint256 motherId
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(fatherId > 0, "Breeding: Invalid father ID");
        require(motherId > 0, "Breeding: Invalid mother ID");
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        INFTMint nft = INFTMint(nftMintContract);

        address maleOwner = nft.ownerOf(fatherId);
        address femaleOwner = nft.ownerOf(motherId);
        
        require(maleOwner != femaleOwner, "Breeding: Must use NFTs from different owners");
        require(msg.sender == maleOwner || msg.sender == femaleOwner, "Breeding: Must be owner of one NFT");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");
        
        _checkDailyBreedingLimit(msg.sender);

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "Breeding: Different zodiac");
        require((fatherType % 2) != (motherType % 2), "Breeding: Same gender");

        require(breedingCooldowns[fatherId] <= block.timestamp, "Breeding: Father in cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "Breeding: Mother in cooldown");

        require(nft.isApprovedForAll(maleOwner, address(this)), "Breeding: Father owner not approved");
        require(nft.isApprovedForAll(femaleOwner, address(this)), "Breeding: Mother owner not approved");

        if (marketBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), marketBreedingFee), "Breeding: Fee transfer failed");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: 0, femaleCoOwnerId: 0, startTime: block.timestamp,
            breedingType: 1, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false,
            cancelledAt: 0
        });

        // 带 try-catch 的 NFT 转账，防止单方转账失败导致费用损失
        bool fatherTransferred = false;
        bool motherTransferred = false;

        try nft.safeTransferFrom(maleOwner, address(this), fatherId) {
            fatherTransferred = true;
        } catch {
            if (marketBreedingFee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, marketBreedingFee);
            }
            revert("Breeding: Father NFT transfer failed");
        }

        try nft.safeTransferFrom(femaleOwner, address(this), motherId) {
            motherTransferred = true;
        } catch {
            if (fatherTransferred) {
                try nft.safeTransferFrom(address(this), maleOwner, fatherId) {
                } catch {
                    emit EmergencyNFTLocked(fatherId, maleOwner);
                }
            }
            if (marketBreedingFee > 0 && tokenContract != address(0)) {
                IERC20(tokenContract).safeTransfer(msg.sender, marketBreedingFee);
            }
            revert("Breeding: Mother NFT transfer failed");
        }
        
        isNFTInActiveBreeding[fatherId] = true;
        isNFTInActiveBreeding[motherId] = true;
        breedingCooldowns[fatherId] = block.timestamp + marketBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + marketBreedingCooldown;
        _updateDailyBreedingCount(msg.sender);
        _addActiveOrder(maleOwner, pairId);
        _addActiveOrder(femaleOwner, pairId);
        emit BreedingPairCreated(pairId, fatherId, motherId, 1);
        return pairId;
    }

    /**
     * @dev 检查每日公开繁殖限制
     * @param user 用户地址
     */
    function _checkDailyBreedingLimit(address user) internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastBreedingDay[user] != currentDay) {
            dailyPublicBreedings[user] = 0;
            lastBreedingDay[user] = currentDay;
        }
        require(dailyPublicBreedings[user] < maxDailyPublicBreedings, "Breeding: Daily breeding limit exceeded");
    }

    /**
     * @dev 更新每日繁殖计数
     * @param user 用户地址
     */
    function _updateDailyBreedingCount(address user) internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastBreedingDay[user] != currentDay) {
            dailyPublicBreedings[user] = 1;
            lastBreedingDay[user] = currentDay;
        } else {
            dailyPublicBreedings[user]++;
        }
    }

    /**
     * @dev 设置每日最大公开繁殖次数
     * @param limit 最大次数
     */
    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    /**
     * @dev 完成繁殖（产出子代NFT）
     * @param pairId 繁殖对ID
     * @dev 取消繁殖配对
     * @param pairId 繁殖配对ID
     */
    function cancelBreeding(uint256 pairId) external nonReentrant whenNotPaused {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "Breeding: Pair not active");
        require(pair.childId == 0, "Breeding: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "Breeding: Not pair owner");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");

        // 只允许在冷却期结束前取消
        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp < pair.startTime + cooldown, "Breeding: Cannot cancel after cooldown ended");

        INFTMint nft = INFTMint(nftMintContract);
        
        // 先更新状态为取消（防止重入）
        pair.status = BREEDING_STATUS_CANCELLED;
        pair.cancelledAt = block.timestamp;
        
        // 清除NFT活跃繁殖标记
        isNFTInActiveBreeding[pair.fatherId] = false;
        isNFTInActiveBreeding[pair.motherId] = false;
        
        // 重置冷却时间（取消后重新计算）
        breedingCooldowns[pair.fatherId] = 0;
        breedingCooldowns[pair.motherId] = 0;

        _removeActiveOrder(pair.maleOwner, pairId);
        _removeActiveOrder(pair.femaleOwner, pairId);
        
        // 最后归还NFT给原所有者，失败时锁在合约中
        try nft.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {
        } catch {
            emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
        }
        
        try nft.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {
        } catch {
            emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
        }
        
        emit BreedingCancelled(pairId, pair.fatherId, pair.motherId, msg.sender);
    }
    
    event BreedingCancelled(uint256 indexed pairId, uint256 fatherId, uint256 motherId, address indexed canceller);
    
    /**
     * @dev 完成繁殖，生成新的NFT
     * @param pairId 繁殖配对ID
     * @return childId 母方获得的子代NFT ID
     * @return maleChildId 父方获得的子代NFT ID（市场繁殖时）
     */
    function completeBreeding(uint256 pairId) external nonReentrant whenNotPaused returns (uint256, uint256) {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == BREEDING_STATUS_ACTIVE, "Breeding: Pair not active");
        require(pair.childId == 0, "Breeding: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "Breeding: Not pair owner");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");

        uint256 cooldown = pair.breedingType == BREEDING_TYPE_SELF ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "Breeding: Cooldown not ended");

        INFTMint nft = INFTMint(nftMintContract);
        uint256 zodiacType = _getChildZodiacType(pair.fatherId, pair.motherId);
        require(zodiacType > 0, "Breeding: Invalid child zodiac type");

        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, pairId, tx.gasprice)));
        uint8 childGrowth = uint8((seed % 91) + 10);

        if (pair.breedingType == BREEDING_TYPE_SELF) {
            uint256 childId = nft.mintForBreeding(pair.femaleOwner, zodiacType, childGrowth);
            require(childId > 0, "Breeding: NFT mint failed");

            pair.childId = childId;
            pair.status = 1;
            isNFTInActiveBreeding[pair.fatherId] = false;
            isNFTInActiveBreeding[pair.motherId] = false;
            _removeActiveOrder(pair.maleOwner, pairId);
            _removeActiveOrder(pair.femaleOwner, pairId);

            _burnFee(pair.breedingType);

            _returnNFT(nft, pair.fatherId, pair.maleOwner);
            _returnNFT(nft, pair.motherId, pair.femaleOwner);

            emit BreedingCompleted(pairId, childId, zodiacType);
            return (childId, 0);
        } else {
            uint8 femaleChildGrowth = uint8((seed % 91) + 10);
            uint8 maleChildGrowth = uint8(((seed + 1000) % 91) + 10);

            uint256 childIdForFemale = nft.mintForBreeding(pair.femaleOwner, zodiacType, femaleChildGrowth);
            require(childIdForFemale > 0, "Breeding: Female child mint failed");

            uint256 childIdForMale = nft.mintForBreeding(pair.maleOwner, zodiacType, maleChildGrowth);
            require(childIdForMale > 0, "Breeding: Male child mint failed");

            pair.childId = childIdForFemale;
            pair.maleChildId = childIdForMale;
            pair.status = 1;
            isNFTInActiveBreeding[pair.fatherId] = false;
            isNFTInActiveBreeding[pair.motherId] = false;
            _removeActiveOrder(pair.maleOwner, pairId);
            _removeActiveOrder(pair.femaleOwner, pairId);

            _burnFee(pair.breedingType);

            _returnNFT(nft, pair.fatherId, pair.maleOwner);
            _returnNFT(nft, pair.motherId, pair.femaleOwner);

            emit BreedingCompleted(pairId, childIdForFemale, zodiacType);
            emit MaleChildGenerated(pairId, childIdForMale);
            emit FemaleChildGenerated(pairId, childIdForFemale);
            return (childIdForFemale, childIdForMale);
        }
    }

    function _returnNFT(INFTMint nft, uint256 tokenId, address owner) internal {
        try nft.safeTransferFrom(address(this), owner, tokenId) {
        } catch {
            emit EmergencyNFTLocked(tokenId, owner);
        }
    }

    

    /**
     * @dev 获取繁殖对信息
     * @param pairId 繁殖对ID
     * @return fatherId 父亲ID
     * @return motherId 母亲ID
     * @return maleOwner 父方所有者
     * @return femaleOwner 母方所有者
     * @return maleCoOwnerId 父方共同所有者NFT ID
     * @return femaleCoOwnerId 母方共同所有者NFT ID
     * @return startTime 开始时间
     * @return breedingType 繁殖类型（0=自己繁殖，1=市场繁殖）
     * @return status 状态（0=进行中，1=已完成，2=已取消）
     * @return childId 子代ID（母方）
     * @return maleChildId 子代ID（父方，市场繁殖）
     * @return rewardsClaimed 奖励是否已领取
     */
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

    /**
     * @dev 检查NFT是否在冷却期
     * @param tokenId NFT ID
     * @return 是否在冷却期
     */
    function isInCooldown(uint256 tokenId) external view returns (bool) { 
        return breedingCooldowns[tokenId] > block.timestamp; 
    }

    /**
     * @dev 获取NFT冷却结束时间
     * @param tokenId NFT ID
     * @return 冷却结束时间戳
     */
    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) { 
        return breedingCooldowns[tokenId]; 
    }

    /**
     * @dev 计算子代NFT的生肖类型
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @return 子代生肖类型
     */
    function _getChildZodiacType(uint256 fatherId, uint256 motherId) internal view returns (uint256) {
        if (nftMintContract == address(0)) return 0;
        INFTMint nftMint = INFTMint(nftMintContract);
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "Breeding: Parent zodiac mismatch");

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

    /**
     * @dev 销毁繁殖费用
     * @param breedingType 繁殖类型
     */
    function _burnFee(uint256 breedingType) internal {
        if (tokenContract == address(0)) return;
        uint256 fee = breedingType == BREEDING_TYPE_SELF ? selfBreedingFee : marketBreedingFee;
        if (fee == 0) return;
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= fee, "Breeding: Insufficient fee balance");
        require(token.transfer(BLACK_HOLE, fee), "Breeding: Fee burn transfer failed");
        emit BreedingFeeBurned(fee);
    }

    /**
     * @dev 设置自己繁殖费用
     * @param fee 费用金额
     */
    function setSelfBreedingFee(uint256 fee) external onlyOwner { 
        selfBreedingFee = fee; 
    }

    /**
     * @dev 设置市场繁殖费用
     * @param fee 费用金额
     */
    function setMarketBreedingFee(uint256 fee) external onlyOwner { 
        marketBreedingFee = fee; 
    }

    /**
     * @dev 设置自己繁殖冷却时间
     * @param cooldown 冷却时间（秒）
     */
    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "Breeding: Cooldown must be > 0"); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    /**
     * @dev 设置市场繁殖冷却时间
     * @param cooldown 冷却时间（秒）
     */
    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "Breeding: Cooldown must be > 0"); 
        marketBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyAuthorized { 
        require(_nftContract != address(0), "Breeding: Invalid NFT contract address"); 
        nftMintContract = _nftContract; 
        emit NFTContractSet(nftMintContract); 
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized { 
        require(_tokenContract != address(0), "Breeding: Invalid token contract address"); 
        tokenContract = _tokenContract; 
        emit TokenContractSet(_tokenContract); 
    }

    /**
     * @dev 获取用户活跃的繁殖订单
     * @param user 用户地址
     * @return 活跃繁殖订单ID数组
     */
    function getUserActiveOrders(address user) external view returns (uint256[] memory) {
        // 过滤出仍活跃的订单，保证返回数据实时准确
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

    /**
     * @dev 将繁殖配对加入用户活跃索引
     */
    function _addActiveOrder(address user, uint256 pairId) internal {
        // 去重，防止重复添加
        uint256[] storage list = _userActiveOrderIds[user];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == pairId) return;
        }
        list.push(pairId);
    }

    /**
     * @dev 将繁殖配对从用户活跃索引移除
     */
    function _removeActiveOrder(address user, uint256 pairId) internal {
        uint256[] storage list = _userActiveOrderIds[user];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == pairId) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }

    /**
     * @dev 将NFT上架到繁殖市场
     * @param tokenId NFT ID
     */
    function listForMarketBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(INFTMint(nftMintContract).ownerOf(tokenId) == msg.sender, "Breeding: Not token owner");
        require(!marketListings[tokenId].isActive, "Breeding: Already listed");
        require(!isInCooldown(tokenId), "Breeding: NFT in cooldown");
        require(!isNFTInActiveBreeding[tokenId], "Breeding: NFT in active breeding");
        require(INFTMint(nftMintContract).tokenLevel(tokenId) >= 5, "Breeding: Level too low");

        marketListings[tokenId] = MarketListing({ tokenId: tokenId, owner: msg.sender, listTime: block.timestamp, isActive: true });
        listedTokenIds.push(tokenId);
        activeListedTokenIds.push(tokenId);
        emit MarketListingCreated(tokenId, msg.sender);
    }

    /**
     * @dev 将NFT从繁殖市场下架
     * @param tokenId NFT ID
     */
    function delistFromMarketBreeding(uint256 tokenId) external nonReentrant whenNotPaused {
        require(marketListings[tokenId].isActive, "Breeding: Not listed");
        require(marketListings[tokenId].owner == msg.sender, "Breeding: Not listing owner");
        delete marketListings[tokenId];
        
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (listedTokenIds[i] == tokenId) {
                listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                listedTokenIds.pop();
                break;
            }
        }
        
        for (uint256 i = 0; i < activeListedTokenIds.length; i++) {
            if (activeListedTokenIds[i] == tokenId) {
                activeListedTokenIds[i] = activeListedTokenIds[activeListedTokenIds.length - 1];
                activeListedTokenIds.pop();
                break;
            }
        }
        
        emit MarketListingRemoved(tokenId);
    }

    /**
     * @dev 获取所有活跃的市场上架NFT ID列表
     * @return 活跃NFT ID数组
     */
    function getMarketListingIds() external view returns (uint256[] memory) {
        return activeListedTokenIds;
    }

    /**
     * @dev 获取市场上架信息
     * @param tokenId NFT ID
     * @return 上架信息结构体
     */
    function getMarketListing(uint256 tokenId) external view returns (MarketListing memory) { 
        return marketListings[tokenId]; 
    }

    /**
     * @dev 获取市场上架数量
     * @return 上架数量
     */
    function getMarketListingCount() external view returns (uint256) { 
        return listedTokenIds.length; 
    }

    /**
     * @dev 获取NFT的繁殖冷却剩余时间
     * @param tokenId NFT ID
     * @return remainingCooldown 剩余冷却时间（秒），0表示无冷却
     */
    function getNFTBreedingCooldown(uint256 tokenId) external view returns (uint256 remainingCooldown) {
        if (breedingCooldowns[tokenId] == 0) {
            return 0;
        }
        if (block.timestamp >= breedingCooldowns[tokenId]) {
            return 0;
        }
        return breedingCooldowns[tokenId] - block.timestamp;
    }

    /**
     * @dev 批量获取NFT的繁殖冷却剩余时间
     * @param tokenIds NFT ID数组
     * @return remainingCooldowns 剩余冷却时间数组
     */
    function getNFTBreedingCooldowns(uint256[] calldata tokenIds) external view returns (uint256[] memory remainingCooldowns) {
        remainingCooldowns = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            remainingCooldowns[i] = getNFTBreedingCooldown(tokenIds[i]);
        }
    }

    /**
     * @dev 获取用户的繁殖对统计
     * @param user 用户地址
     * @return totalPairs 总繁殖对数
     * @return activePairs 进行中繁殖对数
     * @return completedPairs 已完成繁殖对数
     * @return claimablePairs 可领取奖励对数
     */
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

    /**
     * @dev 获取繁殖对详情（带冷却信息）
     * @param pairId 繁殖对ID
     * @return fatherId 父亲ID
     * @return motherId 母亲ID
     * @return fatherCooldown 父亲剩余冷却
     * @return motherCooldown 母亲剩余冷却
     * @return remainingTime 剩余繁殖时间
     * @return status 状态
     */
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

    /**
     * @dev 紧急提取BNB
     * @param amount 提取数量
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Breeding: Amount must be > 0");
        require(amount <= address(this).balance, "Breeding: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Breeding: BNB transfer failed");
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币
     * @param amount 提取数量
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Breeding: Amount must be > 0");
        require(tokenContract != address(0), "Breeding: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "Breeding: Insufficient token balance");
        require(token.transfer(owner(), amount), "Breeding: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取NFT
     * @param tokenId NFT ID
     */
    function emergencyWithdrawNFT(uint256 tokenId) external onlyOwner nonReentrant {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(!isNFTInActiveBreeding[tokenId], "Breeding: NFT in active breeding");
        INFTMint nft = INFTMint(nftMintContract);
        nft.safeTransferFrom(address(this), owner(), tokenId);
        emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenId);
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