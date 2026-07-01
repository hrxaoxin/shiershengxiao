// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFlapPortal {
    struct QuoteExactInputParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
    }
    struct ExactInputParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        bytes permitData;
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
    function swapExactInput(ExactInputParams calldata params) external payable returns (uint256 outputAmount);
}

interface IPancakeRouter02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
}

contract FlapPricePay {
    using SafeERC20 for IERC20;
    IFlapPortal public constant PORTAL = IFlapPortal(0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0);
    IPancakeRouter02 public constant PANCAKE_ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    uint256 public slippageBps = 500; // 5%
    address public owner;
    address public authorizer;

    event SwapBNBForToken(address indexed token, uint256 bnbIn, uint256 tokenOut, address indexed to, string source);
    event SwapTokenForBNB(address indexed token, uint256 tokenIn, uint256 bnbOut, address indexed to, string source);

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

    function setSlippage(uint256 _slippageBps) external onlyOwner {
        require(_slippageBps <= 1000, "Slippage too high");
        slippageBps = _slippageBps;
    }

    // ---------- 查询函数 ----------
    function isTokenOnPancake(address token) public view returns (bool) {
        (bool success, bytes memory data) = address(PANCAKE_ROUTER).staticcall(
            abi.encodeWithSelector(IPancakeRouter02.getAmountsOut.selector, 10**18, _buildPath(token, WBNB))
        );
        if (!success) return false;
        uint256[] memory amounts = abi.decode(data, (uint256[]));
        return amounts.length >= 2 && amounts[1] > 0;
    }

    function isTokenOnFlap(address token) public view returns (bool) {
        IFlapPortal.TokenStateV5 memory state = PORTAL.getTokenV5(token);
        return state.status == 1;
    }

    function _buildPath(address token, address base) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = base;
        return path;
    }

    // ---------- 查询授权额度 ----------
    function getAllowance(address token, address ownerAddr) external view returns (uint256) {
        return IERC20(token).allowance(ownerAddr, address(this));
    }

    // 授权无限额度（兼容 USDT 类）
function approveMax(address token) external {
    require(token != address(0), "Invalid token");
    IERC20(token).approve(address(this), 0); // 先清零
    IERC20(token).approve(address(this), type(uint256).max);
}

// 授权指定额度（也是先清零再设置）
function approveExact(address token, uint256 amount) external {
    require(token != address(0), "Invalid token");
    IERC20(token).approve(address(this), 0);
    IERC20(token).approve(address(this), amount);
}

    // ---------- 买入 ----------
    function buyToken(address token, address to) external payable returns (uint256) {
        require(msg.value > 0, "BNB amount must > 0");
        require(token != address(0) && to != address(0), "Invalid address");

        if (isTokenOnPancake(token)) {
            address[] memory path = new address[](2);
            path[0] = WBNB;
            path[1] = token;
            uint256 expectedOut = PANCAKE_ROUTER.getAmountsOut(msg.value, path)[1];
            uint256 amountOutMin = expectedOut * (10000 - slippageBps) / 10000;
            uint256[] memory amounts = PANCAKE_ROUTER.swapExactETHForTokens{value: msg.value}(
                amountOutMin, path, to, block.timestamp + 300
            );
            uint256 received = amounts[amounts.length - 1];
            emit SwapBNBForToken(token, msg.value, received, to, "PancakeSwap");
            return received;
        }

        if (isTokenOnFlap(token)) {
            IFlapPortal.QuoteExactInputParams memory qp = IFlapPortal.QuoteExactInputParams({
                inputToken: address(0), outputToken: token, inputAmount: msg.value
            });
            uint256 expectedOut = PORTAL.quoteExactInput(qp);
            uint256 amountOutMin = expectedOut * (10000 - slippageBps) / 10000;
            IFlapPortal.ExactInputParams memory sp = IFlapPortal.ExactInputParams({
                inputToken: address(0), outputToken: token, inputAmount: msg.value,
                minOutputAmount: amountOutMin, permitData: ""
            });
            uint256 outputAmount = PORTAL.swapExactInput{value: msg.value}(sp);
            // 将收到的代币转给 to
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(to, balance);
            }
            emit SwapBNBForToken(token, msg.value, outputAmount, to, "FlapPortal");
            return outputAmount;
        }

        revert("Token not available");
    }

    // ---------- 卖出 ----------
    function sellToken(address token, uint256 amountIn, address to) external returns (uint256) {
        require(amountIn > 0 && token != address(0) && to != address(0), "Invalid params");

        // **新增：检查授权额度，如果不足则直接报错**
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        require(allowance >= amountIn, "Insufficient allowance, please approve first");

        // 从调用者转代币到本合约
        IERC20(token).transferFrom(msg.sender, address(this), amountIn);

        if (isTokenOnPancake(token)) {
            IERC20(token).approve(address(PANCAKE_ROUTER), amountIn);
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = WBNB;
            uint256 expectedOut = PANCAKE_ROUTER.getAmountsOut(amountIn, path)[1];
            uint256 amountOutMin = expectedOut * (10000 - slippageBps) / 10000;
            uint256[] memory amounts = PANCAKE_ROUTER.swapExactTokensForETH(
                amountIn, amountOutMin, path, to, block.timestamp + 300
            );
            IERC20(token).approve(address(PANCAKE_ROUTER), 0);
            uint256 received = amounts[amounts.length - 1];
            emit SwapTokenForBNB(token, amountIn, received, to, "PancakeSwap");
            return received;
        }

        if (isTokenOnFlap(token)) {
            IERC20(token).approve(address(PORTAL), amountIn);
            IFlapPortal.QuoteExactInputParams memory qp = IFlapPortal.QuoteExactInputParams({
                inputToken: token, outputToken: address(0), inputAmount: amountIn
            });
            uint256 expectedOut = PORTAL.quoteExactInput(qp);
            uint256 amountOutMin = expectedOut * (10000 - slippageBps) / 10000;
            IFlapPortal.ExactInputParams memory sp = IFlapPortal.ExactInputParams({
                inputToken: token, outputToken: address(0), inputAmount: amountIn,
                minOutputAmount: amountOutMin, permitData: ""
            });
            uint256 outputAmount = PORTAL.swapExactInput(sp);
            IERC20(token).approve(address(PORTAL), 0);
            if (address(this).balance > 0) {
                (bool s1, ) = payable(to).call{value: address(this).balance}("");
                require(s1, "FlapPricePay: BNB transfer failed");
            }
            emit SwapTokenForBNB(token, amountIn, outputAmount, to, "FlapPortal");
            return outputAmount;
        }

        revert("Token not available");
    }

    // ---------- 紧急提款 ----------
    function withdrawToken(address token, address to) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) IERC20(token).safeTransfer(to, balance);
    }
    function withdrawBNB(address to) external onlyOwner {
        (bool s2, ) = payable(to).call{value: address(this).balance}("");
        require(s2, "FlapPricePay: BNB transfer failed");
    }
    receive() external payable {}

    /**
     * @dev 合约数据重置事件
     * @param operator 操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp);

    /**
     * @dev 重置合约核心数据（仅owner或authorizer）
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        slippageBps = 500; // 重置为默认值
        
        emit ContractDataReset(msg.sender, block.timestamp);
    }
}