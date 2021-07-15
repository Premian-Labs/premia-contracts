import { expect } from 'chai';
import { describeBehaviorOfERC1155Enumerable } from '@solidstate/spec';
import {
  ERC20Mock,
  ERC20Mock__factory,
  Pool,
  Pool__factory,
} from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

interface PoolBehaviorArgs {
  deploy: () => Promise<Pool>;
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
    let instance: Pool;

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
      },
      skips,
    );
  });
}
