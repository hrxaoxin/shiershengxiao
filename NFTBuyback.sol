// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract NFTBuyback is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    constructor() {
        _disableInitializers();
    }

    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "NFTBuyback: Paused");
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

    address public nftContract;
    address public tokenContract;
    address public tokenBurnerContract;
    address public nftUpdateContract;
    address public authorizer;

    uint256 public maxBuybackMultiplier = 110;
    uint256 public fixedBuybackPrice;
    bool public fixedBuybackOpen = false;

    mapping(uint256 => uint256) public nftMintTime;

    function maxBonusPercent() public view returns (uint256) {
        return maxBuybackMultiplier - 100;
    }

    function autoBuybackOpen() public view returns (bool) {
        return fixedBuybackOpen;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTBuyback: Not authorized");
        _;
    }

    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "NFTBuyback: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        require(a != address(0), "NFTBuyback: Invalid authorizer address");
        authorizer = a;
    }

    function setNFTContract(address _nftContract) external onlyAuthorized {
        require(_nftContract != address(0), "NFTBuyback: Invalid NFT contract address");
        nftContract = _nftContract;
    }

    function setTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "NFTBuyback: Invalid token contract address");
        tokenContract = _tokenContract;
    }

    function setTokenBurnerContract(address _tokenBurner) external onlyAuthorized {
        require(_tokenBurner != address(0), "NFTBuyback: Invalid token burner address");
        tokenBurnerContract = _tokenBurner;
    }

    function setNFTUpdateContract(address _nftUpdate) external onlyAuthorized {
        require(_nftUpdate != address(0), "NFTBuyback: Invalid NFT update address");
        nftUpdateContract = _nftUpdate;
    }

    function setMaxBuybackMultiplier(uint256 _multiplier) external onlyOwner {
        require(_multiplier >= 100, "NFTBuyback: Multiplier must be at least 100");
        require(_multiplier <= 200, "NFTBuyback: Multiplier cannot exceed 200");
        maxBuybackMultiplier = _multiplier;
        emit MaxBuybackMultiplierUpdated(_multiplier);
    }

    function setFixedBuybackPrice(uint256 _price) external onlyOwner {
        fixedBuybackPrice = _price;
        emit FixedBuybackPriceUpdated(_price);
    }

    function setFixedBuybackOpen(bool _open) external onlyOwner {
        fixedBuybackOpen = _open;
        emit FixedBuybackOpenUpdated(_open);
    }

    function getNFTMintCost(uint8 level, bool isRare) public view returns (uint256) {
        require(tokenBurnerContract != address(0), "NFTBuyback: Token burner not set");
        
        (uint256 normalCost, uint256 rareCost) = ITokenBurner(tokenBurnerContract).getAllCosts();
        uint256 baseCost = isRare ? rareCost : normalCost;

        if (level == 1) {
            return baseCost;
        }

        (uint256 level1Cost, uint256 level2Cost, uint256 level3Cost, uint256 level4Cost) = 
            INFTUpdate(nftUpdateContract).getAllLevelUpgradeCosts();

        uint256 totalCost = baseCost;
        if (level >= 2) totalCost += level1Cost;
        if (level >= 3) totalCost += level2Cost;
        if (level >= 4) totalCost += level3Cost;
        if (level >= 5) totalCost += level4Cost;

        return totalCost;
    }

    function getBuybackDiscount(uint8 level) public pure returns (uint256) {
        if (level == 1) return 10;
        if (level == 2) return 15;
        if (level == 3) return 20;
        if (level == 4) return 25;
        if (level == 5) return 30;
        revert("NFTBuyback: Invalid level");
    }

    function getDaysToBreakEven(uint8 level) public pure returns (uint256) {
        if (level == 1) return 90;
        if (level == 2) return 85;
        if (level == 3) return 80;
        if (level == 4) return 75;
        if (level == 5) return 70;
        revert("NFTBuyback: Invalid level");
    }

    function calculateGrowthPrice(uint256 tokenId) public view returns (uint256) {
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        uint8 level = nft.tokenLevel(tokenId);
        bool isRare = nft.isRare(tokenId);

        uint256 totalCost = getNFTMintCost(level, isRare);
        uint256 discount = getBuybackDiscount(level);
        uint256 basePrice = (totalCost * discount) / 100;

        if (nftMintTime[tokenId] == 0) {
            return basePrice;
        }

        uint256 holdingDays = (block.timestamp - nftMintTime[tokenId]) / 1 days;
        uint256 daysToBreakEven = getDaysToBreakEven(level);
        uint256 maxBonusDays = ((maxBuybackMultiplier - 100) * daysToBreakEven) / (100 - discount);

        uint256 bonusDays = holdingDays > maxBonusDays ? maxBonusDays : holdingDays;
        uint256 bonus = (basePrice * bonusDays) / daysToBreakEven;

        uint256 finalPrice = basePrice + bonus;
        uint256 maxPrice = (totalCost * maxBuybackMultiplier) / 100;

        return finalPrice > maxPrice ? maxPrice : finalPrice;
    }

    function calculateBuybackPrice(uint256 tokenId) public view returns (uint256, uint256, uint256, uint256) {
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        
        INFTMint nft = INFTMint(nftContract);
        uint8 level = nft.tokenLevel(tokenId);
        bool isRare = nft.isRare(tokenId);

        uint256 totalCost = getNFTMintCost(level, isRare);
        uint256 discount = getBuybackDiscount(level);
        uint256 basePrice = (totalCost * discount) / 100;

        uint256 bonusPercent = 0;
        uint256 finalPrice = basePrice;
        uint256 daysToMax = getDaysToBreakEven(level);

        if (nftMintTime[tokenId] != 0) {
            uint256 holdingDays = (block.timestamp - nftMintTime[tokenId]) / 1 days;
            uint256 daysToBreakEven = getDaysToBreakEven(level);
            uint256 maxBonusDays = ((maxBuybackMultiplier - 100) * daysToBreakEven) / (100 - discount);

            uint256 bonusDays = holdingDays > maxBonusDays ? maxBonusDays : holdingDays;
            bonusPercent = (bonusDays * (100 - discount)) / daysToBreakEven;
            if (bonusPercent > (maxBuybackMultiplier - 100)) {
                bonusPercent = maxBuybackMultiplier - 100;
            }

            uint256 bonus = (basePrice * bonusDays) / daysToBreakEven;
            finalPrice = basePrice + bonus;
            uint256 maxPrice = (totalCost * maxBuybackMultiplier) / 100;

            if (finalPrice > maxPrice) {
                finalPrice = maxPrice;
            }
        }

        return (basePrice, bonusPercent, finalPrice, daysToMax);
    }

    function sellWithGrowthPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");

        uint256 buybackPrice = calculateGrowthPrice(tokenId);
        
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= buybackPrice, "NFTBuyback: Insufficient contract balance");

        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        token.safeTransfer(msg.sender, buybackPrice);

        emit NFTBurnedForBuyback(tokenId, msg.sender, buybackPrice, "growth");
    }

    function sellWithFixedPrice(uint256 tokenId) external whenNotPaused nonReentrant {
        require(fixedBuybackOpen, "NFTBuyback: Fixed buyback not open");
        require(nftContract != address(0), "NFTBuyback: NFT contract not set");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");

        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "NFTBuyback: Not owner");
        require(fixedBuybackPrice > 0, "NFTBuyback: Fixed price not set");

        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= fixedBuybackPrice, "NFTBuyback: Insufficient contract balance");

        nft.safeTransferFrom(msg.sender, BLACK_HOLE, tokenId);
        
        token.safeTransfer(msg.sender, fixedBuybackPrice);

        emit NFTBurnedForBuyback(tokenId, msg.sender, fixedBuybackPrice, "fixed");
    }

    function recordMintTime(uint256 tokenId, uint256 mintTime) external onlyAuthorized {
        nftMintTime[tokenId] = mintTime;
    }

    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "NFTBuyback: Amount must be > 0");
        require(tokenContract != address(0), "NFTBuyback: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "NFTBuyback: Insufficient balance");
        token.safeTransfer(owner(), amount);
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    event MaxBuybackMultiplierUpdated(uint256 newMultiplier);
    event FixedBuybackPriceUpdated(uint256 newPrice);
    event FixedBuybackOpenUpdated(bool open);
    event NFTBurnedForBuyback(uint256 indexed tokenId, address indexed seller, uint256 price, string mode);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    receive() external payable {}
    fallback() external payable {}
}

interface ITokenBurner {
    function getAllCosts() external view returns (uint256, uint256);
}

interface INFTUpdate {
    function getAllLevelUpgradeCosts() external view returns (uint256, uint256, uint256, uint256);
}