import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { deployV1, IPremiaContracts } from '../scripts/utils/deployV1';
import { formatEther, parseEther } from 'ethers/lib/utils';
import {
  createUniswap,
  depositUniswapLiquidity,
  IUniswap,
} from './utils/uniswap';
import { ERC20Mock, UniswapV2Pair } from '../typechain';
import { bnToNumber } from './utils/math';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let uniswap: IUniswap;
let premiaWeth: UniswapV2Pair;

const chai = require('chai');
const chaiAlmost = require('chai-almost');

chai.use(chaiAlmost(0.01));

describe('PremiaMaker', () => {
  beforeEach(async () => {
    // Keep to fix "should make premia successfully" test failing when running all tests
    await ethers.provider.send('hardhat_reset', []);

    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployV1(admin, treasury.address, true);

    uniswap = await createUniswap(admin, p.premia);

    await p.premiaMaker.addWhitelistedRouter([uniswap.router.address]);
    premiaWeth = uniswap.premiaWeth as UniswapV2Pair;
  });

  it('should make premia successfully', async () => {
    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      premiaWeth,
      (await premiaWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
      (await premiaWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
    );

    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      uniswap.daiWeth,
      (await premiaWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
      (await premiaWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
    );

    await uniswap.dai.mint(p.premiaMaker.address, parseEther('10'));

    await p.premiaMaker.convert(uniswap.router.address, uniswap.dai.address);

    expect(await uniswap.dai.balanceOf(treasury.address)).to.eq(
      parseEther('2'),
    );
    expect(await uniswap.dai.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(bnToNumber(await p.premia.balanceOf(p.xPremia.address))).to.almost(
      685.94,
    );

    expect(bnToNumber(await p.xPremia.getAvailableRewards())).to.almost(685.94);
  });

  it('should make premia successfully with WETH', async () => {
    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      premiaWeth,
      (await premiaWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
      (await premiaWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
    );

    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      uniswap.daiWeth,
      (await premiaWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
      (await premiaWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
    );

    await uniswap.weth.deposit({ value: parseEther('10') });
    await uniswap.weth.transfer(p.premiaMaker.address, parseEther('10'));

    await p.premiaMaker.convert(uniswap.router.address, uniswap.weth.address);

    expect(await uniswap.weth.balanceOf(treasury.address)).to.eq(
      parseEther('2'),
    );
    expect(await uniswap.weth.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(bnToNumber(await p.premia.balanceOf(p.xPremia.address))).to.almost(
      8885.91,
    );
    expect(bnToNumber(await p.xPremia.getAvailableRewards())).to.almost(
      8885.91,
    );
  });

  it('should send premia successfully to premiaStaking', async () => {
    await (p.premia as ERC20Mock).mint(p.premiaMaker.address, parseEther('10'));
    await p.premiaMaker.convert(uniswap.router.address, p.premia.address);

    expect(await p.premia.balanceOf(treasury.address)).to.eq(parseEther('2'));
    expect(await p.premia.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(await p.premia.balanceOf(p.xPremia.address)).to.eq(parseEther('8'));
    expect(bnToNumber(await p.xPremia.getAvailableRewards())).to.almost(8);
  });
});
