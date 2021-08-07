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

  // Rinkeby addresses
  const weth = ethers.utils.getAddress(
    '0xc778417e063141139fce010982780140aa0cd5ab',
  );

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

  // Rinkeby addresses
  const oracles: TokenAddresses = {
    ETH: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
    DAI: '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF',
    BTC: '0xECe365B379E1dD183B20fc5f022230C044d51404',
    LINK: '0xd8bD0a1cB028a31AA859A21A3758685a95dE4623',
  };

  const premiaDiamond = await deployV2(
    weth,
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
