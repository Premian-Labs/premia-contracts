import { ethers } from 'hardhat';
import {
  PremiaMarket__factory,
  PremiaOption__factory,
  PremiaReferral__factory,
  PremiaUncutErc20__factory,
  PriceProvider__factory,
} from '../../contractsTyped';

async function main() {
  // We get the contract to deploy
  const dai = '0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa';
  const weth = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
  const wbtc = '';
  const rope = '0xc427c5b9be1dfd0fab70ac42f8ce52fe77a3c51e';

  const [deployer] = await ethers.getSigners();

  let uri = 'https://rope.lol/api/RMU/{id}.json';

  const premiaReferralFactory = new PremiaReferral__factory(deployer);
  const priceProviderFactory = new PriceProvider__factory(deployer);
  const premiaUncutErc20Factory = new PremiaUncutErc20__factory(deployer);
  const premiaOptionFactory = new PremiaOption__factory(deployer);
  const premiaMarketFactory = new PremiaMarket__factory(deployer);

  //

  const priceProvider = await priceProviderFactory.deploy();
  const premiaUncutErc20 = await premiaUncutErc20Factory.deploy(
    priceProvider.address,
  );

  const premiaOptionDai = await premiaOptionFactory.deploy(
    uri,
    dai,
    premiaUncutErc20.address,
    deployer.address,
  );

  console.log(
    `premiaOption dai deployed to ${premiaOptionDai.address} from ${deployer.address}`,
  );

  const premiaOptionEth = await premiaOptionFactory.deploy(
    uri,
    weth,
    premiaUncutErc20.address,
    deployer.address,
  );

  console.log(
    `premiaOption weth deployed to ${premiaOptionEth.address} from ${deployer.address}`,
  );

  // const premiaOptionWbtc = await premiaOptionFactory.deploy(
  //   uri,
  //   wbtc,
  //   premiaUncutErc20.address,
  //   deployer.address,
  // );
  //
  // console.log(
  //   `premiaOption wbtc deployed to ${premiaOptionWbtc.address} from ${deployer.address}`,
  // );

  await premiaOptionDai.setToken(
    weth,
    ethers.utils.parseEther('1'),
    ethers.utils.parseEther('10'),
    false,
  );

  console.log('WETH/DAI added');

  await premiaOptionDai.setToken(
    rope,
    ethers.utils.parseEther('1'),
    ethers.utils.parseEther('1'),
    false,
  );

  console.log('ROPE/DAI added');

  await premiaOptionEth.setToken(
    rope,
    ethers.utils.parseEther('1'),
    ethers.utils.parseEther('0.1'),
    false,
  );

  console.log('ROPE/WETH added');

  //

  const premiaReferral = await premiaReferralFactory.deploy();

  console.log(
    `premiaReferral deployed to ${premiaReferral.address} from ${deployer.address}`,
  );

  await premiaReferral.addWhitelisted([
    premiaOptionDai.address,
    premiaOptionEth.address,
    // premiaOptionWbtc.address,
  ]);

  await premiaOptionDai.setPremiaReferral(premiaReferral.address);
  await premiaOptionEth.setPremiaReferral(premiaReferral.address);
  // await premiaOptionWbtc.setPremiaReferral(premiaReferral.address);
  // await premiaOption.setPremiaStaking(premiaStaking.address);

  //

  const premiaMarket = await premiaMarketFactory.deploy(deployer.address);

  console.log(
    `premiaMarket deployed to ${premiaMarket.address} from ${deployer.address}`,
  );

  await premiaMarket.addWhitelistedOptionContracts([
    premiaOptionEth.address,
    premiaOptionDai.address,
    // premiaOptionWbtc.address,
  ]);

  await premiaMarket.addWhitelistedPaymentTokens([dai, weth]);

  await premiaUncutErc20.addMinter([
    premiaOptionEth.address,
    premiaOptionDai.address,
    premiaMarket.address,
  ]);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
