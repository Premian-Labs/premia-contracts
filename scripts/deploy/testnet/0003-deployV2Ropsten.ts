import { deployV2, TokenAddresses, TokenAmounts } from '../../utils/deployV2';
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

  const contracts = await deployV1(
    deployer,
    deployer.address,
    true,
    true,
    premia.address,
  );

  // Ropsten addresses
  const weth = '0xc778417e063141139fce010982780140aa0cd5ab';

  const eth = await new ERC20Mock__factory(deployer).deploy('ETH', 18);
  const dai = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  const wbtc = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  const link = await new ERC20Mock__factory(deployer).deploy('LINK', 18);

  const tokens: TokenAddresses = {
    ETH: eth.address,
    DAI: dai.address,
    BTC: wbtc.address,
    LINK: link.address,
  };

  // Ropsten addresses
  const oracles: TokenAddresses = {
    ETH: '0x8468b2bDCE073A157E560AA4D9CcF6dB1DB98507',
    DAI: '0xec3cf275cAa57dD8aA5c52e9d5b70809Cb01D421',
    BTC: '0x882906a758207FeA9F21e0bb7d2f24E561bd0981',
    LINK: '0xc21c178fE75aAd2017DA25071c54462e26d8face',
  };

  const minimums: TokenAmounts = {
    DAI: '100',
    ETH: '0.05',
    BTC: '0.005',
    LINK: '5',
  };

  const premiaDiamond = await deployV2(
    weth,
    premia.address,
    fixedFromFloat(0.01),
    fixedFromFloat(0.01),
    contracts.premiaMaker.address,
    contracts.xPremia.address,
    tokens,
    oracles,
    minimums,
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
