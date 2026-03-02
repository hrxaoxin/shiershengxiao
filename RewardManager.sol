// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title IERC2981 接口
 */
interface IERC2981 { 
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

/**
 * @title BlessingType 枚举
 */
enum BlessingType { AiGuo, FuQiang, HeXie, YouShan, JingYe, WanNeng, WuFuLinMen }

/**
 * @title RewardManager 合约
 * @dev 管理五福NFT的奖励和分红系统
 */
contract RewardManager is 
    Initializable, 
    Ownable2StepUpgradeable,
    UUPSUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable,
    IERC2981 
{
    // 核心常量
    uint256 public constant VERSION = 2;
    uint256 public constant WEIGHT_PER_CARD = 13;
    uint256 public constant WU_FU_WEIGHT = 100;
    uint256 public constant MIN_OWNER_WEIGHT = 100;
    uint256 public constant MAX_ROYALTY_FEE = 5000;
    uint256 public constant MAX_BATCH_OPERATIONS = 10;

    // 核心状态变量
    uint256 public holdersCount;
    uint256 public dividendPool;
    uint256 public totalDistributed;
    address public operator;
    address public nftContract;
    address public authorizer; // 授权合约地址
    uint256 public ownerWeight;
    address public royaltyWallet;
    uint256 public royaltyFee = 500;
    
    mapping(address => bool) public authorizedNFTContracts;
    mapping(address => mapping(BlessingType => uint256)) public cardCount;
    mapping(address => bool) public isWuFuHolder;
    mapping(address => uint256) public claimedDividend;
    mapping(address => uint256) public precisionAcc;
    mapping(address => uint256) public userWeight;
    uint256 public totalWeight;

    // 合格用户链表
    mapping(address => address) public eligibleUserPrev;
    mapping(address => address) public eligibleUserNext;
    address public eligibleUserHead;
    address public eligibleUserTail;
    mapping(address => bool) public inEligibleList;

    // 交易限速
    mapping(address => mapping(bytes4 => uint256)) public lastOperationTime;
    uint256 public operationCooldown = 1 seconds;

    // 事件定义
    event WuFuAdded(address indexed user, uint256 ts);
    event WuFuRemoved(address indexed user, uint256 ts);
    event CardUpdated(address indexed user, BlessingType t, uint256 c, uint256 ts);
    event DividendClaimed(address indexed user, uint256 amt, uint256 prec, uint256 ts);
    event DividendDeposited(uint256 amt, address indexed sender, uint256 ts);
    event WanNengBurned(address indexed user, uint256 cnt, uint256 ts);
    event UserWeightUpdated(address indexed user, uint256 oldWeight, uint256 newWeight, uint256 ts);
    event TotalWeightUpdated(uint256 oldTotal, uint256 newTotal, uint256 ts);
    event NFTContractAuthorized(address indexed nftContract, bool authorized, uint256 timestamp);
    event EmergencyPause(address indexed owner, uint256 timestamp);
    event NFTContractUpdated(address indexed oldNFTContract, address indexed newNFTContract, uint256 timestamp);
    event RoyaltyWalletUpdated(address indexed oldWallet, address indexed newWallet, uint256 timestamp);
    event ExtraFundsWithdrawn(address indexed owner, uint256 amount, uint256 timestamp);
    event FullFundsWithdrawn(address indexed owner, uint256 amount, uint256 timestamp);

    // 存储间隙
    uint256[90] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // 权限修饰器
    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || 
            msg.sender == operator || 
            msg.sender == nftContract ||
            msg.sender == authorizer ||
            authorizedNFTContracts[msg.sender],
            "RewardManager: Unauthorized"
        );
        _;
    }

    modifier nonZeroAddress(address _addr) {
        require(_addr != address(0), "RewardManager: Zero address");
        _;
    }

    modifier onlyEmergencyOwner() {
        require(msg.sender == owner(), "RewardManager: Only owner");
        _;
    }

    modifier rateLimited(bytes4 funcSig) {
        require(
            block.timestamp >= lastOperationTime[msg.sender][funcSig] + operationCooldown,
            "RewardManager: Operation cooldown active"
        );
        lastOperationTime[msg.sender][funcSig] = block.timestamp;
        _;
    }
    
    // 初始化函数
    function initialize(
        address initialOwner, 
        address _royaltyWallet, 
        address _operator,
        address _nftContract,
        address _authorizer
    ) external initializer nonZeroAddress(initialOwner) nonZeroAddress(_operator) nonZeroAddress(_nftContract) {
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        royaltyWallet = _royaltyWallet == address(0) ? 0x55d398326f99059fF775485246999027B3197955 : _royaltyWallet;
        operator = _operator;
        nftContract = _nftContract;
        authorizer = _authorizer;
        ownerWeight = MIN_OWNER_WEIGHT;
        totalWeight = ownerWeight;

        // 初始化链表
        eligibleUserHead = address(0);
        eligibleUserTail = address(0);

        // 授权初始NFT合约
        authorizedNFTContracts[_nftContract] = true;

        emit TotalWeightUpdated(0, totalWeight, block.timestamp);
    }

    // UUPS升级权限
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyEmergencyOwner 
        nonZeroAddress(newImplementation) 
    {}

    // ERC2981 接口实现
    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        return (royaltyWallet, (salePrice * royaltyFee) / 10000);
    }

    // 设置授权NFT合约
    function setAuthorizedNFTContract(address nft, bool ok) external nonZeroAddress(nft) {
        require(msg.sender == owner() || msg.sender == operator || msg.sender == nftContract || msg.sender == authorizer || authorizedNFTContracts[msg.sender], "RewardManager: Unauthorized");
        authorizedNFTContracts[nft] = ok;
        emit NFTContractAuthorized(nft, ok, block.timestamp);
    }

    // 设置NFT合约
    function setNFTContract(address _newNFTContract) external onlyOwner nonZeroAddress(_newNFTContract) {
        address oldNFTContract = nftContract;
        require(oldNFTContract != _newNFTContract, "RM: same nft contract");
        nftContract = _newNFTContract;
        emit NFTContractUpdated(oldNFTContract, _newNFTContract, block.timestamp);
    }

    // 设置操作员
    function setOperator(address _op) external onlyOwner nonZeroAddress(_op) {
        operator = _op;
    }

    // 设置所有者权重
    function setOwnerWeight(uint256 _w) external onlyOwner {
        require(_w >= MIN_OWNER_WEIGHT, "RM: w low");
        
        uint256 oldOwnerWeight = ownerWeight;
        totalWeight = totalWeight - oldOwnerWeight + _w;
        ownerWeight = _w;
        
        emit TotalWeightUpdated(totalWeight + oldOwnerWeight - _w, totalWeight, block.timestamp);
    }

    // 设置版税钱包
    function setRoyaltyWallet(address _newRoyaltyWallet) external onlyOwner nonZeroAddress(_newRoyaltyWallet) {
        address oldRoyaltyWallet = royaltyWallet;
        require(oldRoyaltyWallet != _newRoyaltyWallet, "RM: same royalty wallet");
        royaltyWallet = _newRoyaltyWallet;
        emit RoyaltyWalletUpdated(oldRoyaltyWallet, _newRoyaltyWallet, block.timestamp);
    }
    
    // 设置版税比例
    function setRoyaltyFee(uint256 _f) external onlyOwner {
        require(_f >= 0 && _f <= MAX_ROYALTY_FEE, "RM: fee invalid");
        royaltyFee = _f;
    }

    // 设置冷却时间
    function setOperationCooldown(uint256 _cooldown) external onlyOwner {
        operationCooldown = _cooldown;
    }

    // 管理函数：设置授权合约地址
    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    // 紧急暂停
    function emergencyPause() external onlyEmergencyOwner {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    // 紧急恢复
    function emergencyUnpause() external onlyEmergencyOwner {
        _unpause();
    }

    // 仅操作员修饰器
    modifier onlyOp() {
        bool isAuthorized = (msg.sender == operator) || (msg.sender == owner()) || 
                            (authorizedNFTContracts[msg.sender]) || (msg.sender == nftContract) || (msg.sender == authorizer);
        require(isAuthorized, "RM: not op");
        _;
    }

    // 计算用户权重
    function _calcUserWeight(address user) internal view returns (uint256) {
        if (user == owner()) return 0;
        return isWuFuHolder[user] ? WU_FU_WEIGHT : _getBasicCount(user) * WEIGHT_PER_CARD;
    }

    // 更新用户权重
    function _updateUserWeight(address user) internal {
        if (user == owner()) return;
        
        uint256 oldWeight = userWeight[user];
        uint256 newWeight = _calcUserWeight(user);
        
        if (oldWeight != newWeight) {
            uint256 oldTotal = totalWeight;
            totalWeight = totalWeight - oldWeight + newWeight;
            userWeight[user] = newWeight;
            
            emit UserWeightUpdated(user, oldWeight, newWeight, block.timestamp);
            emit TotalWeightUpdated(oldTotal, totalWeight, block.timestamp);
        }
    }

    // 获取用户基础卡片数量
    function _getBasicCount(address user) internal view returns (uint256) {
        uint256 cnt = 0;
        BlessingType[5] memory basic = [
            BlessingType.AiGuo, BlessingType.FuQiang, BlessingType.HeXie, BlessingType.YouShan, BlessingType.JingYe
        ];
        
        for (uint8 i = 0; i < 5; i++) {
            if (cardCount[user][basic[i]] > 0) {
                unchecked { cnt++; }
            }
        }
        return cnt;
    }

    // 检查用户是否有分红资格
    function _hasEligibility(address user) internal view returns (bool) {
        if (user == owner()) return true;
        
        return (
            cardCount[user][BlessingType.AiGuo] > 0 ||
            cardCount[user][BlessingType.FuQiang] > 0 ||
            cardCount[user][BlessingType.HeXie] > 0 ||
            cardCount[user][BlessingType.YouShan] > 0 ||
            cardCount[user][BlessingType.JingYe] > 0 ||
            isWuFuHolder[user]
        );
    }

    // 管理合格用户列表
    function _manageEligibleList(address user) internal {
        bool eligible = _hasEligibility(user);
        
        if (eligible && !inEligibleList[user]) {
            if (eligibleUserTail == address(0)) {
                eligibleUserHead = user;
                eligibleUserTail = user;
            } else {
                eligibleUserNext[eligibleUserTail] = user;
                eligibleUserPrev[user] = eligibleUserTail;
                eligibleUserTail = user;
            }
            inEligibleList[user] = true;
        } else if (!eligible && inEligibleList[user]) {
            address prev = eligibleUserPrev[user];
            address next = eligibleUserNext[user];
            
            if (prev != address(0)) eligibleUserNext[prev] = next;
            if (next != address(0)) eligibleUserPrev[next] = prev;
            if (eligibleUserHead == user) eligibleUserHead = next;
            if (eligibleUserTail == user) eligibleUserTail = prev;
            
            delete eligibleUserPrev[user];
            delete eligibleUserNext[user];
            inEligibleList[user] = false;
        }
    }

    // 内部更新卡片数量
    function updateCard(address user, BlessingType t, uint256 cnt) internal returns (bool) {
        cardCount[user][t] = cnt;
        _manageEligibleList(user);
        _updateUserWeight(user);
        emit CardUpdated(user, t, cnt, block.timestamp);
        return true;
    }

    // 外部接口：更新卡片数量（唯一入口）
    function updateCardExternal(address user, BlessingType t, uint256 cnt) external onlyOp whenNotPaused returns (bool) {
        return updateCard(user, t, cnt);
    }

    // 添加五福持有者
    function addWuFu(address user) external onlyOp whenNotPaused returns (bool) {
        if (!isWuFuHolder[user]) {
            isWuFuHolder[user] = true;
            if (holdersCount < type(uint256).max) {
                unchecked { holdersCount++ ; }
            } else {
                revert("Holders count overflow");
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
            emit WuFuAdded(user, block.timestamp);
        }
        return true;
    }

    // 移除五福持有者
    function removeWuFu(address user) external onlyOp whenNotPaused {
        if (isWuFuHolder[user]) {
            isWuFuHolder[user] = false;
            unchecked {
                holdersCount = holdersCount > 0 ? holdersCount - 1 : 0;
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
            emit WuFuRemoved(user, block.timestamp);
        }
    }

    // 重置五福持有者状态
    function resetWuFuHolder(address user) external onlyOp whenNotPaused returns (bool) {
        if (isWuFuHolder[user]) {
            isWuFuHolder[user] = false;
            unchecked {
                holdersCount = holdersCount > 0 ? holdersCount - 1 : 0;
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
            emit WuFuRemoved(user, block.timestamp);
        }
        return true;
    }

    // 检查用户是否拥有所有基础卡片
    function _hasAllBasic(address user) external view returns (bool) {
        uint256 cnt = 0;
        uint256 wanNeng = cardCount[user][BlessingType.WanNeng];
        
        BlessingType[5] memory basic = [
            BlessingType.AiGuo, BlessingType.FuQiang, BlessingType.HeXie, BlessingType.YouShan, BlessingType.JingYe
        ];
        
        for (uint8 i = 0; i < 5; i++) {
            if (cardCount[user][basic[i]] >= 1) {
                cnt++;
            } else if (wanNeng > 0) {
                cnt++;
                wanNeng--;
            }
        }
        
        return cnt == 5;
    }

    // 领取分红
    function claimDividend() external nonReentrant whenNotPaused rateLimited(msg.sig) {
        address user = msg.sender;
        require(_hasEligibility(user), "RM: no elig");
        
        uint256 totalW = totalWeight;
        require(totalW > 0 && dividendPool > 0, "RM: no div");

        uint256 userW = user == owner() ? ownerWeight : userWeight[user];
        require(userW > 0, "RM: no weight");

        require(dividendPool <= type(uint256).max / userW, "RM: overflow");
        uint256 totalDiv = dividendPool * userW;
        uint256 base = totalDiv / totalW;
        uint256 precRemain = totalDiv % totalW;
        
        uint256 acc = precisionAcc[user] + precRemain;
        uint256 precBonus = acc / totalW;
        uint256 finalAmt = base + precBonus;
        require(finalAmt > 0, "RM: no amt");
        require(finalAmt <= address(this).balance, "RM: insufficient balance");
        
        precisionAcc[user] = acc % totalW;
        unchecked {
            dividendPool -= finalAmt;
            claimedDividend[user] += finalAmt;
            totalDistributed += finalAmt;
        }
        emit DividendClaimed(user, finalAmt, precisionAcc[user], block.timestamp);

        (bool success, ) = payable(user).call{value: finalAmt}("");
        require(success, "RM: transfer fail");
    }

    // 接收ETH并添加到分红池
    receive() external payable {
        require(msg.value > 0, "RM: zero");
        unchecked { dividendPool += msg.value; }
        emit DividendDeposited(msg.value, msg.sender, block.timestamp);
    }

    // 提取额外资金
    function withdrawExtraFunds() external onlyOwner nonReentrant whenNotPaused {
        uint256 contractBalance = address(this).balance;
        uint256 extraFunds = contractBalance - dividendPool;
        require(extraFunds > 0, "RM: no extra funds to withdraw");
        require(contractBalance >= dividendPool, "RM: insufficient balance for dividend pool");
        
        emit ExtraFundsWithdrawn(owner(), extraFunds, block.timestamp);
        (bool success, ) = payable(owner()).call{value: extraFunds}("");
        require(success, "RM: extra funds transfer failed");
    }

    // 提取所有资金
    function withdrawAllFunds() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "RM: no balance");
        
        unchecked { 
            dividendPool = 0;
        }
        emit FullFundsWithdrawn(owner(), bal, block.timestamp);
        (bool success, ) = payable(owner()).call{value: bal}("");
        require(success, "RM: withdraw fail");
    }

    // 计算用户可领取的分红
    function calcUserDividend(address user) external view returns (uint256, uint256) {
        uint256 totalW = totalWeight;
        if (totalW == 0 || dividendPool == 0) return (0, 0);
        
        if (user == owner()) {
            if (ownerWeight == 0) return (0, 0);
            uint256 ownerTotalDiv = dividendPool * ownerWeight;
            return (ownerTotalDiv / totalW, ownerTotalDiv % totalW);
        }
        
        if (!_hasEligibility(user) || userWeight[user] == 0) return (0, 0);
        
        uint256 userW = userWeight[user];
        uint256 userTotalDiv = dividendPool * userW;
        uint256 base = userTotalDiv / totalW;
        uint256 acc = precisionAcc[user] + (userTotalDiv % totalW);
        
        return (base + (acc / totalW), acc % totalW);
    }

    // 刷新用户权重
    function refreshUserWeight(address user) external onlyOwner {
        _updateUserWeight(user);
    }

    // 刷新总权重
    function refreshTotalWeight() external onlyOwner {
        emit TotalWeightUpdated(totalWeight, totalWeight, block.timestamp);
    }
}