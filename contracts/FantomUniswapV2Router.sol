pragma solidity ^0.5.17;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import './libraries/UniswapV2Library.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Router.sol';
import './interfaces/IWFTM.sol';

// FantomUniswapV2Router is a port of the Uniswap V2 router contract
// to the Fantom Opera block chain.
contract FantomUniswapV2Router is IUniswapV2Router {
    // define used libs
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    // factory is the address of the core Uniswap Factory contract.
    address public factory;

    // wFTM is the address of the wrapped FTM ERC20 contract,
    // wFTM is a wrapped implementation of the native Fantom Opera token.
    address public wFTM;

    // make sure the transaction deadline was met
    modifier ensure (uint256 deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    // constructor creates a new instance of the Uniswap router
    constructor(address _factory, address _wFTM) public {
        factory = _factory;
        wFTM = _wFTM;
    }

    // payable fallback function verifies that the contract receives native
    // tokens only from the wFTM contract as an unwrap callback.
    function() external payable {
        assert(msg.sender == wFTM);
    }

    // WETH is a compatibility getter around wrapped native FTM tokens
    // address resolution.
    function WETH() public view returns (address) {
        return wFTM;
    }

    // ------------------------------------
    // liquidity management functions below
    // ------------------------------------

    // _addLiquidity adds the given amount of liquidity to the given
    // Uniswap pair.
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }

        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // addLiquidity add liquidity of given ERC20 tokens to the given token pair
    // of the Uniswap core
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        // process liquidity calculations
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        // transfer tokens
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, pair, amountA);
        SafeERC20.safeTransferFrom(IERC20(tokenB), msg.sender, pair, amountB);

        // mint the pair token share to recipient
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    // addLiquidityETH adds received amount of Fantom Opera native FTM tokens
    // to the specified token pair using wrapper contract to wrap native FTMs first.
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        // process liquidity calculations
        (amountToken, amountETH) = _addLiquidity(
            token,
            wFTM,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        // transfer the other token
        address pair = UniswapV2Library.pairFor(factory, token, wFTM);
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, pair, amountToken);

        // swap received FTM before posting it as ERC20
        IWFTM(wFTM).deposit.value(amountETH)();
        assert(IWFTM(wFTM).transfer(pair, amountETH));

        // mint the pair share token to recipient
        liquidity = IUniswapV2Pair(pair).mint(to);

        // refund any remaining dust we couldn't add as liquidity
        if (msg.value > amountETH) {
            Address.sendValue(Address.toPayable(msg.sender), uint256(msg.value).sub(amountETH));
        }
    }

    // removeLiquidity removes specified amount of liquidity from the given
    // Uniswap pair and redeems user's share tokens of the pool.
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        // get the pair
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

        // consume the amount of share tokens available to sender (redeem their share)
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);

        // validate the transfer
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    // removeLiquidityETH removes the given amount of liquidity from the given
    // Uniswap pair and redeems user's share tokens, the wrapped FTM tokens
    // is swapped back to native FTMs before sending.
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountToken, uint amountETH) {
        // remove liquidity, receive the output tokens
        (amountToken, amountETH) = removeLiquidity(
            token,
            wFTM,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );

        // transfer the ERC20 token to recipient
        ERC20(token).safeTransfer(to, amountToken);

        // unwrap FTM and send the native
        IWFTM(wFTM).withdraw(amountETH);
        Address.sendValue(to.toPayable(), amountETH);
    }

    // removeLiquidityWithPermit removes liquidity from the specified
    // token pair using given permit.
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(- 1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // removeLiquidityETHWithPermit removes liquidity from the specified token in conjunction
    // with the wrapped native FTM tokens using given permit.
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, wFTM);
        uint value = approveMax ? uint(- 1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // --------------------------
    // SWAP functions below
    // --------------------------

    // _swap does a sequence of swaps on the core contract using sequence of pools
    // it requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            // parse path
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);

            // calculate swap amounts
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));

            // decide the recipient (intermediate pair or the final receiver)
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;

            // do the swap
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    // swapExactTokensForTokens performs the swap of the exact amount of tokens
    // for calculated amount of target tokens using pairs specified by the swap path.
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        // check validity
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        // transfer input tokens to the first pair
        SafeERC20.safeTransferFrom(IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);

        // do the swap
        _swap(amounts, path, to);
    }

    // swapTokensForExactTokens performs the swap of calculated amounts of input tokens to receive
    // exactly desired amount of target tokens using pairs specified by the swap path.
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        // check validity
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');

        // transfer input tokens to the first pair
        SafeERC20.safeTransferFrom(IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);

        // perform the swap
        _swap(amounts, path, to);
    }

    // swapExactETHForTokens swaps specified amount of native FTM tokens for the target tokens
    // using pairs specified by the swap path.
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint[] memory amounts) {
        // make sure the first step is wrapped native token
        require(path[0] == wFTM, 'UniswapV2Router: INVALID_PATH');

        // validate
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        // do the wrapping so we handle ERC20-s and transfer the wrapped tokens to the first pair
        IWFTM(wFTM).deposit.value(amounts[0])();
        assert(IWFTM(wFTM).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));

        // perform the swap
        _swap(amounts, path, to);
    }

    // swapTokensForExactETH swaps specified token for exact value of native FTM tokens
    // suing pairs specified by the given swap path.
    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        // make sure the final step is the wrapped native FTM token
        require(path[path.length - 1] == wFTM, 'UniswapV2Router: INVALID_PATH');

        // validate
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');

        // transfer the input tokens to the first pair
        SafeERC20.safeTransferFrom(IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);

        // do the swap, receive output tokens
        _swap(amounts, path, address(this));

        // unwrap received tokens and send them to the real recipient
        IWFTM(wFTM).withdraw(amounts[amounts.length - 1]);
        Address.sendValue(to.toPayable(), amounts[amounts.length - 1]);
    }

    // swapExactTokensForETH swaps specified amount of input tokens for calculated
    // amount of native FTM tokens using pairs specified by the swap path.
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        // make sure the final step is the wrapped native FTM token
        require(path[path.length - 1] == wFTM, 'UniswapV2Router: INVALID_PATH');

        // validate
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        // transfer input tokens to the first pair
        SafeERC20.safeTransferFrom(IERC20(path[0]), msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);

        // do the swap
        _swap(amounts, path, address(this));

        // unwrap to native FTM and send the amount to recipient
        IWFTM(wFTM).withdraw(amounts[amounts.length - 1]);
        Address.sendValue(to.toPayable(), amounts[amounts.length - 1]);
    }

    // swapETHForExactTokens swaps native FTM tokens for exact amount of output tokens
    // using pairs specified by given uniswap path.
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint[] memory amounts) {
        // make sure the entry token is wrapped FTM
        require(path[0] == wFTM, 'UniswapV2Router: INVALID_PATH');

        // validate
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');

        // wrap incoming FTM first and than deposit to the first swap pair
        IWFTM(wFTM).deposit.value(amounts[0])();
        assert(IWFTM(wFTM).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));

        // do the swap
        _swap(amounts, path, to);

        // transfer remaining dust back to sender, if any remained
        if (msg.value > amounts[0]) {
            Address.sendValue(Address.toPayable(msg.sender), uint256(msg.value).sub(amounts[0]));
        }
    }

    // ------------------------------------------------------------
    // Library wrappers to quote/calculate input and output amounts
    // ------------------------------------------------------------

    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        return UniswapV2Library.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}