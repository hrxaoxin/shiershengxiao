// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";

interface INFTMint {
    function mintNormal(address to) external returns (uint256);
    function mintRare(address to) external returns (uint256);
    function mintNormalTen(address to) external returns (uint256[] memory);
    function mintRareTen(address to) external returns (uint256[] memory);
    function mintTargeted(address to, uint8 baseZodiac) external returns (uint256[] memory);
}

contract TokenBurner is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    uint256 public normalMintCost = 8888 * 10**18;
    uint256 public rareMintCost = 88888 * 10**18;

    address public tokenContract;
    address public authorizedNFTContract;
    address public nftMintContract;

    event TokenBurned(address indexed user, uint256 amount, uint256 timestamp);
    event MintCostUpdated(uint256 oldNormalCost, uint256 newNormalCost, uint256 oldRareCost, uint256 newRareCost, uint256 timestamp);
    event NFTMinted(address indexed user, uint256 tokenId, uint256 zodiacType, bool isRare);

    modifier onlyAuthorized() {
        require(msg.sender == authorizedNFTContract || msg.sender == owner() || msg.sender == nftMintContract, "TokenBurner: Unauthorized");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenContract, address _nftMint) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        tokenContract = _tokenContract;
        nftMintContract = _nftMint;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setNFTContract(address _nftMint) external onlyOwner {
        require(_nftMint != address(0), "TokenBurner: Zero address");
        nftMintContract = _nftMint;
    }

    function setAuthorizedNFTContract(address _authorized) external onlyOwner {
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

    function setTokenContract(address _tokenContract) external onlyOwner {
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
        normalPart = normalMintCost * 6;
        rarePart = rareMintCost * 4;
    }

    function burnAndMint(address user, bool isRare) external returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        require(nftMintContract != address(0), "TokenBurner: nftMintContract not set");
        require(user != address(0), "TokenBurner: Zero user address");
        require(msg.sender == user || msg.sender == owner(), "TokenBurner: Caller must be user or owner");

        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 cost = isRare ? rareMintCost : normalMintCost;
        require(token.balanceOf(user) >= cost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= cost, "TokenBurner: Insufficient allowance");
        require(token.transferFrom(user, BLACK_HOLE, cost), "TokenBurner: Token transfer failed");

        emit TokenBurned(user, cost, block.timestamp);

        INFTMint nftMint = INFTMint(nftMintContract);
        if (isRare) {
            uint256 tokenId = nftMint.mintRare(user);
            emit NFTMinted(user, tokenId, 0, true);
        } else {
            uint256 tokenId = nftMint.mintNormal(user);
            emit NFTMinted(user, tokenId, 0, false);
        }

        return true;
    }

    function burnAndMintTen(address user, bool isRare) external returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        require(nftMintContract != address(0), "TokenBurner: nftMintContract not set");
        require(user != address(0), "TokenBurner: Zero user address");
        require(msg.sender == user || msg.sender == owner(), "TokenBurner: Caller must be user or owner");

        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
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

    function burnAndMintTargeted(address user, uint8 zodiac) external returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        require(nftMintContract != address(0), "TokenBurner: nftMintContract not set");
        require(user != address(0), "TokenBurner: Zero user address");
        require(msg.sender == user || msg.sender == owner(), "TokenBurner: Caller must be user or owner");

        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 normalPart = normalMintCost * 6;
        uint256 rarePart = rareMintCost * 4;
        uint256 totalCost = normalPart + rarePart;
        require(token.balanceOf(user) >= totalCost, "TokenBurner: Insufficient balance");
        require(token.allowance(user, address(this)) >= totalCost, "TokenBurner: Insufficient allowance");
        require(token.transferFrom(user, BLACK_HOLE, totalCost), "TokenBurner: Token transfer failed");

        emit TokenBurned(user, totalCost, block.timestamp);

        INFTMint nftMint = INFTMint(nftMintContract);
        nftMint.mintTargeted(user, zodiac);

        return true;
    }
}
