import { ethers } from 'hardhat';
import {
  PoolBase__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PoolSell__factory,
  PoolSettings__factory,
  PoolView__factory,
  PoolWrite__factory,
} from '../../typechain';
import { fixedFromFloat } from '@premia/utils';
import { diamondCut } from '../utils/diamond';

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

  const ivolOracle = '0x3A87bB29b984d672664Aa1dD2d19D2e8b24f0f2A';
  const weth = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
  const premiaMining = '0x9aBB27581c2E46A114F8C367355851e0580e9703';
  const feeReceiver = '0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF';
  const feeDiscountAddress = '0xF1bB87563A122211d40d393eBf1c633c330377F9';
  const fee64x64 = fixedFromFloat(0.03);
  const optionMath = '0x0F6E8eF18FB5bb61D545fEe60f779D8aED60408F';
  const uniswapV2Factory = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
  const sushiswapV2Factory = '0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac';
  const nftDisplay = '0x32248Ec445D3c72b42f16B040e55BCD5Cf5a8712';
  // const poolDiamond = '0x48D49466CB2EFbF05FaA5fa5E69f2984eDC8d1D7';

  const poolBaseFactory = new PoolBase__factory(deployer);
  const poolBase = await poolBaseFactory.deploy(
    ivolOracle,
    weth,
    premiaMining,
    feeReceiver,
    feeDiscountAddress,
    fee64x64,
  );

  console.log(
    `PoolBase : ${poolBase.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64}`,
  );

  printFacets(poolBase.address, poolBaseFactory);

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
  );

  console.log(
    `PoolExercise : ${poolExercise.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64}`,
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
    uniswapV2Factory,
    sushiswapV2Factory,
  );

  console.log(
    `PoolIO : ${poolIO.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${uniswapV2Factory} ${sushiswapV2Factory}`,
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
  );

  console.log(
    `PoolSell : ${poolSell.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64}`,
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
  );

  console.log(
    `PoolSettings : ${poolSettings.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64}`,
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
  );

  console.log(
    `PoolView : ${poolView.address} ${nftDisplay} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64}`,
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
    uniswapV2Factory,
    sushiswapV2Factory,
  );

  console.log(
    `PoolWrite : ${poolWrite.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${uniswapV2Factory} ${sushiswapV2Factory}`,
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
