import {
  Median,
  Median__factory,
  Pair,
  Pair__factory,
  Pool,
  Pool__factory,
  ProxyManager__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { describeBehaviorOfProxyManager } from './ProxyManager.behavior';
import { describeBehaviorOfDiamond } from '@solidstate/spec';

describe('Median', function () {
  let nobody: SignerWithAddress;
  let owner: SignerWithAddress;
  let nomineeOwner: SignerWithAddress;

  let pair: Pair;
  let pool: Pool;

  let facetCuts: any[] = [,];

  let instance: Median;

  before(async function () {
    [nobody, owner, nomineeOwner] = await ethers.getSigners();

    pair = await new Pair__factory(owner).deploy();
    pool = await new Pool__factory(owner).deploy(ethers.constants.AddressZero);

    [await new ProxyManager__factory(owner).deploy()].forEach(function (f) {
      facetCuts.push({
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions).map((fn) =>
          f.interface.getSighash(fn),
        ),
      });
    });
  });

  beforeEach(async function () {
    instance = await new Median__factory(owner).deploy(
      pair.address,
      pool.address,
    );

    await instance.diamondCut(
      facetCuts.slice(1),
      ethers.constants.AddressZero,
      '0x',
    );

    facetCuts[0] = {
      target: instance.address,
      action: 0,
      selectors: await instance.callStatic.facetFunctionSelectors(
        instance.address,
      ),
    };
  });

  describeBehaviorOfDiamond(
    {
      deploy: async () => instance,
      getOwner: async () => owner,
      getNomineeOwner: async () => nomineeOwner,
      getNonOwner: async () => nobody,
      facetCuts,
      fallbackAddress: ethers.constants.AddressZero,
    },
    [],
  );

  describeBehaviorOfProxyManager(
    {
      deploy: async () =>
        ProxyManager__factory.connect(instance.address, owner),
      getPairImplementationAddress: () => pair.address,
      getPoolImplementationAddress: () => pool.address,
    },
    [],
  );
});
