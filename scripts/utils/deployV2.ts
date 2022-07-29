import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import {
  ERC20__factory,
  NFTDisplay__factory,
  NFTSVG__factory,
  OptionMath__factory,
  PoolBase__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PoolSell__factory,
  PoolSettings__factory,
  PoolView__factory,
  PoolWrite__factory,
  Premia__factory,
  PremiaMining__factory,
  PremiaMiningProxy__factory,
  PremiaOptionNFTDisplay__factory,
  ProxyManager,
  ProxyManager__factory,
  ProxyUpgradeableOwnable__factory,
  VolatilitySurfaceOracle__factory,
} from '../../typechain';
import { diamondCut } from './diamond';
import { BigNumber } from 'ethers';
import { fixedFromFloat } from '@premia/utils';

export interface PoolToken {
  tokenAddress: string;
  oracleAddress: string;
  minimum: string;
}

export async function deployV2(
  weth: string,
  exchangeHelper: string,
  premia: string,
  fee64x64: BigNumber,
  feeReceiver: string,
  premiaFeeDiscount: string,
  ivolOracleProxyAddress?: string,
) {
  const [deployer] = await ethers.getSigners();

  //

  const optionMath = await new OptionMath__factory(deployer).deploy();
  await optionMath.deployed();

  const premiaDiamond = await new Premia__factory(deployer).deploy();
  await premiaDiamond.deployed();

  const poolDiamond = await new Premia__factory(deployer).deploy();
  await poolDiamond.deployed();

  if (!ivolOracleProxyAddress) {
    const ivolOracleImpl = await new VolatilitySurfaceOracle__factory(
      deployer,
    ).deploy();
    await ivolOracleImpl.deployed();

    const ivolOracleProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(ivolOracleImpl.address);
    await ivolOracleProxy.deployed();
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
  await premiaMiningImpl.deployed();

  const premiaMiningProxy = await new PremiaMiningProxy__factory(
    deployer,
  ).deploy(premiaMiningImpl.address, parseEther('0.5'));
  await premiaMiningProxy.deployed();

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
  await nftSVGLib.deployed();

  const nftDisplayLib = await new NFTDisplay__factory(
    { ['contracts/libraries/NFTSVG.sol:NFTSVG']: nftSVGLib.address },
    deployer,
  ).deploy();
  await nftDisplayLib.deployed();

  const nftDisplay = await new PremiaOptionNFTDisplay__factory(
    {
      ['contracts/libraries/NFTDisplay.sol:NFTDisplay']: nftDisplayLib.address,
    },
    deployer,
  ).deploy();
  await nftDisplay.deployed();

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
    exchangeHelper,
  );
  await poolBaseImpl.deployed();

  console.log(
    `PoolBase Implementation : ${poolBaseImpl.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper}`,
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
    exchangeHelper,
  );
  await poolWriteImpl.deployed();

  console.log(
    `PoolWrite Implementation : ${poolWriteImpl.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper} (OptionMath: ${optionMath.address})`,
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
    exchangeHelper,
  );
  await poolExerciseImpl.deployed();

  console.log(
    `PoolExercise Implementation : ${poolExerciseImpl.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper} (OptionMath: ${optionMath.address})`,
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
    exchangeHelper,
  );
  await poolViewImpl.deployed();

  console.log(
    `PoolView Implementation : ${poolViewImpl.address} ${nftDisplay.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper} (OptionMath: ${optionMath.address})`,
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
    exchangeHelper,
  );
  await poolSellImpl.deployed();

  console.log(
    `PoolSell Implementation : ${poolSellImpl.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper} (OptionMath: ${optionMath.address})`,
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
    exchangeHelper,
  );
  await poolSettingsImpl.deployed();

  console.log(
    `PoolSettings Implementation : ${poolSettingsImpl.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper}`,
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
    exchangeHelper,
  );
  await poolIOImpl.deployed();

  console.log(
    `PoolIO Implementation : ${poolIOImpl.address} ${ivolOracle.address} ${weth} ${premiaMining.address} ${feeReceiver} ${premiaFeeDiscount} ${fee64x64} ${exchangeHelper} (OptionMath: ${optionMath.address})`,
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

  console.log('\n\n------------------------------------------------\n\n');

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

  return { premiaDiamond, proxyManager };
}

export async function deployPool(
  proxyManager: ProxyManager,
  base: PoolToken,
  underlying: PoolToken,
  miningWeight: number,
) {
  const baseTokenSymbol = await ERC20__factory.connect(
    base.tokenAddress,
    proxyManager.provider,
  ).symbol();

  const underlyingTokenSymbol = await ERC20__factory.connect(
    underlying.tokenAddress,
    proxyManager.provider,
  ).symbol();

  const minBase64x64 = fixedFromFloat(base.minimum);
  const minUnderlying64x64 = fixedFromFloat(underlying.minimum);

  const poolAddress = await proxyManager.callStatic.deployPool(
    base.tokenAddress,
    underlying.tokenAddress,
    base.oracleAddress,
    underlying.oracleAddress,
    minBase64x64,
    minUnderlying64x64,
    miningWeight,
  );

  let poolTx = await proxyManager.deployPool(
    base.tokenAddress,
    underlying.tokenAddress,
    base.oracleAddress,
    underlying.oracleAddress,
    minBase64x64,
    minUnderlying64x64,
    miningWeight,
  );

  console.log(
    `${underlyingTokenSymbol}/${baseTokenSymbol} pool : ${poolAddress} ${base.tokenAddress} ${underlying.tokenAddress} ${base.oracleAddress} ${underlying.oracleAddress} ${minBase64x64} ${minUnderlying64x64} ${miningWeight}`,
  );

  await poolTx.wait(1);

  return poolAddress;
}
