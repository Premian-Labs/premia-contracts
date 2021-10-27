// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";

import {IWETH} from "@solidstate/contracts/utils/IWETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {PoolInternal} from "./PoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
abstract contract PoolSwap is PoolInternal {
    using SafeERC20 for IERC20;
    using ABDKMath64x64 for int128;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable UNISWAP_V2_FACTORY;
    address internal immutable SUSHISWAP_FACTORY;

    constructor(
        address ivolOracle,
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64,
        address uniswapV2Factory,
        address sushiswapFactory
    )
        PoolInternal(
            ivolOracle,
            weth,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            fee64x64
        )
    {
        UNISWAP_V2_FACTORY = uniswapV2Factory;
        SUSHISWAP_FACTORY = sushiswapFactory;
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function _pairFor(
        address factory,
        address tokenA,
        address tokenB,
        bool isSushi
    ) internal pure returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            isSushi
                                ? hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303"
                                : hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function _sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    // performs chained getAmountIn calculations on any number of pairs
    function _getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path,
        bool isSushi
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(
                factory,
                path[i - 1],
                path[i],
                isSushi
            );
            amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    // fetches and sorts the reserves for a pair
    function _getReserves(
        address factory,
        address tokenA,
        address tokenB,
        bool isSushi
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(
            _pairFor(factory, tokenA, tokenB, isSushi)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to,
        bool isSushi
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? _pairFor(
                    isSushi ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY,
                    output,
                    path[i + 2],
                    isSushi
                )
                : _to;
            IUniswapV2Pair(
                _pairFor(
                    isSushi ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY,
                    input,
                    output,
                    isSushi
                )
            ).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function _swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        bool isSushi
    ) internal returns (uint256[] memory amounts) {
        amounts = _getAmountsIn(
            isSushi ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY,
            amountOut,
            path,
            isSushi
        );
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            _pairFor(
                isSushi ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY,
                path[0],
                path[1],
                isSushi
            ),
            amounts[0]
        );
        _swap(amounts, path, msg.sender, isSushi);
    }

    function _swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        bool isSushi
    ) internal returns (uint256[] memory amounts) {
        require(path[0] == WETH_ADDRESS, "UniswapV2Router: INVALID_PATH");
        amounts = _getAmountsIn(
            isSushi ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY,
            amountOut,
            path,
            isSushi
        );
        require(
            amounts[0] <= msg.value,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        IWETH(WETH_ADDRESS).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH_ADDRESS).transfer(
                _pairFor(
                    isSushi ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY,
                    path[0],
                    path[1],
                    isSushi
                ),
                amounts[0]
            )
        );

        _swap(amounts, path, msg.sender, isSushi);

        // refund dust eth, if any
        if (msg.value > amounts[0]) {
            (bool success, ) = payable(msg.sender).call{
                value: msg.value - amounts[0]
            }(new bytes(0));
            require(
                success,
                "TransferHelper::safeTransferETH: ETH transfer failed"
            );
        }
    }
}
