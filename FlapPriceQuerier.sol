// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFlapPortal {
    struct QuoteExactInputParams {
        address inputToken;   
        address outputToken;  
        uint256 inputAmount;
    }

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
    function quoteExactInput(QuoteExactInputParams calldata params) external returns (uint256 outputAmount);
}

interface IPancakeRouter02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) 
        external view returns (uint256[] memory amounts);
}

contract FlapPriceQuerier {
    IFlapPortal public constant PORTAL = IFlapPortal(0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0);
    IPancakeRouter02 public constant PANCAKE_ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    address public owner;
    address public authorizer;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @dev 仅owner或authorizer的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner || msg.sender == authorizer, "Not authorized");
        _;
    }

    /**
     * @dev 设置授权合约地址（仅owner）
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    // ==================== Flap 内盘查询 ====================
    function getFlapPriceInBNB(address token, uint256 amountInToken) external returns (uint256 amountOutBNB) {
        IFlapPortal.QuoteExactInputParams memory params = IFlapPortal.QuoteExactInputParams({
            inputToken: token,
            outputToken: address(0),
            inputAmount: amountInToken
        });
        return PORTAL.quoteExactInput(params);
    }

    // ==================== Flap 内盘 USD 查询（已内联，避免声明错误） ====================
    function getFlapPriceInUSD(address token, uint256 amountInToken) external returns (uint256 amountOutUSDT) {
        // 内联 getFlapPriceInBNB
        IFlapPortal.QuoteExactInputParams memory params = IFlapPortal.QuoteExactInputParams({
            inputToken: token,
            outputToken: address(0),
            inputAmount: amountInToken
        });
        uint256 bnbOut = PORTAL.quoteExactInput(params);
        
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = USDT;
        
        uint256[] memory amounts = PANCAKE_ROUTER.getAmountsOut(bnbOut, path);
        return amounts[1];
    }

    // ==================== Pancake 外盘查询 ====================
    function getPancakePrice(address token, uint256 amountIn, bool isBuy) external view returns (uint256) {
        address[] memory path = new address[](2);
        if (isBuy) {
            path[0] = WBNB;
            path[1] = token;
        } else {
            path[0] = token;
            path[1] = WBNB;
        }
        uint256[] memory amounts = PANCAKE_ROUTER.getAmountsOut(amountIn, path);
        return amounts[1];
    }

    function getTokenInfo(address token) external view returns (IFlapPortal.TokenStateV5 memory) {
        return PORTAL.getTokenV5(token);
    }

    // ==================== 推荐：最佳 USD 价格（纯 view） ====================
    function getBestPriceInUSD(address token) external view returns (uint256 priceUSDPerToken) {
        IFlapPortal.TokenStateV5 memory state = PORTAL.getTokenV5(token);
        
        if (state.status == 1 && state.price > 0) {
            address quote = state.quoteTokenAddress;
            if (quote == address(0) || quote == WBNB) {
                address[] memory path = new address[](2);
                path[0] = WBNB;
                path[1] = USDT;
                uint256[] memory amounts = PANCAKE_ROUTER.getAmountsOut(state.price, path);
                return amounts[1];
            } else if (quote == USDT) {
                return state.price;
            }
        }
        
        // Fallback: PancakeSwap 查询 1 token 的 USDT 价格
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
    event ContractDataReset(address indexed operator, uint256 timestamp);

    /**
     * @dev 重置合约核心数据（仅owner或authorizer）
     * 注意：此合约主要为查询合约，无核心状态变量需要重置
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        // FlapPriceQuerier主要为查询合约，无核心状态变量需要重置
        emit ContractDataReset(msg.sender, block.timestamp);
    }
}