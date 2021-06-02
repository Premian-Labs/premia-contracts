import { describeBehaviorOfPair } from './Pair.behavior';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { PairMock, PairMock__factory } from '../../typechain';

describe('Pair', function () {
  let owner: SignerWithAddress;

  let instance: PairMock;

  before(async function () {
    [owner] = await ethers.getSigners();
  });

  beforeEach(async function () {
    instance = await new PairMock__factory(owner).deploy();
  });

  describeBehaviorOfPair(
    {
      deploy: async () => instance,
    },
    [],
  );
});
