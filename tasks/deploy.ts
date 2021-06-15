import { task } from 'hardhat/config';
import { BigNumber, BigNumberish } from 'ethers';
import {
  TradingCompetitionERC20__factory,
  TradingCompetitionFactory__factory,
  TradingCompetitionMerkle__factory,
  Premia__factory,
  Pool__factory,
  ProxyManager__factory,
} from '../typechain';

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
  // const {
  //   TradingCompetitionERC20__factory,
  //   TradingCompetitionFactory__factory,
  //   TradingCompetitionMerkle__factory,
  //   Premia__factory,
  //   Pool__factory,
  //   ProxyManager__factory,
  // } = require('../typechain');

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

    const tradingCompetition = await new TradingCompetitionFactory__factory(
      deployer,
    ).deploy();

    const daiToken = await tradingCompetition.callStatic.deployToken('DAI');
    await (await tradingCompetition.deployToken('DAI')).wait(1);

    const wbtcToken = await tradingCompetition.callStatic.deployToken('wBTC');
    await (await tradingCompetition.deployToken('wBTC')).wait(1);

    const linkToken = await tradingCompetition.callStatic.deployToken('LINK');
    await (await tradingCompetition.deployToken('LINK')).wait(1);

    const yfiToken = await tradingCompetition.callStatic.deployToken('YFI');
    await (await tradingCompetition.deployToken('YFI')).wait(1);

    const uniToken = await tradingCompetition.callStatic.deployToken('UNI');
    await (await tradingCompetition.deployToken('UNI')).wait(1);

    console.log('daiToken', daiToken);
    console.log('wbtcToken', wbtcToken);
    console.log('linkToken', linkToken);
    console.log('yfiToken', yfiToken);
    console.log('uniToken', uniToken);

    const tradingCompetitionMerkle =
      await new TradingCompetitionMerkle__factory(deployer).deploy(
        [daiToken, wbtcToken, linkToken, yfiToken, uniToken],
        [1000000, 10000, 50000, 100000, 100000],
      );

    await tradingCompetitionMerkle.addMerkleRoot(
      0,
      '0x19da299c03aeaabaa21526488c840300881cdfde45f445989e542f2123d8d520',
    );

    await [daiToken, wbtcToken, linkToken, yfiToken, uniToken].reduce(
      async (promise, token) => {
        await promise;

        const tx = await tradingCompetition.addMinters([
          '0x42014C88ccd07f1dA0E22A5095aAA06D2200b2Ea',
          deployer.address,
        ]);

        await tx.wait(1);

        const nextPromise = TradingCompetitionERC20__factory.connect(
          token,
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
      daiToken,
      weth,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_ETH_PRICE_ORACLE,
      fixedFromFloat(2600),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken,
      wbtcToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_WBTC_PRICE_ORACLE,
      fixedFromFloat(37000),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken,
      linkToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_LINK_PRICE_ORACLE,
      fixedFromFloat(24.5),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken,
      yfiToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_WBTC_PRICE_ORACLE,
      fixedFromFloat(39000),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      daiToken,
      uniToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_LINK_PRICE_ORACLE,
      fixedFromFloat(10),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );

    console.log('TradingCompetitionMerkle: ', tradingCompetitionMerkle.address);
  }

  console.log('Deployer: ', deployer.address);
  console.log('PremiaInstance: ', instance.address);
});
