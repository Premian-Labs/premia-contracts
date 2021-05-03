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
  PremiaOptionBatch,
  PremiaOptionBatch__factory,
  PremiaPBC,
  PremiaPBC__factory,
  PremiaReferral,
  PremiaReferral__factory,
  PremiaStaking,
  PremiaStaking__factory,
  TestErc20,
  TestErc20__factory,
} from '../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

export async function deployContracts(
  deployer: SignerWithAddress,
  treasury: string,
  isTest: boolean,
  log = false,
  premiaAddress?: string,
): Promise<IPremiaContracts> {
  let premia: PremiaErc20 | TestErc20;
  let pbcBlockStart: number;
  let pbcBlockEnd: number;

  if (isTest) {
    premia = await new TestErc20__factory(deployer).deploy(18);

    pbcBlockStart = 0;
    pbcBlockEnd = 100;
  } else {
    if (!premiaAddress) {
      throw new Error('Premia address not set');
    }
    // premia = await new PremiaErc20__factory(deployer).deploy();
    premia = PremiaErc20__factory.connect(premiaAddress, deployer);

    pbcBlockStart = 11806500;
    pbcBlockEnd = 11858500;

    if (!pbcBlockStart || !pbcBlockEnd) {
      throw new Error('Settings not set');
    }
  }

  if (log) {
    console.log(`PremiaErc20 deployed at ${premia.address}`);
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

  const premiaOptionBatch = await new PremiaOptionBatch__factory(
    deployer,
  ).deploy();
  if (log) {
    console.log(`PremiaOptionBatch deployed at ${premiaOptionBatch.address}`);
  }

  return {
    premia,
    premiaBondingCurve,
    premiaMaker,
    premiaPBC,
    xPremia,
    premiaFeeDiscount,
    feeCalculator,
    premiaReferral,
    premiaOptionBatch,
  };
}

export interface IPremiaContracts {
  premia: PremiaErc20;
  premiaPBC: PremiaPBC;
  xPremia: PremiaStaking;
  premiaBondingCurve?: PremiaBondingCurve;
  premiaFeeDiscount: PremiaFeeDiscount;
  premiaMaker: PremiaMaker;
  feeCalculator: FeeCalculator;
  premiaReferral: PremiaReferral;
  premiaOptionBatch: PremiaOptionBatch;
}
