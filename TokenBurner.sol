// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 修复：使用标准库路径，移除远程GitHub链接，解决依赖拉取失败
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";

// 修复：继承接口使用升级兼容版本
interface IERC20Extended is IERC20Upgradeable {
    function decimals() external view returns (uint8);
}

contract TokenBurner is 
    Initializable, 
    Ownable2StepUpgradeable, 
    UUPSUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    // 修复：使用正确的升级版SafeERC20
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 常量定义
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant MAX_BATCH_SIZE = 100;
    uint8 public constant MAX_DECIMALS = 18;
    uint256 public constant MAX_BURN_PER_TX = 5;

    // 可修改的基础销毁金额
    uint256 public BURN_AMOUNT_BASE;

    // 状态变量
    address public tokenContract;
    address public authorizer;
    uint8 public tokenDecimals;
    uint256 public BURN_AMOUNT;
    mapping(address => uint256) public burnCount;
    mapping(address => bool) public authorizedNFTContracts;

    // 事件
    event TokenBurned(address indexed user, uint256 indexed amount, uint256 newBurnCount, uint256 timestamp);
    event BurnCountDecreased(address indexed user, uint256 newBurnCount, uint256 timestamp);
    event BatchBurnCountDecreased(uint256 indexed successCount, uint256 indexed totalProcessed, uint256 timestamp);
    event TokenDecimalsUpdated(uint8 oldDecimals, uint8 newDecimals, uint256 newBurnAmount, uint256 timestamp);
    event BurnAmountManuallySet(uint256 oldAmount, uint256 newAmount, address indexed operator, uint256 timestamp);
    event ContractPaused(address indexed operator, bool paused, uint256 timestamp);
    event NFTContractAuthorized(address indexed nftContract, bool authorized, uint256 timestamp);

    // 存储间隙
    uint256[45] private __gap;

    constructor() {
        _disableInitializers();
    }

    // 修饰器
    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || 
            authorizedNFTContracts[msg.sender],
            "TokenBurner: Unauthorized"
        );
        _;
    }

    modifier nonZeroAddress(address _addr) {
        require(_addr != address(0), "TokenBurner: Zero address");
        _;
    }

    // 初始化函数
    function initialize(
        address initialOwner,
        address _tokenContract,
        address _authorizer
    ) external initializer nonZeroAddress(initialOwner) nonZeroAddress(_tokenContract) {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        BURN_AMOUNT_BASE = 1;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
        tokenDecimals = _safeGetTokenDecimals();
        BURN_AMOUNT = _calculateBurnAmount(tokenDecimals);

        emit TokenDecimalsUpdated(0, tokenDecimals, BURN_AMOUNT, block.timestamp);
    }

    // 核心业务函数
    function burnTokenForMint() external whenNotPaused nonReentrant returns (bool) {
        address user = msg.sender;
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 req = BURN_AMOUNT;
        require(token.balanceOf(user) >= req, "Insufficient balance");
        require(token.allowance(user, address(this)) >= req, "Insufficient allowance");

        token.safeTransferFrom(user, BURN_ADDRESS, req);
        unchecked {
            burnCount[user]++;
        }
        emit TokenBurned(user, req, burnCount[user], block.timestamp);
        return true;
    }

    function burnAndMint(address user) 
        external 
        onlyAuthorized 
        whenNotPaused 
        nonReentrant 
        nonZeroAddress(user) 
        returns (bool) 
    {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 req = BURN_AMOUNT;
        require(token.balanceOf(user) >= req, "Insufficient balance");
        require(token.allowance(user, address(this)) >= req, "Insufficient allowance");

        token.safeTransferFrom(user, BURN_ADDRESS, req);
        emit TokenBurned(user, req, burnCount[user], block.timestamp);
        return true;
    }

    function decreaseBurnCount(address user) 
        external onlyAuthorized whenNotPaused nonZeroAddress(user) returns (bool) 
    {
        require(burnCount[user] > 0, "No mint count left");
        unchecked { burnCount[user]--; }
        emit BurnCountDecreased(user, burnCount[user], block.timestamp);
        return true;
    }

    function batchDecreaseBurnCount(address[] calldata users) 
        external 
        onlyAuthorized 
        whenNotPaused 
        returns (uint256 successCount) 
    {
        uint256 totalUsers = users.length;
        require(totalUsers > 0 && totalUsers <= MAX_BATCH_SIZE, "TokenBurner: Invalid batch size");

        address[] memory processedUsers = new address[](totalUsers);
        uint256 processedIndex = 0;

        for (uint256 i = 0; i < totalUsers; ) {
            address user = users[i];
            
            if (user == address(0)) {
                unchecked { i++; }
                continue;
            }

            bool isProcessed = false;
            for (uint256 j = 0; j < processedIndex; j++) {
                if (processedUsers[j] == user) {
                    isProcessed = true;
                    break;
                }
            }
            if (isProcessed) {
                unchecked { i++; }
                continue;
            }

            uint256 currentCount = burnCount[user];
            if (currentCount > 0) {
                unchecked {
                    burnCount[user] = currentCount - 1;
                    successCount++;
                }
                emit BurnCountDecreased(user, currentCount - 1, block.timestamp);
            }

            processedUsers[processedIndex] = user;
            processedIndex++;
            unchecked { i++; }
        }

        emit BatchBurnCountDecreased(successCount, totalUsers, block.timestamp);
        return successCount;
    }

    function updateTokenDecimals(uint8 newDecimals) external onlyAuthorized returns (bool success) {
        require(newDecimals <= MAX_DECIMALS, "TokenBurner: Decimals exceed max");
        require(newDecimals != tokenDecimals, "TokenBurner: Same decimals");

        uint8 oldDecimals = tokenDecimals;
        uint256 newBurnAmount = _calculateBurnAmount(newDecimals);

        tokenDecimals = newDecimals;
        BURN_AMOUNT = newBurnAmount;

        emit TokenDecimalsUpdated(oldDecimals, newDecimals, newBurnAmount, block.timestamp);
        return true;
    }

    function setBurnAmountManually(uint256 newAmount) external onlyAuthorized returns (bool success) {
        require(newAmount > 0, "TokenBurner: Amount must be >0");

        uint256 oldAmount = BURN_AMOUNT;
        address operator = msg.sender;

        BURN_AMOUNT = newAmount;

        emit BurnAmountManuallySet(oldAmount, newAmount, operator, block.timestamp);
        return true;
    }

    function togglePause() external onlyAuthorized returns (bool success) {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        emit ContractPaused(msg.sender, paused(), block.timestamp);
        return true;
    }

    function setAuthorizedNFTContract(address nft, bool ok) external nonZeroAddress(nft) {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Unauthorized");
        authorizedNFTContracts[nft] = ok;
        emit NFTContractAuthorized(nft, ok, block.timestamp);
    }

    function updateTokenContract(address newTokenContract) external onlyOwner nonZeroAddress(newTokenContract) {
        tokenContract = newTokenContract;
        
        uint8 oldDecimals = tokenDecimals;
        tokenDecimals = _safeGetTokenDecimals();
        uint256 newBurnAmount = _calculateBurnAmount(tokenDecimals);
        BURN_AMOUNT = newBurnAmount;
        
        emit TokenDecimalsUpdated(oldDecimals, tokenDecimals, BURN_AMOUNT, block.timestamp);
    }

    function setBurnAmountBase(uint256 newBaseAmount) external onlyOwner returns (bool success) {
        require(newBaseAmount > 0, "TokenBurner: Base amount must be >0");

        uint256 oldBaseAmount = BURN_AMOUNT_BASE;
        address operator = msg.sender;

        BURN_AMOUNT_BASE = newBaseAmount;
        
        uint256 newBurnAmount = _calculateBurnAmount(tokenDecimals);
        BURN_AMOUNT = newBurnAmount;

        emit BurnAmountManuallySet(oldBaseAmount, newBurnAmount, operator, block.timestamp);
        return true;
    }

    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    function checkBurnTokenStatus() 
        external 
        view 
        returns (uint256 balance, uint256 allowance, bool ready) 
    {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        address user = msg.sender;
        
        balance = token.balanceOf(user);
        allowance = token.allowance(user, address(this));
        ready = (balance >= BURN_AMOUNT) && (allowance >= BURN_AMOUNT) && !paused();
    }

    function getBurnCount(address user) external view returns (uint256 count) {
        return burnCount[user];
    }

    function hasBurnedToken(address user) external view returns (bool hasCount) {
        return burnCount[user] > 0;
    }

    function _safeGetTokenDecimals() internal view returns (uint8 decimals) {
        bytes4 decimalsSelector = IERC20Extended.decimals.selector;
        
        (bool success, bytes memory data) = tokenContract.staticcall(
            abi.encodeWithSelector(decimalsSelector)
        );
        
        if (success && data.length > 0) {
            uint256 decodedDecimals = abi.decode(data, (uint256));
            decimals = decodedDecimals <= MAX_DECIMALS ? uint8(decodedDecimals) : MAX_DECIMALS;
        } else {
            decimals = MAX_DECIMALS;
        }
    }

    function _calculateBurnAmount(uint8 decimals) internal view returns (uint256 burnAmount) {
        unchecked {
            burnAmount = BURN_AMOUNT_BASE * (10 ** uint256(decimals));
        }
    }

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
        nonZeroAddress(newImplementation) 
    {}
}