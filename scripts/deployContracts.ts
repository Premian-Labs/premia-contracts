import {
  ERC20,
  ERC20__factory,
  FeeCalculator,
  FeeCalculator__factory,
  Market,
  Market__factory,
  Option,
  Option__factory,
  Premia,
  Premia__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
  PremiaMaker,
  PremiaMaker__factory,
  PremiaOptionBatch,
  PremiaOptionBatch__factory,
  PremiaStaking,
  PremiaStaking__factory,
  ProxyManager__factory,
  TestErc20,
  TestErc20__factory,
} from '../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ZERO_ADDRESS } from '../test/utils/constants';

export async function deployContracts(
  deployer: SignerWithAddress,
  treasury: string,
  isTest: boolean,
  log = false,
  premiaAddress?: string,
  daiAddress?: string,
): Promise<IPremiaContracts> {
  let premia: PremiaErc20 | TestErc20;
  let dai: ERC20 | TestErc20;

  if (isTest) {
    if (!premiaAddress) {
      premia = await new TestErc20__factory(deployer).deploy(18);
    } else {
      premia = PremiaErc20__factory.connect(premiaAddress, deployer);
    }

    if (!daiAddress) {
      dai = await new TestErc20__factory(deployer).deploy(18);
    } else {
      dai = ERC20__factory.connect(daiAddress, deployer);
    }
  } else {
    if (!premiaAddress) {
      throw new Error('Premia address not set');
    }
    if (!daiAddress) {
      throw new Error('Dai address not set');
    }
    // premia = await new PremiaErc20__factory(deployer).deploy();
    premia = PremiaErc20__factory.connect(premiaAddress, deployer);
    dai = ERC20__factory.connect(daiAddress, deployer);
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

  const premiaOptionBatch = await new PremiaOptionBatch__factory(
    deployer,
  ).deploy();
  if (log) {
    console.log(`PremiaOptionBatch deployed at ${premiaOptionBatch.address}`);
  }

  ///

  // Diamond
  const optionImpl = await new Option__factory(deployer).deploy();
  const marketImpl = await new Market__factory(deployer).deploy();

  const premiaDiamond = await new Premia__factory(deployer).deploy(
    optionImpl.address,
    marketImpl.address,
  );

  const facetCuts = [await new ProxyManager__factory(deployer).deploy()].map(
    (f) => {
      return {
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions)
          .filter(
            (fn) => !['owner()', 'transferOwnership(address)'].includes(fn),
          )
          .map((fn) => {
            // console.log(fn);
            return f.interface.getSighash(fn);
          }),
      };
    },
  );

  await premiaDiamond.diamondCut(facetCuts, ZERO_ADDRESS, '0x');
  const proxyManager = ProxyManager__factory.connect(
    premiaDiamond.address,
    deployer,
  );

  await proxyManager.deployOption(
    '',
    dai.address,
    feeCalculator.address,
    treasury,
  );
  await proxyManager.deployMarket(feeCalculator.address, treasury);

  // console.log(await premiaDiamond.owner());
  // console.log(premiaDiamond.address, deployer.address);

  const option = Option__factory.connect(
    await proxyManager.getOption(dai.address),
    deployer,
  );
  const market = Market__factory.connect(
    await proxyManager.getMarket(),
    deployer,
  );

  // console.log('Option owner : ', await option.owner());
  // console.log('Market owner : ', await market.owner());

  return {
    premiaDiamond,
    option,
    market,
    premia,
    dai,
    premiaMaker,
    xPremia,
    premiaFeeDiscount,
    feeCalculator,
    premiaOptionBatch,
  };
}

export interface IPremiaContracts {
  premiaDiamond: Premia;
  option: Option;
  market: Market;
  premia: PremiaErc20 | TestErc20;
  dai: ERC20 | TestErc20;
  xPremia: PremiaStaking;
  premiaFeeDiscount: PremiaFeeDiscount;
  premiaMaker: PremiaMaker;
  feeCalculator: FeeCalculator;
  premiaOptionBatch: PremiaOptionBatch;
}
