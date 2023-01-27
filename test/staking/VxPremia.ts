import {
  ERC20Mock,
  ERC20Mock__factory,
  ExchangeHelper__factory,
  Ownable__factory,
  Premia__factory,
  ProxyManager__factory,
  VxPremia,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../typechain';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { parseEther, solidityPack } from 'ethers/lib/utils';
import { ONE_DAY, PoolUtil } from '../pool/PoolUtil';
import { increaseTimestamp } from '../utils/evm';
import { getEventArgs } from '../utils/events';
import { createUniswap } from '../utils/uniswap';

/* Example to decode packed target data

const targetData = '0x000000000000000000000000000000000000000101;
const pool = hexDataSlice(
  targetData,
  0,
  20,
);
const isCallPool = hexDataSlice(
  targetData,
  20,
  21,
);

 */

////////////////////

let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;

let premia: ERC20Mock;
let usdc: ERC20Mock;
let vxPremia: VxPremia;
let p: PoolUtil;

describe('VxPremia', () => {
  let snapshotId: number;

  before(async () => {
    [admin, alice, bob] = await ethers.getSigners();

    const premiaDiamond = await new Premia__factory(admin).deploy();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    usdc = await new ERC20Mock__factory(admin).deploy('USDC', 6);

    vxPremia = await new VxPremia__factory(admin).deploy(
      premiaDiamond.address,
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      ethers.constants.AddressZero,
    );

    const exchangeHelper = await new ExchangeHelper__factory(admin).deploy();
    const uniswap = await createUniswap(admin);

    p = await PoolUtil.deploy(
      admin,
      premia.address,
      2000,
      admin.address,
      vxPremia.address,
      exchangeHelper.address,
      uniswap.weth.address,
      premiaDiamond.address,
    );

    for (const u of [alice, bob]) {
      await premia.mint(u.address, parseEther('100'));
      await premia
        .connect(u)
        .approve(vxPremia.address, ethers.constants.MaxUint256);
    }
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('#getUserVotes', () => {
    it('should successfully return user votes', async () => {
      await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

      console.log(
        await ProxyManager__factory.connect(
          p.premiaDiamond.address,
          admin,
        ).getPoolList(),
      );
      console.log(solidityPack(['address', 'bool'], [p.pool.address, true]));

      const votes = [
        {
          amount: parseEther('1'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.pool.address, true]),
        },
        {
          amount: parseEther('10'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        },
        {
          amount: parseEther('1.5'),
          version: 0,
          target: solidityPack(
            ['address', 'bool'],
            [p.poolWeth.address, false],
          ),
        },
      ];

      await vxPremia.connect(alice).castVotes(votes);

      expect(
        (await vxPremia.getUserVotes(alice.address)).map((el) => {
          return {
            amount: el.amount,
            version: el.version,
            target: el.target,
          };
        }),
      ).to.deep.eq(votes);
    });
  });

  describe('#castVotes', () => {
    it('should fail casting user vote if not enough voting power', async () => {
      await expect(
        vxPremia.connect(alice).castVotes([
          {
            amount: parseEther('1'),
            version: 0,
            target: solidityPack(['address', 'bool'], [p.pool.address, true]),
          },
        ]),
      ).to.be.revertedWithCustomError(
        vxPremia,
        'VxPremia__NotEnoughVotingPower',
      );

      await vxPremia.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      await expect(
        vxPremia.connect(alice).castVotes([
          {
            amount: parseEther('10'),
            version: 0,
            target: solidityPack(['address', 'bool'], [p.pool.address, true]),
          },
        ]),
      ).to.be.revertedWithCustomError(
        vxPremia,
        'VxPremia__NotEnoughVotingPower',
      );
    });

    it('should successfully cast user votes', async () => {
      await vxPremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365);

      await vxPremia.connect(alice).castVotes([
        {
          amount: parseEther('1'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.pool.address, true]),
        },
        {
          amount: parseEther('3'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        },
        {
          amount: parseEther('2.25'),
          version: 0,
          target: solidityPack(
            ['address', 'bool'],
            [p.poolWeth.address, false],
          ),
        },
      ]);

      let votes = await vxPremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          0,
          solidityPack(['address', 'bool'], [p.pool.address, true]),
        ],
        [
          parseEther('3'),
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        ],
        [
          parseEther('2.25'),
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, false]),
        ],
      ]);

      // Casting new votes should remove all existing votes, and set new ones

      await vxPremia.connect(alice).castVotes([
        {
          amount: parseEther('2'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.pool.address, false]),
        },
      ]);

      votes = await vxPremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('2'),
          0,
          solidityPack(['address', 'bool'], [p.pool.address, false]),
        ],
      ]);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [p.pool.address, true]),
        ),
      ).to.eq(0);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        ),
      ).to.eq(0);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, false]),
        ),
      ).to.eq(0);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [p.pool.address, false]),
        ),
      ).to.eq(parseEther('2'));
    });

    it('should remove some user votes if some tokens are withdrawn', async () => {
      await vxPremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365);

      await vxPremia.connect(alice).castVotes([
        {
          amount: parseEther('1'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.pool.address, true]),
        },
        {
          amount: parseEther('3'),
          version: 0,
          target: solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        },
        {
          amount: parseEther('2.25'),
          version: 0,
          target: solidityPack(
            ['address', 'bool'],
            [p.poolWeth.address, false],
          ),
        },
      ]);

      await increaseTimestamp(ONE_DAY * 366);

      let votes = await vxPremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          0,
          solidityPack(['address', 'bool'], [p.pool.address, true]),
        ],
        [
          parseEther('3'),
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        ],
        [
          parseEther('2.25'),
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, false]),
        ],
      ]);

      expect(await vxPremia.getUserPower(alice.address)).to.eq(
        parseEther('6.25'),
      );

      await vxPremia.connect(alice).startWithdraw(parseEther('2.5'));

      votes = await vxPremia.getUserVotes(alice.address);

      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          0,
          solidityPack(['address', 'bool'], [p.pool.address, true]),
        ],
        [
          parseEther('2.125'),
          0,
          solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
        ],
      ]);

      expect(await vxPremia.getUserPower(alice.address)).to.eq(
        parseEther('3.125'),
      );
    });
  });

  it('should successfully update total pool votes', async () => {
    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('12.5'),
        version: 0,
        target: solidityPack(['address', 'bool'], [p.pool.address, true]),
      },
    ]);

    await increaseTimestamp(ONE_DAY * 366);

    const target = solidityPack(['address', 'bool'], [p.pool.address, true]);
    expect(await vxPremia.getPoolVotes(0, target)).to.eq(parseEther('12.5'));

    await vxPremia.connect(alice).startWithdraw(parseEther('5'));

    expect(await vxPremia.getPoolVotes(0, target)).to.eq(parseEther('6.25'));
  });

  it('should properly remove all votes if unstaking all', async () => {
    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('6.25'),
        version: 0,
        target: solidityPack(['address', 'bool'], [p.pool.address, true]),
      },
      {
        amount: parseEther('6.25'),
        version: 0,
        target: solidityPack(['address', 'bool'], [p.poolWeth.address, true]),
      },
    ]);

    await increaseTimestamp(ONE_DAY * 366);

    expect((await vxPremia.getUserVotes(alice.address)).length).to.eq(2);

    await vxPremia.connect(alice).startWithdraw(parseEther('10'));

    expect((await vxPremia.getUserVotes(alice.address)).length).to.eq(0);
  });

  it('should emit RemoveVote event', async () => {
    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    const target1 = solidityPack(['address', 'bool'], [p.pool.address, true]);

    const target2 = solidityPack(
      ['address', 'bool'],
      [p.poolWeth.address, true],
    );

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    await increaseTimestamp(ONE_DAY * 366);

    let tx = await vxPremia.connect(alice).startWithdraw(parseEther('4'));
    let event = (await getEventArgs(tx, 'RemoveVote'))[0];

    expect(event[0].voter).to.eq(alice.address);
    expect(event[0].version).to.eq(0);
    expect(event[0].target).to.eq(target2);
    expect(event[0].amount).to.eq(parseEther('2.5'));

    tx = await vxPremia.connect(alice).startWithdraw(parseEther('4'));
    event = (await getEventArgs(tx, 'RemoveVote'))[0];

    expect(event[0].voter).to.eq(alice.address);
    expect(event[0].version).to.eq(0);
    expect(event[0].target).to.eq(target2);
    expect(event[0].amount).to.eq(parseEther('0.5'));

    expect(event[1].voter).to.eq(alice.address);
    expect(event[1].version).to.eq(0);
    expect(event[1].target).to.eq(target1);
    expect(event[1].amount).to.eq(parseEther('4.5'));
  });

  it('should reset user votes', async () => {
    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    const target1 = solidityPack(['address', 'bool'], [p.pool.address, true]);

    const target2 = solidityPack(
      ['address', 'bool'],
      [p.poolWeth.address, true],
    );

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    let votes = await vxPremia.getUserVotes(alice.address);

    expect(votes.length).to.eq(2);

    expect(votes[0].target).to.eq(target1);
    expect(votes[0].amount).to.eq(parseEther('7'));

    expect(votes[1].target).to.eq(target2);
    expect(votes[1].amount).to.eq(parseEther('3'));

    await vxPremia.connect(admin).resetUserVotes(alice.address);

    votes = await vxPremia.getUserVotes(alice.address);
    expect(votes.length).to.eq(0);
  });

  it('should fail resetting user votes if not called from owner', async () => {
    await expect(
      vxPremia.connect(alice).resetUserVotes(alice.address),
    ).to.be.revertedWithCustomError(vxPremia, 'Ownable__NotOwner');
  });
});
