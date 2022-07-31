import { ethers } from 'hardhat';
import {
  ExchangeHelper__factory,
  FeeCollector__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import { ZERO_ADDRESS } from '../../../test/utils/constants';

async function main() {
  const [deployer] = await ethers.getSigners();

  const treasury = '0xfc5538E1E9814eD6487b407FaD7b5710739A1cC2';

  const premia = ZERO_ADDRESS;
  const feeDiscount = ZERO_ADDRESS;

  // const xPremia = '';

  const feeCollectorImpl = await new FeeCollector__factory(deployer).deploy(
    treasury,
  );

  const feeCollectorProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(feeCollectorImpl.address);

  console.log(
    `FeeCollector impl deployed at ${feeCollectorImpl.address} (Args: ${treasury})`,
  );

  console.log(`FeeCollector proxy deployed at ${feeCollectorProxy.address})`);

  // const feeDiscountImpl = await new FeeDiscount__factory(deployer).deploy(
  //   xPremia,
  // );
  // console.log(
  //   `FeeDiscount impl deployed at ${feeDiscountImpl.address} (Args: ${xPremia})`,
  // );

  // const feeDiscountProxy = await new ProxyUpgradeableOwnable__factory(
  //   deployer,
  // ).deploy(feeDiscountImpl.address);
  // console.log(`FeeDiscount proxy deployed at ${feeDiscountProxy.address})`);

  // const premia = '0x51fc0f6660482ea73330e414efd7808811a57fa2';

  const eth: PoolToken = {
    tokenAddress: '0x4200000000000000000000000000000000000006',
    oracleAddress: '0x13e3ee699d1909e989722e753853ae30b17e08c5',
    minimum: '0.05',
  };

  const usdc: PoolToken = {
    tokenAddress: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
    oracleAddress: '0x16a9fa2fda030272ce99b29cf780dfa30361e0f3',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: '0x68f180fcCe6836688e9084f035309E29Bf0A2095',
    oracleAddress: '0xd702dd976fb76fffc2d3963d037dfdae5b04e593',
    minimum: '0.005',
  };

  const op: PoolToken = {
    tokenAddress: '0x4200000000000000000000000000000000000042',
    oracleAddress: '0x0d276fc14719f9292d5c1ea2198673d1f4269246',
    minimum: '100',
  };

  const ivolOracleProxyAddress = '0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF';
  const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

  const { proxyManager } = await deployV2(
    eth.tokenAddress,
    exchangeHelper.address,
    premia,
    fixedFromFloat(0.03),
    feeCollectorProxy.address,
    feeDiscount,
    ivolOracleProxyAddress,
  );

  await deployPool(proxyManager, usdc, eth, 100);
  await deployPool(proxyManager, usdc, btc, 100);
  await deployPool(proxyManager, usdc, op, 100);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
