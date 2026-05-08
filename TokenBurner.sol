// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TokenBurner
 * @dev 代币销毁合约，统一管理NFT铸造所需的代币销毁
 * 支持修改销毁费用，仅限合约拥有者操作
 * 基于OpenZeppelin可升级合约实现
 */
import "./NFTData.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TokenBurner
 * @dev 代币销毁合约
 */
contract TokenBurner is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /** @dev 黑洞地址，用于销毁代币 */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    /** @dev 普通铸造费用（默认8888代币） */
    uint256 public normalMintCost = 8888;
    /** @dev 稀有铸造费用（默认88888代币） */
    uint256 public rareMintCost = 88888;

    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 代币销毁事件 */
    event TokenBurned(address indexed user, uint256 amount, uint256 timestamp);
    /** @dev 费用更新事件 */
    event MintCostUpdated(uint256 oldNormalCost, uint256 newNormalCost, uint256 oldRareCost, uint256 newRareCost, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _tokenContract 代币合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        tokenContract = _tokenContract;
        authorizer = _authorizer;
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 销毁普通铸造费用的代币
     * 用户需要先授权代币给合约，然后调用此函数销毁代币
     * @return bool 是否成功
     */
    function burnTokenForMint() external returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transferFrom(msg.sender, BLACK_HOLE, normalMintCost), "TokenBurner: Token transfer failed");
        
        emit TokenBurned(msg.sender, normalMintCost, block.timestamp);
        return true;
    }

    /**
     * @dev 销毁稀有铸造费用的代币
     * 用户需要先授权代币给合约，然后调用此函数销毁代币
     * @return bool 是否成功
     */
    function burnTokenForRareMint() external returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transferFrom(msg.sender, BLACK_HOLE, rareMintCost), "TokenBurner: Token transfer failed");
        
        emit TokenBurned(msg.sender, rareMintCost, block.timestamp);
        return true;
    }

    /**
     * @dev 销毁代币用于铸造（由NFT合约调用）
     * @param user 用户地址
     * @param isRare 是否稀有铸造
     * @return bool 是否成功
     */
    function burnAndMint(address user, bool isRare) external returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 cost = isRare ? rareMintCost : normalMintCost;
        require(token.transferFrom(user, BLACK_HOLE, cost), "TokenBurner: Token transfer failed");
        
        emit TokenBurned(user, cost, block.timestamp);
        return true;
    }

    /**
     * @dev 设置普通铸造费用（仅限合约拥有者）
     * @param cost 新的铸造费用（代币数量）
     */
    function setNormalMintCost(uint256 cost) external onlyOwner {
        require(cost > 0, "TokenBurner: cost must be > 0");
        uint256 oldNormal = normalMintCost;
        uint256 oldRare = rareMintCost;
        normalMintCost = cost;
        emit MintCostUpdated(oldNormal, cost, oldRare, rareMintCost, block.timestamp);
    }

    /**
     * @dev 设置稀有铸造费用（仅限合约拥有者）
     * @param cost 新的铸造费用（代币数量）
     */
    function setRareMintCost(uint256 cost) external onlyOwner {
        require(cost > 0, "TokenBurner: cost must be > 0");
        uint256 oldNormal = normalMintCost;
        uint256 oldRare = rareMintCost;
        rareMintCost = cost;
        emit MintCostUpdated(oldNormal, normalMintCost, oldRare, cost, block.timestamp);
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Unauthorized");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }
}