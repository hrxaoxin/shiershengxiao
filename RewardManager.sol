// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

enum ZodiacType {
    ShuiShu_1, ShuiNiu_1, ShuiHu_1, ShuiTu_1, ShuiLong_1, ShuiShe_1, ShuiMa_1, ShuiYang_1, ShuiHou_1, ShuiJi_1, ShuiGou_1, ShuiZhu_1,
    ShuiShu_0, ShuiNiu_0, ShuiHu_0, ShuiTu_0, ShuiLong_0, ShuiShe_0, ShuiMa_0, ShuiYang_0, ShuiHou_0, ShuiJi_0, ShuiGou_0, ShuiZhu_0,
    FengShu_1, FengNiu_1, FengHu_1, FengTu_1, FengLong_1, FengShe_1, FengMa_1, FengYang_1, FengHou_1, FengJi_1, FengGou_1, FengZhu_1,
    FengShu_0, FengNiu_0, FengHu_0, FengTu_0, FengLong_0, FengShe_0, FengMa_0, FengYang_0, FengHou_0, FengJi_0, FengGou_0, FengZhu_0,
    HuoShu_1, HuoNiu_1, HuoHu_1, HuoTu_1, HuoLong_1, HuoShe_1, HuoMa_1, HuoYang_1, HuoHou_1, HuoJi_1, HuoGou_1, HuoZhu_1,
    HuoShu_0, HuoNiu_0, HuoHu_0, HuoTu_0, HuoLong_0, HuoShe_0, HuoMa_0, HuoYang_0, HuoHou_0, HuoJi_0, HuoGou_0, HuoZhu_0,
    AnShu_1, AnNiu_1, AnHu_1, AnTu_1, AnLong_1, AnShe_1, AnMa_1, AnYang_1, AnHou_1, AnJi_1, AnGou_1, AnZhu_1,
    AnShu_0, AnNiu_0, AnHu_0, AnTu_0, AnLong_0, AnShe_0, AnMa_0, AnYang_0, AnHou_0, AnJi_0, AnGou_0, AnZhu_0,
    GuangShu_1, GuangNiu_1, GuangHu_1, GuangTu_1, GuangLong_1, GuangShe_1, GuangMa_1, GuangYang_1, GuangHou_1, GuangJi_1, GuangGou_1, GuangZhu_1,
    GuangShu_0, GuangNiu_0, GuangHu_0, GuangTu_0, GuangLong_0, GuangShe_0, GuangMa_0, GuangYang_0, GuangHou_0, GuangJi_0, GuangGou_0, GuangZhu_0
}

contract RewardManager is
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IERC2981
{
    uint256 public constant VERSION = 2;
    uint256 public constant WEIGHT_PER_CARD = 8;
    uint256 public constant MIN_OWNER_WEIGHT = 1000;
    uint256 public constant MAX_ROYALTY_FEE = 5000;

    uint256 public holdersCount;
    uint256 public dividendPool;
    uint256 public totalDistributed;
    address public operator;
    address public nftContract;
    address public authorizer;
    uint256 public ownerWeight;
    address public royaltyWallet;
    uint256 public royaltyFee = 500;

    mapping(address => bool) public authorizedNFTContracts;
    mapping(address => mapping(ZodiacType => uint256)) public cardCount;
    mapping(address => bool) public isHolder;
    mapping(address => uint256) public claimedDividend;
    mapping(address => uint256) public precisionAcc;
    mapping(address => uint256) public userWeight;
    uint256 public totalWeight;

    mapping(address => address) public eligibleUserPrev;
    mapping(address => address) public eligibleUserNext;
    address public eligibleUserHead;
    address public eligibleUserTail;
    mapping(address => bool) public inEligibleList;

    mapping(address => mapping(bytes4 => uint256)) public lastOperationTime;
    uint256 public operationCooldown = 1 seconds;

    event CardUpdated(address indexed user, ZodiacType t, uint256 c, uint256 ts);
    event DividendClaimed(address indexed user, uint256 amt, uint256 prec, uint256 ts);
    event DividendDeposited(uint256 amt, address indexed sender, uint256 ts);
    event UserWeightUpdated(address indexed user, uint256 oldWeight, uint256 newWeight, uint256 ts);
    event TotalWeightUpdated(uint256 oldTotal, uint256 newTotal, uint256 ts);
    event NFTContractAuthorized(address indexed nftContract, bool authorized, uint256 timestamp);
    event EmergencyPause(address indexed owner, uint256 timestamp);
    event NFTContractUpdated(address indexed oldNFTContract, address indexed newNFTContract, uint256 timestamp);
    event RoyaltyWalletUpdated(address indexed oldWallet, address indexed newWallet, uint256 timestamp);
    event ExtraFundsWithdrawn(address indexed owner, uint256 amount, uint256 timestamp);
    event FullFundsWithdrawn(address indexed owner, uint256 amount, uint256 timestamp);

    uint256[90] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

        eligibleUserHead = address(0);
        eligibleUserTail = address(0);

        authorizedNFTContracts[_nftContract] = true;

        emit TotalWeightUpdated(0, totalWeight, block.timestamp);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyEmergencyOwner
        nonZeroAddress(newImplementation)
    {}

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        return (royaltyWallet, (salePrice * royaltyFee) / 10000);
    }

    function setAuthorizedNFTContract(address nft, bool ok) external nonZeroAddress(nft) {
        require(msg.sender == owner() || msg.sender == operator || msg.sender == nftContract || msg.sender == authorizer || authorizedNFTContracts[msg.sender], "RewardManager: Unauthorized");
        authorizedNFTContracts[nft] = ok;
        emit NFTContractAuthorized(nft, ok, block.timestamp);
    }

    function setNFTContract(address _newNFTContract) external onlyOwner nonZeroAddress(_newNFTContract) {
        address oldNFTContract = nftContract;
        require(oldNFTContract != _newNFTContract, "RM: same nft contract");
        nftContract = _newNFTContract;
        emit NFTContractUpdated(oldNFTContract, _newNFTContract, block.timestamp);
    }

    function setOperator(address _op) external onlyOwner nonZeroAddress(_op) {
        operator = _op;
    }

    function setOwnerWeight(uint256 _w) external onlyOwner {
        require(_w >= MIN_OWNER_WEIGHT, "RM: w low");

        uint256 oldOwnerWeight = ownerWeight;
        totalWeight = totalWeight - oldOwnerWeight + _w;
        ownerWeight = _w;

        emit TotalWeightUpdated(totalWeight + oldOwnerWeight - _w, totalWeight, block.timestamp);
    }

    function setRoyaltyWallet(address _newRoyaltyWallet) external onlyOwner nonZeroAddress(_newRoyaltyWallet) {
        address oldRoyaltyWallet = royaltyWallet;
        require(oldRoyaltyWallet != _newRoyaltyWallet, "RM: same royalty wallet");
        royaltyWallet = _newRoyaltyWallet;
        emit RoyaltyWalletUpdated(oldRoyaltyWallet, _newRoyaltyWallet, block.timestamp);
    }

    function setRoyaltyFee(uint256 _f) external onlyOwner {
        require(_f >= 0 && _f <= MAX_ROYALTY_FEE, "RM: fee invalid");
        royaltyFee = _f;
    }

    function setOperationCooldown(uint256 _cooldown) external onlyOwner {
        operationCooldown = _cooldown;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    function emergencyPause() external onlyEmergencyOwner {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    function emergencyUnpause() external onlyEmergencyOwner {
        _unpause();
    }

    modifier onlyOp() {
        bool isAuthorized = (msg.sender == operator) || (msg.sender == owner()) ||
                            (authorizedNFTContracts[msg.sender]) || (msg.sender == nftContract) || (msg.sender == authorizer);
        require(isAuthorized, "RM: not op");
        _;
    }

    function _calcUserWeight(address user) internal view returns (uint256) {
        if (user == owner()) return 0;
        return _getTotalCardCount(user) * WEIGHT_PER_CARD;
    }

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

    function _getTotalCardCount(address user) internal view returns (uint256 cnt) {
        for (uint i = 0; i < 120; i++) {
            cnt += cardCount[user][ZodiacType(i)];
        }
    }

    function _hasEligibility(address user) internal view returns (bool) {
        if (user == owner()) return true;
        return _getTotalCardCount(user) > 0;
    }

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

    function updateCard(address user, ZodiacType t, uint256 cnt) internal returns (bool) {
        cardCount[user][t] = cnt;
        _manageEligibleList(user);
        _updateUserWeight(user);
        emit CardUpdated(user, t, cnt, block.timestamp);
        return true;
    }

    function updateCardExternal(address user, ZodiacType t, uint256 cnt) external onlyOp whenNotPaused returns (bool) {
        return updateCard(user, t, cnt);
    }

    function addHolder(address user) external onlyOp whenNotPaused returns (bool) {
        if (!isHolder[user]) {
            isHolder[user] = true;
            if (holdersCount < type(uint256).max) {
                unchecked { holdersCount++; }
            } else {
                revert("Holders count overflow");
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
        }
        return true;
    }

    function removeHolder(address user) external onlyOp whenNotPaused {
        if (isHolder[user]) {
            isHolder[user] = false;
            unchecked {
                holdersCount = holdersCount > 0 ? holdersCount - 1 : 0;
            }
            _manageEligibleList(user);
            _updateUserWeight(user);
        }
    }

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

    receive() external payable {
        require(msg.value > 0, "RM: zero");
        unchecked { dividendPool += msg.value; }
        emit DividendDeposited(msg.value, msg.sender, block.timestamp);
    }

    function withdrawExtraFunds() external onlyOwner nonReentrant whenNotPaused {
        uint256 contractBalance = address(this).balance;
        uint256 extraFunds = contractBalance - dividendPool;
        require(extraFunds > 0, "RM: no extra funds to withdraw");
        require(contractBalance >= dividendPool, "RM: insufficient balance for dividend pool");

        emit ExtraFundsWithdrawn(owner(), extraFunds, block.timestamp);
        (bool success, ) = payable(owner()).call{value: extraFunds}("");
        require(success, "RM: extra funds transfer failed");
    }

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

    function refreshUserWeight(address user) external onlyOwner {
        _updateUserWeight(user);
    }

    function refreshTotalWeight() external onlyOwner {
        emit TotalWeightUpdated(totalWeight, totalWeight, block.timestamp);
    }
}
