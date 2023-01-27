import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { deployV1, IPremiaContracts } from '../scripts/utils/deployV1';
import { parseEther } from 'ethers/lib/utils';
import {
  createUniswap,
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
  uniswapABIs,
} from './utils/uniswap';
import {
  ERC20Mock,
  ExchangeHelper,
  ExchangeHelper__factory,
  PremiaErc20,
  UniswapV2Pair,
} from '../typechain';
import { bnToNumber } from './utils/math';
import { resetHardhat } from './utils/evm';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let uniswap: IUniswap;
let rewardTokenWeth: UniswapV2Pair;
let exchangeProxy: ExchangeHelper;

describe('FeeConverter', () => {
  beforeEach(async () => {
    // Keep to fix "should make premia successfully" test failing when running all tests
    await ethers.provider.send('hardhat_reset', []);

    [admin, user1, treasury] = await ethers.getSigners();

    exchangeProxy = await new ExchangeHelper__factory(admin).deploy();

    p = await deployV1(
      admin,
      treasury.address,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      true,
      false,
      undefined,
      undefined,
      exchangeProxy.address,
    );

    uniswap = await createUniswap(admin, p.premia as PremiaErc20);

    rewardTokenWeth = await createUniswapPair(
      admin,
      uniswap.factory,
      p.rewardToken.address,
      uniswap.weth.address,
    );
  });

  afterEach(async () => {
    await resetHardhat();
  });

  it('should fail to call convert if not authorized', async () => {
    await expect(
      p.feeConverter.convert(
        p.rewardToken.address,
        uniswap.router.address,
        uniswap.router.address,
        '0x',
      ),
    ).to.be.revertedWith('Not authorized');
  });

  it('should convert fees successfully', async () => {
    await p.feeConverter.setAuthorized(admin.address, true);

    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      rewardTokenWeth,
      (await rewardTokenWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
      (await rewardTokenWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
    );

    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      uniswap.daiWeth,
      (await uniswap.daiWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
      (await uniswap.daiWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
    );

    const amount = parseEther('10');
    await uniswap.dai.mint(p.feeConverter.address, amount);

    const uniswapPath = [
      uniswap.dai.address,
      uniswap.weth.address,
      p.rewardToken.address,
    ];

    const { timestamp } = await ethers.provider.getBlock('latest');

    const iface = new ethers.utils.Interface(uniswapABIs);
    const data = iface.encodeFunctionData('swapExactTokensForTokens', [
      amount,
      amount.mul(2),
      uniswapPath,
      exchangeProxy.address,
      timestamp + 86400,
    ]);

    await p.feeConverter.convert(
      uniswap.dai.address,
      uniswap.router.address,
      uniswap.router.address,
      data,
    );

    expect(
      bnToNumber(await p.rewardToken.balanceOf(treasury.address)),
    ).to.almost(165.79);
    expect(await uniswap.dai.balanceOf(p.feeConverter.address)).to.eq(0);
    expect(
      bnToNumber(await p.rewardToken.balanceOf(p.vxPremia.address)),
    ).to.almost(663.16);

    expect(bnToNumber((await p.vxPremia.getAvailableRewards())[0])).to.almost(
      663.16,
    );
  });

  it('should make premia successfully with WETH', async () => {
    await p.feeConverter.setAuthorized(admin.address, true);

    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      rewardTokenWeth,
      (await rewardTokenWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
      (await rewardTokenWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('10000'),
    );

    await depositUniswapLiquidity(
      user1,
      uniswap.weth.address,
      uniswap.daiWeth,
      (await uniswap.daiWeth.token0()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
      (await uniswap.daiWeth.token1()) == uniswap.weth.address
        ? parseEther('1')
        : parseEther('100'),
    );

    const amount = parseEther('10');
    await uniswap.weth.deposit({ value: amount });
    await uniswap.weth.transfer(p.feeConverter.address, amount);

    const uniswapPath = [uniswap.weth.address, p.rewardToken.address];

    const { timestamp } = await ethers.provider.getBlock('latest');

    const iface = new ethers.utils.Interface(uniswapABIs);
    const data = iface.encodeFunctionData('swapExactTokensForTokens', [
      amount,
      amount.mul(2),
      uniswapPath,
      exchangeProxy.address,
      timestamp + 86400,
    ]);

    await p.feeConverter.convert(
      uniswap.weth.address,
      uniswap.router.address,
      uniswap.router.address,
      data,
    );

    expect(
      bnToNumber(await p.rewardToken.balanceOf(treasury.address)),
    ).to.almost(1817.68);
    expect(await uniswap.weth.balanceOf(p.feeConverter.address)).to.eq(0);
    expect(
      bnToNumber(await p.rewardToken.balanceOf(p.vxPremia.address)),
    ).to.almost(7270.73);
    expect(bnToNumber((await p.vxPremia.getAvailableRewards())[0])).to.almost(
      7270.73,
    );
  });

  it('should send rewardToken successfully to vxPremia', async () => {
    await p.feeConverter.setAuthorized(admin.address, true);

    await (p.rewardToken as ERC20Mock).mint(
      p.feeConverter.address,
      parseEther('10'),
    );
    await p.feeConverter.convert(
      p.rewardToken.address,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      '0x',
    );

    expect(await p.rewardToken.balanceOf(treasury.address)).to.eq(
      parseEther('2'),
    );
    expect(await p.rewardToken.balanceOf(p.feeConverter.address)).to.eq(0);
    expect(await p.rewardToken.balanceOf(p.vxPremia.address)).to.eq(
      parseEther('8'),
    );
    expect(bnToNumber((await p.vxPremia.getAvailableRewards())[0])).to.almost(
      8,
    );
  });
});
