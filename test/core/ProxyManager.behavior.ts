import { ProxyManager } from '../../typechain';
import { expect } from 'chai';

interface ProxyBehaviorArgs {
  deploy: () => Promise<ProxyManager>;
  getPairImplementationAddress: () => string;
  getPoolImplementationAddress: () => string;
}

export function describeBehaviorOfProxyManager(
  {
    deploy,
    getPairImplementationAddress,
    getPoolImplementationAddress,
  }: ProxyBehaviorArgs,
  skips?: string[],
) {
  describe('::ProxyManager', function () {
    let instance: ProxyManager;

    beforeEach(async function () {
      instance = await deploy();
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
        expect(await instance.callStatic.getPairImplementation()).to.equal(
          getPairImplementationAddress(),
        );
      });
    });

    describe('#getPoolImplementation', function () {
      it('returns address of pool implementation', async function () {
        expect(await instance.callStatic.getPoolImplementation()).to.equal(
          getPoolImplementationAddress(),
        );
      });
    });
  });
}
