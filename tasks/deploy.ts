import { task } from 'hardhat/config';

task('deploy').setAction(async function (args, hre) {
  const {
    Premia__factory,
    Pair__factory,
    Pool__factory,
    ProxyManager__factory,
  } = require('../typechain');

  const [deployer] = await hre.ethers.getSigners();

  const pair = await new Pair__factory(deployer).deploy();
  const pool = await new Pool__factory(deployer).deploy(
    hre.ethers.constants.AddressZero,
  );

  const facetCuts = [await new ProxyManager__factory(deployer).deploy()].map(
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

  const instance = await new Premia__factory(deployer).deploy(
    pair.address,
    pool.address,
  );

  await instance.diamondCut(facetCuts, hre.ethers.constants.AddressZero, '0x');
});
