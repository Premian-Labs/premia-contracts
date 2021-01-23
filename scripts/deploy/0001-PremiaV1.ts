import { ethers } from 'hardhat';
import {
  PremiaDevFund__factory,
  PremiaMarket__factory,
  PremiaOption__factory,
  PremiaVesting__factory,
} from '../../contractsTyped';
import { BigNumberish } from 'ethers';
import { deployContracts } from '../deployContracts';
import { parseEther } from 'ethers/lib/utils';
import { ZERO_ADDRESS } from '../../test/utils/constants';

async function main() {
  const isTestnet = true;
  const [deployer] = await ethers.getSigners();

  let dai: string;
  let weth: string;
  let wbtc: string;
  let treasury: string;
  let tokens: { [addr: string]: BigNumberish } = {};
  let uniswapRouters = [
    '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F', // SushiSwap router
    '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap router
  ];

  let founder1 = ZERO_ADDRESS;
  let founder2 = ZERO_ADDRESS;
  let founder3 = ZERO_ADDRESS;
  let founder4 = ZERO_ADDRESS;

  if (isTestnet) {
    dai = '0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa';
    weth = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
    wbtc = '0x577D296678535e4903D59A4C929B718e1D575e0A';
    treasury = deployer.address;

    tokens[weth] = parseEther('10');
    tokens[wbtc] = parseEther('1000');
  } else {
    dai = '0x6b175474e89094c44da98b954eedeac495271d0f';
    weth = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
    wbtc = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';
    treasury = '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0 ';

    // ToDo : Add final list of token list

    if (!Object.keys(tokens).length) {
      throw new Error('Token list not set');
    }

    if (
      founder1 == ZERO_ADDRESS ||
      founder2 == ZERO_ADDRESS ||
      founder3 == ZERO_ADDRESS ||
      founder4 == ZERO_ADDRESS
    ) {
      throw new Error('Founder wallet addresses not set');
    }
  }

  let uri = 'https://premia.finance/api/dai/{id}.json';

  //

  const contracts = await deployContracts(deployer, treasury, isTestnet, true);

  //

  const premiaOptionDai = await new PremiaOption__factory(deployer).deploy(
    uri,
    dai,
    contracts.uPremia.address,
    contracts.feeCalculator.address,
    contracts.premiaReferral.address,
    treasury,
  );

  console.log(
    `premiaOption dai deployed at ${premiaOptionDai.address} (Args : ${uri} / ${dai} / ${contracts.uPremia.address} / 
    ${contracts.feeCalculator.address} / ${contracts.premiaReferral.address} / ${treasury})`,
  );

  //

  const tokenAddresses: string[] = [];
  const tokenStrikeIncrements: BigNumberish[] = [];

  Object.keys(tokens).forEach((k) => {
    tokenAddresses.push(k);
    tokenStrikeIncrements.push(tokens[k]);
  });

  await premiaOptionDai.setTokens(tokenAddresses, tokenStrikeIncrements);

  console.log('Tokens for DAI options added');

  //

  await contracts.premiaFeeDiscount.setStakeLevels([
    { amount: parseEther('5000'), discount: 2500 }, // -25%
    { amount: parseEther('50000'), discount: 5000 }, // -50%
    { amount: parseEther('250000'), discount: 7500 }, // -75%
    { amount: parseEther('500000'), discount: 9500 }, // -95%
  ]);
  console.log('Added PremiaFeeDiscount stake levels');

  const oneMonth = 30 * 24 * 3600;
  await contracts.premiaFeeDiscount.setStakePeriod(oneMonth, 10000);
  await contracts.premiaFeeDiscount.setStakePeriod(3 * oneMonth, 12500);
  await contracts.premiaFeeDiscount.setStakePeriod(6 * oneMonth, 15000);
  await contracts.premiaFeeDiscount.setStakePeriod(12 * oneMonth, 20000);
  console.log('Added premiaFeeDiscount stake periods');

  await contracts.premiaReferral.addWhitelisted([
    premiaOptionDai.address,
    // premiaOptionEth.address,
    // premiaOptionWbtc.address,
  ]);
  console.log('Whitelisted PremiaOption on PremiaReferral');

  //

  const premiaMarket = await new PremiaMarket__factory(deployer).deploy(
    contracts.uPremia.address,
    contracts.feeCalculator.address,
    treasury,
  );

  console.log(
    `premiaMarket deployed at ${premiaMarket.address} (Args : ${contracts.uPremia.address} / ${contracts.feeCalculator.address} / ${treasury})`,
  );

  await premiaMarket.addWhitelistedOptionContracts([
    // premiaOptionEth.address,
    premiaOptionDai.address,
    // premiaOptionWbtc.address,
  ]);

  console.log('Whitelisted dai premiaOption contract on PremiaMarket');

  await premiaOptionDai.setWhitelistedUniswapRouters(uniswapRouters);
  console.log('Whitelisted uniswap routers on PremiaOption Dai');

  await contracts.premiaMaker.addWhitelistedRouter(uniswapRouters);
  console.log('Whitelisted uniswap routers on PremiaMaker');

  await contracts.uPremia.addWhitelisted([
    premiaMarket.address,
    contracts.premiaMining.address,
  ]);
  console.log('Whitelisted PremiaMarket and PremiaMining on uPremia');

  await premiaMarket.addWhitelistedPaymentTokens([dai]);
  console.log('Added dai as market payment token');

  await contracts.uPremia.addMinter([
    // premiaOptionEth.address,
    premiaOptionDai.address,
    premiaMarket.address,
  ]);
  console.log('Added premiaOption dai and premiaMarket as uPremia minters');

  await contracts.premiaMining.add(1e4, contracts.uPremia.address, false);
  console.log('Added uPremia mining pool on PremiaMining');

  // DevFund contract
  const devFund = await new PremiaDevFund__factory(deployer).deploy(
    contracts.premia.address,
  );
  console.log(
    `PremiaDevFund deployed at ${devFund.address} (Args : ${contracts.premia.address})`,
  );

  // Founder vesting contracts
  if (!isTestnet) {
    for (const founder of [founder1, founder2, founder3, founder4]) {
      const vestingContract = await new PremiaVesting__factory(deployer).deploy(
        contracts.premia.address,
      );

      console.log(
        `Vesting contract for founder ${founder} deployed at ${vestingContract.address} (Args : ${contracts.premia.address})`,
      );
      await vestingContract.transferOwnership(founder);
      console.log(`Ownership transferred to ${founder}`);
    }
  }

  await contracts.feeCalculator.transferOwnership(treasury);
  console.log(`FeeCalculator ownership transferred to ${treasury}`);

  await devFund.transferOwnership(treasury);
  console.log(`PremiaDevFund ownership transferred to ${treasury}`);

  await contracts.premiaFeeDiscount.transferOwnership(treasury);
  console.log(`PremiaFeeDiscount ownership transferred to ${treasury}`);

  await contracts.premiaMaker.transferOwnership(treasury);
  console.log(`PremiaMaker ownership transferred to ${treasury}`);

  await premiaMarket.transferOwnership(treasury);
  console.log(`PremiaMarket ownership transferred to ${treasury}`);

  await contracts.premiaMining.transferOwnership(treasury);
  console.log(`PremiaMining ownership transferred to ${treasury}`);

  await premiaOptionDai.transferOwnership(treasury);
  console.log(`PremiaOption DAI ownership transferred to ${treasury}`);

  await contracts.premiaPBC.transferOwnership(treasury);
  console.log(`PremiaPBC ownership transferred to ${treasury}`);

  await contracts.premiaReferral.transferOwnership(treasury);
  console.log(`PremiaReferral ownership transferred to ${treasury}`);

  await contracts.uPremia.transferOwnership(treasury);
  console.log(`PremiaUncutErc20 ownership transferred to ${treasury}`);

  await contracts.priceProvider.transferOwnership(treasury);
  console.log(`PriceProvider ownership transferred to ${treasury}`);

  // ToDo after deployment :
  //  - Send Premia to founder vesting contracts
  //  - Send Premia to PremiaMining contracts
  //  - Send Premia to DevFund contract
  //  - Send Premia to PremiaMining contract
  //  - Send Premia to PremiaPBC contract through addPremia call
  //  - Send bonding curve allocation to multisig
  //  - Set token prices on PriceProvider
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
