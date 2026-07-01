// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

interface IFlapPortal {
    struct TokenStateV5 {
        uint8 status;
        uint256 reserve;
        uint256 circulatingSupply;
        uint256 price;
        uint8 tokenVersion;
        uint256 r;
        uint256 h;
        uint256 k;
        uint256 dexSupplyThresh;
        address quoteTokenAddress;
        bool nativeToQuoteSwapEnabled;
        bytes32 extensionID;
    }

    function getTokenV5(address token) external view returns (TokenStateV5 memory);

    struct TokenStateV8 {
        uint8 status;
        uint256 reserve;
        uint256 circulatingSupply;
        uint256 price;
        uint8 tokenVersion;
        uint256 r;
        uint256 h;
        uint256 k;
        uint256 dexSupplyThresh;
        address quoteTokenAddress;
        bool nativeToQuoteSwapEnabled;
        bytes32 extensionID;
        uint256 lpReserve;
        uint256 lpSupply;
        uint256 nativeReserve;
    }

    function getTokenV8(address token) external view returns (TokenStateV8 memory);
}

interface IPancakeRouter02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

contract PriceOracle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    IFlapPortal public constant FLAP_PORTAL = IFlapPortal(0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0);
    IPancakeRouter02 public constant PANCAKE_ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    constructor() {
        _disableInitializers();
    }

    address public authorizer;
    
    uint256 public epoch;

    /**
     * @dev 仅owner或authorizer的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "PriceOracle: Not authorized");
        _;
    }

    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "PriceOracle: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizerAddress;
        epoch = 1;
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == owner(), "PriceOracle: Only owner can upgrade");
    }

    function getTokenPriceUSD() external view returns (uint256) {
        IAuthorizer auth = IAuthorizer(authorizer);
        address token = auth.getAddressByName(\"token\");
        
        if (token == address(0)) return 0;

        try FLAP_PORTAL.getTokenV5(token) returns (IFlapPortal.TokenStateV5 memory tokenState) {
            if (tokenState.status == 1 && tokenState.price > 0) {
                address quoteToken = tokenState.quoteTokenAddress;
                
                if (quoteToken == address(0) || quoteToken == WBNB) {
                    address[] memory path = new address[](2);
                    path[0] = WBNB;
                    path[1] = USDT;
                    
                    try PANCAKE_ROUTER.getAmountsOut(tokenState.price, path) returns (uint256[] memory amounts) {
                        if (amounts.length == 2 && amounts[1] > 0) {
                            return amounts[1];
                        }
                    } catch {}
                } else if (quoteToken == USDT) {
                    return tokenState.price;
                }
            }
        } catch {}

        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = WBNB;
        path[2] = USDT;

        try PANCAKE_ROUTER.getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 3 && amounts[2] > 0) {
                return amounts[2];
            }
        } catch {}

        return 0;
    }

    function getTokenPriceUSDV8() external view returns (uint256) {
        IAuthorizer auth = IAuthorizer(authorizer);
        address token = auth.getAddressByName(\"token\");
        
        if (token == address(0)) return 0;

        try FLAP_PORTAL.getTokenV8(token) returns (IFlapPortal.TokenStateV8 memory tokenState) {
            if (tokenState.status == 1 && tokenState.price > 0) {
                address quoteToken = tokenState.quoteTokenAddress;
                
                if (quoteToken == address(0) || quoteToken == WBNB) {
                    address[] memory path = new address[](2);
                    path[0] = WBNB;
                    path[1] = USDT;
                    
                    try PANCAKE_ROUTER.getAmountsOut(tokenState.price, path) returns (uint256[] memory amounts) {
                        if (amounts.length == 2 && amounts[1] > 0) {
                            return amounts[1];
                        }
                    } catch {}
                } else if (quoteToken == USDT) {
                    return tokenState.price;
                }
            }
        } catch {}

        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = WBNB;
        path[2] = USDT;

        try PANCAKE_ROUTER.getAmountsOut(10**18, path) returns (uint256[] memory amounts) {
            if (amounts.length == 3 && amounts[2] > 0) {
                return amounts[2];
            }
        } catch {}

        return 0;
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp, uint256 oldEpoch, uint256 newEpoch);

    /**
     * @dev 重置合约核心数据（仅owner或authorizer）
     * 注意：此合约主要为查询合约，无核心状态变量需要重置
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        uint256 oldEpoch = epoch;
        epoch = epoch + 1;
        emit ContractDataReset(msg.sender, block.timestamp, oldEpoch, epoch);
    }
}