import {
  ERC20,
  ERC20__factory,
  ERC20Mock,
  ERC20Mock__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaMaker,
  PremiaMaker__factory,
  ProxyUpgradeableOwnable__factory,
  VePremia,
  VePremia__factory,
  VePremiaProxy__factory,
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
    } else {
      premia = PremiaErc20__factory.connect(premiaAddress, deployer);
    }

    if (!rewardTokenAddress) {
      rewardToken = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
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

  const vePremiaImpl = await new VePremia__factory(deployer).deploy(
    lzEndpoint,
    premia.address,
    rewardToken.address,
    exchangeProxy ?? ethers.constants.AddressZero,
  );
  const vePremiaProxy = await new VePremiaProxy__factory(deployer).deploy(
    vePremiaImpl.address,
  );

  const vePremia = VePremia__factory.connect(vePremiaImpl.address, deployer);

  if (log) {
    console.log(
      `PremiaStaking deployed at ${vePremiaProxy.address} (Args : ${vePremiaImpl.address})`,
    );
  }

  const premiaMakerImpl = await new PremiaMaker__factory(deployer).deploy(
    premia.address,
    vePremia.address,
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
      `PremiaMaker deployed at ${premiaMaker.address} (Args : ${premia.address} / ${vePremia.address} / ${treasury})`,
    );
  }

  return {
    premia,
    premiaMaker,
    vePremia,
  };
}

export interface IPremiaContracts {
  premia: PremiaErc20 | ERC20Mock;
  vePremia: VePremia;
  premiaMaker: PremiaMaker;
}
