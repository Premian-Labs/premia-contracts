import { ProxyManager } from '../../typechain';
import { expect } from 'chai';

interface ProxyBehaviorArgs {
  deploy: () => Promise<ProxyManager>;
}

export function describeBehaviorOfProxyManager(
  { deploy }: ProxyBehaviorArgs,
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
  });
}
