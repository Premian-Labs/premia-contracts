import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import {
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

  // Rinkeby addresses
  const weth = ethers.utils.getAddress(
    '0xc778417e063141139fce010982780140aa0cd5ab',
  );

  // const eth = await new ERC20Mock__factory(deployer).deploy('ETH', 18);
  // const dai = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  // const wbtc = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  // const link = await new ERC20Mock__factory(deployer).deploy('LINK', 18);

  const eth: PoolToken = {
    tokenAddress: '0xc778417E063141139Fce010982780140Aa0cD5Ab',
    oracleAddress: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
    minimum: '0.05',
  };

  const dai: PoolToken = {
    tokenAddress: '0xe7ED2AE5fc5E04ba3A9E04fD4a46D210F73990e6',
    oracleAddress: '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: '0xF4A41f753A09BE3DdCB82856808e4B8c44e36f6D',
    oracleAddress: '0xECe365B379E1dD183B20fc5f022230C044d51404',
    minimum: '0.005',
  };

  const link: PoolToken = {
    tokenAddress: '0xd6620e82b200a6486D419c3ea9D840fC811D86be',
    oracleAddress: '0xd8bD0a1cB028a31AA859A21A3758685a95dE4623',
    minimum: '5',
  };

  const { premiaDiamond, proxyManager } = await deployV2(
    weth,
    premia.address,
    fixedFromFloat(0.03),
    fixedFromFloat(0.025),
    contracts.premiaMaker.address,
    contracts.xPremia.address,
    '0x9e88fe5e5249CD6429269B072c9476b6908dCBf2',
    { sushiswapFactory: '0xc35DADB65012eC5796536bD9864eD8773aBc74C4' },
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
