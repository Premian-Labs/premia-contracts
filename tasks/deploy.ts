import { task } from 'hardhat/config';
import { BigNumber, BigNumberish } from 'ethers';

export const RINKEBY_DAI = '0x5592ec0cfb4dbc12d3ab100b257153436a1f0fea';
export const RINKEBY_WETH = '0xc778417e063141139fce010982780140aa0cd5ab';
export const RINKEBY_DAI_PRICE_ORACLE =
  '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF';
export const RINKEBY_ETH_PRICE_ORACLE =
  '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e';
export const RINKEBY_WBTC_PRICE_ORACLE =
  '0xECe365B379E1dD183B20fc5f022230C044d51404';
export const RINKEBY_LINK_PRICE_ORACLE =
  '0xd8bD0a1cB028a31AA859A21A3758685a95dE4623';

const fixedFromBigNumber = function (bn: BigNumber) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const fixedFromFloat = function (float: BigNumberish) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(BigNumber.from(`${integer}${decimal}`)).div(
    BigNumber.from(`1${'0'.repeat(decimal.length)}`),
  );
};

task('deploy').setAction(async function (args, hre) {
  const {
    ERC20Mock__factory,
    Premia__factory,
    Pool__factory,
    ProxyManager__factory,
  } = require('../typechain');

  const [deployer] = await hre.ethers.getSigners();

  const weth =
    hre.network.name === 'rinkeby'
      ? RINKEBY_WETH
      : hre.ethers.constants.AddressZero;

  const pool = await new Pool__factory(deployer).deploy(
    weth,
    deployer.address,
    '0x028f5c28f5c28f5c',
  );

  const facetCuts = [await new ProxyManager__factory(deployer).deploy()].map(
    function (f) {
      return {
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions).map((fn) =>
          f.interface.getSighash(fn),
        ),
      };
    },
  );

  const instance = await new Premia__factory(deployer).deploy(pool.address);

  const tx = await instance.diamondCut(
    facetCuts,
    hre.ethers.constants.AddressZero,
    '0x',
  );

  if (hre.network.name === 'rinkeby') {
    await tx.wait(1);

    const daiToken = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
    const wbtcToken = await new ERC20Mock__factory(deployer).deploy('wBTC', 8);
    const linkToken = await new ERC20Mock__factory(deployer).deploy('LINK', 18);
    const yfiToken = await new ERC20Mock__factory(deployer).deploy('YFI', 18);
    const uniToken = await new ERC20Mock__factory(deployer).deploy('UNI', 18);

    await [daiToken, wbtcToken, linkToken, yfiToken, uniToken].reduce(
      async (promise, token) => {
        await promise;

        const nextPromise = ERC20Mock__factory.connect(
          token.address,
          deployer,
        ).mint(
          '0x42014C88ccd07f1dA0E22A5095aAA06D2200b2Ea',
          '1000000000000000000000000',
        );

        return nextPromise as any;
      },
      Promise.resolve(),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken.address,
      weth,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_ETH_PRICE_ORACLE,
      fixedFromFloat(2600),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken.address,
      wbtcToken.address,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_WBTC_PRICE_ORACLE,
      fixedFromFloat(37000),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken.address,
      linkToken.address,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_LINK_PRICE_ORACLE,
      fixedFromFloat(24.5),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken.address,
      yfiToken.address,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_WBTC_PRICE_ORACLE,
      fixedFromFloat(39000),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken.address,
      uniToken.address,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_LINK_PRICE_ORACLE,
      fixedFromFloat(10),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );
  }

  console.log('Deployer: ', deployer.address);
  console.log('PremiaInstance: ', instance.address);
});
