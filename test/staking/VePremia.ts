import {
  ERC20Mock,
  ERC20Mock__factory,
  VePremia,
  VePremia__factory,
} from '../../typechain';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { beforeEach } from 'mocha';
import { parseEther } from 'ethers/lib/utils';
import { ONE_DAY } from '../pool/PoolUtil';
import { BigNumber } from 'ethers';
import { increaseTimestamp } from '../utils/evm';

let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;

let premia: ERC20Mock;
let vePremia: VePremia;

describe('VePremia', () => {
  let snapshotId: number;

  before(async () => {
    [admin, alice, bob] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);

    vePremia = await new VePremia__factory(admin).deploy(
      ethers.constants.AddressZero,
      premia.address,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
    );

    for (const u of [alice, bob]) {
      await premia.mint(u.address, parseEther('100'));
      await premia
        .connect(u)
        .approve(vePremia.address, ethers.constants.MaxUint256);
    }
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('#getTotalVotingPower', () => {
    it('should successfully return total voting power', async () => {
      expect(await vePremia.getTotalVotingPower()).to.eq(0);

      await vePremia.connect(alice).deposit(parseEther('10'));
      await vePremia.connect(alice).stake(parseEther('1'), ONE_DAY * 360);

      expect(await vePremia.getTotalVotingPower()).to.eq(parseEther('2'));

      await vePremia.connect(bob).deposit(parseEther('10'));
      await vePremia.connect(bob).stake(parseEther('3'), ONE_DAY * 180);

      expect(await vePremia.getTotalVotingPower()).to.eq(parseEther('6.5'));
    });
  });

  describe('#getUserVotingPower', () => {
    it('should successfully return user vorting power', async () => {
      await vePremia.connect(alice).deposit(parseEther('10'));
      await vePremia.connect(alice).stake(parseEther('1'), ONE_DAY * 360);

      await vePremia.connect(bob).deposit(parseEther('10'));
      await vePremia.connect(bob).stake(parseEther('3'), ONE_DAY * 180);

      expect(await vePremia.getUserVotingPower(alice.address)).to.eq(
        parseEther('2'),
      );
      expect(await vePremia.getUserVotingPower(bob.address)).to.eq(
        parseEther('4.5'),
      );
    });
  });

  describe('#getUserVotes', () => {
    it('should successfully return user votes', async () => {
      await vePremia.connect(alice).deposit(parseEther('10'));
      await vePremia.connect(alice).stake(parseEther('10'), ONE_DAY * 360);

      const votes = [
        {
          amount: parseEther('1'),
          chainId: BigNumber.from(10),
          poolAddress: '0x0000000000000000000000000000000000000001',
          isCallPool: true,
        },
        {
          amount: parseEther('15'),
          chainId: BigNumber.from(12),
          poolAddress: '0x0000000000000000000000000000000000000002',
          isCallPool: true,
        },
        {
          amount: parseEther('4'),
          chainId: BigNumber.from(12),
          poolAddress: '0x0000000000000000000000000000000000000002',
          isCallPool: false,
        },
      ];

      await vePremia.connect(alice).castVotes(votes);

      expect(
        (await vePremia.getUserVotes(alice.address)).map((el) => {
          return {
            amount: el.amount,
            chainId: el.chainId,
            poolAddress: el.poolAddress,
            isCallPool: el.isCallPool,
          };
        }),
      ).to.deep.eq(votes);
    });
  });

  describe('#castVotes', () => {
    it('should fail casting user vote if not enough voting power', async () => {
      await vePremia.connect(alice).deposit(parseEther('10'));

      await expect(
        vePremia.connect(alice).castVotes([
          {
            amount: parseEther('1'),
            chainId: 10,
            poolAddress: '0x0000000000000000000000000000000000000001',
            isCallPool: true,
          },
        ]),
      ).to.be.revertedWith('not enough voting power');

      await vePremia.connect(alice).stake(parseEther('1'), ONE_DAY * 360);

      await expect(
        vePremia.connect(alice).castVotes([
          {
            amount: parseEther('10'),
            chainId: 10,
            poolAddress: '0x0000000000000000000000000000000000000001',
            isCallPool: true,
          },
        ]),
      ).to.be.revertedWith('not enough voting power');
    });

    it('should successfully cast user votes', async () => {
      await vePremia.connect(alice).deposit(parseEther('10'));

      await vePremia.connect(alice).stake(parseEther('5'), ONE_DAY * 360);

      await vePremia.connect(alice).castVotes([
        {
          amount: parseEther('10'),
          chainId: 10,
          poolAddress: '0x0000000000000000000000000000000000000001',
          isCallPool: true,
        },
      ]);

      const votes = await vePremia.getUserVotes(alice.address);
      expect(votes.length).to.eq(1);
      expect(votes[0].amount).to.eq(parseEther('10'));
      expect(votes[0].chainId).to.eq(10);
      expect(votes[0].poolAddress).to.eq(
        '0x0000000000000000000000000000000000000001',
      );
      expect(votes[0].isCallPool).to.be.true;
    });

    it('should remove some user votes if some tokens are withdrawn', async () => {
      await vePremia.connect(alice).deposit(parseEther('10'));

      await vePremia.connect(alice).stake(parseEther('5'), ONE_DAY * 360);

      await vePremia.connect(alice).castVotes([
        {
          amount: parseEther('10'),
          chainId: 10,
          poolAddress: '0x0000000000000000000000000000000000000001',
          isCallPool: true,
        },
      ]);

      await increaseTimestamp(ONE_DAY * 361);

      await vePremia.connect(alice).unstake(parseEther('2.5'));

      const votes = await vePremia.getUserVotes(alice.address);
      expect(votes.length).to.eq(1);
      expect(votes[0].amount).to.eq(parseEther('5'));
      expect(votes[0].chainId).to.eq(10);
      expect(votes[0].poolAddress).to.eq(
        '0x0000000000000000000000000000000000000001',
      );
      expect(votes[0].isCallPool).to.be.true;

      expect(await vePremia.getUserVotingPower(alice.address)).to.eq(
        parseEther('5'),
      );
    });
  });
});
