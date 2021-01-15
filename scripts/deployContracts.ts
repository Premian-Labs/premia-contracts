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
  treasury: SignerWithAddress,
  isTest: boolean,
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
    pbcBlockEnd = 100;
    miningBlockStart = 100;
    miningBonusLength = 360e3;
    miningPostBonusLength = 3600e3;
  }

  const priceProvider = await new PriceProvider__factory(deployer).deploy();

  const uPremia = await new PremiaUncutErc20__factory(deployer).deploy(
    priceProvider.address,
  );

  const xPremia = await new PremiaStaking__factory(deployer).deploy(
    premia.address,
  );

  const premiaBondingCurve = await new PremiaBondingCurve__factory(
    deployer,
  ).deploy(premia.address, treasury.address, '200000000000000', '1000000000');

  const premiaPBC = await new PremiaPBC__factory(deployer).deploy(
    premia.address,
    pbcBlockStart,
    pbcBlockEnd,
    treasury.address,
  );

  const premiaMaker = await new PremiaMaker__factory(deployer).deploy(
    premia.address,
    premiaBondingCurve.address,
    xPremia.address,
    treasury.address,
  );

  const premiaMining = await new PremiaMining__factory(deployer).deploy(
    premia.address,
    miningBlockStart,
    miningBonusLength,
    miningPostBonusLength,
  );

  const premiaFeeDiscount = await new PremiaFeeDiscount__factory(
    deployer,
  ).deploy(xPremia.address);

  const feeCalculator = await new FeeCalculator__factory(deployer).deploy(
    premiaFeeDiscount.address,
  );

  const premiaReferral = await new PremiaReferral__factory(deployer).deploy();

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
  premiaBondingCurve: PremiaBondingCurve;
  premiaFeeDiscount: PremiaFeeDiscount;
  premiaMaker: PremiaMaker;
  feeCalculator: FeeCalculator;
  premiaReferral: PremiaReferral;
}
