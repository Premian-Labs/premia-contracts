import { ethers } from 'hardhat';
import {
  ERC20Placeholder__factory,
  FeeCollector__factory,
  FeeDiscount__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';

async function main() {
  const [deployer] = await ethers.getSigners();

  const treasury = '0x0b95674d635c4Cf3E73DD0E4B28b4dcfdccD2Ec2';

  const xPremiaPlaceholder = await new ERC20Placeholder__factory(
    deployer,
  ).deploy();

  await xPremiaPlaceholder.deployed();

  const xPremia = xPremiaPlaceholder.address;

  console.log('xPremia placeholder', xPremiaPlaceholder.address);

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

  const ivolOracleProxyAddress = '0xD77203CDBd33B849Dc0B03A4f906F579A766C0A6';

  const { proxyManager } = await deployV2(
    ftm.tokenAddress,
    premia,
    fixedFromFloat(0.03),
    fixedFromFloat(0.025),
    feeCollectorProxy.address,
    feeDiscountProxy.address,
    ivolOracleProxyAddress,
    {
      // SpookySwap
      sushiswapFactory: '0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3',
      sushiswapInitHash:
        '0xcdf2deca40a0bd56de8e3ce5c7df6727e5b1bf2ac96f283fa9c4b3e6b42ea9d2',

      // SpiritSwap
      uniswapV2Factory: '0xef45d134b73241eda7703fa787148d9c9f4950b0',
      uniswapV2InitHash:
        '0xe242e798f6cee26a9cb0bbf24653bf066e5356ffeac160907fe2cc108e238617',
    },
  );

  await deployPool(proxyManager, usdc, ftm, 100);
  await deployPool(proxyManager, usdc, eth, 150);
  await deployPool(proxyManager, usdc, btc, 75);
  await deployPool(proxyManager, usdc, yfi, 75);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
