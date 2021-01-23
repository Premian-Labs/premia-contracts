import {
  FeeCalculator,
  FeeCalculator__factory,
  PremiaBondingCurve,
  PremiaBondingCurve__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
  PremiaMaker,
  PremiaMaker__factory,
  PremiaMining,
  PremiaMining__factory,
  PremiaPBC,
  PremiaPBC__factory,
  PremiaReferral,
  PremiaReferral__factory,
  PremiaStaking,
  PremiaStaking__factory,
  PremiaUncutErc20,
  PremiaUncutErc20__factory,
  PriceProvider,
  PriceProvider__factory,
  TestErc20,
  TestErc20__factory,
} from '../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

export async function deployContracts(
  deployer: SignerWithAddress,
  treasury: string,
  isTest: boolean,
  log = false,
): Promise<IPremiaContracts> {
  let premia: PremiaErc20 | TestErc20;
  let miningBlockStart: number;
  let pbcBlockStart: number;
  let pbcBlockEnd: number;
  let miningBonusLength: number;
  let miningPostBonusLength: number;

  if (isTest) {
    premia = await new TestErc20__factory(deployer).deploy();

    pbcBlockStart = 0;
    pbcBlockEnd = 100;

    miningBlockStart = 100;
    miningBonusLength = 100;
    miningPostBonusLength = 200;
  } else {
    premia = await new PremiaErc20__factory(deployer).deploy();

    pbcBlockStart = 0;
    pbcBlockEnd = 0;
    miningBlockStart = 0;
    miningBonusLength = 360e3;
    miningPostBonusLength = 3600e3;

    if (!pbcBlockStart || !pbcBlockEnd || !miningBlockStart) {
      throw new Error('Settings not set');
    }
  }

  if (log) {
    console.log(`PremiaErc20 deployed at ${premia.address}`);
  }

  //

  const priceProvider = await new PriceProvider__factory(deployer).deploy();
  if (log) {
    console.log(`PriceProvider deployed at ${priceProvider.address}`);
  }

  //

  const uPremia = await new PremiaUncutErc20__factory(deployer).deploy(
    priceProvider.address,
  );
  if (log) {
    console.log(
      `PremiaUncutErc20 deployed at ${uPremia.address} (Args : ${priceProvider.address})`,
    );
  }

  //

  const xPremia = await new PremiaStaking__factory(deployer).deploy(
    premia.address,
  );
  if (log) {
    console.log(
      `PremiaStaking deployed at ${xPremia.address} (Args : ${premia.address})`,
    );
  }

  let premiaBondingCurve: PremiaBondingCurve | undefined;
  if (isTest) {
    // We only deploy premiaBondingCurve now on testnet.
    // For mainnet, we will need to know end price of the PBC, to use it as start price of the bonding curve

    const startPrice = '200000000000000';
    const k = '1000000000';

    premiaBondingCurve = await new PremiaBondingCurve__factory(deployer).deploy(
      premia.address,
      treasury,
      startPrice,
      k,
    );
    if (log) {
      console.log(
        `PremiaBondingCurve deployed at ${premiaBondingCurve.address} (Args : ${premia.address} / ${treasury} / ${startPrice} / ${k})`,
      );
    }
  }

  const premiaPBC = await new PremiaPBC__factory(deployer).deploy(
    premia.address,
    pbcBlockStart,
    pbcBlockEnd,
    treasury,
  );
  if (log) {
    console.log(
      `PremiaPBC deployed at ${premiaPBC.address} (Args : ${premia.address} / ${pbcBlockStart} / ${pbcBlockEnd} / ${treasury})`,
    );
  }

  const premiaMaker = await new PremiaMaker__factory(deployer).deploy(
    premia.address,
    xPremia.address,
    treasury,
  );
  if (log) {
    console.log(
      `PremiaMaker deployed at ${premiaMaker.address} (Args : ${premia.address} / ${xPremia.address} / ${treasury})`,
    );
  }

  const premiaMining = await new PremiaMining__factory(deployer).deploy(
    premia.address,
    miningBlockStart,
    miningBonusLength,
    miningPostBonusLength,
  );
  if (log) {
    console.log(
      `PremiaMining deployed at ${premiaMining.address} (Args : ${premia.address} / ${miningBlockStart} / ${miningBonusLength} / ${miningPostBonusLength})`,
    );
  }

  const premiaFeeDiscount = await new PremiaFeeDiscount__factory(
    deployer,
  ).deploy(xPremia.address);
  if (log) {
    console.log(
      `PremiaFeeDiscount deployed at ${premiaFeeDiscount.address} (Args : ${xPremia.address})`,
    );
  }

  const feeCalculator = await new FeeCalculator__factory(deployer).deploy(
    premiaFeeDiscount.address,
  );
  if (log) {
    console.log(
      `FeeCalculator deployed at ${feeCalculator.address} (Args : ${premiaFeeDiscount.address})`,
    );
  }

  const premiaReferral = await new PremiaReferral__factory(deployer).deploy();
  if (log) {
    console.log(`PremiaReferral deployed at ${premiaReferral.address}`);
  }

  return {
    premia,
    premiaBondingCurve,
    premiaMaker,
    premiaMining,
    premiaPBC,
    priceProvider,
    uPremia,
    xPremia,
    premiaFeeDiscount,
    feeCalculator,
    premiaReferral,
  };
}

export interface IPremiaContracts {
  premia: PremiaErc20;
  premiaMining: PremiaMining;
  premiaPBC: PremiaPBC;
  priceProvider: PriceProvider;
  uPremia: PremiaUncutErc20;
  xPremia: PremiaStaking;
  premiaBondingCurve?: PremiaBondingCurve;
  premiaFeeDiscount: PremiaFeeDiscount;
  premiaMaker: PremiaMaker;
  feeCalculator: FeeCalculator;
  premiaReferral: PremiaReferral;
}
