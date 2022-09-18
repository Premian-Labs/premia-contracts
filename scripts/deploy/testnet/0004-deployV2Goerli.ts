import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import {
  ERC20Mock__factory,
  ExchangeHelper__factory,
  PremiaErc20__factory,
  ProcessExpiredKeeper__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { deployV1 } from '../../utils/deployV1';

async function main() {
  const [deployer] = await ethers.getSigners();
  const premia = await new PremiaErc20__factory(deployer).deploy();
  await premia.deployed();

  const contracts = await deployV1(
    deployer,
    deployer.address,
    ethers.constants.AddressZero,
    true,
    true,
    premia.address,
  );

  const weth = ethers.utils.getAddress(
    '0xb4fbf271143f4fbf7b91a5ded31805e42b2208d6',
  );

  const daiToken = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  await daiToken.deployed();
  const wbtcToken = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  await wbtcToken.deployed();
  const linkToken = await new ERC20Mock__factory(deployer).deploy('LINK', 18);
  await linkToken.deployed();

  const eth: PoolToken = {
    tokenAddress: '0xb4fbf271143f4fbf7b91a5ded31805e42b2208d6',
    oracleAddress: '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e',
    minimum: '0.05',
  };

  const dai: PoolToken = {
    tokenAddress: daiToken.address,
    oracleAddress: '0x0d79df66BE487753B02D015Fb622DED7f0E9798d',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: wbtcToken.address,
    oracleAddress: '0xA39434A63A52E749F02807ae27335515BA4b07F7',
    minimum: '0.005',
  };

  const link: PoolToken = {
    tokenAddress: linkToken.address,
    oracleAddress: '0x48731cF7e84dc94C5f84577882c14Be11a5B7456',
    minimum: '5',
  };

  const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

  const { premiaDiamond, proxyManager } = await deployV2(
    weth,
    exchangeHelper.address,
    premia.address,
    fixedFromFloat(0.03),
    contracts.feeConverter.address,
    contracts.vePremia.address,
  );

  await deployPool(proxyManager, dai, eth, 100);
  await deployPool(proxyManager, dai, btc, 100);
  await deployPool(proxyManager, dai, link, 100);

  const processExpiredKeeper = await new ProcessExpiredKeeper__factory(
    deployer,
  ).deploy(premiaDiamond.address);

  console.log('ProcessExpiredKeeper', processExpiredKeeper.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
