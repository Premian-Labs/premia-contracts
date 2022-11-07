import {
  ERC20,
  ERC20__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FeeConverter,
  FeeConverter__factory,
  PremiaErc20,
  PremiaErc20__factory,
  ProxyUpgradeableOwnable__factory,
  VxPremia,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ethers } from 'ethers';

export async function deployV1(
  deployer: SignerWithAddress,
  treasury: string,
  lzEndpoint: string,
  isTest: boolean,
  log = false,
  premiaAddress?: string,
  rewardTokenAddress?: string,
  exchangeProxy?: string,
): Promise<IPremiaContracts> {
  let premia: PremiaErc20 | ERC20Mock;
  let rewardToken: ERC20 | ERC20Mock;

  if (isTest) {
    if (!premiaAddress) {
      premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);
      await premia.deployed();
    } else {
      premia = PremiaErc20__factory.connect(premiaAddress, deployer);
    }

    if (!rewardTokenAddress) {
      rewardToken = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
      await rewardToken.deployed();
    } else {
      rewardToken = ERC20Mock__factory.connect(rewardTokenAddress, deployer);
    }
  } else {
    if (!premiaAddress) {
      throw new Error('Premia address not set');
    }

    if (!rewardTokenAddress) {
      throw new Error('Reward token address not set');
    }

    premia = PremiaErc20__factory.connect(premiaAddress, deployer);
    rewardToken = ERC20__factory.connect(rewardTokenAddress, deployer);
  }

  if (log) {
    console.log(`PremiaErc20 deployed at ${premia.address}`);
  }

  //

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    lzEndpoint,
    premia.address,
    rewardToken.address,
    exchangeProxy ?? ethers.constants.AddressZero,
  );
  await vxPremiaImpl.deployed();
  const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
    vxPremiaImpl.address,
  );
  await vxPremiaProxy.deployed();

  const vxPremia = VxPremia__factory.connect(vxPremiaImpl.address, deployer);

  if (log) {
    console.log(
      `PremiaStaking deployed at ${vxPremiaProxy.address} (Args : ${vxPremiaImpl.address})`,
    );
  }

  const feeConverterImpl = await new FeeConverter__factory(deployer).deploy(
    exchangeProxy ?? ethers.constants.AddressZero,
    rewardToken.address,
    vxPremia.address,
    treasury,
  );
  await feeConverterImpl.deployed();

  const premiaMakerProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(feeConverterImpl.address);

  const feeConverter = FeeConverter__factory.connect(
    premiaMakerProxy.address,
    deployer,
  );

  if (log) {
    console.log(
      `PremiaMaker deployed at ${feeConverter.address} (Args : ${premia.address} / ${vxPremia.address} / ${treasury})`,
    );
  }

  return {
    premia,
    feeConverter,
    vxPremia: vxPremia,
    rewardToken,
  };
}

export interface IPremiaContracts {
  premia: PremiaErc20 | ERC20Mock;
  vxPremia: VxPremia;
  feeConverter: FeeConverter;
  rewardToken: ERC20 | ERC20Mock;
}
