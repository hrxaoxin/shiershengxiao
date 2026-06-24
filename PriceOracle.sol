// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";
import "./PriceLibrary.sol";

contract PriceOracle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    address public constant PANCAKE_SWAP_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    constructor() {
        _disableInitializers();
    }

    address public authorizer;

    bool public paused;
    string public pauseReason;

    event Paused(address account, string reason);
    event Unpaused(address account);

    uint256 public tokenPriceUSD;
    uint256 public tokenPriceUpdatedAt;
    uint256 public ethPriceUSD;
    uint256 public ethPriceUpdatedAt;
    uint256 public priceValidityPeriod = 86400;

    address public flapSwapPair_WBNB;
    address public pancakeSwapPair_WBNB;
    address public wbnbUsdtPair;

    bool public autoPriceEnabled;
    uint256 public maxPriceChangePercent;
    uint256 public priceUpdateCooldown;

    event PriceUpdated(uint256 tokenPriceUSD, uint256 ethPriceUSD, address updater);
    event PairAddressSet(uint8 dexType, address pair);

    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "PriceOracle: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;

        priceValidityPeriod = 86400;
        autoPriceEnabled = true;
        maxPriceChangePercent = 5000;
        priceUpdateCooldown = 5 minutes;
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

    modifier whenNotPaused() {
        require(!paused, "PriceOracle: Paused");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "PriceOracle: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "PriceOracle: Not authorized");
        _;
    }

    function isTokenPriceValid() external view returns (bool) {
        return _isTokenPriceValid();
    }

    function isETHPriceValid() external view returns (bool) {
        return _isETHPriceValid();
    }

    function _isTokenPriceValid() internal view returns (bool) {
        return tokenPriceUSD > 0 && block.timestamp <= tokenPriceUpdatedAt + priceValidityPeriod;
    }

    function _isETHPriceValid() internal view returns (bool) {
        return ethPriceUSD > 0 && block.timestamp <= ethPriceUpdatedAt + priceValidityPeriod;
    }

    function fetchPriceFromDEX() external nonReentrant whenNotPaused returns (bool) {
        require(autoPriceEnabled, "PriceOracle: Auto price not enabled");

        uint256 tokenPriceSum = 0;
        uint256 tokenCount = 0;
        uint256 ethPriceSum = 0;
        uint256 ethCount = 0;
        uint256 avgTokenPrice = 0;
        uint256 avgETHPrice = 0;

        IAuthorizer auth = IAuthorizer(authorizer);
        address flapSwapRouter = auth.getFlapSwapRouter();
        address pancakeSwapRouter = auth.getPancakeSwapRouter();

        uint256 flapPrice = _getPriceFromManualPairs(0);
        if (flapPrice == 0 && flapSwapRouter != address(0)) {
            flapPrice = _fetchTokenPrice(flapSwapRouter);
        }
        if (flapPrice > 0) {
            tokenPriceSum += flapPrice;
            tokenCount++;
        }

        uint256 pancakePrice = _fetchPriceFromPancakeSwap();
        if (pancakePrice == 0) {
            pancakePrice = _getPriceFromManualPairs(1);
        }
        if (pancakePrice == 0 && pancakeSwapRouter != address(0)) {
            pancakePrice = _fetchTokenPrice(pancakeSwapRouter);
        }
        if (pancakePrice > 0) {
            tokenPriceSum += pancakePrice;
            tokenCount++;
        }

        if (tokenCount > 0) {
            avgTokenPrice = tokenPriceSum / tokenCount;
            tokenPriceUSD = avgTokenPrice;
            tokenPriceUpdatedAt = block.timestamp;
        }

        uint256 ethPrice = _getWbnbUsdtPrice();
        if (ethPrice > 0) {
            ethPriceSum += ethPrice;
            ethCount++;
        }

        if (ethCount > 0) {
            avgETHPrice = ethPriceSum / ethCount;
            ethPriceUSD = avgETHPrice;
            ethPriceUpdatedAt = block.timestamp;
        }

        emit PriceUpdated(tokenPriceUSD, ethPriceUSD, msg.sender);
        return tokenCount > 0 && ethCount > 0;
    }

    function _fetchTokenPrice(address router) internal view returns (uint256) {
        if (router == address(0)) return 0;
        IAuthorizer auth = IAuthorizer(authorizer);
        return PriceLibrary.getPriceFromRouter(router, auth.getToken(), auth.getWBNB(), auth.getUSDT());
    }

    function _fetchPriceFromPancakeSwap() internal view returns (uint256) {
        IAuthorizer auth = IAuthorizer(authorizer);
        address token = auth.getToken();

        if (token == address(0)) {
            return 0;
        }

        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = WBNB;
        path[2] = USDT;

        try IDexRouter(PANCAKE_SWAP_ROUTER).getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 3 && amounts[2] > 0) {
                return amounts[2] * 10**12;
            }
        } catch {}

        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = USDT;

        try IDexRouter(PANCAKE_SWAP_ROUTER).getAmountsOut(10**18, directPath) returns (uint256[] memory amounts) {
            if (amounts.length == 2 && amounts[1] > 0) {
                return amounts[1] * 10**12;
            }
        } catch {}

        return 0;
    }

    function _getPriceFromManualPairs(uint8 dexType) internal view returns (uint256) {
        IAuthorizer auth = IAuthorizer(authorizer);
        address tokenAddress = auth.getToken();
        address wbnb = auth.getWBNB();

        address pair;
        if (dexType == 0) {
            pair = flapSwapPair_WBNB;
        } else if (dexType == 1) {
            pair = pancakeSwapPair_WBNB;
        } else {
            return 0;
        }

        if (pair == address(0)) return 0;

        return PriceLibrary.getPriceFromPairs(pair, wbnbUsdtPair, tokenAddress, wbnb, USDT);
    }

    function _getWbnbUsdtPrice() internal view returns (uint256) {
        if (wbnbUsdtPair == address(0)) return 0;
        return PriceLibrary.getWbnbUsdtPriceFromPair(wbnbUsdtPair, WBNB, USDT);
    }

    function setPriceValidityPeriod(uint256 duration) external onlyOwner {
        priceValidityPeriod = duration;
    }

    function setFlapSwapPair(address pair) external onlyOwner {
        flapSwapPair_WBNB = pair;
        emit PairAddressSet(0, pair);
    }

    function setPancakeSwapPair(address pair) external onlyOwner {
        pancakeSwapPair_WBNB = pair;
        emit PairAddressSet(1, pair);
    }

    function setWbnbUsdtPair(address pair) external onlyOwner {
        wbnbUsdtPair = pair;
        emit PairAddressSet(3, pair);
    }

    function setAllPairs(address _flapSwapPair, address _pancakeSwapPair, address _wbnbUsdtPair) external onlyOwner {
        flapSwapPair_WBNB = _flapSwapPair;
        pancakeSwapPair_WBNB = _pancakeSwapPair;
        wbnbUsdtPair = _wbnbUsdtPair;
        emit PairAddressSet(0, _flapSwapPair);
        emit PairAddressSet(1, _pancakeSwapPair);
        emit PairAddressSet(3, _wbnbUsdtPair);
    }

    function setAutoPriceEnabled(bool enabled) external onlyOwner {
        autoPriceEnabled = enabled;
    }

    function setMaxPriceChangePercent(uint256 percent) external onlyOwner {
        require(percent <= 10000, "PriceOracle: Invalid percent");
        maxPriceChangePercent = percent;
    }

    function setPriceUpdateCooldown(uint256 cooldown) external onlyOwner {
        priceUpdateCooldown = cooldown;
    }

    function getPriceInUSD(uint256 tokenAmount) external view returns (uint256) {
        if (tokenPriceUSD == 0 || tokenAmount == 0) return 0;
        return (tokenAmount * tokenPriceUSD) / (10**18);
    }

    function getPriceInUSDT(uint256 tokenAmount) external view returns (uint256) {
        if (tokenPriceUSD == 0 || tokenAmount == 0) return 0;
        return (tokenAmount * tokenPriceUSD) / (10**24);
    }

    function getTokensForUSD(uint256 usdAmount) external view returns (uint256) {
        if (tokenPriceUSD == 0 || usdAmount == 0) return 0;
        return (usdAmount * 10**18) / tokenPriceUSD;
    }

    function getTokensForUSDT(uint256 usdtAmount) external view returns (uint256) {
        if (tokenPriceUSD == 0 || usdtAmount == 0) return 0;
        return (usdtAmount * 10**24) / tokenPriceUSD;
    }

    function calculateETHUSDTEquivalent(uint256 ethAmount) external view returns (uint256) {
        if (ethPriceUSD == 0 || ethAmount == 0) return 0;
        return (ethAmount * ethPriceUSD) / (10**30);
    }

    function getAllDEXPrices() external view returns (uint256[] memory prices, uint256 lowestPrice, uint8 bestDEX) {
        prices = new uint256[](2);
        lowestPrice = 0;
        bestDEX = 0;

        IAuthorizer auth = IAuthorizer(authorizer);
        address flapSwapRouter = auth.getFlapSwapRouter();
        address pancakeSwapRouter = auth.getPancakeSwapRouter();

        uint256 flapPrice = _getPriceFromManualPairs(0);
        if (flapPrice == 0 && flapSwapRouter != address(0)) {
            flapPrice = _fetchTokenPrice(flapSwapRouter);
        }
        prices[0] = flapPrice;

        uint256 pancakePrice = _fetchPriceFromPancakeSwap();
        if (pancakePrice == 0) {
            pancakePrice = _getPriceFromManualPairs(1);
        }
        if (pancakePrice == 0 && pancakeSwapRouter != address(0)) {
            pancakePrice = _fetchTokenPrice(pancakeSwapRouter);
        }
        prices[1] = pancakePrice;

        for (uint8 i = 0; i < 2; i++) {
            if (prices[i] > 0) {
                if (lowestPrice == 0 || prices[i] < lowestPrice) {
                    lowestPrice = prices[i];
                    bestDEX = i;
                }
            }
        }

        if (tokenPriceUSD > 0 && _isTokenPriceValid()) {
            if (lowestPrice == 0 || tokenPriceUSD < lowestPrice) {
                lowestPrice = tokenPriceUSD;
                bestDEX = 255;
            }
        }
    }

    function getEffectiveTokenPrice() external view returns (uint256) {
        if (tokenPriceUSD > 0 && _isTokenPriceValid()) {
            return tokenPriceUSD;
        }

        (uint256[] memory prices, uint256 lowestPrice, ) = this.getAllDEXPrices();
        return lowestPrice;
    }

    function isPriceValid() external view returns (bool) {
        return _isTokenPriceValid() && _isETHPriceValid();
    }

    receive() external payable {}
    fallback() external payable {}
}