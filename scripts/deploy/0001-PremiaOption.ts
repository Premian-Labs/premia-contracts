import { ethers } from 'hardhat';
import {
  PremiaMarket__factory,
  PremiaOption__factory,
} from '../../contractsTyped';
import { deployContracts } from '../deployContracts';
import { parseEther } from 'ethers/lib/utils';

async function main() {
  // We get the contract to deploy
  const dai = '0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa';
  const weth = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
  const wbtc = '';
  const rope = '0xc427c5b9be1dfd0fab70ac42f8ce52fe77a3c51e';

  const [deployer] = await ethers.getSigners();

  let uri = 'https://rope.lol/api/RMU/{id}.json';

  const premiaOptionFactory = new PremiaOption__factory(deployer);
  const premiaMarketFactory = new PremiaMarket__factory(deployer);

  //

  const contracts = await deployContracts(deployer);

  Object.keys(contracts).forEach((k) => {
    console.log(`${k} : ${(contracts as any)[k]}`);
  });

  const premiaOptionDai = await premiaOptionFactory.deploy(
    uri,
    dai,
    contracts.premiaUncutErc20.address,
    contracts.feeCalculator.address,
    contracts.premiaReferral.address,
    deployer.address,
  );

  console.log(
    `premiaOption dai deployed at ${premiaOptionDai.address} from ${deployer.address}`,
  );

  const premiaOptionEth = await premiaOptionFactory.deploy(
    uri,
    weth,
    contracts.premiaUncutErc20.address,
    contracts.feeCalculator.address,
    contracts.premiaReferral.address,
    deployer.address,
  );

  console.log(
    `premiaOption weth deployed at ${premiaOptionEth.address} from ${deployer.address}`,
  );

  // const premiaOptionWbtc = await premiaOptionFactory.deploy(
  //   uri,
  //   wbtc,
  //   premiaUncutErc20.address,
  //   feeCalculator.address,
  //   deployer.address,
  // );
  //
  // console.log(
  //   `premiaOption wbtc deployed at ${premiaOptionWbtc.address} from ${deployer.address}`,
  // );

  await premiaOptionDai.setToken(
    weth,
    parseEther('1'),
    parseEther('10'),
    false,
  );

  console.log('WETH/DAI added');

  await premiaOptionDai.setToken(rope, parseEther('1'), parseEther('1'), false);

  console.log('ROPE/DAI added');

  await premiaOptionEth.setToken(
    rope,
    parseEther('1'),
    parseEther('0.1'),
    false,
  );

  console.log('ROPE/WETH added');

  //

  await contracts.premiaReferral.addWhitelisted([
    premiaOptionDai.address,
    premiaOptionEth.address,
    // premiaOptionWbtc.address,
  ]);

  await premiaOptionDai.setPremiaReferral(contracts.premiaReferral.address);
  await premiaOptionEth.setPremiaReferral(contracts.premiaReferral.address);
  // await premiaOptionWbtc.setPremiaReferral(premiaReferral.address);
  // await premiaOption.setPremiaStaking(premiaStaking.address);

  //

  const premiaMarket = await premiaMarketFactory.deploy(
    contracts.premiaUncutErc20.address,
    contracts.feeCalculator.address,
    deployer.address,
  );

  console.log(
    `premiaMarket deployed at ${premiaMarket.address} from ${deployer.address}`,
  );

  await premiaMarket.addWhitelistedOptionContracts([
    premiaOptionEth.address,
    premiaOptionDai.address,
    // premiaOptionWbtc.address,
  ]);

  await premiaMarket.addWhitelistedPaymentTokens([dai, weth]);

  await contracts.premiaUncutErc20.addMinter([
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
