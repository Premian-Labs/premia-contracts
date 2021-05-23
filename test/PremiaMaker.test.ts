import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat } from './utils/evm';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { createUniswap, IUniswap } from './utils/uniswap';
import { TestErc20 } from '../typechain';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let uniswap: IUniswap;

const chai = require('chai');
const chaiAlmost = require('chai-almost');

chai.use(chaiAlmost(0.01));

describe('PremiaMaker', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury.address, true);

    uniswap = await createUniswap(admin, p.premia);

    await p.premiaMaker.addWhitelistedRouter([uniswap.router.address]);
  });

  it('should make premia successfully', async () => {
    await (p.premia as TestErc20).mint(
      uniswap.premiaWeth.address,
      parseEther('10000'),
    );
    await uniswap.weth.deposit({ value: parseEther('1') });
    await uniswap.weth.transfer(uniswap.premiaWeth.address, parseEther('1'));
    await uniswap.premiaWeth.mint(user1.address);

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
      Number(formatEther(await p.premia.balanceOf(p.xPremia.address))),
    ).to.almost(685.94);
  });

  it('should make premia successfully with WETH', async () => {
    await (p.premia as TestErc20).mint(
      uniswap.premiaWeth.address,
      parseEther('10000'),
    );
    await uniswap.weth.deposit({ value: parseEther('1') });
    await uniswap.weth.transfer(uniswap.premiaWeth.address, parseEther('1'));
    await uniswap.premiaWeth.mint(user1.address);

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
      Number(formatEther(await p.premia.balanceOf(p.xPremia.address))),
    ).to.almost(8885.91);
  });

  it('should send premia successfully to premiaStaking', async () => {
    await (p.premia as TestErc20).mint(p.premiaMaker.address, parseEther('10'));
    await p.premiaMaker.convert(uniswap.router.address, p.premia.address);

    expect(await p.premia.balanceOf(treasury.address)).to.eq(parseEther('2'));
    expect(await p.premia.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(await p.premia.balanceOf(p.xPremia.address)).to.eq(parseEther('8'));
  });
});
