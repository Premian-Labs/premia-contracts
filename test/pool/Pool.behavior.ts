import {
  describeBehaviorOfERC1155Enumerable
} from '@solidstate/spec';
import { Pool } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';

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
  {
    deploy,
    mintERC1155,
    burnERC1155,
  }: PoolBehaviorArgs,
  skips?: string[],
) {
  describe('::Pool', function () {
    let instance: Pool;

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

    describe('#getPair', function () {
      it('returns pair address');
    });

    describe('#getUnderlying', function () {
      it('todo');
    });

    describe('#quote', function () {
      it('returns price for given option parameters');
    });

    describe('#deposit', function () {
      it('returns share tokens granted to sender');

      it('todo');
    });

    describe('#withdraw', function () {
      it('returns underlying tokens withdrawn by sender');

      it('todo');
    });

    describe('#purchase', function () {
      it('todo');
    });

    describe('#exercise', function () {
      describe('(uint256,uint192,uint64)', function () {
        it('todo');
      });

      describe('(uint256,uint256)', function () {
        it('todo');
      });
    });
  });
}
