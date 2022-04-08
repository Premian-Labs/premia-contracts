import { ethers } from 'hardhat';
import { fixedFromFloat } from '@premia/utils';

import { PoolSell__factory, Premia__factory } from '../../../typechain';
import { diamondCut } from '../../utils/diamond';

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

  const premiaDiamondAddress = '0x32B3ccde9e8E8A235837F726C1F06B2B579c864B';
  const ivolOracle = '0x9e88fe5e5249CD6429269B072c9476b6908dCBf2';
  const weth = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
  const premiaMining = '0xc165AD135814467277fEA9FcdC4Fa456Be828E10';
  const feeReceiver = '0x71656519B14e25a688Aa27761705d7607417231d';
  const feeDiscountAddress = '0x8F949e46D5487970DA8F8F8D828C280CDFbb940A';
  const optionMath = '0x349dc2d1AD597c6fa2f716549d235a0f02273d2c';
  const fee64x64 = fixedFromFloat(0.03);
  const feeApy64x64 = fixedFromFloat(0.03);

  const premiaDiamond = await Premia__factory.connect(
    premiaDiamondAddress,
    deployer,
  );

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
    feeApy64x64,
  );

  console.log(
    `PoolSell : ${poolSell.address} ${ivolOracle} ${weth} ${premiaMining} ${feeReceiver} ${feeDiscountAddress} ${fee64x64} ${feeApy64x64}`,
  );

  printFacets(poolSell.address, poolSellFactory);

  await diamondCut(premiaDiamond, poolSell.address, poolSellFactory, [], 1);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
