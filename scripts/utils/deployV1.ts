import {
  ERC20Mock,
  ERC20Mock__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
  PremiaMaker,
  PremiaMaker__factory,
  PremiaStaking,
  PremiaStaking__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

export async function deployV1(
  deployer: SignerWithAddress,
  treasury: string,
  isTest: boolean,
  log = false,
  premiaAddress?: string,
): Promise<IPremiaContracts> {
  let premia: PremiaErc20 | ERC20Mock;

  if (isTest) {
    if (!premiaAddress) {
      premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);
    } else {
      premia = PremiaErc20__factory.connect(premiaAddress, deployer);
    }
  } else {
    if (!premiaAddress) {
      throw new Error('Premia address not set');
    }
    // premia = await new PremiaErc20__factory(deployer).deploy();
    premia = PremiaErc20__factory.connect(premiaAddress, deployer);
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

  const premiaMakerImpl = await new PremiaMaker__factory(deployer).deploy(
    premia.address,
    xPremia.address,
    treasury,
  );

  const premiaMakerProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(premiaMakerImpl.address);

  const premiaMaker = PremiaMaker__factory.connect(
    premiaMakerProxy.address,
    deployer,
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

  return {
    premia,
    premiaMaker,
    xPremia,
    premiaFeeDiscount,
  };
}

export interface IPremiaContracts {
  premia: PremiaErc20 | ERC20Mock;
  xPremia: PremiaStaking;
  premiaFeeDiscount: PremiaFeeDiscount;
  premiaMaker: PremiaMaker;
}
