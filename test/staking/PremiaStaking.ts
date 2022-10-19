import { expect } from 'chai';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IExchangeHelper,
  ExchangeHelper__factory,
  PremiaStakingMock,
  PremiaStakingMock__factory,
  PremiaStakingProxy__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { signERC2612Permit } from 'eth-permit';
import { increaseTimestamp, setTimestamp } from '../utils/evm';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { bnToNumber } from '../utils/math';
import { BigNumber, BigNumberish } from 'ethers';
import { ONE_YEAR } from '../pool/PoolUtil';
import {
  createUniswap,
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
  uniswapABIs,
} from '../utils/uniswap';

let uniswap: IUniswap;
let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let carol: SignerWithAddress;
let premia: ERC20Mock;
let usdc: ERC20Mock;
let premiaStakingImplementation: PremiaStakingMock;
let premiaStaking: PremiaStakingMock;
let otherPremiaStaking: PremiaStakingMock;
let exchangeHelper: IExchangeHelper;

const ONE_DAY = 3600 * 24;
const USDC_DECIMALS = 6;

function parseUSDC(amount: string) {
  return parseUnits(amount, USDC_DECIMALS);
}

function decay(
  pendingRewards: number,
  oldTimestamp: number,
  newTimestamp: number,
) {
  return Math.pow(1 - 2.7e-7, newTimestamp - oldTimestamp) * pendingRewards;
}

async function bridge(
  premiaStaking: PremiaStakingMock,
  otherPremiaStaking: PremiaStakingMock,
  user: SignerWithAddress,
  amount: BigNumberish,
  stakePeriod: number,
  lockedUntil: number,
) {
  // Mocked bridge out
  await premiaStaking
    .connect(alice)
    .sendFrom(
      user.address,
      0,
      user.address,
      amount,
      user.address,
      ethers.constants.AddressZero,
      '0x',
    );

  // Mocked bridge in
  await otherPremiaStaking.creditTo(
    user.address,
    amount,
    stakePeriod,
    lockedUntil,
  );
}

describe('PremiaStaking', () => {
  let snapshotId: number;

  before(async () => {
    [admin, alice, bob, carol] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    usdc = await new ERC20Mock__factory(admin).deploy('USDC', USDC_DECIMALS);
    exchangeHelper = await new ExchangeHelper__factory(admin).deploy();
    premiaStakingImplementation = await new PremiaStakingMock__factory(
      admin,
    ).deploy(
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      exchangeHelper.address,
    );

    const premiaStakingProxy = await new PremiaStakingProxy__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    const otherPremiaStakingProxy = await new PremiaStakingProxy__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    premiaStaking = PremiaStakingMock__factory.connect(
      premiaStakingProxy.address,
      admin,
    );

    otherPremiaStaking = PremiaStakingMock__factory.connect(
      otherPremiaStakingProxy.address,
      admin,
    );

    await usdc.mint(admin.address, parseUSDC('1000'));
    await premia.mint(alice.address, parseEther('100'));
    await premia.mint(bob.address, parseEther('100'));
    await premia.mint(carol.address, parseEther('100'));

    await usdc
      .connect(admin)
      .approve(premiaStaking.address, ethers.constants.MaxUint256);

    uniswap = await createUniswap(admin);

    const pairUsdc = await createUniswapPair(
      admin,
      uniswap.factory,
      usdc.address,
      uniswap.weth.address,
    );

    const pairPremia = await createUniswapPair(
      admin,
      uniswap.factory,
      premia.address,
      uniswap.weth.address,
    );

    await depositUniswapLiquidity(
      admin,
      uniswap.weth.address,
      pairUsdc,
      ethers.utils.parseUnits('100', 18),
      ethers.utils.parseUnits('100', 18),
    );

    await depositUniswapLiquidity(
      admin,
      uniswap.weth.address,
      pairPremia,
      ethers.utils.parseUnits('100', 18),
      ethers.utils.parseUnits('100', 18),
    );
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('#getTotalVotingPower', () => {
    it('should successfully return total voting power', async () => {
      expect(await premiaStaking.getTotalPower()).to.eq(0);

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      expect(await premiaStaking.getTotalPower()).to.eq(parseEther('1.25'));

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking
        .connect(bob)
        .stake(parseEther('3'), (ONE_DAY * 365) / 2);

      expect(await premiaStaking.getTotalPower()).to.eq(parseEther('3.5'));
    });
  });

  describe('#getUserVotingPower', () => {
    it('should successfully return user voting power', async () => {
      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking
        .connect(bob)
        .stake(parseEther('3'), (ONE_DAY * 365) / 2);

      expect(await premiaStaking.getUserPower(alice.address)).to.eq(
        parseEther('1.25'),
      );
      expect(await premiaStaking.getUserPower(bob.address)).to.eq(
        parseEther('2.25'),
      );
    });
  });

  describe('FeeDiscount', () => {
    const stakeAmount = parseEther('120000');
    const oneMonth = 30 * ONE_DAY;

    beforeEach(async () => {
      await premia.mint(alice.address, stakeAmount);
      await premia
        .connect(alice)
        .increaseAllowance(premiaStaking.address, ethers.constants.MaxUint256);
    });

    it('should stake and calculate discount successfully', async () => {
      await premiaStaking.connect(alice).stake(stakeAmount, ONE_YEAR);
      let amountWithBonus = await premiaStaking.getUserPower(alice.address);
      expect(amountWithBonus).to.eq(parseEther('150000'));
      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(2722);

      await increaseTimestamp(ONE_YEAR + 1);

      await premiaStaking.connect(alice).startWithdraw(parseEther('10000'));

      amountWithBonus = await premiaStaking.getUserPower(alice.address);

      expect(amountWithBonus).to.eq(parseEther('137500'));
      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(2694);

      await premia.mint(alice.address, parseEther('5000000'));
      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('5000000'));
      await premiaStaking.connect(alice).stake(parseEther('5000000'), ONE_YEAR);

      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(6000);
    });

    it('should stake successfully with permit', async () => {
      const { timestamp } = await ethers.provider.getBlock('latest');
      const deadline = timestamp + 3600;

      const result = await signERC2612Permit(
        alice.provider,
        premia.address,
        alice.address,
        premiaStaking.address,
        stakeAmount.toString(),
        deadline,
      );

      await premiaStaking
        .connect(alice)
        .stakeWithPermit(
          stakeAmount,
          ONE_YEAR,
          deadline,
          result.v,
          result.r,
          result.s,
        );

      const amountWithBonus = await premiaStaking.getUserPower(alice.address);
      expect(amountWithBonus).to.eq(parseEther('150000'));
    });

    it('should fail unstaking if stake is still locked', async () => {
      await premiaStaking.connect(alice).stake(stakeAmount, oneMonth);
      await expect(
        premiaStaking.connect(alice).startWithdraw(1),
      ).to.be.revertedWithCustomError(
        premiaStaking,
        'PremiaStaking__StakeLocked',
      );
    });

    it('should correctly calculate stake period multiplier', async () => {
      expect(await premiaStaking.getStakePeriodMultiplierBPS(0)).to.eq(2500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(ONE_YEAR / 2),
      ).to.eq(7500);
      expect(await premiaStaking.getStakePeriodMultiplierBPS(ONE_YEAR)).to.eq(
        12500,
      );
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(2 * ONE_YEAR),
      ).to.eq(22500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(4 * ONE_YEAR),
      ).to.eq(42500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(5 * ONE_YEAR),
      ).to.eq(42500);
    });
  });

  it('should fail transferring token if locked', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 30 * ONE_DAY);

    await expect(
      premiaStaking.connect(alice).transfer(bob.address, parseEther('1')),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__CantTransferWhenLocked',
    );
  });

  it('should successfully transfer tokens if not locked', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await premiaStaking.connect(alice).transfer(bob.address, parseEther('1'));

    expect(await premiaStaking.balanceOf(alice.address)).to.eq(
      parseEther('99'),
    );
    expect(await premiaStaking.balanceOf(bob.address)).to.eq(parseEther('1'));
  });

  it('should successfully stake with permit', async () => {
    const { timestamp } = await ethers.provider.getBlock('latest');
    const deadline = timestamp + 3600;

    const result = await signERC2612Permit(
      alice.provider,
      premia.address,
      alice.address,
      premiaStaking.address,
      parseEther('100').toString(),
      deadline,
    );

    await premiaStaking
      .connect(alice)
      .stakeWithPermit(
        parseEther('100'),
        0,
        deadline,
        result.v,
        result.r,
        result.s,
      );
    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(parseEther('100'));
  });

  it('should not allow enter if not enough approve', async () => {
    await expect(
      premiaStaking.connect(alice).stake(parseEther('100'), 0),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'ERC20Base__InsufficientAllowance',
    );
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('50'));
    await expect(
      premiaStaking.connect(alice).stake(parseEther('100'), 0),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'ERC20Base__InsufficientAllowance',
    );
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(parseEther('100'));
  });

  it('should only allow to withdraw what is available', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await premia
      .connect(bob)
      .approve(otherPremiaStaking.address, parseEther('40'));
    await otherPremiaStaking.connect(bob).stake(parseEther('20'), 0);

    await bridge(
      premiaStaking,
      otherPremiaStaking,
      alice,
      parseEther('50'),
      0,
      0,
    );

    await premiaStaking.connect(alice).startWithdraw(parseEther('50'));
    await otherPremiaStaking.connect(alice).startWithdraw(parseEther('10'));
    await otherPremiaStaking.connect(bob).startWithdraw(parseEther('5'));

    await expect(
      otherPremiaStaking.connect(alice).startWithdraw(parseEther('10')),
    ).to.be.revertedWithCustomError(
      otherPremiaStaking,
      'PremiaStaking__NotEnoughLiquidity',
    );
  });

  it('should correctly handle withdrawal with delay', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await expect(
      premiaStaking.connect(alice).withdraw(),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__NoPendingWithdrawal',
    );

    await premiaStaking.connect(alice).startWithdraw(parseEther('40'));

    expect(await premiaStaking.getAvailablePremiaAmount()).to.eq(
      parseEther('60'),
    );

    await increaseTimestamp(ONE_DAY * 10 - 5);
    await expect(
      premiaStaking.connect(alice).withdraw(),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__WithdrawalStillPending',
    );

    await increaseTimestamp(10);

    await premiaStaking.connect(alice).withdraw();
    expect(await premiaStaking.balanceOf(alice.address)).to.eq(
      parseEther('60'),
    );
    expect(await premia.balanceOf(alice.address)).to.eq(parseEther('40'));

    await expect(
      premiaStaking.connect(alice).withdraw(),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__NoPendingWithdrawal',
    );
  });

  it('should distribute partial rewards properly', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premia.connect(bob).approve(premiaStaking.address, parseEther('100'));
    await premia
      .connect(carol)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking.connect(alice).stake(parseEther('30'), 0);
    await premiaStaking.connect(bob).stake(parseEther('10'), 0);
    await premiaStaking.connect(carol).stake(parseEther('10'), 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('10'));
    expect(carolBalance).to.eq(parseEther('10'));
    expect(contractBalance).to.eq(parseEther('50'));

    await premiaStaking.connect(bob).startWithdraw(parseEther('10'));

    // PremiaStaking get 50 USDC rewards
    await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

    expect((await premiaStaking.getPendingWithdrawal(bob.address))[0]).to.eq(
      parseEther('10'),
    );

    await increaseTimestamp(ONE_DAY * 30);

    const pendingRewards = await premiaStaking.getPendingRewards();

    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      pendingRewards.mul(10).div(40),
    );
  });

  it('should work with more than one participant', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premia.connect(bob).approve(premiaStaking.address, parseEther('100'));
    await premia
      .connect(carol)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking.connect(alice).stake(parseEther('30'), 0);
    await premiaStaking.connect(bob).stake(parseEther('10'), 0);
    await premiaStaking.connect(carol).stake(parseEther('10'), 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('10'));
    expect(carolBalance).to.eq(parseEther('10'));
    expect(contractBalance).to.eq(parseEther('50'));

    await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

    let { timestamp } = await ethers.provider.getBlock('latest');

    await increaseTimestamp(ONE_DAY * 30);

    const pendingRewards1 = await premiaStaking.getPendingRewards();
    let availableRewards = await premiaStaking.getAvailableRewards();

    let decayValue = BigNumber.from(
      Math.floor(
        decay(50, timestamp, timestamp + ONE_DAY * 30) *
          Math.pow(10, USDC_DECIMALS),
      ),
    );

    expect(pendingRewards1).to.eq(parseUSDC('50').sub(decayValue));
    expect(availableRewards[0]).to.eq(
      parseUSDC('50').sub(parseUSDC('50').sub(decayValue)),
    );
    expect(availableRewards[1]).to.eq(0);

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      pendingRewards1.mul(30).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      pendingRewards1.mul(10).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      pendingRewards1.mul(10).div(50),
    );

    await increaseTimestamp(ONE_DAY * 300000);

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      parseUSDC('50').mul(30).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50),
    );

    await premiaStaking.connect(bob).stake(parseEther('50'), 0);

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('60'));
    expect(carolBalance).to.eq(parseEther('10'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('5'));
    await premiaStaking.connect(bob).startWithdraw(parseEther('20'));

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(parseEther('25'));
    expect(bobBalance).to.eq(parseEther('40'));
    expect(carolBalance).to.eq(parseEther('10'));

    // Pending withdrawals should not count anymore as staked
    await premiaStaking.connect(admin).addRewards(parseUSDC('100'));
    timestamp = (await ethers.provider.getBlock('latest')).timestamp;

    await increaseTimestamp(ONE_DAY * 30);

    const pendingRewards2 = await premiaStaking.getPendingRewards();
    availableRewards = await premiaStaking.getAvailableRewards();
    decayValue = BigNumber.from(
      Math.floor(
        decay(100, timestamp, timestamp + ONE_DAY * 30) *
          Math.pow(10, USDC_DECIMALS),
      ),
    );

    expect(pendingRewards2).to.eq(parseUSDC('100').sub(decayValue));
    expect(availableRewards[0]).to.eq(
      parseUSDC('100').sub(parseUSDC('100').sub(decayValue)),
    );
    expect(availableRewards[1]).to.eq(0);

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      parseUSDC('50').mul(30).div(50).add(pendingRewards2.mul(25).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(pendingRewards2.mul(40).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(pendingRewards2.mul(10).div(75)),
    );

    await increaseTimestamp(ONE_DAY * 300000);

    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();

    let alicePremiaBalance = await premia.balanceOf(alice.address);
    let bobPremiaBalance = await premia.balanceOf(bob.address);

    // Alice = 100 - 30 + 5
    expect(alicePremiaBalance).to.eq(parseEther('75'));
    // Bob = 100 - 10 - 50 + 20
    expect(bobPremiaBalance).to.eq(parseEther('60'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('25'));
    await premiaStaking.connect(bob).startWithdraw(parseEther('40'));
    await premiaStaking.connect(carol).startWithdraw(parseEther('10'));

    await increaseTimestamp(10 * ONE_DAY + 1);

    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();
    await premiaStaking.connect(carol).withdraw();

    alicePremiaBalance = await premia.balanceOf(alice.address);
    bobPremiaBalance = await premia.balanceOf(bob.address);
    const carolPremiaBalance = await premia.balanceOf(carol.address);

    expect(await premiaStaking.totalSupply()).to.eq(0);
    expect(alicePremiaBalance).to.eq(parseEther('100'));
    expect(bobPremiaBalance).to.eq(parseEther('100'));
    expect(carolPremiaBalance).to.eq(parseEther('100'));

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      parseUSDC('50').mul(30).div(50).add(parseUSDC('100').mul(25).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(parseUSDC('100').mul(40).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(parseUSDC('100').mul(10).div(75)),
    );
  });

  it('should correctly calculate decay', async () => {
    const oneMonth = 30 * ONE_DAY;
    expect(
      bnToNumber(await premiaStaking.decay(parseEther('100'), 0, oneMonth)),
    ).to.almost(49.66);

    expect(
      bnToNumber(await premiaStaking.decay(parseEther('100'), 0, oneMonth * 2)),
    ).to.almost(24.66);
  });

  it('should correctly bridge to other contract', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking.connect(alice).stake(parseEther('100'), 365 * ONE_DAY);
    await premiaStaking
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));

    expect(await premiaStaking.totalSupply()).to.eq(parseEther('100'));
    expect(await otherPremiaStaking.totalSupply()).to.eq(0);

    await bridge(
      premiaStaking,
      otherPremiaStaking,
      alice,
      parseEther('10'),
      0,
      0,
    );

    expect(await premia.balanceOf(premiaStaking.address)).to.eq(
      parseEther('100'),
    );
    expect(await premia.balanceOf(otherPremiaStaking.address)).to.eq(0);
    expect(await premiaStaking.totalSupply()).to.eq(parseEther('90'));
    expect(await otherPremiaStaking.totalSupply()).to.eq(parseEther('10'));
  });

  describe('#getStakeLevels', () => {
    it('should correctly return stake levels', async () => {
      expect(await premiaStaking.getStakeLevels()).to.deep.eq([
        [parseEther('5000'), BigNumber.from(1000)],
        [parseEther('50000'), BigNumber.from(2500)],
        [parseEther('500000'), BigNumber.from(3500)],
        [parseEther('2500000'), BigNumber.from(6000)],
      ]);
    });
  });

  describe('#harvest', () => {
    it('should correctly harvest pending rewards of user', async () => {
      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premia
        .connect(carol)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking.connect(alice).stake(parseEther('30'), 0);
      await premiaStaking.connect(bob).stake(parseEther('10'), 0);
      await premiaStaking.connect(carol).stake(parseEther('10'), 0);

      await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

      await increaseTimestamp(ONE_DAY * 30);

      const aliceRewards = await premiaStaking.getPendingUserRewards(
        alice.address,
      );

      await premiaStaking.connect(alice).harvest();
      expect(await usdc.balanceOf(alice.address)).to.eq(aliceRewards[0].add(3)); // Amount is slightly higher because block timestamp increase by 1 second on harvest
      expect(
        (await premiaStaking.getPendingUserRewards(alice.address))[0],
      ).to.eq(0);
    });
  });

  describe('#harvestAndStake', () => {
    it('harvests rewards, converts to PREMIA, and stakes', async () => {
      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premia
        .connect(carol)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking.connect(alice).stake(parseEther('30'), 0);
      await premiaStaking.connect(bob).stake(parseEther('10'), 0);
      await premiaStaking.connect(carol).stake(parseEther('10'), 0);

      await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

      await increaseTimestamp(ONE_DAY * 30);

      const aliceRewards = await premiaStaking.getPendingUserRewards(
        alice.address,
      );

      const amountBefore = await premiaStaking.callStatic.balanceOf(
        alice.address,
      );

      const uniswapPath = [usdc.address, uniswap.weth.address, premia.address];

      const { timestamp } = await ethers.provider.getBlock('latest');

      const totalRewards = aliceRewards[0].add(aliceRewards[1]);

      const iface = new ethers.utils.Interface(uniswapABIs);
      const data = iface.encodeFunctionData('swapExactTokensForTokens', [
        totalRewards,
        ethers.constants.Zero,
        uniswapPath,
        exchangeHelper.address,
        ethers.constants.MaxUint256,
      ]);

      await premiaStaking.connect(alice).harvestAndStake(
        {
          amountOutMin: ethers.constants.Zero,
          callee: uniswap.router.address,
          allowanceTarget: uniswap.router.address,
          data,
          refundAddress: alice.address,
        },
        ethers.constants.Zero,
      );

      const amountAfter = await premiaStaking.balanceOf(alice.address);

      expect(amountAfter).to.be.gt(amountBefore);
    });
  });

  describe('#earlyUnstake', () => {
    it('should correctly apply early unstake fee and distribute it to stakers', async () => {
      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('50'));

      await premiaStaking.connect(bob).stake(parseEther('50'), 365 * ONE_DAY);

      //

      await premia
        .connect(carol)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking
        .connect(carol)
        .stake(parseEther('100'), 365 * ONE_DAY);

      //

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking
        .connect(alice)
        .stake(parseEther('100'), 4 * 365 * ONE_DAY);

      //

      expect(await premiaStaking.getEarlyUnstakeFeeBPS(alice.address)).to.eq(
        7500,
      );

      await increaseTimestamp(2 * 365 * ONE_DAY);

      expect(await premiaStaking.getEarlyUnstakeFeeBPS(alice.address)).to.eq(
        5000,
      );

      await premiaStaking.connect(alice).earlyUnstake(parseEther('100'));

      expect(
        (await premiaStaking.connect(alice).getPendingWithdrawal(alice.address))
          .amount,
      ).to.eq(parseEther('50.01')); // Small difference due to block timestamp increase by 1 second on new block mined

      const totalFee = parseEther('100').sub(parseEther('50.01'));
      const bobFeeReward = totalFee.div(3);
      const carolFeeReward = totalFee.mul(2).div(3);

      expect(
        (await premiaStaking.getPendingUserRewards(bob.address)).unstakeReward,
      ).to.eq(bobFeeReward);
      expect(
        (await premiaStaking.getPendingUserRewards(carol.address))
          .unstakeReward,
      ).to.eq(carolFeeReward);

      await premiaStaking.connect(bob).harvest();

      expect(await premiaStaking.balanceOf(bob.address)).to.eq(
        parseEther('50').add(bobFeeReward),
      );

      await premiaStaking.connect(carol).harvest();

      expect(await premiaStaking.balanceOf(carol.address)).to.eq(
        parseEther('100').add(carolFeeReward),
      );
    });
  });

  describe('#sendFrom', () => {
    it('should not revert if no approval but owner', async () => {
      await premia.connect(alice).approve(premiaStaking.address, 1);
      await premiaStaking.connect(alice).stake(1, 0);

      await premiaStaking
        .connect(alice)
        .sendFrom(
          alice.address,
          0,
          alice.address,
          1,
          alice.address,
          ethers.constants.AddressZero,
          '0x',
        );
    });

    describe('reverts if', () => {
      it('sender is not approved or owner', async () => {
        await expect(
          premiaStaking
            .connect(alice)
            .sendFrom(
              premiaStaking.address,
              0,
              alice.address,
              1,
              alice.address,
              ethers.constants.AddressZero,
              '0x',
            ),
        ).to.be.revertedWithCustomError(
          premiaStaking,
          'OFT_InsufficientAllowance',
        );
      });
    });
  });
});
