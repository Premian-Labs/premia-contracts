const factory = require("../lib/factory.js");

task("deploy").setAction(async function() {
  const [deployer] = await ethers.getSigners();

  const pair = await factory.Pair({ deployer });
  const pool = await factory.Pool({ deployer });

  const facetCuts = [await factory.ProxyManager({ deployer })].map(function(f) {
    return {
      target: f.address,
      action: 0,
      selectors: Object.keys(f.interface.functions).map(fn =>
        f.interface.getSighash(fn)
      )
    };
  });

  const instance = await factory.Median({
    deployer,
    facetCuts,
    pairImplementation: pair.address,
    poolImplementation: pool.address
  });

  console.log(instance.address);
});
