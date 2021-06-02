import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Pair } from '../../typechain';

interface PairBehaviorArgs {
  deploy: () => Promise<Pair>;
}

export function describeBehaviorOfPair(
  { deploy }: PairBehaviorArgs,
  skips?: string[],
) {
  describe('::Pool', function () {
    let instance;

    beforeEach(async function () {
      instance = await ethers.getContractAt('Pool', (await deploy()).address);
    });

    describe('#getPools', function () {
      it('returns pool addresses');
    });

    describe('#getVariance', function () {
      it('todo');
    });

    describe('#update', function () {
      it('todo');
    });
  });
}
