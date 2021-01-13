import { expect } from 'chai';
import { TestErc20__factory } from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { mineBlockUntil, resetHardhat } from './utils/evm';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { signERC2612Permit } from './eth-permit/eth-permit';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let carol: SignerWithAddress;
let treasury: SignerWithAddress;

async function depositWithPermit(
  user: SignerWithAddress,
  token: string,
  pid: number,
  amount: BigNumber,
) {
  const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

  const result = await signERC2612Permit(
    user.provider,
    token,
    user.address,
    p.premiaMining.address,
    amount.toString(),
    deadline,
  );

  await p.premiaMining
    .connect(user)
    .depositWithPermit(pid, amount, deadline, result.v, result.r, result.s);
}

describe('PremiaMining', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, alice, bob, carol, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury, true);
    await p.premia.mint(p.premiaMining.address, parseEther('18000000'));
    await p.uPremia.addWhitelisted([p.premiaMining.address]);
    await p.premiaMining.add(1e4, p.uPremia.address, true);
    await p.uPremia.addMinter([admin.address]);
    await p.priceProvider.setTokenPrices([p.premia.address], [parseEther('1')]);

    for (const u of [alice, bob, carol]) {
      await p.uPremia.mintReward(
        u.address,
        p.premia.address,
        parseEther('100'),
      );
    }
  });

  it('should successfully deposit with permit', async () => {
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('1'));

    expect(await p.uPremia.balanceOf(alice.address)).to.eq(parseEther('99'));
    expect(await p.uPremia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('1'),
    );
  });

  it('should allow emergency withdraw', async () => {
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('1'));

    await p.premiaMining.connect(alice).emergencyWithdraw(0);

    expect(await p.uPremia.balanceOf(alice.address)).to.eq(parseEther('100'));
    expect(await p.uPremia.balanceOf(p.premiaMining.address)).to.eq(0);
  });

  it('should give out premia only after farming time', async () => {
    // 4 per block farming rate starting at block 100 with bonus 2.5x bonus for 100 blocks

    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('1'));

    await mineBlockUntil(89);
    await p.premiaMining.connect(alice).deposit(0, 0); // Block 90
    expect(await p.premia.balanceOf(alice.address)).to.eq(0);

    await mineBlockUntil(94);
    await p.premiaMining.connect(alice).deposit(0, 0); // Block 95
    expect(await p.premia.balanceOf(alice.address)).to.eq(0);

    await mineBlockUntil(99);
    await p.premiaMining.connect(alice).deposit(0, 0); // Block 100
    expect(await p.premia.balanceOf(alice.address)).to.eq(0);

    await mineBlockUntil(100);
    await p.premiaMining.connect(alice).deposit(0, 0); // Block 101
    expect(await p.premia.balanceOf(alice.address)).to.eq(parseEther('10'));

    await mineBlockUntil(104);
    await p.premiaMining.connect(alice).deposit(0, 0); // Block 105
    expect(await p.premia.balanceOf(alice.address)).to.eq(parseEther('50'));
    expect(await p.premia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('18000000').sub(parseEther('50')),
    );
  });

  it('should not distribute premia if no one deposit', async () => {
    // 4 per block farming rate starting at block 100 with bonus 2.5x bonus for 100 blocks

    await mineBlockUntil(99);
    expect(await p.premia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('18000000'),
    );

    await mineBlockUntil(104);
    expect(await p.premia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('18000000'),
    );

    await mineBlockUntil(109);
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('1'));
    expect(await p.premia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('18000000'),
    );
    expect(await p.premia.balanceOf(alice.address)).to.eq(0);
    expect(await p.uPremia.balanceOf(alice.address)).to.eq(parseEther('99'));

    await mineBlockUntil(119);
    await p.premiaMining.connect(alice).withdraw(0, parseEther('1'));
    expect(await p.premia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('18000000').sub(parseEther('100')),
    );
    expect(await p.premia.balanceOf(alice.address)).to.eq(parseEther('100'));
    expect(await p.uPremia.balanceOf(alice.address)).to.eq(parseEther('100'));
  });

  it('should distribute premia properly for each staker', async () => {
    // 4 per block farming rate starting at block 100 with bonus 2.5x bonus for 100 blocks

    // Alice deposits 10 uPremia at block 110
    await mineBlockUntil(109);
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('10'));

    // Bob deposits 20 uPremia at block 114
    await mineBlockUntil(113);
    await depositWithPermit(bob, p.uPremia.address, 0, parseEther('20'));

    // Carol deposits 30 uPremia at block 118
    await mineBlockUntil(117);
    await depositWithPermit(carol, p.uPremia.address, 0, parseEther('30'));

    // Alice deposits 10 more uPremia at block 120. At this point:
    //   Alice should have: 4*10 + 4*1/3*10 + 2*1/6*10 = 56.66
    await mineBlockUntil(119);
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('10'));

    let aliceBal = await p.premia.balanceOf(alice.address);
    let bobBal = await p.premia.balanceOf(bob.address);
    let carolBal = await p.premia.balanceOf(carol.address);

    expect(aliceBal.gt(parseEther('56.66')) && aliceBal.lt(parseEther('56.67')))
      .to.be.true;
    expect(bobBal).to.eq(0);
    expect(carolBal).to.eq(0);

    // Bob withdraws 5 uPremia at block 330. At this point:
    //   Bob should have: 4*2/3*10 + 2*2/6*10 + 10*2/7*10 = 61.90
    await mineBlockUntil(129);
    await p.premiaMining.connect(bob).withdraw(0, parseEther('5'));

    aliceBal = await p.premia.balanceOf(alice.address);
    bobBal = await p.premia.balanceOf(bob.address);
    carolBal = await p.premia.balanceOf(carol.address);

    expect(aliceBal.gt(parseEther('56.66')) && aliceBal.lt(parseEther('56.67')))
      .to.be.true;
    expect(bobBal.gt(parseEther('61.90')) && bobBal.lt(parseEther('61.91'))).to
      .be.true;
    expect(carolBal).to.eq(0);

    // Alice withdraws 20 uPremia at block 340.
    // Bob withdraws 15 uPremia at block 350.
    // Carol withdraws 30 uPremia at block 360.
    await mineBlockUntil(139);
    await p.premiaMining.connect(alice).withdraw(0, parseEther('20'));

    await mineBlockUntil(149);
    await p.premiaMining.connect(bob).withdraw(0, parseEther('15'));

    await mineBlockUntil(159);
    await p.premiaMining.connect(carol).withdraw(0, parseEther('30'));

    aliceBal = await p.premia.balanceOf(alice.address);
    bobBal = await p.premia.balanceOf(bob.address);
    carolBal = await p.premia.balanceOf(carol.address);

    // Alice should have: 56.66 + 10*2/7*10 + 10*2/6.5*10 = 116.00
    expect(
      aliceBal.gt(parseEther('116.00')) && aliceBal.lt(parseEther('116.01')),
    ).to.be.true;
    // Bob should have: 61.90 + 10*1.5/6.5 * 10 + 10*1.5/4.5*10 = 118.31
    expect(bobBal.gt(parseEther('118.31')) && bobBal.lt(parseEther('118.32')))
      .to.be.true;
    // Carol should have: 2*3/6*10 + 10*3/7*10 + 10*3/6.5*10 + 10*3/4.5*10 + 10*10 = 265.67
    expect(
      carolBal.gt(parseEther('265.67')) && carolBal.lt(parseEther('265.68')),
    ).to.be.true;

    // All of them should have 100 uPremia back.
    expect(await p.uPremia.balanceOf(alice.address)).to.eq(parseEther('100'));
    expect(await p.uPremia.balanceOf(bob.address)).to.eq(parseEther('100'));
    expect(await p.uPremia.balanceOf(carol.address)).to.eq(parseEther('100'));
  });

  it('should give proper premia allocation to each pool', async () => {
    const dai = await new TestErc20__factory(admin).deploy();
    await dai.mint(bob.address, parseEther('100'));

    // Add first LP to the pool with allocation 1
    await mineBlockUntil(109);
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('10'));

    await mineBlockUntil(119);
    await p.premiaMining.add(2e4, dai.address, true);

    // Alice should have 10*1000 pending reward
    expect(await p.premiaMining.pendingPremia(0, alice.address)).to.eq(
      parseEther('100'),
    );

    // Bob deposits 5 LP2s at block 425
    await mineBlockUntil(124);
    await depositWithPermit(bob, dai.address, 1, parseEther('5'));

    // Alice should have 100 + 5*1/3*10 = 116.66 pending reward
    let alicePending = await p.premiaMining.pendingPremia(0, alice.address);
    expect(
      alicePending.gt(parseEther('116.66')) &&
        alicePending.lt(parseEther('116.67')),
    ).to.be.true;

    // At block 430. Bob should get 5*2/3*10 = 33.33. Alice should get ~16.66 more.
    await mineBlockUntil(130);
    alicePending = await p.premiaMining.pendingPremia(0, alice.address);
    let bobPending = await p.premiaMining.pendingPremia(1, bob.address);

    expect(
      alicePending.gt(parseEther('133.33')) &&
        alicePending.lt(parseEther('133.34')),
    ).to.be.true;
    expect(
      bobPending.gt(parseEther('33.33')) && bobPending.lt(parseEther('33.34')),
    ).to.be.true;
  });

  it('should stop giving bonus premia after the bonus period ends', async () => {
    // Alice deposits 10 LPs at block 590
    await mineBlockUntil(189);
    await depositWithPermit(alice, p.uPremia.address, 0, parseEther('10'));

    // At block 605, she should have 10*10 + 4*5 = 120 pending.
    await mineBlockUntil(205);
    expect(await p.premiaMining.pendingPremia(0, alice.address)).to.eq(
      parseEther('120'),
    );

    // At block 606, Alice withdraws all pending rewards and should get 124.
    await p.premiaMining.connect(alice).deposit(0, 0);
    expect(await p.premia.balanceOf(alice.address)).to.eq(parseEther('124'));
    expect(await p.premia.balanceOf(p.premiaMining.address)).to.eq(
      parseEther('18000000').sub(parseEther('124')),
    );
  });
});
