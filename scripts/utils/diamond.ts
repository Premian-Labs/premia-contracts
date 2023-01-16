import { Premia } from '../../typechain';
import { ContractFactory, ethers } from 'ethers';

export async function diamondCut(
  diamond: Premia,
  target: string,
  factory: ContractFactory,
  excludeList: string[] = [],
  action: number = 0,
) {
  const selectors =
     Object.keys(factory.interface.functions)
           .map(factory.interface.getSighash)
           .filter(hash => !excludeList.includes(hash))

  const tx = await diamond.diamondCut(
    [{ target, action, selectors }],
    ethers.constants.AddressZero,
    '0x',
  );
  await tx.wait(1);

  return registeredSelectors;
}
