import { deployMockContract } from 'ethereum-waffle';
import { describeBehaviorOfManagedProxyOwnable } from '@solidstate/spec';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { describeBehaviorOfPair } from './Pair.behavior';
import {
  Median,
  Pair,
  Pair__factory,
  ManagedProxyOwnable__factory,
  ManagedProxyOwnable,
  Pool__factory,
  ProxyManager__factory,
  Median__factory,
} from '../../typechain';

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

describe('PairProxy', function () {
  let owner: SignerWithAddress;

  let median: Median;
  let instanceProxy: ManagedProxyOwnable;
  let instancePair: Pair;

  before(async function () {
    [owner] = await ethers.getSigners();

    const pair = await new Pair__factory(owner).deploy();
    const pool = await new Pool__factory(owner).deploy(
      ethers.constants.AddressZero,
    );

    const facetCuts = [await new ProxyManager__factory(owner).deploy()].map(
      function (f) {
        return {
          target: f.address,
          action: 0,
          selectors: Object.keys(f.interface.functions).map((fn) =>
            f.interface.getSighash(fn),
          ),
        };
      },
    );

    median = await new Median__factory(owner).deploy(
      pair.address,
      pool.address,
    );

    await median.diamondCut(facetCuts, ethers.constants.AddressZero, '0x');
  });

  beforeEach(async function () {
    const manager = await ethers.getContractAt('ProxyManager', median.address);

    const erc20Factory = await ethers.getContractFactory('ERC20Mock', owner);

    const token0 = await erc20Factory.deploy(SYMBOL_BASE);
    await token0.deployed();
    const token1 = await erc20Factory.deploy(SYMBOL_UNDERLYING);
    await token1.deployed();

    const oracle0 = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    const oracle1 = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    await oracle0.mock.decimals.returns(8);
    await oracle1.mock.decimals.returns(8);

    const tx = await manager.deployPair(
      token0.address,
      token1.address,
      oracle0.address,
      oracle1.address,
    );

    const pair = (await tx.wait()).events[0].args.pair;

    instanceProxy = ManagedProxyOwnable__factory.connect(pair, owner);
    instancePair = Pair__factory.connect(pair, owner);
  });

  describeBehaviorOfManagedProxyOwnable({
    deploy: async () => instanceProxy,
    implementationFunction: 'getPools()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPair(
    {
      deploy: async () => instancePair,
    },
    [],
  );
});
