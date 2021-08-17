import { BigNumber } from 'ethers';
import { formatUnits } from 'ethers/lib/utils';

export function bnToNumber(bn: BigNumber, decimals = 18) {
  return Number(formatUnits(bn, decimals));
}
