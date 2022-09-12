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

  const contracts = await deployV1(
    deployer,
    deployer.address,
    ethers.constants.AddressZero,
    true,
    true,
    premia.address,
  );

  // Ropsten addresses
  const weth = '0xc778417e063141139fce010982780140aa0cd5ab';

  const ethToken = await new ERC20Mock__factory(deployer).deploy('ETH', 18);
  const daiToken = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  const wbtcToken = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  const linkToken = await new ERC20Mock__factory(deployer).deploy('LINK', 18);

  const eth: PoolToken = {
    tokenAddress: ethToken.address,
    oracleAddress: '0x8468b2bDCE073A157E560AA4D9CcF6dB1DB98507',
    minimum: '0.05',
  };

  const dai: PoolToken = {
    tokenAddress: daiToken.address,
    oracleAddress: '0xec3cf275cAa57dD8aA5c52e9d5b70809Cb01D421',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: wbtcToken.address,
    oracleAddress: '0x882906a758207FeA9F21e0bb7d2f24E561bd0981',
    minimum: '0.005',
  };

  const link: PoolToken = {
    tokenAddress: linkToken.address,
    oracleAddress: '0xc21c178fE75aAd2017DA25071c54462e26d8face',
    minimum: '5',
  };

  const exchangeHelper = await ExchangeHelper__factory(deployer).deploy();

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
