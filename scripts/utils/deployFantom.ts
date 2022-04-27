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
  PoolSell__factory,
} from '../../typechain';
import { diamondCut } from './diamond';
import { BigNumber, BigNumberish } from 'ethers';
import { fixedFromFloat } from '@premia/utils';

const SPIRITSWAP_FACTORY = '0xef45d134b73241eda7703fa787148d9c9f4950b0';
const SPOOKYSWAP_FACTORY = '0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3';

const SPIRITSWAP_INIT_HASH =
  '0xe242e798f6cee26a9cb0bbf24653bf066e5356ffeac160907fe2cc108e238617';
const SPOOKYSWAP_INIT_HASH =
  '0xcdf2deca40a0bd56de8e3ce5c7df6727e5b1bf2ac96f283fa9c4b3e6b42ea9d2';

export interface TokenAddresses {
  FTM: string;
  YFI: string;
  WETH: string;
  WBTC: string;
  USDC: string;
}

export interface TokenAmounts {
  FTM: BigNumberish;
  YFI: BigNumberish;
  WETH: BigNumberish;
  WBTC: BigNumberish;
  USDC: BigNumberish;
}

export async function deployV2(
  weth: string,
  premia: string,
  fee64x64: BigNumber,
  utilizationFee64x64: BigNumber,
  feeReceiver: string,
  premiaFeeDiscount: string,
  tokens: TokenAddresses,
  oracles: TokenAddresses,
  minAmounts: TokenAmounts,
  sushiswapFactoryOverride?: string,
  ivolOracleProxyAddress?: string,
) {
  const [deployer] = await ethers.getSigners();

  const getSpookyswapFactory = () =>
    sushiswapFactoryOverride ?? SPOOKYSWAP_FACTORY;

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

  console.log(
    `Premia Mining implementation : ${premiaMiningImpl.address} (Args: ${premiaDiamond.address} / ${premia})`,
  );
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
    `NFT Display : ${nftDisplayLib.address} (NFTSVG: ${nftSVGLib.address})`,
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
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
  );
  await poolBaseImpl.deployed();

  console.log(
    `PoolBase Implementation : ${poolBaseImpl.address} (${ivolOracle.address}, ${weth}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64})`,
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
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
    SPIRITSWAP_FACTORY,
    getSpookyswapFactory(),
    SPIRITSWAP_INIT_HASH,
    SPOOKYSWAP_INIT_HASH,
  );
  await poolWriteImpl.deployed();

  console.log(
    `PoolWrite Implementation : ${poolWriteImpl.address} (${
      ivolOracle.address
    }, ${weth}, ${
      premiaMining.address
    }, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}, ${SPIRITSWAP_FACTORY}, ${getSpookyswapFactory()}) (OptionMath: ${
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
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
  );
  await poolExerciseImpl.deployed();

  console.log(
    `PoolExercise Implementation : ${poolExerciseImpl.address} (${ivolOracle.address}, ${weth}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}) (OptionMath: ${optionMath.address})`,
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
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
  );
  await poolViewImpl.deployed();

  console.log(
    `PoolView Implementation : ${poolViewImpl.address} (${nftDisplay.address}, ${ivolOracle.address}, ${weth}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}) (OptionMath: ${optionMath.address})`,
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

  const poolSellFactory = new PoolSell__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
    deployer,
  );
  const poolSellImpl = await poolSellFactory.deploy(
    ivolOracle.address,
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
  );
  await poolSellImpl.deployed();

  console.log(
    `PoolSell Implementation : ${poolSellImpl.address} (${ivolOracle.address}, ${weth}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}) (OptionMath: ${optionMath.address})`,
  );

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolSellImpl.address,
      poolSellFactory,
      registeredSelectors,
    ),
  );

  //////////////////////////////////////////////

  const poolSettingsFactory = new PoolSettings__factory(deployer);
  const poolSettingsImpl = await poolSettingsFactory.deploy(
    ivolOracle.address,
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
  );
  await poolSettingsImpl.deployed();

  console.log(
    `PoolSettings Implementation : ${poolSettingsImpl.address} (${ivolOracle.address}, ${weth}, ${premiaMining.address}, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64})`,
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
    weth,
    premiaMining.address,
    feeReceiver,
    premiaFeeDiscount,
    fee64x64,
    utilizationFee64x64,
    SPIRITSWAP_FACTORY,
    getSpookyswapFactory(),
    SPIRITSWAP_INIT_HASH,
    SPOOKYSWAP_INIT_HASH,
  );
  await poolIOImpl.deployed();

  console.log(
    `PoolIO Implementation : ${poolIOImpl.address} (${
      ivolOracle.address
    }, ${weth}, ${
      premiaMining.address
    }, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}, ${SPIRITSWAP_FACTORY}, ${getSpookyswapFactory()}) (OptionMath: ${
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

  const minWeth = fixedFromFloat(minAmounts.WETH);
  const minWbtc = fixedFromFloat(minAmounts.WBTC);
  const minUsdc = fixedFromFloat(minAmounts.USDC);
  const minYfi = fixedFromFloat(minAmounts.YFI);
  const minFtm = fixedFromFloat(minAmounts.FTM);

  const wethPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.USDC,
    tokens.WETH,
    oracles.USDC,
    oracles.WETH,
    // minimum amounts
    minUsdc,
    minWeth,
    100,
  );

  let poolTx = await proxyManager.deployPool(
    tokens.USDC,
    tokens.WETH,
    oracles.USDC,
    oracles.WETH,
    // minimum amounts
    minUsdc,
    minWeth,
    100,
  );

  console.log(
    `WETH/USDC pool : ${wethPoolAddress} (${tokens.USDC}, ${tokens.WETH}, ${
      oracles.USDC
    }, ${oracles.WETH}, ${minUsdc}, ${minWeth}, ${100})`,
  );

  await poolTx.wait(1);

  const wbtcPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.USDC,
    tokens.WBTC,
    oracles.USDC,
    oracles.WBTC,
    // minimum amounts
    minUsdc,
    minWbtc,
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.USDC,
    tokens.WBTC,
    oracles.USDC,
    oracles.WBTC,
    // minimum amounts
    minUsdc,
    minWbtc,
    100,
  );

  console.log(
    `WBTC/USDC pool : ${wbtcPoolAddress} (${tokens.USDC}, ${tokens.WBTC}, ${
      oracles.USDC
    }, ${oracles.WBTC}, ${minUsdc}, ${minWbtc}, ${100})`,
  );

  await poolTx.wait(1);

  const ftmPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.USDC,
    tokens.FTM,
    oracles.USDC,
    oracles.FTM,
    // minimum amounts
    minUsdc,
    minFtm,
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.USDC,
    tokens.FTM,
    oracles.USDC,
    oracles.FTM,
    // minimum amounts
    minUsdc,
    minFtm,
    100,
  );

  console.log(
    `FTM/USDC pool : ${ftmPoolAddress} (${tokens.USDC}, ${tokens.FTM}, ${
      oracles.USDC
    }, ${oracles.FTM}, ${minUsdc}, ${minFtm}, ${100})`,
  );

  await poolTx.wait(1);

  const yfiPoolAddress = await proxyManager.callStatic.deployPool(
    tokens.USDC,
    tokens.YFI,
    oracles.USDC,
    oracles.YFI,
    // minimum amounts
    minUsdc,
    minYfi,
    100,
  );

  poolTx = await proxyManager.deployPool(
    tokens.USDC,
    tokens.YFI,
    oracles.USDC,
    oracles.YFI,
    // minimum amounts
    minUsdc,
    minYfi,
    100,
  );

  console.log(
    `YFI/USDC pool : ${yfiPoolAddress} (${tokens.USDC}, ${tokens.YFI}, ${
      oracles.USDC
    }, ${oracles.YFI}, ${minUsdc}, ${minYfi}, ${100})`,
  );

  await poolTx.wait(1);

  console.log('\n\n------------------------------------------------\n\n');

  console.log('usdc token:', tokens.USDC);
  console.log('weth token:', tokens.WETH);
  console.log('wbtc token:', tokens.WBTC);
  console.log('yfi token:', tokens.YFI);
  console.log('ftm token:', tokens.FTM);
  console.log('weth pool address:', wethPoolAddress);
  console.log('wbtc pool address:', wbtcPoolAddress);
  console.log('yfi pool address:', yfiPoolAddress);
  console.log('ftm pool address:', ftmPoolAddress);

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
