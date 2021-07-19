import { Premia } from '../../typechain';
import { ContractFactory, ethers } from 'ethers';

export async function diamondCut(
  diamond: Premia,
  contractAddress: string,
  factory: ContractFactory,
  excludeList: string[] = [],
) {
  const registeredSelectors: string[] = [];
  const facetCuts = [
    {
      target: contractAddress,
      action: 0,
      selectors: Object.keys(factory.interface.functions)
        .filter((fn) => !excludeList.includes(factory.interface.getSighash(fn)))
        .map((fn) => {
          const sl = factory.interface.getSighash(fn);
          registeredSelectors.push(sl);
          return sl;
        }),
    },
  ];

  await diamond.diamondCut(facetCuts, ethers.constants.AddressZero, '0x');

  return registeredSelectors;
}
