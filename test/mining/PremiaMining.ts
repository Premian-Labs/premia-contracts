import chai, { expect } from 'chai';
import { PoolUtil } from '../pool/PoolUtil';
import { increaseTimestamp, mineBlockUntil } from '../utils/evm';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  ERC20Mock,
  ERC20Mock__factory,
  FeeDiscount,
  FeeDiscount__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { bnToNumber } from '../utils/math';
import chaiAlmost from 'chai-almost';

chai.use(chaiAlmost(0.05));

const oneDay = 24 * 3600;
const oneMonth = 30 * oneDay;

const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`;
const blockNumber = 13569795;

describe('PremiaMining', () => {
  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let lp3: SignerWithAddress;
  let buyer: SignerWithAddress;
  let feeReceiver: SignerWithAddress;
  let multisig: SignerWithAddress;

  let premia: ERC20Mock;
  let xPremia: ERC20Mock;
  let feeDiscount: FeeDiscount;

  let p: PoolUtil;

  const spotPrice = 2000;
  const totalRewardAmount = 200000;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    // Impersonate multisig
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0'],
    });
    multisig = await ethers.getSigner(
      '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0',
    );

    [owner, lp1, lp2, lp3, buyer, feeReceiver] = await ethers.getSigners();

    const erc20Factory = new ERC20Mock__factory(owner);
    premia = await erc20Factory.deploy('PREMIA', 18);
    xPremia = await erc20Factory.deploy('xPREMIA', 18);
    const feeDiscountImpl = await new FeeDiscount__factory(owner).deploy(
      xPremia.address,
    );
    const feeDiscountProxy = await new ProxyUpgradeableOwnable__factory(
      owner,
    ).deploy(feeDiscountImpl.address);
    feeDiscount = FeeDiscount__factory.connect(feeDiscountProxy.address, owner);

    p = await PoolUtil.deploy(
      owner,
      premia.address,
      spotPrice,
      feeReceiver,
      feeDiscount.address,
    );

    await premia.mint(owner.address, parseEther(totalRewardAmount.toString()));
    await premia
      .connect(owner)
      .approve(p.premiaMining.address, ethers.constants.MaxUint256);
    await p.premiaMining.addPremiaRewards(
      parseEther(totalRewardAmount.toString()),
    );

    for (const lp of [lp1, lp2, lp3]) {
      await p.underlying.mint(
        lp.address,
        parseUnits('100', p.getTokenDecimals(true)),
      );
      await p.underlying
        .connect(lp)
        .approve(p.pool.address, ethers.constants.MaxUint256);

      await p.base.mint(
        lp.address,
        parseUnits('100', p.getTokenDecimals(false)),
      );
      await p.base
        .connect(lp)
        .approve(p.pool.address, ethers.constants.MaxUint256);
    }
  });

  it('should revert if calling update not from the option pool', async () => {
    await expect(
      p.premiaMining.updatePool(p.pool.address, true, parseEther('1')),
    ).to.be.revertedWith('Not pool');
  });

  it('should distribute PREMIA properly for each LP', async () => {
    const { number: initial } = await ethers.provider.getBlock('latest');

    await p.pool
      .connect(lp1)
      .deposit(parseUnits('10', p.getTokenDecimals(false)), false);

    await increaseTimestamp(oneDay);

    await p.pool
      .connect(lp1)
      .deposit(parseUnits('10', p.getTokenDecimals(true)), true);

    await increaseTimestamp(2 * oneDay);

    await p.pool
      .connect(lp2)
      .deposit(parseUnits('20', p.getTokenDecimals(true)), true);

    // There is 4 pools with equal alloc points, with premia reward of 1k per day
    // Each pool should get 250 reward per day. Lp1 should therefore have 2 * 250 pending reward now
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(500);

    await increaseTimestamp(3 * oneDay);
    await p.pool
      .connect(lp3)
      .deposit(parseUnits('30', p.getTokenDecimals(true)), true);

    // LP1 should have pending reward of : 2*250 + 3*1/3*250 + 2*1/6*250 = 833.33
    await increaseTimestamp(2 * oneDay);
    await p.pool
      .connect(lp1)
      .deposit(parseUnits('10', p.getTokenDecimals(true)), true);
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(833.33);

    // LP2 should have pending reward of: 3*2/3*250 + 2*2/6*250 + 5*2/7*250 = 1023.81
    await increaseTimestamp(5 * oneDay);
    await p.pool
      .connect(lp2)
      .withdraw(parseUnits('5', p.getTokenDecimals(true)), true);
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp2.address),
      ),
    ).to.almost(1023.81);

    await increaseTimestamp(oneDay);
    await p.pool
      .connect(lp1)
      .withdraw(parseUnits('20', p.getTokenDecimals(true)), true);

    await increaseTimestamp(oneDay);
    await p.pool
      .connect(lp2)
      .withdraw(parseUnits('15', p.getTokenDecimals(true)), true);

    await increaseTimestamp(oneDay);
    await p.pool
      .connect(lp3)
      .withdraw(parseUnits('30', p.getTokenDecimals(true)), true);

    expect(bnToNumber(await p.premiaMining.premiaRewardsAvailable())).to.almost(
      totalRewardAmount - 15000 / 4,
    );

    // LP1 should have: 833.33 + 5*2/7*250 + 1*2/6.5*250 = 1267.4
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(1267.4);
    // LP2 should have: 1023.81 + 1*1.5/6.5 * 250 + 1*1.5/4.5*250 = 1164.84
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp2.address),
      ),
    ).to.almost(1164.84);
    // LP3 should have: 2*3/6*250 + 5*3/7*250 + 1*3/6.5*250 + 1*3/4.5*250 + 1*250 = 1317.77
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp3.address),
      ),
    ).to.almost(1317.77);
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, false, lp1.address),
      ),
    ).to.almost(4000);

    await p.pool.connect(lp1)['claimRewards(bool)'](true);
    await p.pool.connect(lp2)['claimRewards(bool)'](true);
    await p.pool.connect(lp3)['claimRewards(bool)'](true);
    await expect(bnToNumber(await premia.balanceOf(lp1.address))).to.almost(
      1267.4,
    );
    await expect(bnToNumber(await premia.balanceOf(lp2.address))).to.almost(
      1164.84,
    );
    await expect(bnToNumber(await premia.balanceOf(lp3.address))).to.almost(
      1317.77,
    );
  });

  it('should stop distributing rewards if available rewards run out', async () => {
    const { number: initial } = await ethers.provider.getBlock('latest');

    await p.pool
      .connect(lp1)
      .deposit(parseUnits('10', p.getTokenDecimals(true)), true);

    await increaseTimestamp(4 * 200 * oneDay + oneDay);

    expect(
      await p.premiaMining.pendingPremia(p.pool.address, true, lp1.address),
    ).to.eq(parseEther(totalRewardAmount.toString()));

    await p.pool.connect(lp1)['claimRewards(bool)'](true);
    expect(await p.premiaMining.premiaRewardsAvailable()).to.eq(0);
    expect(await premia.balanceOf(lp1.address)).to.eq(
      parseEther(totalRewardAmount.toString()),
    );

    await mineBlockUntil(initial + 320);
    expect(
      await p.premiaMining.pendingPremia(p.pool.address, true, lp1.address),
    ).to.eq(0);

    await premia.mint(owner.address, parseEther(totalRewardAmount.toString()));
    await mineBlockUntil(initial + 349);
    // Trigger pool update
    await p.pool.connect(lp1).updateMiningPools();
    await p.premiaMining
      .connect(owner)
      .addPremiaRewards(parseEther(totalRewardAmount.toString()));

    await increaseTimestamp(oneDay);
    expect(
      bnToNumber(
        await p.premiaMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(250);
  });
});
