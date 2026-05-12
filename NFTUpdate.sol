// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTDataType.sol";
import "./NFTInterface.sol";
import "./NFTLib.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

contract NFTUpdate is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using NFTLib for uint256;
    using NFTLib for address;

    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    address public nftContract;
    address public metadataContract;
    address public tokenContract;
    address public pancakeSwapPair;
    address public authorizer;

    uint256 public priceExpirySeconds = 3600;
    uint256 public priceDeviationThreshold = 5000;
    uint256 public lastPrice;
    uint256 public lastPriceUpdateTime;

    uint256 public level1UpgradeCost = 10000;
    uint256 public level2UpgradeCost = 40000;
    uint256 public level3UpgradeCost = 120000;
    uint256 public level4UpgradeCost = 480000;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address initialOwner, address _nftContract, address _metadataContract) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        transferOwnership(initialOwner);
        nftContract = _nftContract;
        metadataContract = _metadataContract;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    function setNFTContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        nftContract = a;
    }

    function setMetadataContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        metadataContract = a;
    }

    function setTokenContract(address a) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        tokenContract = a;
    }

    function setPancakeSwapPair(address pair) external {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        require(pair != address(0), "E27: Zero address");
        pancakeSwapPair = pair;
    }

    function setPriceExpirySeconds(uint256 seconds_) external onlyOwner {
        require(seconds_ > 0, "NFTUpdate: expiry must be > 0");
        priceExpirySeconds = seconds_;
    }

    function setPriceDeviationThreshold(uint256 threshold) external onlyOwner {
        require(threshold <= 10000, "NFTUpdate: threshold <= 10000");
        priceDeviationThreshold = threshold;
    }

    function resetPriceCache() external onlyOwner {
        lastPrice = 0;
        lastPriceUpdateTime = 0;
    }

    function setLevel1UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level1UpgradeCost = cost;
    }

    function setLevel2UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level2UpgradeCost = cost;
    }

    function setLevel3UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level3UpgradeCost = cost;
    }

    function setLevel4UpgradeCost(uint256 cost) external onlyOwner {
        require(cost > 0, "NFTUpdate: cost must be > 0");
        level4UpgradeCost = cost;
    }

    function getTokenPriceFromPancakeSwap() public view returns (uint256) {
        require(pancakeSwapPair != address(0), "E24: PancakeSwap pair not set");
        
        IPancakeSwapPair pair = IPancakeSwapPair(pancakeSwapPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "E25: Insufficient liquidity");
        
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        uint8 decimals0 = 18;
        uint8 decimals1 = 18;
        
        if (token0 == tokenContract) {
            try IBEP20(token1).decimals() returns (uint8 d) {
                decimals1 = d;
            } catch {}
            
            uint256 price = (uint256(reserve1) * 10**18) / uint256(reserve0);
            return adjustDecimals(price, 18, decimals1);
        } else if (token1 == tokenContract) {
            try IBEP20(token0).decimals() returns (uint8 d) {
                decimals0 = d;
            } catch {}
            
            uint256 price = (uint256(reserve0) * 10**18) / uint256(reserve1);
            return adjustDecimals(price, decimals0, 18);
        } else {
            revert("E26: Token not found in pair");
        }
    }

    function adjustDecimals(uint256 value, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return value;
        } else if (fromDecimals < toDecimals) {
            return value * 10**(toDecimals - fromDecimals);
        } else {
            return value / 10**(fromDecimals - toDecimals);
        }
    }

    function upgradeWithNFT(uint256 tokenId) external nonReentrant returns (uint8) {
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        uint req = lv;
        
        uint256[] memory arr = m.userTokens(msg.sender, t);
        uint256 count = 0;
        
        for (uint i = 0; i < arr.length; i++) {
            if (m.tokenLevel(arr[i]) == lv) {
                count++;
            }
        }
        require(count >= req + 1, "E17");
        
        uint256[] memory burnCandidates = new uint256[](req);
        uint256 candidateIdx = 0;
        
        for (uint i = 0; i < arr.length && candidateIdx < req; i++) {
            uint256 currentId = arr[i];
            if (currentId != tokenId && m.tokenLevel(currentId) == lv) {
                burnCandidates[candidateIdx++] = currentId;
            }
        }
        
        require(candidateIdx == req, "E28: Insufficient burn candidates");
        
        for (uint i = 0; i < req; i++) {
            uint burnId = burnCandidates[i];
            nft.safeTransferFrom(msg.sender, BLACK_HOLE, burnId);
            emit CardBurned(burnId, t, msg.sender);
        }
        
        uint8 newLv = lv + 1;
        m.setTokenLevel(tokenId, newLv);
        m.updateUserWeight(msg.sender, lv, false);
        m.updateUserWeight(msg.sender, newLv, true);
        emit CardUpgraded(tokenId, t, lv, newLv, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    function upgradeWithToken(uint256 tokenId) external nonReentrant returns (uint8) {
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        require(tokenContract != address(0), "E7: Token contract not set");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        uint256 cost;
        if (lv == 1) cost = level1UpgradeCost;
        else if (lv == 2) cost = level2UpgradeCost;
        else if (lv == 3) cost = level3UpgradeCost;
        else if (lv == 4) cost = level4UpgradeCost;
        else revert("E18: Invalid level");
        
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8: Insufficient balance");
        require(t.transferFrom(msg.sender, BLACK_HOLE, cost), "E9: Transfer failed");
        
        uint8 newLv = _upgradeLevel(tokenId, lv);
        emit TokenUpgraded(tokenId, m.tokenType(tokenId), lv, newLv, cost, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    function upgradeWithUSDValue(uint256 tokenId) external nonReentrant returns (uint8) {
        INFTMint nft = INFTMint(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "E15: Not owner");
        require(tokenContract != address(0) && pancakeSwapPair != address(0), "E19: Missing contracts");
        
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16: Max level reached");
        
        uint256 usdValue;
        if (lv == 1) usdValue = 1e18;
        else if (lv == 2) usdValue = 4e18;
        else if (lv == 3) usdValue = 12e18;
        else if (lv == 4) usdValue = 48e18;
        else revert("E18: Invalid level");
        
        uint256 price = getTokenPriceFromPancakeSwap();
        require(price > 0, "E20: Price oracle returned zero");
        
        if (lastPrice > 0) {
            require(block.timestamp <= lastPriceUpdateTime + priceExpirySeconds, "E30: Price expired");
            
            uint256 deviation;
            if (price > lastPrice) {
                deviation = ((price - lastPrice) * 10000) / lastPrice;
            } else {
                deviation = ((lastPrice - price) * 10000) / lastPrice;
            }
            require(deviation <= priceDeviationThreshold, "E23: Price deviation too high");
        }
        
        lastPrice = price;
        lastPriceUpdateTime = block.timestamp;
        emit PriceUpdated(price, block.timestamp);
        
        uint256 cost = (usdValue * 1e18) / price;
        require(cost > 0, "E21: Invalid cost");
        
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msg.sender) >= cost, "E8: Insufficient balance");
        require(t.transferFrom(msg.sender, BLACK_HOLE, cost), "E9: Transfer failed");
        
        uint8 newLv = _upgradeLevel(tokenId, lv);
        emit USDValueUpgraded(tokenId, m.tokenType(tokenId), lv, newLv, usdValue, cost, price, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    function _upgradeLevel(uint id, uint8 oldLv) internal returns (uint8) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(id);
        uint8 newLv = oldLv + 1;
        m.setTokenLevel(id, newLv);
        m.updateUserWeight(msg.sender, oldLv, false);
        m.updateUserWeight(msg.sender, newLv, true);
        emit CardUpgraded(id, t, oldLv, newLv, msg.sender, uint64(block.timestamp));
        return newLv;
    }

    event CardBurned(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner);
    event CardUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);
    event TokenUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, uint256 tokensBurned, address indexed owner, uint64 timestamp);
    event USDValueUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, uint256 usdValue, uint256 tokensBurned, uint256 tokenPrice, address indexed owner, uint64 timestamp);
    event PriceUpdated(uint256 price, uint256 timestamp);
}