import { ethers } from 'hardhat';
import {
  TradingCompetitionFactory__factory,
  TradingCompetitionSwap__factory,
} from '../../typechain';

export const RINKEBY_DAI_PRICE_ORACLE =
  '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF';
export const RINKEBY_ETH_PRICE_ORACLE =
  '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e';
export const RINKEBY_WBTC_PRICE_ORACLE =
  '0xECe365B379E1dD183B20fc5f022230C044d51404';
export const RINKEBY_LINK_PRICE_ORACLE =
  '0xd8bD0a1cB028a31AA859A21A3758685a95dE4623';

const DAI = '0xA41595a9FDDE4fdFB6E9Bcfe9d501Ffba82f30F1';
const WETH = '0x8B4A830548A9E16FF3cD99216a0fBb3bDdc64B86';
const WBTC = '0xE94AA87F3cb653878bF13Ff92f93c8fB2808d8b5';
const LINK = '0x5F9ebe6B507B6bCE580aAa14f5Cdc92F934e21f1';

async function main() {
  const [deployer] = await ethers.getSigners();

  const swap = await new TradingCompetitionSwap__factory(deployer).deploy();
  await swap.setOracle(DAI, RINKEBY_DAI_PRICE_ORACLE);
  await swap.setOracle(WETH, RINKEBY_ETH_PRICE_ORACLE);
  await swap.setOracle(WBTC, RINKEBY_WBTC_PRICE_ORACLE);
  await swap.setOracle(LINK, RINKEBY_LINK_PRICE_ORACLE);

  const factory = TradingCompetitionFactory__factory.connect(
    '0x621447Dd96Ea8555cFa6Ec538c50acB17e0c138e',
    deployer,
  );

  await factory.addMinters([swap.address]);

  console.log('swap', swap.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
