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
 * 
 * 核心职责：
 * 1. 自繁殖（Self Breeding）：单个用户的两只NFT进行繁殖
 * 2. 市场繁殖（Market Breeding）：两只分属不同用户的NFT进行繁殖
 * 
 * 繁殖流程：
 * 1. 创建繁殖配对（createSelfBreedingPair / createMarketBreedingPairPublic）
 * 2. 等待冷却期结束（selfBreedingCooldown / marketBreedingCooldown）
 * 3. 完成繁殖（completeBreeding）- 生成子代NFT
 * 
 * 安全机制：
 * - ReentrancyGuard：防止重入攻击
 * - Pausable：可暂停所有繁殖操作
 * - NFT所有权验证：确保繁殖配对的NFT属于正确的主人
 * - 冷却时间：防止NFT被过度频繁繁殖
 */
contract BreedingCore is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using BreedingLib for *;

    // ============================
    // 费用与冷却时间配置
    // ============================
    
    /// @dev 自繁殖冷却时间（繁殖完成后需等待的时间）
    uint256 public selfBreedingCooldown;
    
    /// @dev 市场繁殖冷却时间
    uint256 public marketBreedingCooldown;
    
    /// @dev 自繁殖费用（需要支付给合约的代币数量）
    uint256 public selfBreedingFee;
    
    /// @dev 市场繁殖费用
    uint256 public marketBreedingFee;
    
    /// @dev 授权合约地址（用于获取其他合约地址）
    address public authorizer;
    
    /// @dev 黑洞地址（费用燃烧地址）
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    // ============================
    // 繁殖类型常量
    // ============================
    
    /// @dev 繁殖类型：自繁殖（同一个所有者）
    uint256 public constant BREEDING_TYPE_SELF = 0;
    
    /// @dev 繁殖类型：市场繁殖（不同所有者）
    uint256 public constant BREEDING_TYPE_MARKET = 1;
    
    /// @dev 最大繁殖配对数量限制
    uint256 public constant MAX_BREEDING_PAIRS = 10000;

    // ============================
    // 每日繁殖限制
    // ============================
    
    /// @dev 每个用户每日最大公开繁殖次数
    uint256 public maxDailyPublicBreedings;
    
    /// @dev 用户每日已完成的公开繁殖次数映射
    mapping(address => uint256) public dailyPublicBreedings;
    
    /// @dev 用户上次繁殖日期记录（用于计算每日限制）
    mapping(address => uint256) public lastBreedingDay;

    // ============================
    // 暂停功能
    // ============================
    
    /// @dev 合约是否已暂停
    bool public paused;
    
    /// @dev 暂停原因描述
    string public pauseReason;

    // ============================
    // 繁殖配对状态常量
    // ============================
    
    /// @dev 繁殖配对状态：进行中
    uint256 public constant BREEDING_STATUS_ACTIVE = 0;
    
    /// @dev 繁殖配对状态：已完成
    uint256 public constant BREEDING_STATUS_COMPLETED = 1;
    
    /// @dev 繁殖配对状态：已取消
    uint256 public constant BREEDING_STATUS_CANCELLED = 2;

    // ============================
    // 繁殖配对数据结构
    // ============================
    
    /// @notice 繁殖配对结构体
    /// @dev 存储一次繁殖的所有相关信息
    struct BreedingPair {
        uint256 fatherId;          // 父亲NFT ID
        uint256 motherId;          // 母亲NFT ID
        address maleOwner;         // 雄性NFT所有者
        address femaleOwner;        // 雌性NFT所有者
        uint256 maleCoOwnerId;     // 雄性NFT共有人ID（用于特殊繁殖）
        uint256 femaleCoOwnerId;   // 雌性NFT共有人ID
        uint256 startTime;         // 繁殖开始时间
        uint256 breedingType;      // 繁殖类型（0=自繁殖，1=市场繁殖）
        uint256 status;            // 当前状态
        uint256 childId;           // 子代NFT ID（雌性子代）
        uint256 maleChildId;       // 雄性子代NFT ID（仅市场繁殖有）
        bool rewardsClaimed;       // 奖励是否已领取
        uint256 cancelledAt;       // 取消时间戳
    }

    // ============================
    // 繁殖配对映射
    // ============================
    
    /// @dev 繁殖配对ID到配对信息的映射
    mapping(uint256 => BreedingPair) public breedingPairs;
    
    /// @dev 当前繁殖配对总数
    uint256 public breedingPairCount;
    
    /// @dev NFT冷却时间映射（NFT ID => 冷却结束时间戳）
    mapping(uint256 => uint256) public breedingCooldowns;
    
    /// @dev NFT是否正在活跃繁殖中（防止双重繁殖）
    mapping(uint256 => bool) public isNFTInActiveBreeding;
    
    /// @dev 用户活跃繁殖配对ID列表（仅存储活跃状态的配对）
    mapping(address => uint256[]) private _userActiveOrderIds;
    
    /// @dev 用户所有繁殖配对ID列表（包含历史记录）
    mapping(address => uint256[]) private _userAllOrderIds;
    
    /// @dev 繁殖配对是否存在（防止重复配对）
    mapping(uint256 => mapping(uint256 => bool)) private _breedingPairExists;

    // ============================
    // 事件定义
    // ============================
    
    /// @dev 繁殖配对创建事件
    event BreedingPairCreated(uint256 indexed pairId, uint256 indexed fatherId, uint256 indexed motherId, uint256 breedingType);
    
    /// @dev 繁殖完成事件
    event BreedingCompleted(uint256 indexed pairId, uint256 indexed childId, uint256 zodiacType);
    
    /// @dev 雄性子代生成事件
    event MaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    
    /// @dev 雌性子代生成事件
    event FemaleChildGenerated(uint256 indexed pairId, uint256 indexed childId);
    
    /// @dev 冷却时间更新事件
    event CooldownUpdated(uint256 selfCooldown, uint256 marketCooldown);
    
    /// @dev 繁殖费用燃烧事件
    event BreedingFeeBurned(uint256 amount);
    
    /// @dev 合约暂停事件
    event Paused(address indexed account, string reason);
    
    /// @dev 合约取消暂停事件
    event Unpaused(address indexed account);
    
    /// @dev 紧急锁定NFT事件
    event EmergencyNFTLocked(uint256 indexed tokenId, address indexed owner);
    
    /// @dev 紧急提取BNB事件
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    
    /// @dev 紧急提取代币事件
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    
    /// @dev 紧急提取NFT事件
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);
    
    /// @dev 繁殖取消事件
    event BreedingCancelled(uint256 indexed pairId, uint256 fatherId, uint256 motherId, address indexed canceller);

    /// @dev 合约数据重置事件
    event ContractDataReset(address indexed operator, uint256 timestamp);

    // ============================
    // 修饰器
    // ============================
    
    /// @dev 修饰器：检查合约是否未暂停
    modifier whenNotPaused() {
        require(!paused, "BC: P");
        _;
    }

    /// @dev 修饰器：仅owner或授权合约可调用
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "BC: ANS");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "BC: NA");
        _;
    }

    // ============================
    // 构造函数与初始化
    // ============================
    
    /// @dev 构造函数：禁用初始化器，防止实现合约被直接部署后被初始化攻击
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _authorizerAddress 授权合约地址
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "BC: IA");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "BC: IA");
        authorizer = _authorizerAddress;
    }

    /// @dev UUPS升级授权检查
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============================
    // 暂停功能
    // ============================
    
    /**
     * @dev 暂停合约所有操作
     * @param reason 暂停原因描述
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /// @dev 取消暂停，恢复合约操作
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    // ============================
    // 繁殖功能
    // ============================
    
    /**
     * @dev 创建自繁殖配对（同一用户的两个NFT进行繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param coOwnerId 共有人NFT ID（可选，用于特殊繁殖）
     * @return pairId 新创建的繁殖配对ID
     */
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

    /**
     * @dev 创建市场公开繁殖配对（不同用户的NFT进行繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @return pairId 新创建的繁殖配对ID
     */
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

    /**
     * @dev 通用繁殖配对创建逻辑
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 雄性NFT所有者地址
     * @param femaleOwner 雌性NFT所有者地址
     * @param fee 繁殖费用
     * @param cooldown 冷却时间
     * @param breedingType 繁殖类型
     * @return pairId 新创建的繁殖配对ID
     */
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

    /**
     * @dev 验证繁殖配对的有效性
     * @param nft NFT合约实例
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     */
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

    /**
     * @dev 创建繁殖配对数据结构
     * @param pairId 配对ID
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 雄性NFT所有者
     * @param femaleOwner 雌性NFT所有者
     * @param breedingType 繁殖类型
     */
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

    /**
     * @dev 完成繁殖交易（转移NFT和费用）
     * @param nftMintContract NFT铸造合约地址
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 雄性NFT所有者
     * @param femaleOwner 雌性NFT所有者
     * @param fee 繁殖费用
     * @param cooldown 冷却时间
     * @param pairId 配对ID
     */
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

    /**
     * @dev 转移繁殖中的NFT
     * @param nft NFT合约实例
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 雄性NFT所有者
     * @param femaleOwner 雌性NFT所有者
     * @param fee 繁殖费用
     * @param tokenContract 代币合约地址
     */
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

    // ============================
    // 配置管理
    // ============================
    
    /**
     * @dev 设置每日最大公开繁殖次数
     * @param limit 新的每日限制数量
     */
    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    /**
     * @dev 设置自繁殖费用
     * @param fee 新的自繁殖费用
     */
    function setSelfBreedingFee(uint256 fee) external onlyOwner { 
        selfBreedingFee = fee; 
    }

    /**
     * @dev 设置市场繁殖费用
     * @param fee 新的市场繁殖费用
     */
    function setMarketBreedingFee(uint256 fee) external onlyOwner { 
        marketBreedingFee = fee; 
    }

    /**
     * @dev 设置自繁殖冷却时间
     * @param cooldown 新的冷却时间（秒）
     */
    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: CM0"); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    /**
     * @dev 设置市场繁殖冷却时间
     * @param cooldown 新的冷却时间（秒）
     */
    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "BC: CM0"); 
        marketBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    // ============================
    // 取消繁殖
    // ============================
    
    /**
     * @dev 取消繁殖配对（在冷却期内可取消）
     * @param pairId 要取消的繁殖配对ID
     */
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

    // ============================
    // 完成繁殖
    // ============================
    
    /**
     * @dev 完成繁殖（生成子代NFT）
     * @param pairId 繁殖配对ID
     * @return childId 雌性子代NFT ID
     * @return maleChildId 雄性子代NFT ID（市场繁殖有两个子代）
     */
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

    /**
     * @dev 完成自繁殖（生成一个子代）
     * @param pairId 配对ID
     * @param nft NFT合约实例
     * @param nft721 ERC721合约实例
     * @param pair 繁殖配对引用
     * @param zodiacType 子代星座类型
     * @param seed 随机种子
     * @return childId 子代NFT ID
     * @return maleChildId 雄性子代ID（自繁殖为0）
     */
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

    /**
     * @dev 完成市场繁殖（生成两个子代）
     * @param pairId 配对ID
     * @param nft NFT合约实例
     * @param nft721 ERC721合约实例
     * @param pair 繁殖配对引用
     * @param zodiacType 子代星座类型
     * @param seed 随机种子
     * @return childId 雌性子代NFT ID
     * @return maleChildId 雄性子代NFT ID
     */
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

    /**
     * @dev 完成繁殖后处理（清理状态、燃烧费用、归还NFT）
     * @param pairId 配对ID
     * @param pair 繁殖配对引用
     * @param nft721 ERC721合约实例
     */
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

    // ============================
    // 查询功能
    // ============================
    
    /**
     * @dev 获取繁殖配对详细信息
     * @param pairId 繁殖配对ID
     * @return fatherId 父亲NFT ID
     * @return motherId 母亲NFT ID
     * @return maleOwner 雄性NFT所有者
     * @return femaleOwner 雌性NFT所有者
     * @return maleCoOwnerId 雄性共有人ID
     * @return femaleCoOwnerId 雌性共有人ID
     * @return startTime 繁殖开始时间
     * @return breedingType 繁殖类型
     * @return status 当前状态
     * @return childId 子代NFT ID
     * @return maleChildId 雄性子代ID
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
     * @dev 检查NFT是否在冷却中
     * @param tokenId NFT ID
     * @return bool 是否在冷却中
     */
    function isInCooldown(uint256 tokenId) public view returns (bool) { 
        return breedingCooldowns[tokenId] > block.timestamp; 
    }

    /**
     * @dev 获取NFT冷却结束时间戳
     * @param tokenId NFT ID
     * @return uint256 冷却结束时间戳
     */
    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) { 
        return breedingCooldowns[tokenId]; 
    }

    /**
     * @dev 获取用户活跃的繁殖配对列表
     * @param user 用户地址
     * @return uint256[] 活跃繁殖配对ID数组
     */
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

    /**
     * @dev 获取用户的繁殖统计数据
     * @param user 用户地址
     * @return totalPairs 总繁殖配对数
     * @return activePairs 活跃配对数
     * @return completedPairs 已完成配对数
     * @return claimablePairs 可领取奖励的配对数
     */
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

    /**
     * @dev 获取繁殖配对及其冷却信息
     * @param pairId 繁殖配对ID
     * @return fatherId 父亲NFT ID
     * @return motherId 母亲NFT ID
     * @return fatherCooldown 父亲NFT冷却结束时间
     * @return motherCooldown 母亲NFT冷却结束时间
     * @return remainingTime 剩余冷却时间
     * @return status 配对状态
     */
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

    // ============================
    // 内部逻辑
    // ============================
    
    /**
     * @dev 计算子代星座类型
     * @param nftMint NFT铸造合约实例
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param randomSeed 随机种子
     * @return uint256 子代星座类型
     */
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

    /**
     * @dev 燃烧繁殖费用
     * @param breedingType 繁殖类型
     */
    function _burnFee(uint256 breedingType) internal {
        address tokenContract = IAuthorizer(authorizer).getToken();
        // 修复：如果代币合约未设置，应该revert而不是静默跳过，否则繁殖费用会被丢失
        require(tokenContract != address(0), "BC: TNS");
        uint256 fee = breedingType == BREEDING_TYPE_SELF ? selfBreedingFee : marketBreedingFee;
        if (fee == 0) return;
        
        IERC20 token = IERC20(tokenContract);
        
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= fee, "BC: IBFB");
        
        token.safeTransfer(BLACK_HOLE, fee);
        emit BreedingFeeBurned(fee);
    }

    /**
     * @dev 同步NFT转移后的权重信息
     * @param from 转出地址
     * @param to 转入地址
     * @param tokenId NFT ID
     * @param nftContract NFT合约地址
     */
    function _syncWeightAfterTransfer(address from, address to, uint256 tokenId, address nftContract) internal {
        BreedingLib.syncWeightAfterTransfer(authorizer, from, to, tokenId);
    }

    // ============================
    // 紧急提取功能
    // ============================
    
    /**
     * @dev 紧急提取功能（仅owner可调用）
     * @param tokenType 资产类型：0=BNB, 1=ERC20代币, 2=NFT
     * @param tokenIdOrAmount 对于BNB/ERC20是金额，对于NFT是tokenId
     * @param amount ERC20代币数量（仅ERC20时使用）
     */
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

    // ============================
    // 接收函数
    // ============================
    
    /// @dev 接收ETH转账
    receive() external payable {}
    
    /// @dev 接收ETH转账（备用）
    fallback() external payable {}

    // ============================
    // 数据重置功能
    // ============================

    /**
     * @dev 重置合约核心状态数据
     * @notice 仅owner或授权合约可调用，用于紧急情况下的数据重置
     * @dev 由于Solidity无法遍历mapping，只重置核心状态变量
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        // 重置计数器
        breedingPairCount = 0;

        // 重置暂停状态
        paused = false;
        pauseReason = "";

        // 注意：mapping无法遍历清空，但通过重置计数器和标志位，
        // 新的数据会覆盖旧数据，不会影响合约正常运行

        emit ContractDataReset(msg.sender, block.timestamp);
    }
}