import { ethers } from 'hardhat';
import { ProxyManager__factory } from '../../typechain';

function printFacets(implAddress: string, factory: any) {
  const facetCuts = [
    {
      target: implAddress,
      action: 1,
      selectors: Object.keys(factory.interface.functions).map((fn) => {
        const selector = factory.interface.getSighash(fn);
        console.log(selector, fn);

        return selector;
      }),
    },
  ];

  console.log(facetCuts);
}

async function main() {
  const [deployer] = await ethers.getSigners();

  const proxyManagerFactory = new ProxyManager__factory(deployer);

  const poolDiamond = '0x48D49466CB2EFbF05FaA5fa5E69f2984eDC8d1D7';
  const proxyManager = await proxyManagerFactory.deploy(poolDiamond);

  printFacets(proxyManager.address, proxyManagerFactory);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
