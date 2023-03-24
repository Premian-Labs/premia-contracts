// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IUniswapV3Factory} from "../vendor/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../vendor/uniswap/IUniswapV3Pool.sol";
import {OracleLibrary} from "../vendor/uniswap/OracleLibrary.sol";
import {PoolAddress} from "../vendor/uniswap/PoolAddress.sol";

import {IChainlinkWrapperInternal} from "./IChainlinkWrapperInternal.sol";
import {ChainlinkWrapperStorage} from "./ChainlinkWrapperStorage.sol";

contract ChainlinkWrapperInternal is IChainlinkWrapperInternal {
    using SafeCast for int256;
    using SafeCast for uint256;
    using ChainlinkWrapperStorage for ChainlinkWrapperStorage.Layout;

    IUniswapV3Factory internal immutable UNISWAP_V3_FACTORY;
    AggregatorV3Interface internal immutable TOKEN_OUT_USD_ORACLE;

    uint32 internal constant PERIOD = 10 minutes;

    address internal immutable TOKEN_IN;
    address internal immutable TOKEN_OUT;

    /// @dev init bytecode from the deployed version of Uniswap V3 Pool contract
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    constructor(
        IUniswapV3Factory uniswapV3Factory,
        AggregatorV3Interface tokenOutUSDOracle,
        address tokenIn,
        address tokenOut
    ) {
        UNISWAP_V3_FACTORY = uniswapV3Factory;
        TOKEN_OUT_USD_ORACLE = tokenOutUSDOracle;

        TOKEN_IN = tokenIn;
        TOKEN_OUT = tokenOut;
    }

    function _quote() internal view returns (int256) {
        address[] memory pools = _getAllPoolsForPair(TOKEN_IN, TOKEN_OUT);
        int24 weightedTick = _fetchWeightedTick(pools, PERIOD);

        int8 tokenOutOracleDecimals = int8(TOKEN_OUT_USD_ORACLE.decimals());
        int256 factor = tokenOutOracleDecimals - int8(_decimals(TOKEN_OUT));

        // scale quote in tokenOut ERC20 decimals to tokenOut oracle decimals
        uint256 tokenInTokenOut = _scale(
            OracleLibrary.getQuoteAtTick(
                weightedTick,
                uint128(10 ** _decimals(TOKEN_IN)),
                TOKEN_IN,
                TOKEN_OUT
            ),
            factor
        );

        // scale tokenInTokenOut * answer to tokenOut oracle decimals
        int256 price = _scale(
            // tokenIn/tokenOut * tokenOut/USD -> tokenIn/USD
            tokenInTokenOut * _latestAnswer().toUint256(),
            int256(-tokenOutOracleDecimals)
        ).toInt256();

        _ensurePricePositive(price);
        return price;
    }

    function _getAllPoolsForPair(
        address tokenA,
        address tokenB
    ) internal view returns (address[] memory pools) {
        ChainlinkWrapperStorage.Layout storage l = ChainlinkWrapperStorage
            .layout();

        uint24[] memory feeTiers = l.feeTiers;

        pools = new address[](feeTiers.length);
        uint256 validPools;

        for (uint256 i; i < feeTiers.length; i++) {
            address pool = _computeAddress(
                address(UNISWAP_V3_FACTORY),
                PoolAddress.getPoolKey(tokenA, tokenB, feeTiers[i])
            );

            if (AddressUtils.isContract(pool) && _isUnlocked(pool)) {
                pools[validPools++] = pool;
            }
        }

        _resizeArray(pools, validPools);
    }

    function _fetchWeightedTick(
        address[] memory pools,
        uint32 period
    ) internal view returns (int24) {
        OracleLibrary.WeightedTickData[]
            memory tickData = new OracleLibrary.WeightedTickData[](
                pools.length
            );

        for (uint256 i; i < pools.length; i++) {
            (tickData[i].tick, tickData[i].weight) = OracleLibrary.consult(
                pools[i],
                period
            );
        }

        return
            tickData.length == 1
                ? tickData[0].tick
                : OracleLibrary.getWeightedArithmeticMeanTick(tickData);
    }

    function _latestAnswer() internal view returns (int256) {
        try TOKEN_OUT_USD_ORACLE.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        ) {
            return answer;
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory data) {
            revert ChainlinkWrapper__LatestRoundDataCallReverted(data);
        }
    }

    function _scale(
        uint256 amount,
        int256 factor
    ) internal pure returns (uint256) {
        if (factor < 0) {
            return amount / (10 ** (-factor).toUint256());
        } else {
            return amount * (10 ** factor.toUint256());
        }
    }

    function _ensurePricePositive(int256 price) internal pure {
        if (price <= 0) revert ChainlinkWrapper__NonPositivePrice(price);
    }

    function _decimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    function _isUnlocked(address pool) internal view returns (bool unlocked) {
        (, , , , , , unlocked) = IUniswapV3Pool(pool).slot0();
    }

    function _resizeArray(address[] memory array, uint256 size) internal pure {
        if (array.length == size) return;
        if (array.length < size) revert ChainlinkWrapper__ArrayCannotExpand();

        assembly {
            mstore(array, size)
        }
    }

    /// @dev https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/PoolAddress.sol#L33-L47
    ///      This function uses the POOL_INIT_CODE_HASH from the deployed version of Uniswap V3 Pool contract
    function _computeAddress(
        address factory,
        PoolAddress.PoolKey memory key
    ) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encode(key.token0, key.token1, key.fee)
                            ),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
