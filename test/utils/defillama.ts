import { ethers } from 'hardhat';
import { BigNumber, utils } from 'ethers';

import axios from 'axios';
import { expect } from 'chai';

import { CHAINLINK_USD } from './constants';

export const getPrice = async (
  network: string,
  coin: string,
  timestamp?: number,
): Promise<number> => {
  const { price } = await getTokenData(network, coin, timestamp);
  return price;
};

export const getTokenData = async (
  network: string,
  coin: string,
  timestamp?: number,
): Promise<{ price: number; decimals: number }> => {
  const coinId = `${network}:${coin.toLowerCase()}`;
  const response = await axios.post('https://coins.llama.fi/prices', {
    coins: [coinId],
    timestamp,
  });

  const { coins } = response.data;

  return coins[coinId];
};

export const convertPriceToBigNumberWithDecimals = (
  price: number,
  decimals: number,
): BigNumber => {
  return utils.parseUnits(price.toFixed(decimals), decimals);
};

export const convertPriceToNumberWithDecimals = (
  price: number,
  decimals: number,
): number => {
  return convertPriceToBigNumberWithDecimals(price, decimals).toNumber();
};

export function validateQuote(
  percentage: number,
  quote: BigNumber,
  expected: BigNumber,
) {
  const threshold = expected.mul(percentage * 10).div(100 * 10);
  const [upperThreshold, lowerThreshold] = [
    expected.add(threshold),
    expected.sub(threshold),
  ];
  const diff = quote.sub(expected);
  const sign = diff.isNegative() ? '-' : '+';
  const diffPercentage = diff.abs().mul(10000).div(expected).toNumber() / 100;

  expect(
    quote.lte(upperThreshold) && quote.gte(lowerThreshold),
    `Expected ${quote.toString()} to be within [${lowerThreshold.toString()},${upperThreshold.toString()}]. Diff was ${sign}${diffPercentage}%`,
  ).to.be.true;
}

export async function getPriceBetweenTokens(
  networks: { tokenIn: string; tokenOut: string },
  tokenIn: string,
  tokenOut: string,
  target: number = 0,
) {
  if (tokenIn === CHAINLINK_USD) {
    return 1 / (await fetchPrice(networks.tokenOut, tokenOut, target));
  }
  if (tokenOut === CHAINLINK_USD) {
    return await fetchPrice(networks.tokenIn, tokenIn, target);
  }

  let tokenInPrice = await fetchPrice(networks.tokenIn, tokenIn, target);
  let tokenOutPrice = await fetchPrice(networks.tokenOut, tokenOut, target);

  return tokenInPrice / tokenOutPrice;
}

let cache: { [address: string]: { [target: number]: number } } = {};

export async function fetchPrice(
  network: string,
  address: string,
  target: number = 0,
): Promise<number> {
  if (!cache[address]) cache[address] = {};
  if (!cache[address][target]) {
    if (target == 0)
      target = await (await ethers.provider.getBlock('latest')).timestamp;
    const price = await getPrice(network, address, target);
    cache[address][target] = price;
  }
  return cache[address][target];
}
