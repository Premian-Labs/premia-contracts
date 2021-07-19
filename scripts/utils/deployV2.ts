import { ethers } from 'hardhat';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { fixedFromFloat } from '../../test/utils/math';
import {
  OptionMath__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PoolView__factory,
  PoolWrite__factory,
  Premia__factory,
  ProxyManager__factory,
} from '../../typechain';
import { diamondCut } from './diamond';
import { BigNumber } from 'ethers';

export interface TokenAddresses {
  ETH: string;
  DAI: string;
  BTC: string;
  LINK: string;
}

export async function deployV2(
  weth: string,
  fee64x64: BigNumber,
  feeReceiver: string,
  premiaFeeDiscount: string,
  tokens: TokenAddresses,
  oracles: TokenAddresses,
  isTestnet: boolean,
) {
  const [deployer] = await ethers.getSigners();

  const optionMath = await new OptionMath__factory(deployer).deploy();

  const premiaDiamond = await new Premia__factory(deployer).deploy();
  const poolDiamond = await new Premia__factory(deployer).deploy();

  //

  const proxyManagerFactory = new ProxyManager__factory(deployer);
  const proxyManager = await proxyManagerFactory.deploy(poolDiamond.address);
  await diamondCut(premiaDiamond, proxyManager.address, proxyManagerFactory);

  let registeredSelectors = [
    poolDiamond.interface.getSighash('supportsInterface(bytes4)'),
  ];

  //////////////////////////////////////////////

  const poolWriteFactory = new PoolWrite__factory(
    { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
    deployer,
  );
  const poolWriteImpl = await poolWriteFactory.deploy(
    tokens.ETH,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolWriteImpl.address,
      poolWriteFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const poolExerciseFactory = new PoolExercise__factory(
    { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
    deployer,
  );
  const poolExerciseImpl = await poolExerciseFactory.deploy(
    tokens.ETH,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolExerciseImpl.address,
      poolExerciseFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const poolViewFactory = new PoolView__factory(deployer);
  const poolViewImpl = await poolViewFactory.deploy(
    tokens.ETH,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolViewImpl.address,
      poolViewFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const poolIOFactory = new PoolIO__factory(
    { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
    deployer,
  );
  const poolIOImpl = await poolIOFactory.deploy(
    tokens.ETH,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolIOImpl.address,
      poolIOFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const facetCuts = [
    await new ProxyManager__factory(deployer).deploy(poolDiamond.address),
  ].map(function (f) {
    return {
      target: f.address,
      action: 0,
      selectors: Object.keys(f.interface.functions).map((fn) =>
        f.interface.getSighash(fn),
      ),
    };
  });

  const instance = await new Premia__factory(deployer).deploy();

  const diamondTx = await instance.diamondCut(
    facetCuts,
    ethers.constants.AddressZero,
    '0x',
  );

  await diamondTx.wait(1);

  // ToDo : Deploy test tokens pools for testnet

  const wethPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    parseUnits('100', 8),
    parseUnits('0.05', 18),
    fixedFromFloat(1.92),
  );

  let poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    parseUnits('100', 8),
    parseUnits('0.05', 18),
    fixedFromFloat(1.92),
  );

  await poolTx.wait(1);

  const wbtcPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    parseUnits('100', 8),
    parseUnits('0.005', 8),
    fixedFromFloat(1.35),
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    parseUnits('100', 8),
    parseUnits('0.005', 8),
    fixedFromFloat(1.35),
  );

  await poolTx.wait(1);

  const linkPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    parseUnits('100', 8),
    parseUnits('5', 18),
    fixedFromFloat(3.12),
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    parseUnits('100', 8),
    parseUnits('5', 18),
    fixedFromFloat(3.12),
  );

  await poolTx.wait(1);

  console.log('daiToken', tokens.DAI);
  console.log('wethToken', tokens.ETH);
  console.log('wbtcToken', tokens.BTC);
  console.log('linkToken', tokens.LINK);
  console.log('wethPoolAddress', wethPoolAddress);
  console.log('wbtcPoolAddress', wbtcPoolAddress);
  console.log('linkPoolAddress', linkPoolAddress);

  console.log('PoolWrite implementation:', poolWriteImpl.address);
  console.log('PoolIO implementation:', poolIOImpl.address);
  console.log('PoolView implementation:', poolViewImpl.address);
  console.log('PoolExercise implementation:', poolExerciseImpl.address);
  console.log('Deployer: ', deployer.address);
  console.log('PremiaInstance: ', instance.address);
}
