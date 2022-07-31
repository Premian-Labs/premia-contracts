import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import {
  ERC20Mock__factory,
  PremiaErc20__factory,
  ProcessExpiredKeeper__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { deployV1 } from '../../utils/deployV1';

async function main() {
  const [deployer] = await ethers.getSigners();
  const premia = await new PremiaErc20__factory(deployer).deploy();

  const contracts = await deployV1(
    deployer,
    deployer.address,
    true,
    true,
    premia.address,
  );

  // BSC addresses
  const wbnb = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';

  const ethToken = await new ERC20Mock__factory(deployer).deploy('ETH', 18);
  const daiToken = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  const wbtcToken = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  const linkToken = await new ERC20Mock__factory(deployer).deploy('LINK', 18);

  const eth: PoolToken = {
    tokenAddress: ethToken.address,
    oracleAddress: '0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e',
    minimum: '0.05',
  };

  const dai: PoolToken = {
    tokenAddress: daiToken.address,
    oracleAddress: '0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: wbtcToken.address,
    oracleAddress: '0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf',
    minimum: '0.005',
  };

  const link: PoolToken = {
    tokenAddress: linkToken.address,
    oracleAddress: '0xca236E327F629f9Fc2c30A4E95775EbF0B89fac8',
    minimum: '5',
  };

  const { premiaDiamond, proxyManager } = await deployV2(
    wbnb,
    premia.address,
    fixedFromFloat(0.03),
    fixedFromFloat(0.025),
    contracts.premiaMaker.address,
    contracts.xPremia.address,
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
