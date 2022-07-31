import { ethers } from 'hardhat';
import {
  PoolBase__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PoolSell__factory,
  PoolSettings__factory,
  PoolView__factory,
  PoolWrite__factory,
} from '../../../typechain';
import { fixedFromFloat } from '@premia/utils';

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

  const ivolOracle = '0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF';
  const weth = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1';
  const premiaMining = '0xbC3c01D954282eEd8433da4359C1ac1443a7d09A';
  const feeReceiver = '0x7bf2392bd078C8353069CffeAcc67c094079be23';
  const feeDiscountAddress = '0x7Fa86681A7c19416950bAE6c04A5116f3b07116D';
  const fee64x64 = fixedFromFloat(0.03);
  const optionMath = '0xC7A7275BC25a7Bf07C6D0c2f8784c5450Cb9B8f5';
  const nftDisplay = '0x9d22c080fde848f47b0c7654483715f27e44e433';

  const exchangeHelper = ''; // ToDo : add exchange helper

  if (exchangeHelper.length == 0) {
    throw new Error('Exchange helper address is not set');
  }

  // const poolDiamond = '0xaD74c7C6485b65dc1E38342D390F72d85DeE3411';

  const poolBaseFactory = new PoolBase__factory(deployer);
  const poolBase = await poolBaseFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolBase : ${poolBase.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolBase.address, poolBaseFactory);

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
    exchangeHelper,
  );

  console.log(
    `PoolExercise : ${poolExercise.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolExercise.address, poolExerciseFactory);

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
    exchangeHelper,
  );

  console.log(
    `PoolIO : ${poolIO.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolIO.address, poolIOFactory);

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
    exchangeHelper,
  );

  console.log(
    `PoolSell : ${poolSell.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolSell.address, poolSellFactory);

  //

  const poolSettingsFactory = new PoolSettings__factory(deployer);
  const poolSettings = await poolSettingsFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolSettings : ${poolSettings.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolSettings.address, poolSettingsFactory);

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
    exchangeHelper,
  );

  console.log(
    `PoolView : ${poolView.address} ${nftDisplay} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolView.address, poolViewFactory);

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
    exchangeHelper,
  );

  console.log(
    `PoolWrite : ${poolWrite.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolWrite.address, poolWriteFactory);

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
