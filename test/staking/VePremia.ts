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
import { parseEther, solidityPack } from 'ethers/lib/utils';
import { ONE_DAY } from '../pool/PoolUtil';
import { increaseTimestamp } from '../utils/evm';

let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;

let premia: ERC20Mock;
let usdc: ERC20Mock;
let vePremia: VePremia;

describe('VePremia', () => {
  let snapshotId: number;

  before(async () => {
    [admin, alice, bob] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    usdc = await new ERC20Mock__factory(admin).deploy('USDC', 6);

    vePremia = await new VePremia__factory(admin).deploy(
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
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

  describe('#getUserVotes', () => {
    it('should successfully return user votes', async () => {
      await vePremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

      const votes = [
        {
          amount: parseEther('1'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        },
        {
          amount: parseEther('10'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        },
        {
          amount: parseEther('1.5'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', false],
          ),
        },
      ];

      await vePremia.connect(alice).castVotes(votes);

      expect(
        (await vePremia.getUserVotes(alice.address)).map((el) => {
          return {
            amount: el.amount,
            target: el.target,
          };
        }),
      ).to.deep.eq(votes);
    });
  });

  describe('#castVotes', () => {
    it('should fail casting user vote if not enough voting power', async () => {
      await expect(
        vePremia.connect(alice).castVotes([
          {
            amount: parseEther('1'),
            target: solidityPack(
              ['address', 'bool'],
              ['0x0000000000000000000000000000000000000001', true],
            ),
          },
        ]),
      ).to.be.revertedWith('not enough voting power');

      await vePremia.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      await expect(
        vePremia.connect(alice).castVotes([
          {
            amount: parseEther('10'),
            target: solidityPack(
              ['address', 'bool'],
              ['0x0000000000000000000000000000000000000001', true],
            ),
          },
        ]),
      ).to.be.revertedWith('not enough voting power');
    });

    it('should successfully cast user votes', async () => {
      await vePremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365);

      await vePremia.connect(alice).castVotes([
        {
          amount: parseEther('1'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        },
        {
          amount: parseEther('3'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        },
        {
          amount: parseEther('2.25'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000003', false],
          ),
        },
      ]);

      let votes = await vePremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        ],
        [
          parseEther('3'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        ],
        [
          parseEther('2.25'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000003', false],
          ),
        ],
      ]);

      // Casting new votes should remove all existing votes, and set new ones

      await vePremia.connect(alice).castVotes([
        {
          amount: parseEther('2'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000005', true],
          ),
        },
      ]);

      votes = await vePremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('2'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000005', true],
          ),
        ],
      ]);

      expect(
        await vePremia.getPoolVotes(
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        ),
      ).to.eq(0);

      expect(
        await vePremia.getPoolVotes(
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        ),
      ).to.eq(0);

      expect(
        await vePremia.getPoolVotes(
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000003', false],
          ),
        ),
      ).to.eq(0);

      expect(
        await vePremia.getPoolVotes(
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000005', true],
          ),
        ),
      ).to.eq(parseEther('2'));
    });

    it('should remove some user votes if some tokens are withdrawn', async () => {
      await vePremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365);

      await vePremia.connect(alice).castVotes([
        {
          amount: parseEther('1'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        },
        {
          amount: parseEther('3'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        },
        {
          amount: parseEther('2.25'),
          target: solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000003', false],
          ),
        },
      ]);

      await increaseTimestamp(ONE_DAY * 366);

      let votes = await vePremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        ],
        [
          parseEther('3'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        ],
        [
          parseEther('2.25'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000003', false],
          ),
        ],
      ]);

      expect(await vePremia.getUserPower(alice.address)).to.eq(
        parseEther('6.25'),
      );

      await vePremia.connect(alice).startWithdraw(parseEther('2.5'));

      votes = await vePremia.getUserVotes(alice.address);

      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000001', true],
          ),
        ],
        [
          parseEther('2.125'),
          solidityPack(
            ['address', 'bool'],
            ['0x0000000000000000000000000000000000000002', true],
          ),
        ],
      ]);

      expect(await vePremia.getUserPower(alice.address)).to.eq(
        parseEther('3.125'),
      );
    });
  });

  it('should remove some user votes if new power is lower after stake with new lock period', async () => {
    await vePremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365 * 4);

    await vePremia.connect(alice).castVotes([
      {
        amount: parseEther('10'),
        target: solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000001', true],
        ),
      },
      {
        amount: parseEther('5'),
        target: solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000002', true],
        ),
      },
      {
        amount: parseEther('6.25'),
        target: solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000003', false],
        ),
      },
    ]);

    expect(await vePremia.getUserPower(alice.address)).to.eq(
      parseEther('21.25'),
    );

    await increaseTimestamp(ONE_DAY * 365 * 4 + ONE_DAY);

    let votes = await vePremia.getUserVotes(alice.address);
    expect(votes).to.deep.eq([
      [
        parseEther('10'),
        solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000001', true],
        ),
      ],
      [
        parseEther('5'),
        solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000002', true],
        ),
      ],
      [
        parseEther('6.25'),
        solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000003', false],
        ),
      ],
    ]);

    await vePremia.connect(alice).stake(parseEther('1'), ONE_DAY * 365);
    expect(await vePremia.getUserPower(alice.address)).to.eq(parseEther('7.5'));

    votes = await vePremia.getUserVotes(alice.address);
    expect(votes).to.deep.eq([
      [
        parseEther('7.5'),
        solidityPack(
          ['address', 'bool'],
          ['0x0000000000000000000000000000000000000001', true],
        ),
      ],
    ]);
  });
});
