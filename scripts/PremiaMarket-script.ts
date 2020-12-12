import { ethers } from 'hardhat';
import {
  PremiaErc20__factory,
  PremiaMarket__factory,
  PremiaOption__factory,
  TestErc20__factory,
  TestPremiaOption__factory,
} from '../contractsTyped';
import { PremiaOptionTestUtil } from '../test/utils/PremiaOptionTestUtil';

async function main() {
  // We get the contract to deploy
  const daiAddress = '0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa';
  const wethAddress = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
  const ropeAddress = '0xc427c5b9be1dfd0fab70ac42f8ce52fe77a3c51e';

  const [deployer] = await ethers.getSigners();

  const premiaMarketFactory = new PremiaMarket__factory(deployer);
  const premiaMarket = await premiaMarketFactory.deploy(
    deployer.address,
    wethAddress,
  );
  // const premiaMarket = await PremiaMarket__factory.connect(
  //   '0x13f8A7AE5426239ecDDcCf4f622aA233d4cA33B0',
  //   deployer,
  // );

  // await premiaOption.deployed();
  console.log(
    `premiaMarket deployed to ${premiaMarket.address} from ${deployer.address}`,
  );

  // const weth = PremiaErc20__factory.connect(wethAddress, deployer);
  // const dai = PremiaErc20__factory.connect(daiAddress, deployer);
  // const rope = PremiaErc20__factory.connect(ropeAddress, deployer);
  // const premiaOptionWeth = PremiaOption__factory.connect(
  //   '0x49293cFed5BF22e9a0b3850711d4cE73299A40f7',
  //   deployer,
  // );

  // await premiaMarket.addWhitelistedOptionContracts([premiaOptionWeth.address]);
  // await premiaOptionWeth.setApprovalForAll(premiaMarket.address, true);
  // const balance = await premiaOptionWeth.balanceOf(deployer.address, 1);
  // console.log('Balance', balance);
  //
  // const tx = await premiaMarket.createOrder(
  //   '0x0000000000000000000000000000000000000000',
  //   1,
  //   premiaOptionWeth.address,
  //   1,
  //   2,
  //   ethers.utils.parseEther('1'),
  // );
  //
  // console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
