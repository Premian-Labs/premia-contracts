import { network } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  PremiaErc20,
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
import { BigNumberish } from 'ethers';

export const uniswapABIs = [
  'function swapExactTokensForTokens(uint,uint,address[],address,uint) returns (uint[])',
  'function swapExactETHForTokens(uint, address[], address to, uint) returns (uint[])',
  'function swapTokensForExactTokens(uint,uint,address[],address,uint) returns (uint[])',
  'function swapETHForExactTokens(uint,address[],address,uint) returns (uint[])',
];
export interface IUniswap {
  weth: WETH9;
  dai: ERC20Mock;
  factory: UniswapV2Factory;
  router: UniswapV2Router02;
  daiWeth: UniswapV2Pair;
  premiaWeth?: UniswapV2Pair;
}

export async function createUniswap(
  admin: SignerWithAddress,
  premia?: PremiaErc20,
  dai?: ERC20Mock,
) {
  if (!dai) {
    dai = await new ERC20Mock__factory(admin).deploy('DAI', 18);
  }

  let weth;
  let factory;
  let router;

  if ((network as any).config.forking?.enabled) {
    weth = WETH9__factory.connect(
      '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
      admin,
    );

    factory = UniswapV2Factory__factory.connect(
      '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f',
      admin,
    );

    router = UniswapV2Router02__factory.connect(
      '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
      admin,
    );
  } else {
    weth = await new WETH9__factory(admin).deploy();

    factory = await new UniswapV2Factory__factory(admin).deploy(admin.address);

    router = await new UniswapV2Router02__factory(admin).deploy(
      factory.address,
      weth.address,
    );
  }

  const daiWeth = await createUniswapPair(
    admin,
    factory,
    dai.address,
    weth.address,
  );

  let premiaWeth: UniswapV2Pair | undefined;
  if (premia) {
    premiaWeth = await createUniswapPair(
      admin,
      factory,
      premia.address,
      weth.address,
    );
  }

  return { weth, factory, router, daiWeth, dai, premiaWeth };
}

export async function createUniswapPair(
  admin: SignerWithAddress,
  factory: UniswapV2Factory,
  token0: string,
  token1: string,
) {
  await factory.createPair(token0, token1);
  const pairAddr = await factory.getPair(token0, token1);
  return UniswapV2Pair__factory.connect(pairAddr, admin);
}

export async function depositUniswapLiquidity(
  user: SignerWithAddress,
  weth: string,
  pair: UniswapV2Pair,
  amountToken0: BigNumberish,
  amountToken1: BigNumberish,
) {
  const token0 = await pair.token0();
  const token1 = await pair.token1();

  let i = 0;
  for (const t of [token0, token1]) {
    const amount = i === 0 ? amountToken0 : amountToken1;
    if (t === weth) {
      await WETH9__factory.connect(t, user).deposit({
        value: amount,
      });
      await WETH9__factory.connect(t, user).transfer(pair.address, amount);
    } else {
      await ERC20Mock__factory.connect(t, user).mint(pair.address, amount);
    }

    i++;
  }
  await pair.mint(user.address);
}
