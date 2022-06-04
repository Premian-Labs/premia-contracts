import {
  ERC20Mock,
  ERC20Mock__factory,
  FeeDiscount,
  FeeDiscount__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaMaker,
  PremiaMaker__factory,
  PremiaStakingProxy__factory,
  PremiaStakingWithFeeDiscount,
  PremiaStakingWithFeeDiscount__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ZERO_ADDRESS } from '../../test/utils/constants';

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

  const xPremiaImpl = await new PremiaStakingWithFeeDiscount__factory(
    deployer,
  ).deploy(ZERO_ADDRESS, premia.address, ZERO_ADDRESS, ZERO_ADDRESS);
  const xPremiaProxy = await new PremiaStakingProxy__factory(deployer).deploy(
    xPremiaImpl.address,
  );

  const xPremia = PremiaStakingWithFeeDiscount__factory.connect(
    xPremiaImpl.address,
    deployer,
  );

  if (log) {
    console.log(
      `PremiaStaking deployed at ${xPremiaProxy.address} (Args : ${xPremiaImpl.address})`,
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

  const feeDiscountStandaloneImpl = await new FeeDiscount__factory(
    deployer,
  ).deploy(xPremia.address);
  const feeDiscountStandaloneProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(feeDiscountStandaloneImpl.address);
  const feeDiscountStandalone = FeeDiscount__factory.connect(
    feeDiscountStandaloneProxy.address,
    deployer,
  );

  if (log) {
    console.log(
      `PremiaFeeDiscount deployed at ${feeDiscountStandalone.address} (Args : ${xPremia.address})`,
    );
  }

  return {
    premia,
    premiaMaker,
    xPremia,
    feeDiscountStandalone,
  };
}

export interface IPremiaContracts {
  premia: PremiaErc20 | ERC20Mock;
  xPremia: PremiaStakingWithFeeDiscount;
  feeDiscountStandalone: FeeDiscount;
  premiaMaker: PremiaMaker;
}
