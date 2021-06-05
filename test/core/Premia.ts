import {
  Premia,
  Premia__factory,
  Pool,
  Pool__factory,
  ProxyManager__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { describeBehaviorOfProxyManager } from './ProxyManager.behavior';
import { describeBehaviorOfDiamond } from '@solidstate/spec';

describe('Premia', function () {
  let nobody: SignerWithAddress;
  let owner: SignerWithAddress;
  let nomineeOwner: SignerWithAddress;

  let pool: Pool;

  let facetCuts: any[] = [,];

  let instance: Premia;

  before(async function () {
    [nobody, owner, nomineeOwner] = await ethers.getSigners();

    // TODO: pass PremiaMaker proxy address instead of zero address
    pool = await new Pool__factory(owner).deploy(
      ethers.constants.AddressZero,
      ethers.constants.AddressZero
    );

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
    instance = await new Premia__factory(owner).deploy(pool.address);

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
      getPoolImplementationAddress: () => pool.address,
    },
    [],
  );
});
