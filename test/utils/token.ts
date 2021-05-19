import { TestErc20, WETH9 } from '../../contractsTyped';
import { TEST_TOKEN_DECIMALS, TEST_USE_WETH } from './constants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumberish } from 'ethers';
import { parseUnits } from 'ethers/lib/utils';

export function getToken(weth: WETH9, wbtc: TestErc20) {
  return TEST_USE_WETH ? weth : wbtc;
}

export async function mintTestToken(
  user: SignerWithAddress,
  token: WETH9 | TestErc20,
  amount: BigNumberish,
) {
  if (TEST_USE_WETH) {
    await (token as WETH9).connect(user).deposit({ value: amount });
  } else {
    await (token as TestErc20).connect(user).mint(user.address, amount);
  }
}

export function parseTestToken(amount: string) {
  return parseUnits(amount, TEST_TOKEN_DECIMALS);
}

export function getAmountExceedsBalanceRevertMsg() {
  return TEST_USE_WETH
    ? 'SafeERC20: low-level call failed'
    : 'ERC20: transfer amount exceeds balance';
}
