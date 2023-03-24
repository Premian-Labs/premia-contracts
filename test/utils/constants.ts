export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
export const ONE_ADDRESS = '0x0000000000000000000000000000000000000001';
export const CHAINLINK_USD = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

export const ONE_WEEK = 7 * 24 * 3600;

// Set TEST_USE_WETH to false and TEST_TOKEN_DECIMALS to 8 to run tests using WBTC (8 decimals)
export const TEST_USE_WETH = true;
// If TEST_USE_WETH is true, TEST_TOKEN_DECIMALS should be always 18
export const TEST_TOKEN_DECIMALS = TEST_USE_WETH ? 18 : 8;
