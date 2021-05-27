import { ProxyManager, ProxyManager__factory } from '../../typechain';
import { expect } from 'chai';
import { ethers } from 'hardhat';

interface ProxyBehaviorArgs {
  deploy: any;
  getPairImplementationAddress: () => string;
  getPoolImplementationAddress: () => string;
}

export function describeBehaviorOfProxyManager(
  {
    deploy,
    getPairImplementationAddress,
    getPoolImplementationAddress,
  }: ProxyBehaviorArgs,
  skips: any[],
) {
  describe('::ProxyManager', function () {
    let instance: ProxyManager;

    beforeEach(async function () {
      const [deployer] = await ethers.getSigners();
      instance = await new ProxyManager__factory(deployer).deploy();
    });

    describe('#getPair', function () {
      it('todo');
    });

    describe('#deployPair', function () {
      it('todo');

      describe('reverts if', function () {
        it('todo');
      });
    });

    describe('#getPairImplementation', function () {
      it('returns address of pair implementation', async function () {
        console.log(
          await instance.callStatic.getPairImplementation(),
          getPairImplementationAddress(),
        );
        expect(await instance.callStatic.getPairImplementation()).to.equal(
          getPairImplementationAddress(),
        );
      });
    });

    describe('#getPoolImplementation', function () {
      it('returns address of pool implementation', async function () {
        console.log(
          await instance.callStatic.getPoolImplementation(),
          getPoolImplementationAddress(),
        );
        expect(await instance.callStatic.getPoolImplementation()).to.equal(
          getPoolImplementationAddress(),
        );
      });
    });
  });
}
