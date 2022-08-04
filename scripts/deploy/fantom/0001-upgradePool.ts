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

  const ivolOracle = '0xD77203CDBd33B849Dc0B03A4f906F579A766C0A6';
  const wftm = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';
  const premiaMining = '0x0389996552F5Da35fa6Ddc80B083F78622df3A6f';
  const feeReceiver = '0xfE817b00f2Cd0e062a5F66067E9A9ef789144Cbf';
  const feeDiscountAddress = '0xb5Ab6ccd7CaC6bba5DC31EcE0845f282BCD7E527';
  const fee64x64 = fixedFromFloat(0.03);
  const optionMath = '0x25c1445d8FAc6645Ec88Ff62BaC777e3e7b4840F';
  const nftDisplay = '0x8D69eAcDFfEE59c5F4C9936aDaBE72EAF891745D';

  const exchangeHelper = '0x5Af7a354C9C35B58b4278aB0e1E934fab01b26Ab';

  // const poolDiamond = '0x834C025fA5Eb6726803a2D67f160fcfABC49a174';

  const poolBaseFactory = new PoolBase__factory(deployer);
  const poolBase = await poolBaseFactory.deploy(
    ivolOracle,
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolBase : ${poolBase.address} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolBase.address, poolBaseFactory);
  await poolBase.deployed();

  const poolExerciseFactory = new PoolExercise__factory(
    { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath },
    deployer,
  );
  const poolExercise = await poolExerciseFactory.deploy(
    ivolOracle,
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolExercise : ${poolExercise.address} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
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
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolIO : ${poolIO.address} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
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
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolSell : ${poolSell.address} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
  );

  printFacets(poolSell.address, poolSellFactory);
  await poolSell.deployed();

  //

  const poolSettingsFactory = new PoolSettings__factory(deployer);
  const poolSettings = await poolSettingsFactory.deploy(
    ivolOracle,
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolSettings : ${poolSettings.address} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
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
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolView : ${poolView.address} ${nftDisplay} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
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
    wftm,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
    exchangeHelper,
  );

  console.log(
    `PoolWrite : ${poolWrite.address} ${ivolOracle} ${wftm} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${exchangeHelper}`,
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
