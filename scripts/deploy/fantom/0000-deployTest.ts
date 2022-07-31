import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import {
  ExchangeHelper__factory,
  PremiaErc20__factory,
  PremiaMakerKeeper__factory,
  ProcessExpiredKeeper__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { deployV1 } from '../../utils/deployV1';

async function main() {
  const [deployer] = await ethers.getSigners();
  const premia = await new PremiaErc20__factory(deployer).deploy();

  await new Promise((resolve) => setTimeout(resolve, 1000));

  const contracts = await deployV1(
    deployer,
    deployer.address,
    true,
    true,
    premia.address,
  );

  await new Promise((resolve) => setTimeout(resolve, 1000));

  // const ftm = await new ERC20Mock__factory(deployer).deploy('FTM', 18);
  // const weth = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
  // const wbtc = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  // const yfi = await new ERC20Mock__factory(deployer).deploy('YFI', 18);
  // const usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

  const ftm: PoolToken = {
    tokenAddress: '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83',
    oracleAddress: '0xf4766552D15AE4d256Ad41B6cf2933482B0680dc',
    minimum: '10',
  };

  const yfi: PoolToken = {
    tokenAddress: '0x29b0Da86e484E1C0029B56e817912d778aC0EC69',
    oracleAddress: '0x9B25eC3d6acfF665DfbbFD68B3C1D896E067F0ae',
    minimum: '0.0005',
  };

  const eth: PoolToken = {
    tokenAddress: '0x74b23882a30290451A17c44f4F05243b6b58C76d',
    oracleAddress: '0x11DdD3d147E5b83D01cee7070027092397d63658',
    minimum: '0.005',
  };

  const btc: PoolToken = {
    tokenAddress: '0x321162Cd933E2Be498Cd2267a90534A804051b11',
    oracleAddress: '0x8e94C22142F4A64b99022ccDd994f4e9EC86E4B4',
    minimum: '0.0005',
  };

  const usdc: PoolToken = {
    tokenAddress: '0x04068DA6C83AFCFA0e13ba15A6696662335D5B75',
    oracleAddress: '0x2553f4eeb82d5A26427b8d1106C51499CBa5D99c',
    minimum: '10',
  };

  const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

  const { premiaDiamond, proxyManager } = await deployV2(
    ftm.tokenAddress,
    exchangeHelper.address,
    premia.address,
    fixedFromFloat(0.03),
    contracts.premiaMaker.address,
    contracts.xPremia.address,
    '0xD77203CDBd33B849Dc0B03A4f906F579A766C0A6',
  );

  await deployPool(proxyManager, usdc, ftm, 100);
  await deployPool(proxyManager, usdc, eth, 150);
  await deployPool(proxyManager, usdc, btc, 75);
  await deployPool(proxyManager, usdc, yfi, 75);

  const premiaMakerKeeper = await new PremiaMakerKeeper__factory(
    deployer,
  ).deploy(contracts.premiaMaker.address, premiaDiamond.address);

  const processExpiredKeeper = await new ProcessExpiredKeeper__factory(
    deployer,
  ).deploy(premiaDiamond.address);

  console.log('PremiaMakerKeeper', premiaMakerKeeper.address);
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
