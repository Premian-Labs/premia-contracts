import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  ABDKMath64x64TokenMock,
  ABDKMath64x64TokenMock__factory,
} from '../../typechain';

describe('ABDKMath64x64Token', function () {
  let instance: ABDKMath64x64TokenMock;

  const decimalValues = ['0', '1', '2.718281828459045', '9223372036854775807'];

  const fixedPointValues = [
    '0x00000000000000000',
    '0x10000000000000000',
    '0x2b7e151628aed1975',
    '0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
  ];

  before(async function () {
    const [deployer] = await ethers.getSigners();
    instance = await new ABDKMath64x64TokenMock__factory(deployer).deploy();
  });

  describe('#toDecimals', function () {
    it('returns scaled decimal representation of 64x64 fixed point number', async function () {
      for (let decimals = 0; decimals < 22; decimals++) {
        for (let fixed of fixedPointValues) {
          const bn = ethers.BigNumber.from(fixed);

          expect(await instance.callStatic.toDecimals(bn, decimals)).to.equal(
            bn.mul(ethers.BigNumber.from(`1${'0'.repeat(decimals)}`)).shr(64),
          );
        }
      }
    });

    describe('reverts if', function () {
      it('given 64x64 fixed point number is negative', async function () {
        for (let decimals = 0; decimals < 22; decimals++) {
          for (let fixed of fixedPointValues.filter((f) => Number(f) > 0)) {
            const bn = ethers.constants.Zero.sub(ethers.BigNumber.from(fixed));

            await expect(
              instance.callStatic.toDecimals(bn, decimals),
            ).to.be.revertedWith('Transaction reverted without a reason');
          }
        }
      });
    });
  });

  describe('#fromDecimals', function () {
    it('returns 64x64 fixed point representation of scaled decimal number', async function () {
      for (let decimals = 0; decimals < 22; decimals++) {
        for (let decimal of decimalValues) {
          const truncatedArray = decimal.match(
            new RegExp(`^\\d+(.\\d{,${decimals}})?`),
          );

          const truncated = truncatedArray?.[0] ?? '0';

          const bn = ethers.utils.parseUnits(truncated, decimals);

          expect(await instance.callStatic.fromDecimals(bn, decimals)).to.equal(
            bn.shl(64).div(ethers.BigNumber.from(`1${'0'.repeat(decimals)}`)),
          );
        }
      }
    });

    describe('reverts if', function () {
      it('given number exceeds range of 64x64 fixed point representation', async function () {
        const max = ethers.BigNumber.from('0x7FFFFFFFFFFFFFFF');

        for (let decimals = 0; decimals < 22; decimals++) {
          const bn = max
            .add(ethers.constants.One)
            .mul(ethers.BigNumber.from(`1${'0'.repeat(decimals)}`))
            .sub(ethers.constants.One);

          await expect(instance.callStatic.fromDecimals(bn, decimals)).not.to.be
            .reverted;

          await expect(
            instance.callStatic.fromDecimals(
              bn.add(ethers.constants.One),
              decimals,
            ),
          ).to.be.reverted;
        }
      });
    });
  });

  describe('#toWei', function () {
    it('returns wei representation of 64x64 fixed point number', async function () {
      for (let fixed of fixedPointValues) {
        const bn = ethers.BigNumber.from(fixed);

        expect(await instance.callStatic.toWei(bn)).to.equal(
          bn.mul(ethers.BigNumber.from(`1${'0'.repeat(18)}`)).shr(64),
        );
      }
    });

    describe('reverts if', function () {
      it('given 64x64 fixed point number is negative', async function () {
        for (let fixed of fixedPointValues.filter((f) => Number(f) > 0)) {
          const bn = ethers.constants.Zero.sub(ethers.BigNumber.from(fixed));

          await expect(instance.callStatic.toWei(bn)).to.be.revertedWith(
            'Transaction reverted without a reason',
          );
        }
      });
    });
  });

  describe('#fromWei', function () {
    it('returns 64x64 fixed point representation of wei number', async function () {
      for (let decimal of decimalValues) {
        const bn = ethers.utils.parseEther(decimal);

        expect(await instance.callStatic.fromWei(bn)).to.equal(
          bn.shl(64).div(ethers.BigNumber.from(`1${'0'.repeat(18)}`)),
        );
      }
    });

    describe('reverts if', function () {
      it('given wei number exceeds range of 64x64 fixed point representation', async function () {
        const max = ethers.BigNumber.from('0x7FFFFFFFFFFFFFFF');

        const bn = max
          .add(ethers.constants.One)
          .mul(ethers.BigNumber.from(`1${'0'.repeat(18)}`))
          .sub(ethers.constants.One);

        await expect(instance.callStatic.fromWei(bn)).not.to.be.reverted;

        await expect(instance.callStatic.fromWei(bn.add(ethers.constants.One)))
          .to.be.reverted;
      });
    });
  });
});
