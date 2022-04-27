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

export const UNISWAP_V2_FACTORY = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
export const SUSHISWAP_FACTORY = '0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac';

export const UNISWAP_V2_INIT_HASH =
  '96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
export const SUSHISWAP_INIT_HASH =
  'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303';

export interface PoolToken {
  tokenAddress: string;
  oracleAddress: string;
  minimum: string;
}

export interface DEXOverrides {
  uniswapV2Factory?: string;
  uniswapV2InitHash?: string;
  sushiswapFactory?: string;
  sushiswapInitHash?: string;
}

export async function deployV2(
  weth: string,
  premia: string,
  fee64x64: BigNumber,
  utilizationFee64x64: BigNumber,
  feeReceiver: string,
  premiaFeeDiscount: string,
  ivolOracleProxyAddress?: string,
  dexOverrides?: DEXOverrides,
) {
  const [deployer] = await ethers.getSigners();

  const getSushiswapFactory = () =>
    dexOverrides?.sushiswapFactory ?? SUSHISWAP_FACTORY;

  const getUniswapV2Factory = () =>
    dexOverrides?.uniswapV2Factory ?? UNISWAP_V2_FACTORY;

  const getSushiswapInitHash = () =>
    dexOverrides?.sushiswapInitHash ?? SUSHISWAP_INIT_HASH;

  const getUniswapV2InitHash = () =>
    dexOverrides?.uniswapV2InitHash ?? UNISWAP_V2_INIT_HASH;

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
    getUniswapV2Factory(),
    getSushiswapFactory(),
    getUniswapV2InitHash(),
    getSushiswapInitHash(),
  );
  await poolWriteImpl.deployed();

  console.log(
    `PoolWrite Implementation : ${poolWriteImpl.address} (${
      ivolOracle.address
    }, ${weth}, ${
      premiaMining.address
    }, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}, ${getUniswapV2Factory()}, ${getSushiswapFactory()} ${getUniswapV2InitHash()} ${getSushiswapInitHash()}) (OptionMath: ${
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
    getUniswapV2Factory(),
    getSushiswapFactory(),
    getUniswapV2InitHash(),
    getSushiswapInitHash(),
  );
  await poolIOImpl.deployed();

  console.log(
    `PoolIO Implementation : ${poolIOImpl.address} (${
      ivolOracle.address
    }, ${weth}, ${
      premiaMining.address
    }, ${feeReceiver}, ${premiaFeeDiscount}, ${fee64x64}, ${utilizationFee64x64}, ${getUniswapV2Factory()}, ${getSushiswapFactory()} ${getUniswapV2InitHash()} ${getSushiswapInitHash()}) (OptionMath: ${
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
    `${underlyingTokenSymbol}/${baseTokenSymbol} pool : ${poolAddress} ${base.tokenAddress} ${underlying.tokenAddress} ${base.oracleAddress} ${underlying.oracleAddress} ${base.minimum} ${underlying.minimum} ${miningWeight}`,
  );

  await poolTx.wait(1);

  return poolAddress;
}
