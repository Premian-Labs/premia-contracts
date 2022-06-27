import {
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

export async function deployV1(
  deployer: SignerWithAddress,
  treasury: string,
  lzEndpoint: string,
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

  const vePremiaImpl = await new VePremia__factory(deployer).deploy(
    lzEndpoint,
    premia.address,
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
