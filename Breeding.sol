// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

interface INFTMint {
    function mint(address to, uint256 zodiacType) external returns (uint256);
    function tokenType(uint256 tokenId) external view returns (uint256);
    function tokenLevel(uint256 tokenId) external view returns (uint8);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isRare(uint256 tokenId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract Breeding is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    uint256 public selfBreedingCooldown = 12 hours;
    uint256 public marketBreedingCooldown = 24 hours;
    uint256 public selfBreedingFee;
    uint256 public marketBreedingFee;
    address public nftMintContract;
    address public authorizer;
    address public tokenContract;
    
    bool public paused;
    string public pauseReason;

    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    function setAuthorizer(address a) external onlyOwner { authorizer = a; }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Not authorized");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
        bool rewardsClaimed;
    }

    mapping(uint256 => BreedingPair) public breedingPairs;
    uint256 public breedingPairCount;
    mapping(uint256 => uint256) public breedingCooldowns;

    event BreedingPairCreated(uint256 indexed pairId, uint256 fatherId, uint256 motherId, uint256 breedingType);
    event BreedingCompleted(uint256 indexed pairId, uint256 childId, uint256 zodiacType);
    event BreedingCancelled(uint256 indexed pairId);
    event CooldownUpdated(uint256 selfCooldown, uint256 marketCooldown);
    event BreedingRewardsClaimed(uint256 indexed pairId, uint256 motherReward, uint256 fatherReward, uint256 coOwnerReward);
    event Paused(address account, string reason);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!paused, "Breeding: Paused");
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

    function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
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

        if (selfBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), selfBreedingFee), "Breeding: Fee transfer failed");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: msg.sender, femaleOwner: msg.sender,
            maleCoOwnerId: coOwnerId, femaleCoOwnerId: coOwnerId, startTime: block.timestamp,
            breedingType: 0, status: 0, childId: 0, rewardsClaimed: false
        });

        breedingCooldowns[fatherId] = block.timestamp + selfBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + selfBreedingCooldown;
        emit BreedingPairCreated(pairId, fatherId, motherId, 0);
        return pairId;
    }

    function createMarketBreedingPair(
        uint256 fatherId, uint256 motherId, address maleOwner, address femaleOwner,
        uint256 maleCoOwnerId, uint256 femaleCoOwnerId
    ) external whenNotPaused onlyAuthorized returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(maleOwner != femaleOwner, "Breeding: Same owner for market breeding");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        INFTMint nft = INFTMint(nftMintContract);

        require(nft.ownerOf(fatherId) == maleOwner, "Breeding: Father ownership mismatch");
        require(nft.ownerOf(motherId) == femaleOwner, "Breeding: Mother ownership mismatch");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "Breeding: Different zodiac");
        require((fatherType % 2) != (motherType % 2), "Breeding: Same gender");

        require(breedingCooldowns[fatherId] <= block.timestamp, "Breeding: Father in cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "Breeding: Mother in cooldown");

        if (marketBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), marketBreedingFee), "Breeding: Fee transfer failed");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: maleCoOwnerId, femaleCoOwnerId: femaleCoOwnerId, startTime: block.timestamp,
            breedingType: 1, status: 0, childId: 0, rewardsClaimed: false
        });

        breedingCooldowns[fatherId] = block.timestamp + marketBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + marketBreedingCooldown;
        emit BreedingPairCreated(pairId, fatherId, motherId, 1);
        return pairId;
    }

    function createMarketBreedingPairPublic(
        uint256 fatherId, uint256 motherId
    ) external whenNotPaused returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        INFTMint nft = INFTMint(nftMintContract);

        address maleOwner = nft.ownerOf(fatherId);
        address femaleOwner = nft.ownerOf(motherId);
        
        require(maleOwner != femaleOwner, "Breeding: Must use NFTs from different owners");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");

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
            breedingType: 1, status: 0, childId: 0, rewardsClaimed: false
        });

        breedingCooldowns[fatherId] = block.timestamp + marketBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + marketBreedingCooldown;
        emit BreedingPairCreated(pairId, fatherId, motherId, 1);
        return pairId;
    }

    function completeBreeding(uint256 pairId) external returns (uint256) {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 0, "Breeding: Pair not active");
        require(pair.childId == 0, "Breeding: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "Breeding: Not pair owner");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");

        uint256 cooldown = pair.breedingType == 0 ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "Breeding: Cooldown not ended");

        uint256 childId = _generateChild(pair.fatherId, pair.motherId, pair.maleOwner, pair.femaleOwner);
        pair.childId = childId;
        pair.status = 1;
        emit BreedingCompleted(pairId, childId, _getChildZodiacType(pair.fatherId, pair.motherId));
        return childId;
    }

    function cancelBreeding(uint256 pairId) external {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 0, "Breeding: Pair not active");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "Breeding: Not pair owner");

        uint256 feeToRefund = pair.breedingType == 0 ? selfBreedingFee : marketBreedingFee;
        if (feeToRefund > 0 && tokenContract != address(0)) {
            IERC20 token = IERC20(tokenContract);
            if (token.balanceOf(address(this)) >= feeToRefund) {
                require(token.transfer(msg.sender, feeToRefund), "Breeding: Fee refund failed");
            }
        }

        pair.status = 2;
        delete breedingCooldowns[pair.fatherId];
        delete breedingCooldowns[pair.motherId];
        emit BreedingCancelled(pairId);
    }

    function getBreedingInfo(uint256 pairId) external view returns (uint256 fatherId, uint256 motherId, address maleOwner, address femaleOwner, uint256 startTime, uint256 breedingType, uint256 status, uint256 childId, bool rewardsClaimed) {
        BreedingPair memory pair = breedingPairs[pairId];
        return (pair.fatherId, pair.motherId, pair.maleOwner, pair.femaleOwner, pair.startTime, pair.breedingType, pair.status, pair.childId, pair.rewardsClaimed);
    }

    function isInCooldown(uint256 tokenId) external view returns (bool) { return breedingCooldowns[tokenId] > block.timestamp; }
    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) { return breedingCooldowns[tokenId]; }

    function _generateChild(uint256 fatherId, uint256 motherId, address maleOwner, address femaleOwner) internal returns (uint256) {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        uint256 zodiacType = _getChildZodiacType(fatherId, motherId);
        INFTMint nftMint = INFTMint(nftMintContract);
        return nftMint.mint(femaleOwner, zodiacType);
    }

    function _getChildZodiacType(uint256 fatherId, uint256 motherId) internal view returns (uint256) {
        if (nftMintContract == address(0)) return 0;
        INFTMint nftMint = INFTMint(nftMintContract);
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "Breeding: Parent zodiac mismatch");

        uint256 seed = uint256(keccak256(abi.encodePacked(fatherId, motherId, block.timestamp)));
        uint256 fatherElement = fatherType / 24;
        uint256 motherElement = motherType / 24;
        uint256 inheritedElement = (seed % 2 == 0) ? fatherElement : motherElement;
        uint256 inheritedGender = (seed / 2) % 2;
        return inheritedElement * 24 + fatherZodiac * 2 + inheritedGender;
    }

    function calculateBreedingRewards(uint256 pairId) external view returns (uint256 motherReward, uint256 fatherReward, uint256 coOwnerReward) {
        BreedingPair memory pair = breedingPairs[pairId];
        uint256 totalReward = marketBreedingFee;
        return (totalReward * 80 / 100, totalReward * 15 / 100, totalReward * 5 / 100);
    }

    function claimBreedingRewards(uint256 pairId) external whenNotPaused {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 1, "Breeding: Pair not completed");
        require(pair.rewardsClaimed == false, "Breeding: Rewards already claimed");
        bool isAuthorized = msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner;
        if (!isAuthorized && pair.maleCoOwnerId != 0) {
            isAuthorized = msg.sender == INFTMint(nftMintContract).ownerOf(pair.maleCoOwnerId);
        }
        if (!isAuthorized && pair.femaleCoOwnerId != 0) {
            isAuthorized = msg.sender == INFTMint(nftMintContract).ownerOf(pair.femaleCoOwnerId);
        }
        require(isAuthorized, "Breeding: Not authorized");

        uint256 motherReward;
        uint256 fatherReward;
        uint256 coOwnerReward;
        
        (motherReward, fatherReward, coOwnerReward) = calculateBreedingRewards(pairId);
        
        require(tokenContract != address(0), "Breeding: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        uint256 totalReward = motherReward + fatherReward + coOwnerReward;
        require(token.balanceOf(address(this)) >= totalReward, "Breeding: Insufficient reward balance");

        if (motherReward > 0) {
            require(token.transfer(pair.femaleOwner, motherReward), "Breeding: Mother reward transfer failed");
        }
        if (fatherReward > 0) {
            require(token.transfer(pair.maleOwner, fatherReward), "Breeding: Father reward transfer failed");
        }
        if (coOwnerReward > 0) {
            if (pair.maleCoOwnerId != 0) {
                address maleCoOwner = INFTMint(nftMintContract).ownerOf(pair.maleCoOwnerId);
                require(token.transfer(maleCoOwner, coOwnerReward / 2), "Breeding: Male co-owner reward transfer failed");
            }
            if (pair.femaleCoOwnerId != 0 && pair.femaleCoOwnerId != pair.maleCoOwnerId) {
                address femaleCoOwner = INFTMint(nftMintContract).ownerOf(pair.femaleCoOwnerId);
                require(token.transfer(femaleCoOwner, coOwnerReward / 2), "Breeding: Female co-owner reward transfer failed");
            }
        }

        pair.rewardsClaimed = true;
        emit BreedingRewardsClaimed(pairId, motherReward, fatherReward, coOwnerReward);
    }
    
    function getPendingRewards(address owner) external view returns (uint256) {
        uint256 totalPending = 0;
        uint256 pairCount = breedingPairCount;
        
        for (uint256 i = 1; i <= pairCount; i++) {
            BreedingPair memory pair = breedingPairs[i];
            if (pair.status == 1 && !pair.rewardsClaimed) {
                if (owner == pair.maleOwner || owner == pair.femaleOwner) {
                    (uint256 motherReward, uint256 fatherReward, ) = calculateBreedingRewards(i);
                    if (owner == pair.femaleOwner) {
                        totalPending += motherReward;
                    } else {
                        totalPending += fatherReward;
                    }
                }
            }
        }
        
        return totalPending;
    }

    function setSelfBreedingFee(uint256 fee) external onlyOwner { selfBreedingFee = fee; }
    function setMarketBreedingFee(uint256 fee) external onlyOwner { marketBreedingFee = fee; }
    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { require(cooldown > 0, "Breeding: Cooldown must be > 0"); selfBreedingCooldown = cooldown; emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); }
    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { require(cooldown > 0, "Breeding: Cooldown must be > 0"); marketBreedingCooldown = cooldown; emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); }
    function setNFTContract(address _nftContract) external onlyAuthorized { require(_nftContract != address(0), "Breeding: Invalid NFT contract address"); nftMintContract = _nftContract; emit NFTContractSet(nftMintContract); }
    function setTokenContract(address _tokenContract) external onlyAuthorized { require(_tokenContract != address(0), "Breeding: Invalid token contract address"); tokenContract = _tokenContract; emit TokenContractSet(_tokenContract); }

    event NFTContractSet(address indexed nftContract);
    event TokenContractSet(address indexed tokenContract);

    // Market Listing Logic
    struct MarketListing { uint256 tokenId; address owner; uint256 listTime; bool isActive; }
    mapping(uint256 => MarketListing) public marketListings;
    uint256[] public listedTokenIds;

    event MarketListingCreated(uint256 indexed tokenId, address indexed owner);
    event MarketListingRemoved(uint256 indexed tokenId);

    function listForMarketBreeding(uint256 tokenId) external whenNotPaused {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(INFTMint(nftMintContract).ownerOf(tokenId) == msg.sender, "Breeding: Not token owner");
        require(!marketListings[tokenId].isActive, "Breeding: Already listed");
        require(!isInCooldown(tokenId), "Breeding: NFT in cooldown");
        require(INFTMint(nftMintContract).tokenLevel(tokenId) >= 5, "Breeding: Level too low");

        marketListings[tokenId] = MarketListing({ tokenId: tokenId, owner: msg.sender, listTime: block.timestamp, isActive: true });
        listedTokenIds.push(tokenId);
        emit MarketListingCreated(tokenId, msg.sender);
    }

    function delistFromMarketBreeding(uint256 tokenId) external whenNotPaused {
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
        emit MarketListingRemoved(tokenId);
    }

    function getMarketListingIds() external view returns (uint256[] memory) {
        uint256[] memory activeIds = new uint256[](listedTokenIds.length);
        uint256 count = 0;
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (marketListings[listedTokenIds[i]].isActive) {
                activeIds[count] = listedTokenIds[i];
                count++;
            }
        }
        assembly { mstore(activeIds, count) }
        return activeIds;
    }

    function getMarketListing(uint256 tokenId) external view returns (MarketListing memory) { return marketListings[tokenId]; }
    function getMarketListingCount() external view returns (uint256) { return listedTokenIds.length; }
}