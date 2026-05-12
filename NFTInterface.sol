// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";

interface ITokenBurner {
    function burnTokenForMint() external returns (bool);
    function burnTokenForRareMint() external returns (bool);
    function burnAndMint(address user, bool isRare) external returns (bool);
    function normalMintCost() external view returns (uint256);
    function rareMintCost() external view returns (uint256);
    function setAuthorizedNFTContract(address nftContract) external;
    function setTokenContract(address tokenContract) external;
}

interface IToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracle {
    function getTokenPriceInUSD() external view returns (uint256);
    function getPriceTimestamp() external view returns (uint256);
}

interface IPancakeSwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IBEP20 {
    function decimals() external view returns (uint8);
}

interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

interface INFTMint {
    function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function mintNormal(address to) external returns (uint256);
    function mintRare(address to) external returns (uint256);
    function mintCustom(address to, NFTDataTypes.ZodiacType zodiacType) external returns (uint256);
    function mintBreedResult(address to, NFTDataTypes.ZodiacType zodiacType) external returns (uint256);
    function upgradeWithNFT(uint256 tokenId) external returns (uint8);
    function upgradeWithToken(uint256 tokenId) external returns (uint8);
    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function getApproved(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function setAddresses(address tb, address rm) external;
    function setMetadataContract(address a) external;
    function setTokenContract(address a) external;
    function setBreedingContract(address a) external;
    function calcUserWeight(address user) external view returns (uint256);
}

interface INFTMintWeight {
    function calcUserWeight(address user) external view returns (uint256);
}

interface IRewardManager {
    function royaltyWallet() external view returns (address);
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256);
    function claimDividend() external;
    function cardCount(address user, NFTDataTypes.ZodiacType zodiacType) external view returns (uint256);
    function updateCardExternal(address user, NFTDataTypes.ZodiacType zodiacType, uint256 count) external returns (bool);
    function setAuthorizedNFTContract(address nft, bool ok) external;
    function setNFTContract(address _newNFTContract) external;
    function setNFTDataContract(address _nftDataContract) external;
}

interface INFTDataInterface {
    function getNFTInfo(uint256 tokenId) external view returns (NFTDataTypes.NFTInfo memory);
    function setNFTInfo(uint256 tokenId, NFTDataTypes.NFTInfo memory info) external;
    function clearNFTInfo(uint256 tokenId) external;
    function getElementName(NFTDataTypes.ElementType element) external view returns (string memory);
    function getZodiacName(NFTDataTypes.BaseZodiac zodiac) external view returns (string memory);
    function getGenderName(NFTDataTypes.GenderType gender) external view returns (string memory);
    function getFullTypeName(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    function collName() external pure returns (string memory);
    function collDesc() external pure returns (string memory);
    function collImage() external pure returns (string memory);
    function sellerFeeBasisPoints() external pure returns (uint256);
    function getCardName(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    function getCardDesc(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);
    function getCardImage(NFTDataTypes.ZodiacType zodiacType) external view returns (string memory);

    function tokenType(uint256 tokenId) external view returns (NFTDataTypes.ZodiacType);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function userTokens(address user, NFTDataTypes.ZodiacType type_) external view returns (uint256[] memory);
    function userAllTokens(address user) external view returns (uint256[] memory);
    function userWeightCache(address user) external view returns (uint256);

    function setTokenType(uint256 tokenId, NFTDataTypes.ZodiacType type_) external;
    function setTokenLevel(uint256 tokenId, uint8 level) external;
    function addUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external;
    function removeUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external;
    function updateUserWeightCache(address user, uint256 weight) external;
    /** @dev 统一的权重更新函数（计算并更新用户权重） */
    function updateUserWeight(address user, uint8 level, bool add) external;
    function getUserTokenCount(address user, NFTDataTypes.ZodiacType type_) external view returns (uint256);
    function getUserTotalTokenCount(address user) external view returns (uint256);

    function initialize(address initialOwner) external;
    function setAuthorizedNFTContract(address nftContract) external;
    function hasEligibility(address user) external view returns (bool);
    function getUserTokenTypes(address user) external view returns (NFTDataTypes.ZodiacType[] memory);
}

interface INFTTrading {
    function setNFTContract(address newNFTContract) external;
    function setRewardManager(address newRewardManager) external;
}

interface IBreeding {
    function setNFTContract(address nftContract) external;
    function startSelfBreeding(uint256 tokenId1, uint256 tokenId2) external;
    function listForBreeding(uint256 tokenId) external;
    function joinBreeding(uint256 orderId, uint256 tokenId) external;
    function completeSelfBreeding(uint256 orderId) external;
    function completeMarketBreeding(uint256 orderId) external;
    function cancelBreedingListing(uint256 orderId) external;
    function getMarketBreedingOrders() external view returns (uint256[] memory);
    function getUserBreedingOrders(address user) external view returns (uint256[] memory);
    function breedingOrders(uint256 orderId) external view returns (address, address, uint256, uint256, uint256, bool, bool);
}

interface IStaking {
    function setNFTContract(address nftContract) external;
    function setTokenContract(address tokenContract) external;
}

interface INFTUpdate {
    function upgradeWithNFT(uint256 tokenId) external returns (uint8);
    function upgradeWithToken(uint256 tokenId) external returns (uint8);
    function upgradeWithUSDValue(uint256 tokenId) external returns (uint8);
    function getTokenPriceFromPancakeSwap() external view returns (uint256);
    function setNFTContract(address a) external;
    function setMetadataContract(address a) external;
    function setTokenContract(address a) external;
    function setPancakeSwapPair(address pair) external;
    function setPriceExpirySeconds(uint256 seconds_) external;
    function setPriceDeviationThreshold(uint256 threshold) external;
    function resetPriceCache() external;
    function setLevel1UpgradeCost(uint256 cost) external;
    function setLevel2UpgradeCost(uint256 cost) external;
    function setLevel3UpgradeCost(uint256 cost) external;
    function setLevel4UpgradeCost(uint256 cost) external;
}