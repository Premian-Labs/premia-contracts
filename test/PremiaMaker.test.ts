import { expect } from 'chai';
import {
  TestErc20,
  TestErc20__factory,
  UniswapV2Factory,
  UniswapV2Factory__factory,
  UniswapV2Pair,
  UniswapV2Pair__factory,
  UniswapV2Router02,
  UniswapV2Router02__factory,
  WETH9,
  WETH9__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, resetHardhat } from './utils/evm';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let dai: TestErc20;
let weth: WETH9;
let factory: UniswapV2Factory;
let router: UniswapV2Router02;
let daiWeth: UniswapV2Pair;

describe('PremiaMaker', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury, true);

    dai = await new TestErc20__factory(admin).deploy();
    weth = await new WETH9__factory(admin).deploy();
    factory = await new UniswapV2Factory__factory(admin).deploy(admin.address);
    router = await new UniswapV2Router02__factory(admin).deploy(
      factory.address,
      weth.address,
    );
    await p.premiaMaker.addWhitelistedRouter([router.address]);
    await factory.createPair(dai.address, weth.address);
    const daiWethAddr = await factory.getPair(dai.address, weth.address);
    daiWeth = await UniswapV2Pair__factory.connect(daiWethAddr, admin);

    await p.premia.mint(p.premiaBondingCurve.address, parseEther('10000000'));
  });

  it('should make premia successfully', async () => {
    await dai.mint(daiWeth.address, parseEther('100'));
    await weth.deposit({ value: parseEther('1') });
    await weth.transfer(daiWeth.address, parseEther('1'));
    await daiWeth.mint(user1.address);

    await dai.mint(p.premiaMaker.address, parseEther('10'));

    await p.premiaMaker.convert(router.address, dai.address);

    expect(await dai.balanceOf(treasury.address)).to.eq(parseEther('2'));
    expect(await dai.balanceOf(p.premiaMaker.address)).to.eq(0);
    expect(
      (await getEthBalance(p.premiaBondingCurve.address)).gt(
        parseEther('0.07'),
      ),
    ).to.be.true;
    expect((await p.premia.balanceOf(p.xPremia.address)).gt(360)).to.be.true;
  });
});
