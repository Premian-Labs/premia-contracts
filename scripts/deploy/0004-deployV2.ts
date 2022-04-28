import { deployPool, deployV2, PoolToken } from '../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';

async function main() {
  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';

  const eth: PoolToken = {
    tokenAddress: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    oracleAddress: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
    minimum: '0.05',
  };

  const dai: PoolToken = {
    tokenAddress: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    oracleAddress: '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
    oracleAddress: '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c',
    minimum: '0.005',
  };

  const link: PoolToken = {
    tokenAddress: '0x514910771AF9Ca656af840dff83E8264EcF986CA',
    oracleAddress: '0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c',
    minimum: '5',
  };

  const premiaMaker = '0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF';
  const premiaFeeDiscount = '0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854';

  const { proxyManager } = await deployV2(
    eth.tokenAddress,
    premia,
    fixedFromFloat(0.03),
    fixedFromFloat(0.025),
    premiaMaker,
    premiaFeeDiscount,
    '0x9e88fe5e5249CD6429269B072c9476b6908dCBf2',
  );

  await deployPool(proxyManager, dai, eth, 100);
  await deployPool(proxyManager, dai, btc, 100);
  await deployPool(proxyManager, dai, link, 100);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
