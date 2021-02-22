const factory = require('../lib/factory.js');

task(
  'deploy'
).setAction(async function () {
  const [deployer] = await ethers.getSigners();

  const pair = await factory.Pair({ deployer });
  const pool = await factory.Pool({ deployer });

  const facets = [
    await factory.DiamondCuttable({ deployer }),
    await factory.DiamondLoupe({ deployer }),
    await factory.ProxyManager({ deployer }),
    await factory.SafeOwnable({ deployer }),
  ];

  const facetCuts = [];

  facets.forEach(function (f) {
    Object.keys(f.interface.functions).forEach(function (fn) {
      facetCuts.push([
        f.address,
        f.interface.getSighash(fn),
      ]);
    });
  });

  const instance = await factory.Openhedge({
    deployer,
    facetCuts,
    pairImplementation: pair.address,
    poolImplementation: pool.address,
  });

  console.log(instance.address);
});
