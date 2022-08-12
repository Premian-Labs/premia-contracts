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
  const weth = '0x4200000000000000000000000000000000000006';
  const premiaMining = '0xbfDC37499D99046710a9C567016791c71cD25Cf6';
  const feeReceiver = '0x982aD8F6b468DfC460e3cd3087DF348895CA3080';
  const feeDiscountAddress = ethers.constants.AddressZero;
  const fee64x64 = fixedFromFloat(0.03);
  const optionMath = '0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350';
  const nftDisplay = '0x9d3F42C5ca9426303b91567288E461230049e092';

  const exchangeHelper = '0x834C025fA5Eb6726803a2D67f160fcfABC49a174';

  // const poolDiamond = '0x089E3422F23A57fD07ae68a4ffB7268B3bd78Fa2';

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
  await poolBase.deployed();

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
  await poolExercise.deployed();

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
  await poolIO.deployed();

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
  await poolSell.deployed();

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
  await poolSettings.deployed();

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
  await poolView.deployed();

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
  await poolWrite.deployed();

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
