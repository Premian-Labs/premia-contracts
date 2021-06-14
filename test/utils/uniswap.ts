import {
  PremiaErc20,
  ERC20Mock,
  ERC20Mock__factory,
  UniswapV2Factory,
  UniswapV2Factory__factory,
  UniswapV2Pair,
  UniswapV2Pair__factory,
  UniswapV2Router02,
  UniswapV2Router02__factory,
  WETH9,
  WETH9__factory,
} from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

export interface IUniswap {
  weth: WETH9;
  dai: ERC20Mock;
  factory: UniswapV2Factory;
  router: UniswapV2Router02;
  daiWeth: UniswapV2Pair;
  premiaWeth: UniswapV2Pair;
}

export async function createUniswap(
  admin: SignerWithAddress,
  premia: PremiaErc20,
  dai?: ERC20Mock,
  weth?: WETH9,
) {
  if (!dai) {
    dai = await new ERC20Mock__factory(admin).deploy('DAI', 18);
  }

  if (!weth) {
    weth = await new WETH9__factory(admin).deploy();
  }

  const factory = await new UniswapV2Factory__factory(admin).deploy(
    admin.address,
  );
  const router = await new UniswapV2Router02__factory(admin).deploy(
    factory.address,
    weth.address,
  );
  await factory.createPair(dai.address, weth.address);
  const daiWethAddr = await factory.getPair(dai.address, weth.address);
  const daiWeth = await UniswapV2Pair__factory.connect(daiWethAddr, admin);

  await factory.createPair(premia.address, weth.address);
  const premiaWethAddr = await factory.getPair(premia.address, weth.address);
  const premiaWeth = await UniswapV2Pair__factory.connect(
    premiaWethAddr,
    admin,
  );

  return { weth, factory, router, daiWeth, dai, premiaWeth };
}
