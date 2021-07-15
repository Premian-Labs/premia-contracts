import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import { fixedFromFloat } from '../../test/utils/math';
import {
  OptionMath__factory,
  Pool,
  Pool__factory,
  PoolTradingCompetition,
  PoolTradingCompetition__factory,
  Premia__factory,
  ProxyManager__factory,
  TradingCompetitionFactory,
  TradingCompetitionFactory__factory,
  TradingCompetitionMerkle,
  TradingCompetitionMerkle__factory,
} from '../../typechain';

export interface TokenAddresses {
  ETH: string;
  DAI: string;
  BTC: string;
  LINK: string;
}

export async function deployV2(
  weth: string,
  tokens: TokenAddresses,
  oracles: TokenAddresses,
  isTestnet: boolean,
) {
  const [deployer] = await ethers.getSigners();

  const optionMath = await new OptionMath__factory(deployer).deploy();

  let pool: Pool | PoolTradingCompetition;
  if (isTestnet) {
    pool = await new PoolTradingCompetition__factory(
      { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
      deployer,
    ).deploy(weth, deployer.address, 0, 260);
  } else {
    pool = await new Pool__factory(
      { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
      deployer,
    ).deploy(weth, deployer.address, fixedFromFloat(0.01), 260);
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
    ethers.constants.AddressZero,
    '0x',
  );

  await diamondTx.wait(1);

  let tradingCompetition: TradingCompetitionFactory | undefined;
  let tradingCompetitionMerkle: TradingCompetitionMerkle | undefined;

  if (isTestnet) {
    tradingCompetition = await new TradingCompetitionFactory__factory(
      deployer,
    ).deploy();

    const wethToken = await tradingCompetition.callStatic.deployToken(
      'WETH',
      oracles.ETH,
    );
    await (await tradingCompetition.deployToken('WETH', oracles.ETH)).wait(1);

    const daiToken = await tradingCompetition.callStatic.deployToken(
      'DAI',
      oracles.DAI,
    );
    await (await tradingCompetition.deployToken('DAI', oracles.DAI)).wait(1);

    const wbtcToken = await tradingCompetition.callStatic.deployToken(
      'wBTC',
      oracles.BTC,
    );
    await (await tradingCompetition.deployToken('wBTC', oracles.BTC)).wait(1);

    const linkToken = await tradingCompetition.callStatic.deployToken(
      'LINK',
      oracles.LINK,
    );
    await (await tradingCompetition.deployToken('LINK', oracles.LINK)).wait(1);

    tokens = { ETH: wethToken, BTC: wbtcToken, DAI: daiToken, LINK: linkToken };

    tradingCompetitionMerkle = await new TradingCompetitionMerkle__factory(
      deployer,
    ).deploy(
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
  }

  const proxyManager = ProxyManager__factory.connect(
    instance.address,
    deployer,
  );

  const wethPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    fixedFromFloat(1.92),
  );

  let poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    fixedFromFloat(1.92),
  );

  await poolTx.wait(1);

  const wbtcPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    fixedFromFloat(1.35),
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    fixedFromFloat(1.35),
  );

  await poolTx.wait(1);

  const linkPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    fixedFromFloat(3.12),
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    fixedFromFloat(3.12),
  );

  await poolTx.wait(1);

  if (isTestnet && tradingCompetitionMerkle) {
    await tradingCompetition?.addWhitelisted([
      wethPoolAddress,
      wbtcPoolAddress,
      linkPoolAddress,
      tradingCompetitionMerkle.address,
    ]);
  }

  console.log('daiToken', tokens.DAI);
  console.log('wethToken', tokens.ETH);
  console.log('wbtcToken', tokens.BTC);
  console.log('linkToken', tokens.LINK);
  console.log('wethPoolAddress', wethPoolAddress);
  console.log('wbtcPoolAddress', wbtcPoolAddress);
  console.log('linkPoolAddress', linkPoolAddress);
  console.log('TradingCompetition: ', tradingCompetition?.address);
  console.log('TradingCompetitionMerkle: ', tradingCompetitionMerkle?.address);

  console.log('Deployer: ', deployer.address);
  console.log('PremiaInstance: ', instance.address);
}
