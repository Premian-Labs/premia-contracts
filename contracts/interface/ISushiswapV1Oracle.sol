// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './IKeep3rV1.sol';
import './WETH9.sol';
import './ISushiswapV2Router.sol';

interface ISushiswapV1Oracle {
    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    function pairs() external view returns (address[] memory);
    function observations(address token) external view returns (Observation[] memory);
    function observationLength(address pair) external view returns (uint);
    
    function pairFor(address tokenA, address tokenB) external pure returns (address);
    
    function pairForWETH(address tokenA) external pure returns (address);
    function updatePair(address pair) external returns (bool);
    function update(address tokenA, address tokenB) external returns (bool);
    function add(address tokenA, address tokenB) external;
    
    function lastObservation(address pair) external view returns (Observation memory);
    function updateFor(uint i, uint length) external returns (bool updated);
    function current(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);
    function quote(address tokenIn, uint amountIn, address tokenOut, uint granularity) external view returns (uint amountOut);
    
    function prices(address tokenIn, uint amountIn, address tokenOut, uint points) external view returns (uint[] memory);
    function sample(address tokenIn, uint amountIn, address tokenOut, uint points, uint window) external view returns (uint[] memory);
    function hourly(address tokenIn, uint amountIn, address tokenOut, uint points) external view returns (uint[] memory);
    function daily(address tokenIn, uint amountIn, address tokenOut, uint points) external view returns (uint[] memory);
    function weekly(address tokenIn, uint amountIn, address tokenOut, uint points) external view returns (uint[] memory);
    function realizedVolatility(address tokenIn, uint amountIn, address tokenOut, uint points, uint window) external view returns (uint);
    function realizedVolatilityHourly(address tokenIn, uint amountIn, address tokenOut) external view returns (uint);
    function realizedVolatilityDaily(address tokenIn, uint amountIn, address tokenOut) external view returns (uint);
    function realizedVolatilityWeekly(address tokenIn, uint amountIn, address tokenOut) external view returns (uint);
    
    /**
     * @dev sqrt calculates the square root of a given number x
     * @dev for precision into decimals the number must first
     * @dev be multiplied by the precision factor desired
     * @param x uint256 number for the calculation of square root
     */
    function sqrt(uint256 x) external pure returns (uint256);
    
    /**
     * @dev stddev calculates the standard deviation for an array of integers
     * @dev precision is the same as sqrt above meaning for higher precision
     * @dev the decimal place must be moved prior to passing the params
     * @param numbers uint[] array of numbers to be used in calculation
     */
    function stddev(uint[] memory numbers) external pure returns (uint256 sd);
    
    
    /**
     * @dev blackScholesEstimate calculates a rough price estimate for an ATM option
     * @dev input parameters should be transformed prior to being passed to the function
     * @dev so as to remove decimal places otherwise results will be far less accurate
     * @param _vol uint256 volatility of the underlying converted to remove decimals
     * @param _underlying uint256 price of the underlying asset
     * @param _time uint256 days to expiration in years multiplied to remove decimals
     */
    function blackScholesEstimate(
        uint256 _vol,
        uint256 _underlying,
        uint256 _time
    ) external pure returns (uint256 estimate);
    
    /**
     * @dev fromReturnsBSestimate first calculates the stddev of an array of price returns
     * @dev then uses that as the volatility param for the blackScholesEstimate
     * @param _numbers uint256[] array of price returns for volatility calculation
     * @param _underlying uint256 price of the underlying asset
     * @param _time uint256 days to expiration in years multiplied to remove decimals
     */
    function retBasedBlackScholesEstimate(
        uint256[] memory _numbers,
        uint256 _underlying,
        uint256 _time
    ) external pure;
    
    receive() external payable;
}