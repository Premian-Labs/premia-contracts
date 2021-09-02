import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import {
  OptionMath__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PremiaMining__factory,
  PremiaMiningProxy__factory,
  PoolBase__factory,
  PoolView__factory,
  PoolWrite__factory,
  Premia__factory,
  ProxyManager__factory,
  VolatilitySurfaceOracle__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { diamondCut } from './diamond';
import { BigNumber } from 'ethers';
import { fixedFromFloat } from '@premia/utils';

const UNISWAP_V2_FACTORY = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
const SUSHISWAP_FACTORY = '0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac';

export interface TokenAddresses {
  ETH: string;
  DAI: string;
  BTC: string;
  LINK: string;
}

export async function deployV2(
  weth: string,
  premia: string,
  fee64x64: BigNumber,
  feeReceiver: string,
  premiaFeeDiscount: string,
  tokens: TokenAddresses,
  oracles: TokenAddresses,
  sushiswapFactoryOverride?: string,
) {
  const [deployer] = await ethers.getSigners();

  const getSushiswapFactory = () =>
    sushiswapFactoryOverride ?? SUSHISWAP_FACTORY;

  //

  const optionMath = await new OptionMath__factory(deployer).deploy();

  const premiaDiamond = await new Premia__factory(deployer).deploy();
  const poolDiamond = await new Premia__factory(deployer).deploy();

  const ivolOracleImpl = await new VolatilitySurfaceOracle__factory(
    deployer,
  ).deploy();
  const ivolOracleProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(ivolOracleImpl.address);
  const ivolOracle = VolatilitySurfaceOracle__factory.connect(
    ivolOracleProxy.address,
    deployer,
  );

  //

  const premiaMiningImpl = await new PremiaMining__factory(deployer).deploy(
    premiaDiamond.address,
    premia,
  );

  const premiaMiningProxy = await new PremiaMiningProxy__factory(
    deployer,
  ).deploy(premiaMiningImpl.address, parseEther('10'));

  const premiaMining = PremiaMining__factory.connect(
    premiaMiningProxy.address,
    deployer,
  );

  //

  const proxyManagerFactory = new ProxyManager__factory(deployer);
  const proxyManagerImpl = await proxyManagerFactory.deploy(
    poolDiamond.address,
  );
  await proxyManagerImpl.deployed();

  await diamondCut(
    premiaDiamond,
    proxyManagerImpl.address,
    proxyManagerFactory,
  );
  const proxyManager = ProxyManager__factory.connect(
    premiaDiamond.address,
    deployer,
  );

  //////////////////////////////////////////////

  let registeredSelectors = [
    poolDiamond.interface.getSighash('supportsInterface(bytes4)'),
  ];

  const poolBaseFactory = new PoolBase__factory(deployer);
  const poolBaseImpl = await poolBaseFactory.deploy(
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  await poolBaseImpl.deployed();

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolBaseImpl.address,
      poolBaseFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const poolWriteFactory = new PoolWrite__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
    deployer,
  );
  const poolWriteImpl = await poolWriteFactory.deploy(
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    UNISWAP_V2_FACTORY,
    getSushiswapFactory(),
  );
  await poolWriteImpl.deployed();

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
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
    deployer,
  );
  const poolExerciseImpl = await poolExerciseFactory.deploy(
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  await poolExerciseImpl.deployed();

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolExerciseImpl.address,
      poolExerciseFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const poolViewFactory = new PoolView__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
    deployer,
  );
  const poolViewImpl = await poolViewFactory.deploy(
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  await poolViewImpl.deployed();

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
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
    deployer,
  );
  const poolIOImpl = await poolIOFactory.deploy(
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    UNISWAP_V2_FACTORY,
    getSushiswapFactory(),
  );
  await poolIOImpl.deployed();

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolIOImpl.address,
      poolIOFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const wethPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    // minimum amounts
    fixedFromFloat(100),
    fixedFromFloat(0.05),
    // deposit caps
    fixedFromFloat(1000000),
    fixedFromFloat(300),
    100,
  );

  let poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    // minimum amounts
    fixedFromFloat(100),
    fixedFromFloat(0.05),
    // deposit caps
    fixedFromFloat(1000000),
    fixedFromFloat(300),
    100,
  );

  await poolTx.wait(1);

  const wbtcPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    // minimum amounts
    fixedFromFloat(100),
    fixedFromFloat(0.005),
    // deposit caps
    fixedFromFloat(1000000),
    fixedFromFloat(25),
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    // minimum amounts
    fixedFromFloat(100),
    fixedFromFloat(0.005),
    // deposit caps
    fixedFromFloat(1000000),
    fixedFromFloat(25),
    100,
  );

  await poolTx.wait(1);

  const linkPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    // minimum amounts
    fixedFromFloat(100),
    fixedFromFloat(5),
    // deposit caps
    fixedFromFloat(1000000),
    fixedFromFloat(40000),
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    // minimum amounts
    fixedFromFloat(100),
    fixedFromFloat(5),
    // deposit caps
    fixedFromFloat(1000000),
    fixedFromFloat(40000),
    100,
  );

  await poolTx.wait(1);

  console.log('daiToken', tokens.DAI);
  console.log('wethToken', tokens.ETH);
  console.log('wbtcToken', tokens.BTC);
  console.log('linkToken', tokens.LINK);
  console.log('wethPoolAddress', wethPoolAddress);
  console.log('wbtcPoolAddress', wbtcPoolAddress);
  console.log('linkPoolAddress', linkPoolAddress);

  console.log('PremiaMining implementation:', premiaMiningImpl.address);
  console.log('PremiaMining proxy:', premiaMiningProxy.address);

  console.log('PoolWrite implementation:', poolWriteImpl.address);
  console.log('PoolIO implementation:', poolIOImpl.address);
  console.log('PoolView implementation:', poolViewImpl.address);
  console.log('PoolExercise implementation:', poolExerciseImpl.address);
  console.log('Deployer: ', deployer.address);
  console.log('PoolDiamond: ', poolDiamond.address);
  console.log('PremiaDiamond: ', premiaDiamond.address);

  console.log('IVOL oracle implementation: ', ivolOracleImpl.address);
  console.log('IVOL oracle: ', ivolOracle.address);

  return premiaDiamond.address;
}
