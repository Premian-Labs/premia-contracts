import { deployV2, TokenAddresses } from '../utils/deployV2';

async function main() {
  // Test tokens will be deployed, so this doesnt need to be set
  const tokens: TokenAddresses = {
    ETH: '',
    DAI: '',
    BTC: '',
    LINK: '',
  };

  const oracles: TokenAddresses = {
    ETH: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
    DAI: '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF',
    BTC: '0xECe365B379E1dD183B20fc5f022230C044d51404',
    LINK: '0xd8bD0a1cB028a31AA859A21A3758685a95dE4623',
  };

  await deployV2(
    '0xc778417e063141139fce010982780140aa0cd5ab',
    tokens,
    oracles,
    true,
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
