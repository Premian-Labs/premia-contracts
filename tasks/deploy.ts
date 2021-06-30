import { task } from 'hardhat/config';
import { fixedFromFloat } from '../test/utils/math';
import { parseEther } from 'ethers/lib/utils';

// uncomment for type support but make sure to re-comment before committing b/c hardhat sucks
// import {
//   TradingCompetitionFactory__factory,
//   TradingCompetitionMerkle__factory,
//   Premia__factory,
//   ProxyManager__factory,
//   Pool,
//   Pool__factory,
//   PoolTradingCompetition,
//   PoolTradingCompetition__factory,
// } from '../typechain';

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

task('deploy').setAction(async function (args, hre) {
  // Leave imports here so that we can run hardhat compile even if typechain folder has not been generated  yet
  const {
    TradingCompetitionFactory__factory,
    TradingCompetitionMerkle__factory,
    Premia__factory,
    ProxyManager__factory,
    Pool,
    Pool__factory,
    PoolTradingCompetition,
    PoolTradingCompetition__factory,
    OptionMath__factory,
  } = require('../typechain');

  const [deployer] = await hre.ethers.getSigners();

  const weth =
    hre.network.name === 'rinkeby'
      ? RINKEBY_WETH
      : hre.ethers.constants.AddressZero;

  const optionMath = await new OptionMath__factory(deployer).deploy();

  let pool: typeof Pool | typeof PoolTradingCompetition;
  if (hre.network.name === 'rinkeby') {
    pool = await new PoolTradingCompetition__factory({ '__$430b703ddf4d641dc7662832950ed9cf8d$__': optionMath.address }, deployer).deploy(
      weth,
      deployer.address,
      0,
      260,
    );
  } else {
    pool = await new Pool__factory({ '__$430b703ddf4d641dc7662832950ed9cf8d$__': optionMath.address }, deployer).deploy(
      weth,
      deployer.address,
      '0x028f5c28f5c28f5c',
      260,
    );
  }

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

  const diamondTx = await instance.diamondCut(
    facetCuts,
    hre.ethers.constants.AddressZero,
    '0x',
  );

  if (hre.network.name === 'rinkeby') {
    await diamondTx.wait(1);

    const tradingCompetition = await new TradingCompetitionFactory__factory(
      deployer,
    ).deploy();

    const wethToken = await tradingCompetition.callStatic.deployToken(
      'WETH',
      RINKEBY_ETH_PRICE_ORACLE,
    );
    await (
      await tradingCompetition.deployToken('WETH', RINKEBY_ETH_PRICE_ORACLE)
    ).wait(1);

    const daiToken = await tradingCompetition.callStatic.deployToken(
      'DAI',
      RINKEBY_DAI_PRICE_ORACLE,
    );
    await (
      await tradingCompetition.deployToken('DAI', RINKEBY_DAI_PRICE_ORACLE)
    ).wait(1);

    const wbtcToken = await tradingCompetition.callStatic.deployToken(
      'wBTC',
      RINKEBY_WBTC_PRICE_ORACLE,
    );
    await (
      await tradingCompetition.deployToken('wBTC', RINKEBY_WBTC_PRICE_ORACLE)
    ).wait(1);

    const linkToken = await tradingCompetition.callStatic.deployToken(
      'LINK',
      RINKEBY_LINK_PRICE_ORACLE,
    );
    await (
      await tradingCompetition.deployToken('LINK', RINKEBY_LINK_PRICE_ORACLE)
    ).wait(1);

    const tradingCompetitionMerkle =
      await new TradingCompetitionMerkle__factory(deployer).deploy(
        [wethToken, daiToken, wbtcToken, linkToken],
        [
          parseEther('5'),
          parseEther('20000'),
          parseEther('0.3'),
          parseEther('500'),
        ],
      );

    await tradingCompetitionMerkle.addMerkleRoot(
      0,
      '0x7854e4fea1b4cc79e4c13d6ccb9c31782fb2831a1b12b32b6a02289a5733648a',
    );

    const tx = await tradingCompetition.addMinters([
      '0x42014C88ccd07f1dA0E22A5095aAA06D2200b2Ea',
      '0xFBB8495A691232Cb819b84475F57e76aa9aBb6f1',
      deployer.address,
      tradingCompetitionMerkle.address,
    ]);

    await tx.wait(1);

    // await [daiToken, wbtcToken, linkToken].reduce(async (promise, token) => {
    //   await promise;
    //
    //   await TradingCompetitionERC20__factory.connect(token, deployer).mint(
    //     '0xB26D90D66E046f2c72bd038F42151ACECB17238D',
    //     '10000000000000000000000000000000000000',
    //   );
    //
    //   const nextPromise = TradingCompetitionERC20__factory.connect(
    //     token,
    //     deployer,
    //   ).mint(
    //     '0x42014C88ccd07f1dA0E22A5095aAA06D2200b2Ea',
    //     '10000000000000000000000000000000000000',
    //   );
    //
    //   return nextPromise as any;
    // }, Promise.resolve());

    const proxyManager = ProxyManager__factory.connect(
      instance.address,
      deployer,
    );

    const wethPoolAddress = await proxyManager.callStatic.deployPool(
      daiToken,
      wethToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_ETH_PRICE_ORACLE,
      fixedFromFloat(1.92),
    );

    let poolTx = await proxyManager.deployPool(
      daiToken,
      wethToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_ETH_PRICE_ORACLE,
      fixedFromFloat(1.92),
    );

    await poolTx.wait(1);

    const wbtcPoolAddress = await proxyManager.callStatic.deployPool(
      daiToken,
      wbtcToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_WBTC_PRICE_ORACLE,
      fixedFromFloat(1.35),
    );

    poolTx = await proxyManager.deployPool(
      daiToken,
      wbtcToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_WBTC_PRICE_ORACLE,
      fixedFromFloat(1.35),
    );

    await poolTx.wait(1);

    const linkPoolAddress = await proxyManager.callStatic.deployPool(
      daiToken,
      linkToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_LINK_PRICE_ORACLE,
      fixedFromFloat(3.12),
    );

    poolTx = await proxyManager.deployPool(
      daiToken,
      linkToken,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_LINK_PRICE_ORACLE,
      fixedFromFloat(3.12),
    );

    await poolTx.wait(1);

    await tradingCompetition.addWhitelisted([
      wethPoolAddress,
      wbtcPoolAddress,
      linkPoolAddress,
      tradingCompetitionMerkle.address,
    ]);

    console.log('daiToken', daiToken);
    console.log('wethToken', wethToken);
    console.log('wbtcToken', wbtcToken);
    console.log('linkToken', linkToken);
    console.log('wethPoolAddress', wethPoolAddress);
    console.log('wbtcPoolAddress', wbtcPoolAddress);
    console.log('linkPoolAddress', linkPoolAddress);
    console.log('TradingCompetition: ', tradingCompetition.address);
    console.log('TradingCompetitionMerkle: ', tradingCompetitionMerkle.address);
  }

  console.log('Deployer: ', deployer.address);
  console.log('PremiaInstance: ', instance.address);
});
