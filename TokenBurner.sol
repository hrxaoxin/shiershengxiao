// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract TokenBurner is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "TokenBurner: Paused");
        _;
    }

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
    uint256 public normalMintCost = 8888 * 10**18;
    uint256 public rareMintCost = 88888 * 10**18;

    address public tokenContract;
    address public authorizedNFTContract;
    address public nftMintContract;
    address public authorizer;

    event TokenBurned(address indexed user, uint256 amount, uint256 timestamp);
    event MintCostUpdated(uint256 oldNormalCost, uint256 newNormalCost, uint256 oldRareCost, uint256 newRareCost, uint256 timestamp);
    event NFTMinted(address indexed user, uint256 tokenId, uint256 zodiacType, bool isRare);

    modifier onlyAuthorized() {
        require(msg.sender == authorizedNFTContract || msg.sender == owner() || msg.sender == nftMintContract, "TokenBurner: Unauthorized");
        _;
    }

    modifier onlyAdminOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Not admin or authorizer");
        _;
    }

    function initialize(address _tokenContract, address _nftMint, address _authorizer) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        tokenContract = _tokenContract;
        nftMintContract = _nftMint;
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "TokenBurner: Invalid authorizer address");
        authorizer = a;
    }

    function setNFTContract(address _nftMint) external onlyAdminOrAuthorizer {
        require(_nftMint != address(0), "TokenBurner: Zero address");
        nftMintContract = _nftMint;
    }

    function setAuthorizedNFTContract(address _authorized) external onlyAdminOrAuthorizer {
        require(_authorized != address(0), "TokenBurner: Zero address");
        authorizedNFTContract = _authorized;
    }

    function setNormalMintCost(uint256 cost) external onlyOwner {
        require(cost > 0, "TokenBurner: cost must be > 0");
        uint256 oldNormal = normalMintCost;
        normalMintCost = cost;
        emit MintCostUpdated(oldNormal, cost, rareMintCost, rareMintCost, block.timestamp);
    }

    function setRareMintCost(uint256 cost) external onlyOwner {
        require(cost > 0, "TokenBurner: cost must be > 0");
        uint256 oldRare = rareMintCost;
        rareMintCost = cost;
        emit MintCostUpdated(normalMintCost, normalMintCost, oldRare, cost, block.timestamp);
    }

    function setTokenContract(address _tokenContract) external onlyAdminOrAuthorizer {
        require(_tokenContract != address(0), "TokenBurner: Zero address");
        tokenContract = _tokenContract;
    }

    function normalMintTenCost() external view returns (uint256) {
        return normalMintCost * 10;
    }

    function rareMintTenCost() external view returns (uint256) {
        return rareMintCost * 10;
    }

    function targetedMintCost() external view returns (uint256 normalPart, uint256 rarePart) {
        normalPart = normalMintCost * 6 * 10;
        rarePart = rareMintCost * 4 * 10;
    }

    function burnAndMint(address user, bool isRare) external onlyAuthorized nonReentrant whenNotPaused returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        require(nftMintContract != address(0), "TokenBurner: nftMintContract not set");
        require(user != address(0), "TokenBurner: Zero user address");

        IERC20 token = IERC20(tokenContract);
        uint256 cost = isRare ? rareMintCost : normalMintCost;
        require(token.balanceOf(user) >= cost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= cost, "TokenBurner: Insufficient allowance");
        require(token.transferFrom(user, BLACK_HOLE, cost), "TokenBurner: Token transfer failed");

        emit TokenBurned(user, cost, block.timestamp);

        INFTMint nftMint = INFTMint(nftMintContract);
        uint256 tokenId;
        if (isRare) {
            tokenId = nftMint.mintRare(user);
        } else {
            tokenId = nftMint.mintNormal(user);
        }
        require(tokenId > 0, "TokenBurner: NFT mint failed");

        uint256 zodiacType = nftMint.tokenType(tokenId);
        emit NFTMinted(user, tokenId, zodiacType, isRare);

        return true;
    }

    function burnAndMintTen(address user, bool isRare) external onlyAuthorized nonReentrant whenNotPaused returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        require(nftMintContract != address(0), "TokenBurner: nftMintContract not set");
        require(user != address(0), "TokenBurner: Zero user address");

        IERC20 token = IERC20(tokenContract);
        uint256 cost = isRare ? rareMintCost * 10 : normalMintCost * 10;
        require(token.balanceOf(user) >= cost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= cost, "TokenBurner: Insufficient allowance");
        require(token.transferFrom(user, BLACK_HOLE, cost), "TokenBurner: Token transfer failed");

        emit TokenBurned(user, cost, block.timestamp);

        INFTMint nftMint = INFTMint(nftMintContract);
        if (isRare) {
            nftMint.mintRareTen(user);
        } else {
            nftMint.mintNormalTen(user);
        }

        return true;
    }

    function burnAndMintTargeted(address user, uint8 zodiac) external onlyAuthorized nonReentrant whenNotPaused returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        require(nftMintContract != address(0), "TokenBurner: nftMintContract not set");
        require(user != address(0), "TokenBurner: Zero user address");
        require(zodiac < 12, "TokenBurner: Invalid zodiac type");

        IERC20 token = IERC20(tokenContract);
        uint256 normalPart = normalMintCost * 6 * 10;
        uint256 rarePart = rareMintCost * 4 * 10;
        uint256 totalCost = normalPart + rarePart;
        require(token.balanceOf(user) >= totalCost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= totalCost, "TokenBurner: Insufficient allowance");
        require(token.transferFrom(user, BLACK_HOLE, totalCost), "TokenBurner: Token transfer failed");

        emit TokenBurned(user, totalCost, block.timestamp);

        INFTMint nftMint = INFTMint(nftMintContract);
        nftMint.mintTargeted(user, zodiac);

        return true;
    }

    /**
     * @dev 获取铸造费用
     * @param isRare 是否稀有
     * @param count 数量
     * @return 总费用
     */
    function getMintCost(bool isRare, uint256 count) external view returns (uint256) {
        require(count > 0, "TokenBurner: Invalid count");
        uint256 singleCost = isRare ? rareMintCost : normalMintCost;
        return singleCost * count;
    }

    /**
     * @dev 获取定向铸造费用
     * @return 普通部分费用
     * @return 稀有部分费用
     * @return 总费用
     */
    function getTargetedMintCost() external view returns (uint256, uint256, uint256) {
        uint256 normalPart = normalMintCost * 6 * 10;
        uint256 rarePart = rareMintCost * 4 * 10;
        return (normalPart, rarePart, normalPart + rarePart);
    }

    /**
     * @dev 获取所有费用配置
     * @return 普通铸造费用
     * @return 稀有铸造费用
     */
    function getAllCosts() external view returns (uint256, uint256) {
        return (normalMintCost, rareMintCost);
    }
}
