import { Premia } from '../../typechain';
import { ContractFactory, ethers } from 'ethers';

export async function diamondCut(
  diamond: Premia,
  contractAddress: string,
  factory: ContractFactory,
  excludeList: string[] = [],
  action: number = 0,
) {
  const registeredSelectors: string[] = [];
  const facetCuts = [
    {
      target: contractAddress,
      action: action,
      selectors: Object.keys(factory.interface.functions)
        .filter((fn) => !excludeList.includes(factory.interface.getSighash(fn)))
        .map((fn) => {
          const sl = factory.interface.getSighash(fn);
          registeredSelectors.push(sl);
          return sl;
        }),
    },
  ];

  const tx = await diamond.diamondCut(
    facetCuts,
    ethers.constants.AddressZero,
    '0x',
  );
  await tx.wait(1);

  return registeredSelectors;
}
