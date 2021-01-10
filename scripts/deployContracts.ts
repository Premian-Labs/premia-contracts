import {
  FeeCalculator__factory,
  PremiaErc20__factory,
  PremiaFeeDiscount__factory,
  PremiaReferral__factory,
  PremiaStaking__factory,
  PremiaUncutErc20__factory,
  PriceProvider__factory,
} from '../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

export async function deployContracts(deployer: SignerWithAddress) {
  const premiaFactory = new PremiaErc20__factory(deployer);
  const priceProviderFactory = new PriceProvider__factory(deployer);
  const premiaReferralFactory = new PremiaReferral__factory(deployer);
  const premiaFeeDiscountFactory = new PremiaFeeDiscount__factory(deployer);
  const feeCalculatorFactory = new FeeCalculator__factory(deployer);
  const premiaStakingFactory = new PremiaStaking__factory(deployer);
  const premiaUncutErc20Factory = new PremiaUncutErc20__factory(deployer);

  const premia = await premiaFactory.deploy();
  const priceProvider = await priceProviderFactory.deploy();
  const premiaUncutErc20 = await premiaUncutErc20Factory.deploy(
    priceProvider.address,
  );
  const premiaStaking = await premiaStakingFactory.deploy(premia.address);
  const premiaFeeDiscount = await premiaFeeDiscountFactory.deploy(
    premiaStaking.address,
  );
  const feeCalculator = await feeCalculatorFactory.deploy(
    premiaFeeDiscount.address,
  );
  const premiaReferral = await premiaReferralFactory.deploy();

  return {
    premia,
    priceProvider,
    premiaUncutErc20,
    premiaStaking,
    premiaFeeDiscount,
    feeCalculator,
    premiaReferral,
  };
}
