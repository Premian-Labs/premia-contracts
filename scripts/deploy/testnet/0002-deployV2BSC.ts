import { deployV2, TokenAddresses } from '../../utils/deployV2';
import { fixedFromFloat } from '../../../test/utils/math';
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

  // BSC addresses
  const wbnb = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';

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

  // BSC addresses
  const oracles: TokenAddresses = {
    ETH: '0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e',
    DAI: '0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA',
    BTC: '0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf',
    LINK: '0xca236E327F629f9Fc2c30A4E95775EbF0B89fac8',
  };

  const premiaDiamond = await deployV2(
    wbnb,
    premia.address,
    fixedFromFloat(0.1),
    contracts.premiaMaker.address,
    contracts.premiaFeeDiscount.address,
    tokens,
    oracles,
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
