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
  NFTSVG__factory,
  NFTDisplay__factory,
  PremiaOptionNFTDisplay__factory,
  PoolSettings__factory,
} from '../../typechain';
import { diamondCut } from './diamond';
import { BigNumber, BigNumberish } from 'ethers';
import { fixedFromFloat } from '@premia/utils';

const UNISWAP_V2_FACTORY = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
const SUSHISWAP_FACTORY = '0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac';

export interface TokenAddresses {
  ETH: string;
  DAI: string;
  BTC: string;
  LINK: string;
}

export interface TokenAmounts {
  ETH: BigNumberish;
  DAI: BigNumberish;
  BTC: BigNumberish;
  LINK: BigNumberish;
}

export async function deployV2(
  weth: string,
  premia: string,
  fee64x64: BigNumber,
  feeReceiver: string,
  premiaFeeDiscount: string,
  tokens: TokenAddresses,
  oracles: TokenAddresses,
  minAmounts: TokenAmounts,
  capAmounts: TokenAmounts,
  sushiswapFactoryOverride?: string,
  ivolOracleProxyAddress?: string,
) {
  const [deployer] = await ethers.getSigners();

  const getSushiswapFactory = () =>
    sushiswapFactoryOverride ?? SUSHISWAP_FACTORY;

  //

  const optionMath = await new OptionMath__factory(deployer).deploy();
  const premiaDiamond = await new Premia__factory(deployer).deploy();
  const poolDiamond = await new Premia__factory(deployer).deploy();

  if (!ivolOracleProxyAddress) {
    const ivolOracleImpl = await new VolatilitySurfaceOracle__factory(
      deployer,
    ).deploy();
    const ivolOracleProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(ivolOracleImpl.address);
    ivolOracleProxyAddress = ivolOracleProxy.address;
  }

  const ivolOracle = VolatilitySurfaceOracle__factory.connect(
    ivolOracleProxyAddress,
    deployer,
  );

  console.log(`Option math : ${optionMath.address}`);
  console.log(`Premia Diamond : ${premiaDiamond.address}`);
  console.log(`Pool Diamond : ${poolDiamond.address}`);
  console.log(`IVOL oracle implementation : ${ivolOracleProxyAddress}`);
  console.log(
    `IVOL oracle : ${ivolOracleProxyAddress} (${ivolOracleProxyAddress})`,
  );

  //

  const premiaMiningImpl = await new PremiaMining__factory(deployer).deploy(
    premiaDiamond.address,
    premia,
  );

  const premiaMiningProxy = await new PremiaMiningProxy__factory(
    deployer,
  ).deploy(premiaMiningImpl.address, parseEther('0.5'));

  const premiaMining = PremiaMining__factory.connect(
    premiaMiningProxy.address,
    deployer,
  );

  console.log(`Premia Mining implementation : ${premiaMiningImpl.address}`);
  console.log(
    `Premia Mining : ${premiaMiningProxy.address} (${
      premiaMiningImpl.address
    } / ${parseEther('0.5')})`,
  );

  const nftSVGLib = await new NFTSVG__factory(deployer).deploy();

  const nftDisplayLib = await new NFTDisplay__factory(
    { ['contracts/libraries/NFTSVG.sol:NFTSVG']: nftSVGLib.address },
    deployer,
  ).deploy();

  const nftDisplay = await new PremiaOptionNFTDisplay__factory(
    {
      ['contracts/libraries/NFTDisplay.sol:NFTDisplay']: nftDisplayLib.address,
    },
    deployer,
  ).deploy();

  console.log(`NFT SVG : ${nftSVGLib.address}`);
  console.log(
    `NFT Display : ${nftSVGLib.address} (NFTSVG: ${nftSVGLib.address})`,
  );
  console.log(
    `Option display : ${nftDisplay.address} (NFTDisplay: ${nftDisplayLib.address})`,
  );

  //

  const proxyManagerFactory = new ProxyManager__factory(deployer);
  const proxyManagerImpl = await proxyManagerFactory.deploy(
    poolDiamond.address,
  );
  await proxyManagerImpl.deployed();

  console.log(
    `Proxy Manager : ${proxyManagerImpl.address} (${poolDiamond.address})`,
  );

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

  console.log(
    `PoolBase Implementation : ${poolBaseImpl.address} (${ivolOracle.address}, ${tokens.ETH}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64})`,
  );

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

  console.log(
    `PoolWrite Implementation : ${poolWriteImpl.address} (${
      ivolOracle.address
    }, ${tokens.ETH}, ${
      premiaMining.address
    }, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${UNISWAP_V2_FACTORY}, ${getSushiswapFactory()}) (OptionMath: ${
      optionMath.address
    })`,
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

  console.log(
    `PoolExercise Implementation : ${poolExerciseImpl.address} (${ivolOracle.address}, ${tokens.ETH}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}) (OptionMath: ${optionMath.address})`,
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

  const poolViewFactory = new PoolView__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
    deployer,
  );
  const poolViewImpl = await poolViewFactory.deploy(
    nftDisplay.address,
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  await poolViewImpl.deployed();

  console.log(
    `PoolView Implementation : ${poolViewImpl.address} (${nftDisplay.address}, ${ivolOracle.address}, ${tokens.ETH}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}) (OptionMath: ${optionMath.address})`,
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

  const poolSettingsFactory = new PoolSettings__factory(deployer);
  const poolSettingsImpl = await poolSettingsFactory.deploy(
    ivolOracle.address,
    tokens.ETH,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
  );
  await poolSettingsImpl.deployed();

  console.log(
    `PoolSettings Implementation : ${poolSettingsImpl.address} (${nftDisplay.address}, ${ivolOracle.address}, ${tokens.ETH}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64})`,
  );

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolSettingsImpl.address,
      poolSettingsFactory,
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

  console.log(
    `PoolIO Implementation : ${poolIOImpl.address} (${ivolOracle.address}, ${
      tokens.ETH
    }, ${
      premiaMining.address
    }, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${UNISWAP_V2_FACTORY}, ${getSushiswapFactory()}) (OptionMath: ${
      optionMath.address
    })`,
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

  const minDai = fixedFromFloat(minAmounts.DAI);
  const minWeth = fixedFromFloat(minAmounts.ETH);
  const minWbtc = fixedFromFloat(minAmounts.BTC);
  const minLink = fixedFromFloat(minAmounts.LINK);

  const capDai = fixedFromFloat(capAmounts.DAI);
  const capWeth = fixedFromFloat(capAmounts.ETH);
  const capWbtc = fixedFromFloat(capAmounts.BTC);
  const capLink = fixedFromFloat(capAmounts.LINK);

  const wethPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    // minimum amounts
    minDai,
    minWeth,
    // deposit caps
    capDai,
    capWeth,
    100,
  );

  let poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.ETH,
    oracles.DAI,
    oracles.ETH,
    // minimum amounts
    minDai,
    minWeth,
    // deposit caps
    capDai,
    capWeth,
    100,
  );

  console.log(
    `WETH/DAI pool : ${wethPoolAddress} (${tokens.DAI}, ${tokens.ETH}, ${
      oracles.DAI
    }, ${oracles.ETH}, ${minDai}, ${minWeth}, ${capDai}, ${capWeth}, ${100})`,
  );

  await poolTx.wait(1);

  const wbtcPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    // minimum amounts
    minDai,
    minWbtc,
    // deposit caps
    capDai,
    capWbtc,
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.BTC,
    oracles.DAI,
    oracles.BTC,
    // minimum amounts
    minDai,
    minWbtc,
    // deposit caps
    capDai,
    capWbtc,
    100,
  );

  console.log(
    `WBTC/DAI pool : ${wbtcPoolAddress} (${tokens.DAI}, ${tokens.BTC}, ${
      oracles.DAI
    }, ${oracles.BTC}, ${minDai}, ${minWbtc}, ${capDai}, ${capWbtc}, ${100})`,
  );

  await poolTx.wait(1);

  const linkPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    // minimum amounts
    minDai,
    minLink,
    // deposit caps
    capDai,
    capLink,
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.DAI,
    tokens.LINK,
    oracles.DAI,
    oracles.LINK,
    // minimum amounts
    minDai,
    minLink,
    // deposit caps
    capDai,
    capLink,
    100,
  );

  console.log(
    `LINK/DAI pool : ${linkPoolAddress} (${tokens.DAI}, ${tokens.LINK}, ${
      oracles.DAI
    }, ${oracles.LINK}, ${minDai}, ${minLink}, ${capDai}, ${capLink}, ${100})`,
  );

  await poolTx.wait(1);

  console.log('\n\n------------------------------------------------\n\n');

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

  console.log('IVOL oracle implementation: ', ivolOracleProxyAddress);
  console.log('IVOL oracle: ', ivolOracle.address);

  return premiaDiamond.address;
}
