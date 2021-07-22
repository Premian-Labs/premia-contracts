import { describeBehaviorOfERC1155Enumerable } from '@solidstate/spec';
import { PoolInternal } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

interface PoolBehaviorArgs {
  deploy: () => Promise<PoolInternal>;
  mintERC1155: (
    address: string,
    id: BigNumber,
    amount: BigNumber,
  ) => Promise<ContractTransaction>;
  burnERC1155: (
    address: string,
    id: BigNumber,
    amount: BigNumber,
  ) => Promise<ContractTransaction>;
}

export function describeBehaviorOfPool(
  { deploy, mintERC1155, burnERC1155 }: PoolBehaviorArgs,
  skips?: string[],
) {
  describe('::Pool', function () {
    let deployer: SignerWithAddress;
    let instance: PoolInternal;

    before(async () => {
      [deployer] = await ethers.getSigners();
    });

    beforeEach(async function () {
      instance = await deploy();
    });

    describeBehaviorOfERC1155Enumerable(
      {
        deploy: async () => instance,
        mint: mintERC1155,
        burn: burnERC1155,
        tokenId: BigNumber.from('1'),
      },
      skips,
    );
  });
}
