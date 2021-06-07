import { BigNumber, BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { formatEther, parseEther } from 'ethers/lib/utils';

export function fixedFromBigNumber(bn: BigNumber) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
}

export function fixedFromFloat(float: BigNumberish) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(ethers.BigNumber.from(`${integer}${decimal}`)).div(
    ethers.BigNumber.from(`1${'0'.repeat(decimal.length)}`),
  );
}

export function bnToNumber(bn: BigNumber) {
  return Number(formatEther(bn));
}

export function fixedToDecimals(fixed: BigNumber, decimals: BigNumberish) {
  return fixed.mul(parseEther(decimals.toString())).shr(64);
}

export function fixedToNumber(fixed: BigNumber) {
  const integer = fixed.shr(64);
  const decimals = fixed.sub(integer.shl(64));

  const decimalsNumber = decimals.mul(1e10).div(BigNumber.from(1).shl(64));

  return Number(integer) + Number(decimalsNumber) / 1e10;
}
