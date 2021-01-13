import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, resetHardhat } from './utils/evm';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { parseEther } from 'ethers/lib/utils';
import { createUniswap, IUniswap } from './utils/uniswap';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let uniswap: IUniswap;

describe('PremiaMaker', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury, true);

    uniswap = await createUniswap(admin);

    await p.premiaMaker.addWhitelistedRouter([uniswap.router.address]);
    await p.premia.mint(p.premiaBondingCurve.address, parseEther('10000000'));
  });

  it('should make premia successfully', async () => {
    await uniswap.dai.mint(uniswap.daiWeth.address, parseEther('100'));
    await uniswap.weth.deposit({ value: parseEther('1') });
    await uniswap.weth.transfer(uniswap.daiWeth.address, parseEther('1'));
    await uniswap.daiWeth.mint(user1.address);

    await uniswap.dai.mint(p.premiaMaker.address, parseEther('10'));

    await p.premiaMaker.convert(uniswap.router.address, uniswap.dai.address);

    expect(await uniswap.dai.balanceOf(treasury.address)).to.eq(
      parseEther('2'),
    );
    expect(await uniswap.dai.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(
      (await getEthBalance(p.premiaBondingCurve.address)).gt(
        parseEther('0.07'),
      ),
    ).to.be.true;
    expect((await p.premia.balanceOf(p.xPremia.address)).gt(360)).to.be.true;
  });

  it('should make premia successfully with WETH', async () => {
    await uniswap.dai.mint(uniswap.daiWeth.address, parseEther('100'));
    await uniswap.weth.deposit({ value: parseEther('1') });
    await uniswap.weth.transfer(uniswap.daiWeth.address, parseEther('1'));
    await uniswap.daiWeth.mint(user1.address);

    await uniswap.weth.deposit({ value: parseEther('10') });
    await uniswap.weth.transfer(p.premiaMaker.address, parseEther('10'));

    await p.premiaMaker.convert(uniswap.router.address, uniswap.weth.address);

    expect(await uniswap.weth.balanceOf(treasury.address)).to.eq(
      parseEther('2'),
    );
    expect(await uniswap.weth.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(
      (await getEthBalance(p.premiaBondingCurve.address)).gt(
        parseEther('0.07'),
      ),
    ).to.be.true;
    expect((await p.premia.balanceOf(p.xPremia.address)).gt(360)).to.be.true;
  });

  it('should send premia successfully to premiaStaking', async () => {
    await p.premia.mint(p.premiaMaker.address, parseEther('10'));
    await p.premiaMaker.convert(uniswap.router.address, p.premia.address);

    expect(await p.premia.balanceOf(treasury.address)).to.eq(parseEther('2'));
    expect(await p.premia.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(await p.premia.balanceOf(p.xPremia.address)).to.eq(parseEther('8'));
  });
});
