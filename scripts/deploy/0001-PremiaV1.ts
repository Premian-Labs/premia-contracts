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
  let premia: string | undefined;
  let treasury: string;
  let tokens: { [addr: string]: BigNumberish } = {};
  let uniswapRouters = [
    '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F', // SushiSwap router
    '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap router
  ];

  let founder1 = '0xC340B7A2A70d7e08F25435CB97F3B25A45002e6C';
  let founder2 = '0xfCF7c21910A878b5A31D31bA29789C3ff235fC17';
  let founder3 = '0x50CC6BE786aeF59EaD19fa4438dFe139D6837822';
  let founder4 = '0xDEAD5D3c486AcE753c839e2EB27BacdabBA06dD6';

  if (isTestnet) {
    dai = '0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa';
    weth = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
    wbtc = '0x577D296678535e4903D59A4C929B718e1D575e0A';
    treasury = deployer.address;

    tokens[weth] = parseEther('10');
    tokens[wbtc] = parseEther('1000');
  } else {
    premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
    dai = '0x6b175474e89094c44da98b954eedeac495271d0f';
    // weth = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
    // wbtc = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';
    treasury = '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0';

    // WETH
    tokens['0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'] = parseEther('200');

    // WBTC
    tokens['0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'] = parseEther('500');

    // LINK
    tokens['0x514910771AF9Ca656af840dff83E8264EcF986CA'] = parseEther('2.5');

    // AAVE
    tokens['0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9'] = parseEther('50');

    // SNX
    tokens['0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F'] = parseEther('2.5');

    // COMP
    tokens['0xc00e94Cb662C3520282E6f5717214004A7f26888'] = parseEther('50');

    // MKR
    tokens['0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2'] = parseEther('250');

    // REN
    tokens['0x408e41876cCCDC0F92210600ef50372656052a38'] = parseEther('0.1');

    // CRV
    tokens['0xD533a949740bb3306d119CC777fa900bA034cd52'] = parseEther('0.5');

    // UNI
    tokens['0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984'] = parseEther('2.5');

    // SUSHI
    tokens['0x6B3595068778DD592e39A122f4f5a5cF09C90fE2'] = parseEther('2.5');

    // YFI
    tokens['0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e'] = parseEther('5000');

    // BADGER
    tokens['0x3472A5A71965499acd81997a54BBA8D852C6E53d'] = parseEther('10');

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

  const contracts = await deployContracts(
    deployer,
    treasury,
    isTestnet,
    true,
    premia,
  );

  //

  const premiaOptionDai = await new PremiaOption__factory(deployer).deploy(
    uri,
    dai,
    ZERO_ADDRESS,
    contracts.feeCalculator.address,
    contracts.premiaReferral.address,
    treasury,
  );

  console.log(
    `premiaOption dai deployed at ${premiaOptionDai.address} (Args : ${uri} / ${dai} / ${ZERO_ADDRESS} / 
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

  //

  const premiaMarket = await new PremiaMarket__factory(deployer).deploy(
    ZERO_ADDRESS,
    contracts.feeCalculator.address,
    treasury,
    contracts.premiaReferral.address,
  );

  console.log(
    `premiaMarket deployed at ${premiaMarket.address} (Args : ${ZERO_ADDRESS} / ${contracts.feeCalculator.address} / ${treasury})`,
  );

  await contracts.premiaReferral.addWhitelisted([
    premiaOptionDai.address,
    premiaMarket.address,
    // premiaOptionEth.address,
    // premiaOptionWbtc.address,
  ]);
  console.log('Whitelisted PremiaOption on PremiaReferral');

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

  await premiaMarket.addWhitelistedPaymentTokens([dai]);
  console.log('Added dai as market payment token');

  // DevFund contract
  const devFund = await new PremiaDevFund__factory(deployer).deploy(
    contracts.premia.address,
  );
  console.log(
    `PremiaDevFund deployed at ${devFund.address} (Args : ${contracts.premia.address})`,
  );

  // Mining fund contract
  const miningFund = await new PremiaDevFund__factory(deployer).deploy(
    contracts.premia.address,
  );
  console.log(
    `MiningFund deployed at ${miningFund.address} (Args : ${contracts.premia.address})`,
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

  // Fee sharing disabled by default - Enabling protocol fee sharing will have to be voted on by the community
  await contracts.premiaMaker.setTreasuryFee(1e4);
  console.log('Protocol fee sharing disabled');

  if (!isTestnet) {
    // Badger routing : Badger -> Wbtc -> Weth
    await contracts.premiaMaker.setCustomPath(
      '0x3472A5A71965499acd81997a54BBA8D852C6E53d',
      [
        '0x3472A5A71965499acd81997a54BBA8D852C6E53d',
        '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
        '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
      ],
    );
    console.log('Added badger custom routing');
  }

  await contracts.feeCalculator.transferOwnership(treasury);
  console.log(`FeeCalculator ownership transferred to ${treasury}`);

  await devFund.transferOwnership(treasury);
  console.log(`PremiaDevFund ownership transferred to ${treasury}`);

  await miningFund.transferOwnership(treasury);
  console.log(`MiningFund ownership transferred to ${treasury}`);

  await contracts.premiaFeeDiscount.transferOwnership(treasury);
  console.log(`PremiaFeeDiscount ownership transferred to ${treasury}`);

  await contracts.premiaMaker.transferOwnership(treasury);
  console.log(`PremiaMaker ownership transferred to ${treasury}`);

  await premiaMarket.transferOwnership(treasury);
  console.log(`PremiaMarket ownership transferred to ${treasury}`);

  await premiaOptionDai.transferOwnership(treasury);
  console.log(`PremiaOption DAI ownership transferred to ${treasury}`);

  await contracts.premiaPBC.transferOwnership(treasury);
  console.log(`PremiaPBC ownership transferred to ${treasury}`);

  await contracts.premiaReferral.transferOwnership(treasury);
  console.log(`PremiaReferral ownership transferred to ${treasury}`);

  // ToDo after deployment :
  //  - Send Premia to founder vesting contracts
  //  - Send Premia to DevFund contract
  //  - Send Premia to PremiaPBC contract through addPremia call
  //  - Send bonding curve allocation to multisig
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
