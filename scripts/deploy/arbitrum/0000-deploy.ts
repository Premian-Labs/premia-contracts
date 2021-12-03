import { ethers } from 'hardhat';
import {
  ERC20Mock__factory,
  FeeCollector__factory,
  FeeDiscount__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import { deployV2, TokenAddresses, TokenAmounts } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';

async function main() {
  const [deployer] = await ethers.getSigners();

  const treasury = '0xa079C6B032133b95Cf8b3d273D27eeb6B110a469';

  const xPremia = '0x0d7d0eFdCbfe5466b387e127709F24603920f671';

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

  const feeDiscountImpl = await new FeeDiscount__factory(deployer).deploy(
    xPremia,
  );
  console.log(
    `FeeDiscount impl deployed at ${feeDiscountImpl.address} (Args: ${xPremia})`,
  );

  const feeDiscountProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(feeDiscountImpl.address);
  console.log(`FeeDiscount proxy deployed at ${feeDiscountProxy.address})`);

  const premia = '0x51fc0f6660482ea73330e414efd7808811a57fa2';

  const tokens: TokenAddresses = {
    ETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    DAI: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    BTC: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
    LINK: '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4',
  };

  const oracles: TokenAddresses = {
    ETH: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
    DAI: '0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB',
    BTC: '0x6ce185860a4963106506C203335A2910413708e9',
    LINK: '0x86E53CF1B870786351Da77A57575e79CB55812CB',
  };

  const minimums: TokenAmounts = {
    DAI: '200',
    ETH: '0.05',
    BTC: '0.005',
    LINK: '5',
  };

  const caps: TokenAmounts = {
    DAI: '10000',
    ETH: '2.5',
    BTC: '0.15',
    LINK: '300',
  };

  const ivolOracleProxyAddress = '0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF';
  const sushiswapFactory = '0xc35DADB65012eC5796536bD9864eD8773aBc74C4';

  await deployV2(
    tokens.ETH,
    premia,
    fixedFromFloat(0.03),
    feeCollectorProxy.address,
    feeDiscountProxy.address,
    tokens,
    oracles,
    minimums,
    caps,
    sushiswapFactory,
    ivolOracleProxyAddress,
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
