import {
  Premia,
  Premia__factory,
  PoolWrite,
  PoolWrite__factory,
  ProxyManager__factory,
  OptionMath,
  OptionMath__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { describeBehaviorOfProxyManager } from './ProxyManager.behavior';
import { describeBehaviorOfDiamond } from '@solidstate/spec';

describe('Premia', function () {
  let nobody: SignerWithAddress;
  let owner: SignerWithAddress;
  let nomineeOwner: SignerWithAddress;

  let optionMath: OptionMath;
  let poolWrite: PoolWrite;

  let facetCuts: any[] = [,];

  let instance: Premia;

  before(async function () {
    [nobody, owner, nomineeOwner] = await ethers.getSigners();

    optionMath = await new OptionMath__factory(owner).deploy();
    poolWrite = await new PoolWrite__factory(
      { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
      owner,
    ).deploy(
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      ethers.constants.Zero,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
    );

    [
      await new ProxyManager__factory(owner).deploy(
        ethers.constants.AddressZero,
      ),
    ].forEach(function (f) {
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
    instance = await new Premia__factory(owner).deploy();

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
    },
    [],
  );
});
