import { ethers } from 'hardhat';
import { deployV2, TokenAddresses, TokenAmounts } from '../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';

async function main() {
  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';

  const tokens: TokenAddresses = {
    ETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    BTC: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
    LINK: '0x514910771AF9Ca656af840dff83E8264EcF986CA',
  };

  const oracles: TokenAddresses = {
    ETH: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
    DAI: '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9',
    BTC: '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c',
    LINK: '0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c',
  };

  const minimums: TokenAmounts = {
    DAI: '200',
    ETH: '0.05',
    BTC: '0.005',
    LINK: '5',
  };

  const caps: TokenAmounts = {
    DAI: '10000',
    ETH: '2.5',
    BTC: '0.15',
    LINK: '300',
  };

  const premiaMaker = '0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF';
  const premiaFeeDiscount = '0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854';

  await deployV2(
    tokens.ETH,
    premia,
    fixedFromFloat(0.01),
    premiaMaker,
    premiaFeeDiscount,
    tokens,
    oracles,
    minimums,
    caps,
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
