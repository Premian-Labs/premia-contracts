import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { ABDKMath64x64Mock, ABDKMath64x64Mock__factory } from '../../typechain';

const toFixed = function (bn: BigNumber) {
  return bn.shl(64);
};

const range = function (bits: number, signed: boolean) {
  if (signed) {
    return {
      min: ethers.constants.Zero.sub(ethers.constants.Two.pow(bits / 2 - 1)),
      max: ethers.constants.Two.pow(bits / 2 - 1).sub(ethers.constants.One),
    };
  } else {
    return {
      min: ethers.constants.Zero,
      max: ethers.constants.Two.pow(bits).sub(ethers.constants.One),
    };
  }
};

describe('ABDKMath64x64', function () {
  let instance: ABDKMath64x64Mock;

  before(async function () {
    const [deployer] = await ethers.getSigners();
    instance = await new ABDKMath64x64Mock__factory(deployer).deploy();
  });

  describe('#fromInt', function () {
    it('returns 64.64 bit representation of given int', async function () {
      const inputs = [0, 1, 2, Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );

      for (let bn of inputs) {
        expect(await instance.callStatic.fromInt(bn)).to.equal(toFixed(bn));
      }
    });

    describe('reverts if', function () {
      it('input is greater than max int128', async function () {
        const { max } = range(128, true);

        await expect(instance.callStatic.fromInt(max)).not.to.be.reverted;

        await expect(instance.callStatic.fromInt(max.add(ethers.constants.One)))
          .to.be.reverted;
      });

      it('input is less than min int128', async function () {
        const { min } = range(128, true);

        await expect(instance.callStatic.fromInt(min)).not.to.be.reverted;

        await expect(instance.callStatic.fromInt(min.sub(ethers.constants.One)))
          .to.be.reverted;
      });
    });
  });

  describe('#toInt', function () {
    it('returns 64 bit integer from 64.64 representation of given int', async function () {
      const inputs = [
        -2,
        -1,
        0,
        1,
        2,
        Math.floor(Math.random() * 1e6),
        -Math.floor(Math.random() * 1e6),
      ].map(BigNumber.from);

      for (let bn of inputs) {
        const representation = await instance.callStatic.fromInt(bn);
        expect(await instance.callStatic.toInt(representation)).to.equal(bn);
      }
    });
  });

  describe('#fromUInt', function () {
    it('returns 64.64 bit representation of given uint', async function () {
      const inputs = [0, 1, 2, Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );

      for (let bn of inputs) {
        expect(await instance.callStatic.fromUInt(bn)).to.equal(toFixed(bn));
      }
    });

    describe('reverts if', function () {
      it('input is greater than max int128', async function () {
        const { max } = range(128, true);

        await expect(instance.callStatic.fromInt(max)).not.to.be.reverted;

        await expect(instance.callStatic.fromInt(max.add(ethers.constants.One)))
          .to.be.reverted;
      });
    });
  });

  describe('#toUInt', function () {
    it('returns 64 bit integer from 64.64 representation of given uint', async function () {
      const inputs = [1, 2, Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );

      for (let bn of inputs) {
        const representation = await instance.callStatic.fromUInt(bn);
        expect(await instance.callStatic.toUInt(representation)).to.equal(bn);
      }
    });

    describe('reverts if', function () {
      it('input is negative', async function () {
        const representation = await instance.callStatic.fromInt(
          BigNumber.from(-1),
        );
        await expect(instance.callStatic.toUInt(representation)).to.be.reverted;
      });
    });
  });

  describe('#from128x128', function () {
    it('todo');

    describe('reverts if', function () {
      it('todo');
    });
  });

  describe('#to128x128', function () {
    it('todo');
  });

  describe('#add', function () {
    it('adds two 64x64s together', async function () {
      const inputs = [1, 2, Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );
      const inputs2 = [3, -4, -Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );

      for (let i = 0; i < inputs.length; i++) {
        const bn = await instance.callStatic.fromInt(inputs[i]);
        const bn2 = await instance.callStatic.fromInt(inputs2[i]);
        const answer = bn.add(bn2);
        expect(await instance.callStatic.add(bn, bn2)).to.equal(answer);
      }
    });

    describe('reverts if', function () {
      it('result would overflow', async function () {
        const max = await instance.callStatic.fromInt(0x7fffffffffffffffn);
        const one = await instance.callStatic.fromInt(1);

        await expect(instance.callStatic.add(max, one)).to.be.reverted;
      });
    });
  });

  describe('#sub', function () {
    it('subtracts two 64x64s', async function () {
      const inputs = [1, 2, Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );
      const inputs2 = [-3, 4, -Math.floor(Math.random() * 1e6)].map(
        BigNumber.from,
      );

      for (let i = 0; i < inputs.length; i++) {
        const bn = await instance.callStatic.fromInt(inputs[i]);
        const bn2 = await instance.callStatic.fromInt(inputs2[i]);
        const answer = bn.sub(bn2);
        expect(await instance.callStatic.sub(bn, bn2)).to.equal(answer);
      }
    });

    describe('reverts if', function () {
      it('result would overflow', async function () {
        const max = await instance.callStatic.fromInt(0x7fffffffffffffffn);
        const one = await instance.callStatic.fromInt(-1);

        await expect(instance.callStatic.sub(max, one)).to.be.reverted;
      });
    });
  });

  describe('#mul', function () {
    it('multiplies two 64x64s', async function () {
      const inputs = [
        Math.floor(Math.random() * 1e6),
        Math.floor(Math.random() * 1e6),
        -Math.floor(Math.random() * 1e6),
      ].map(BigNumber.from);
      const inputs2 = [
        Math.floor(Math.random() * 1e6),
        -Math.floor(Math.random() * 1e6),
        -Math.floor(Math.random() * 1e6),
      ].map(BigNumber.from);

      for (let i = 0; i < inputs.length; i++) {
        const bn = await instance.callStatic.fromInt(inputs[i]);
        const bn2 = await instance.callStatic.fromInt(inputs2[i]);
        let answer = bn.mul(bn2);
        if (answer.gt(0)) {
          answer = answer.shr(64);
        } else {
          answer = answer.mul(-1).shr(64).mul(-1);
        }
        expect(await instance.callStatic.mul(bn, bn2)).to.equal(answer);
      }
    });

    describe('reverts if', function () {
      it('result would overflow', async function () {
        const halfOfMax = await instance.callStatic.fromInt(
          4611686018427387904n,
        );
        const two = await instance.callStatic.fromInt(2);

        await expect(instance.callStatic.mul(halfOfMax, two)).to.be.reverted;
      });
    });
  });

  describe('#muli', function () {
    it('multiplies a 64x64 with an int', async function () {
      const inputs = [
        Math.floor(Math.random() * 1e6),
        -Math.floor(Math.random() * 1e6),
      ].map(BigNumber.from);

      for (let i = 0; i < inputs.length; i++) {
        const bn = await instance.callStatic.fromInt(inputs[i]);
        let answer = bn.mul(BigNumber.from(7));
        if (answer.gt(0)) {
          answer = answer.shr(64);
        } else {
          answer = answer.mul(-1).shr(64).mul(-1);
        }

        expect(await instance.callStatic.muli(bn, BigNumber.from(7))).to.equal(
          answer,
        );
      }
    });

    describe('reverts if', function () {
      it('input is too small', async function () {
        await expect(
          instance.callStatic.muli(
            BigNumber.from(
              -0xffffffffffffffffffffffffffffffffffffffffffffffffn,
            ).sub(1n),
            1,
          ),
        ).to.be.reverted;
      });

      it('input is too large', async function () {
        await expect(
          instance.callStatic.muli(
            BigNumber.from(
              0x1000000000000000000000000000000000000000000000000n,
            ).add(1n),
            1,
          ),
        ).to.be.reverted;
      });

      it('result would overflow', async function () {
        const halfOfMax =
          '28948022309329048855892746252171976963317496166410141009864396001978282409984n';

        await expect(instance.callStatic.muli(halfOfMax, 2)).to.be.reverted;
      });
    });
  });

  describe('#mulu', function () {
    it('multiplies a 64x64 with an unsigned int', async function () {
      const inputs = [Math.floor(Math.random() * 1e6)].map(BigNumber.from);

      for (let i = 0; i < inputs.length; i++) {
        const bn = await instance.callStatic.fromInt(inputs[i]);
        const answer = bn.mul(7).shr(64);

        expect(await instance.callStatic.mulu(bn, BigNumber.from(7))).to.equal(
          answer,
        );
      }
    });

    describe('reverts if', function () {
      it('overflows', async function () {
        await expect(
          instance.callStatic.mulu(
            '0xffffffffffffffffffffffffffffffffffffffffffffffffn',
            2,
          ),
        ).to.be.reverted;
      });
    });
  });

  describe('#div', function () {
    it('divides x by y', async function () {
      const x = await instance.callStatic.fromInt(21);
      const y = await instance.callStatic.fromInt(7);
      const answer = await instance.callStatic.fromInt(3);
      expect(await instance.callStatic.div(x, y)).to.equal(answer);
    });

    describe('reverts if', function () {
      it('y is 0', async function () {
        const x = await instance.callStatic.fromInt(21);
        const y = await instance.callStatic.fromInt(0);
        await expect(instance.callStatic.div(x, y)).to.be.reverted;
      });
      it('overflows', async function () {
        await expect(
          instance.callStatic.div(
            '170141183460469231731687303715884105727n',
            '184467440737n',
          ),
        ).to.be.reverted;
      });
    });
  });

  describe('#divi', function () {
    it('divided x by y where both are ints, result is 64x64', async function () {
      const answer = await instance.callStatic.fromInt(-14);
      expect(await instance.callStatic.divi(42, -3)).to.equal(answer);
    });

    describe('reverts if', function () {
      it('y is 0', async function () {
        await expect(instance.callStatic.divi(99, 0)).to.be.reverted;
      });
      it('overflows', async function () {
        await expect(
          instance.callStatic.divi(
            '170141183460469231731687303715884105727n',
            '184467440737n',
          ),
        ).to.be.reverted;
      });
    });
  });

  describe('#divu', function () {
    it('divided x by y where both are ints, result is 64x64', async function () {
      const answer = await instance.callStatic.fromInt(14);
      expect(await instance.callStatic.divu(42, 3)).to.equal(answer);
    });

    describe('reverts if', function () {
      it('y is 0', async function () {
        await expect(instance.callStatic.divu(99, 0)).to.be.reverted;
      });
      it('overflows', async function () {
        await expect(
          instance.callStatic.divu(
            '170141183460469231731687303715884105727n',
            '184467440737n',
          ),
        ).to.be.reverted;
      });
    });
  });

  describe('#neg', function () {
    it('returns the negative', async function () {
      const randomInt = Math.floor(Math.random() * 1e3);
      const input = await instance.callStatic.fromInt(randomInt);
      const answer = BigInt(-input);
      expect(await instance.callStatic.neg(input)).to.equal(answer);
    });

    describe('reverts if', function () {
      it('overflows', async function () {
        await expect(
          instance.callStatic.neg(-0x80000000000000000000000000000000),
        ).to.be.reverted;
      });
    });
  });

  describe('#abs', function () {
    it('returns the absolute |x|', async function () {
      const randomInt = Math.floor(Math.random() * 1e3);
      const input = await instance.callStatic.fromInt(randomInt);
      expect(await instance.callStatic.abs(input)).to.equal(input);
      const randomIntNeg = Math.floor(-Math.random() * 1e3);
      const inputNeg = await instance.callStatic.fromInt(randomIntNeg);
      expect(await instance.callStatic.abs(inputNeg)).to.equal(
        BigInt(-inputNeg),
      );
    });

    describe('reverts if', function () {
      it('overflows', async function () {
        await expect(
          instance.callStatic.abs(-0x80000000000000000000000000000000),
        ).to.be.reverted;
      });
    });
  });

  describe('#inv', function () {
    it('returns the inverse', async function () {
      const input = await instance.callStatic.fromInt(20);
      const answer = 922337203685477580n;
      expect(await instance.callStatic.inv(input)).to.equal(answer);
    });

    describe('reverts if', function () {
      it('x is zero', async function () {
        await expect(instance.callStatic.inv(0)).to.be.reverted;
      });
      it('overflows', async function () {
        await expect(instance.callStatic.inv(-1)).to.be.reverted;
      });
    });
  });

  describe('#avg', function () {
    it('calculates average', async function () {
      const inputs = [
        await instance.callStatic.fromInt(5),
        await instance.callStatic.fromInt(9),
      ];
      const answer = await instance.callStatic.fromInt(7);
      expect(await instance.callStatic.avg(inputs[0], inputs[1])).to.equal(
        answer,
      );
    });
  });

  describe('#gavg', function () {
    it('calculates average', async function () {
      const inputs = [
        await instance.callStatic.fromInt(16),
        await instance.callStatic.fromInt(25),
      ];
      const answer = await instance.callStatic.fromInt(20);
      expect(await instance.callStatic.gavg(inputs[0], inputs[1])).to.equal(
        answer,
      );
    });

    describe('reverts if', function () {
      it('has negative radicant', async function () {
        const inputs = [
          await instance.callStatic.fromInt(16),
          await instance.callStatic.fromInt(-25),
        ];
        await expect(instance.callStatic.gavg(inputs[0], inputs[1])).to.be
          .reverted;
      });
    });
  });

  describe('#pow', function () {
    it('calculates power', async function () {
      const input = await instance.callStatic.fromInt(5);
      expect(await instance.callStatic.pow(input, 5)).to.equal(
        57646075230342348800000n,
      );
    });

    describe('reverts if', function () {
      it('overflow', async function () {
        const input = await instance.callStatic.fromInt(2);
        await expect(instance.callStatic.pow(input, 129)).to.be.reverted;
      });
    });
  });

  describe('#sqrt', function () {
    it('calculates square root', async function () {
      const input = await instance.callStatic.fromInt(25);
      expect(await instance.callStatic.sqrt(input)).to.equal(
        92233720368547758080n,
      );
    });

    describe('reverts if', function () {
      it('x is negative', async function () {
        const input = await instance.callStatic.fromInt(-1);
        await expect(instance.callStatic.sqrt(input)).to.be.reverted;
      });
    });
  });

  describe('#log_2', function () {
    it('calculates binary logarithm of x', async function () {
      const input = await instance.callStatic.fromInt(8);
      expect(await instance.callStatic.log_2(input)).to.equal(
        55340232221128654848n,
      );
    });

    describe('reverts if', function () {
      it('x is 0', async function () {
        const input = await instance.callStatic.fromInt(0);
        await expect(instance.callStatic.log_2(input)).to.be.reverted;
      });
    });
  });

  describe('#ln', function () {
    it('calculates natural log of x', async function () {
      const input = await instance.callStatic.fromInt(54);
      expect(await instance.callStatic.ln(input)).to.equal(
        73583767821081474575n,
      );
    });

    describe('reverts if', function () {
      it('x is 0', async function () {
        const input = await instance.callStatic.fromInt(0);
        await expect(instance.callStatic.ln(input)).to.be.reverted;
      });
    });
  });

  describe('#exp_2', function () {
    it('calculate binary exponent of x', async function () {
      const input = await instance.callStatic.fromInt(8);
      expect(await instance.callStatic.exp_2(input)).to.equal(
        4722366482869645213696n,
      );
    });

    describe('reverts if', function () {
      it('overflows', async function () {
        const input = await instance.callStatic.fromInt(64);
        await expect(instance.callStatic.exp_2(input)).to.be.reverted;
      });
    });
  });
});
