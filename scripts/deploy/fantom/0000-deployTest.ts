import {
  deployV2,
  TokenAddresses,
  TokenAmounts,
} from '../../utils/deployFantom';
import { fixedFromFloat } from '@premia/utils';
import {
  ERC20Mock__factory,
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

  // Rinkeby addresses
  const wftm = ethers.utils.getAddress(
    '0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83',
  );

  // const ftm = await new ERC20Mock__factory(deployer).deploy('FTM', 18);
  // const weth = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
  // const wbtc = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  // const yfi = await new ERC20Mock__factory(deployer).deploy('YFI', 18);
  // const usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

  const tokens: TokenAddresses = {
    FTM: '0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83',
    WETH: '0x74b23882a30290451a17c44f4f05243b6b58c76d',
    WBTC: '0x321162cd933e2be498cd2267a90534a804051b11',
    YFI: '0x29b0da86e484e1c0029b56e817912d778ac0ec69',
    USDC: '0x04068da6c83afcfa0e13ba15a6696662335d5b75',
  };

  // Rinkeby addresses
  const oracles: TokenAddresses = {
    FTM: '0xf4766552D15AE4d256Ad41B6cf2933482B0680dc',
    WETH: '0x11DdD3d147E5b83D01cee7070027092397d63658',
    WBTC: '0x8e94C22142F4A64b99022ccDd994f4e9EC86E4B4',
    YFI: '0x9B25eC3d6acfF665DfbbFD68B3C1D896E067F0ae',
    USDC: '0x2553f4eeb82d5A26427b8d1106C51499CBa5D99c',
  };

  const minimums: TokenAmounts = {
    FTM: '100',
    WETH: '0.05',
    WBTC: '0.005',
    YFI: '0.005',
    USDC: '100',
  };

  const premiaDiamond = await deployV2(
    wftm,
    premia.address,
    fixedFromFloat(0.03),
    fixedFromFloat(0.03),
    contracts.premiaMaker.address,
    contracts.xPremia.address,
    tokens,
    oracles,
    minimums,
    undefined,
    '0xD77203CDBd33B849Dc0B03A4f906F579A766C0A6',
  );

  const premiaMakerKeeper = await new PremiaMakerKeeper__factory(
    deployer,
  ).deploy(contracts.premiaMaker.address, premiaDiamond);

  const processExpiredKeeper = await new ProcessExpiredKeeper__factory(
    deployer,
  ).deploy(premiaDiamond);

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
