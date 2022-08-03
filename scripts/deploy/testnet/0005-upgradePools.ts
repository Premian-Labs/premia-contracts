import { ethers } from 'hardhat';
import {
  ExchangeHelper__factory,
  PoolBase__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PoolSell__factory,
  PoolSettings__factory,
  PoolView__factory,
  PoolWrite__factory,
  Premia__factory,
} from '../../../typechain';
import { fixedFromFloat } from '@premia/utils';
import { diamondCut } from '../../utils/diamond';
import { ZERO_ADDRESS } from '../../../test/utils/constants';

function printFacets(implAddress: string, factory: any) {
  const facetCuts = [
    {
      target: implAddress,
      action: 1,
      selectors: Object.keys(factory.interface.functions).map((fn) => {
        const selector = factory.interface.getSighash(fn);
        console.log(selector, fn);

        return selector;
      }),
    },
  ];

  console.log(facetCuts);
}

async function main() {
  const [deployer] = await ethers.getSigners();

  const ivolOracle = '0x9e88fe5e5249CD6429269B072c9476b6908dCBf2';
  const weth = '0xc778417e063141139fce010982780140aa0cd5ab';
  const premiaMining = '0x127cA21D2773229e1728D606921162733798b7B1';
  const feeReceiver = '0xB447ae5Cf7367a29bF69ED7C961Eb1D20c10AB9E';
  const feeDiscountAddress = '0x82f4E449476430246FDaa3A820E1910f303cD16D';
  const fee64x64 = fixedFromFloat(0.03);
  const optionMath = '0x99e603c3Ac7b0cB5CE6460D878750C1930DdB356';
  const sushiswapFactory = '0xc35DADB65012eC5796536bD9864eD8773aBc74C4';
  const nftDisplay = '0x3bc3654819abceE7581940315ed156e2323f086a';
  const poolDiamondAddress = '0xB07aEe041eF7aa301BDd8926886E6E45ae71D52b';

  const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

  const poolDiamond = Premia__factory.connect(poolDiamondAddress, deployer);

  const facets = (await poolDiamond.facets()).filter(
    (el) => el.target !== poolDiamond.address,
  );

  const selectorsToRemove = [];
  for (const el of facets) {
    for (const sel of el.selectors) {
      selectorsToRemove.push(sel);
    }
  }

  if (selectorsToRemove.length > 0) {
    await poolDiamond.diamondCut(
      [{ target: ZERO_ADDRESS, selectors: selectorsToRemove, action: 2 }],
      ZERO_ADDRESS,
      '0x',
    );
  }

  let registeredSelectors = [
    poolDiamond.interface.getSighash('supportsInterface(bytes4)'),
  ];

  const poolBaseFactory = new PoolBase__factory(deployer);
  const poolBase = await poolBaseFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  console.log(
    `PoolBase : ${poolBase.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  await poolBase.deployed();
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolBase.address,
      poolBaseFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolBase.address, poolBaseFactory);

  //

  const poolExerciseFactory = new PoolExercise__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath },
    deployer,
  );
  const poolExercise = await poolExerciseFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  console.log(
    `PoolExercise : ${poolExercise.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  await poolExercise.deployed();
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolExercise.address,
      poolExerciseFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolExercise.address, poolExerciseFactory);

  //

  const poolIOFactory = new PoolIO__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath },
    deployer,
  );
  const poolIO = await poolIOFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  console.log(
    `PoolIO : ${poolIO.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  await poolIO.deployed();
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolIO.address,
      poolIOFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolIO.address, poolIOFactory);

  //

  const poolSellFactory = new PoolSell__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath },
    deployer,
  );
  const poolSell = await poolSellFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  console.log(
    `PoolSell : ${poolSell.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  await poolSell.deployed();
  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolSell.address,
      poolSellFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolSell.address, poolSellFactory);

  //

  const poolSettingsFactory = new PoolSettings__factory(deployer);
  const poolSettings = await poolSettingsFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  await poolSettings.deployed();
  console.log(
    `PoolSettings : ${poolSettings.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolSettings.address,
      poolSettingsFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolSettings.address, poolSettingsFactory);

  //

  const poolViewFactory = new PoolView__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath },
    deployer,
  );
  const poolView = await poolViewFactory.deploy(
    nftDisplay,
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  await poolView.deployed();
  console.log(
    `PoolView : ${poolView.address} ${nftDisplay} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolView.address,
      poolViewFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolView.address, poolViewFactory);

  //

  const poolWriteFactory = await new PoolWrite__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath },
    deployer,
  );
  const poolWrite = await poolWriteFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper.address,
  );

  await poolWrite.deployed();
  console.log(
    `PoolWrite : ${poolWrite.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper.address}`,
  );

  registeredSelectors = registeredSelectors.concat(
    await diamondCut(
      poolDiamond,
      poolWrite.address,
      poolWriteFactory,
      registeredSelectors,
    ),
  );

  // printFacets(poolWrite.address, poolWriteFactory);

  //
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
