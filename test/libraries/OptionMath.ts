import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  OptionMathMock,
  OptionMathMock__factory,
  OptionMath__factory,
} from '../../typechain';
import { bnToNumber, fixedFromFloat, fixedToNumber } from '../utils/math';

/*
  Pricing feed mock:
  [unix timestamp, rounded price in USD, log returns]
*/
const raw = [
  [1616543600000, 55222, 0.000001], // Tue Mar 23 2021 23:53:20 GMT+0000
  [1616803000000, 55973, 0.013508], // Fri Mar 26 2021 23:56:40 GMT+0000
  [1616803200000, 55688, -0.005104], // Sat Mar 27 2021 00:00:00 GMT+0000
  [1616889600000, 55284, -0.007281], // Sun Mar 28 2021 00:00:00 GMT+0000
];

const input = raw.map(([x, y, log_returns]) => [
  x / 1000,
  fixedFromFloat(y),
  fixedFromFloat(log_returns),
]);

let [input_t, input_t_1, input_t_2, input_t_3] = input.reverse();

describe('OptionMath', function () {
  let instance: OptionMathMock;

  before(async function () {
    const [deployer] = await ethers.getSigners();
    const optionMath = await new OptionMath__factory(deployer).deploy();
    instance = await new OptionMathMock__factory(
      { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
      deployer,
    ).deploy();
  });

  describe('#decay', function () {
    it('calculates exponential decay', async function () {
      let t = input_t[0];
      let t_1 = input_t_1[0];

      // w = 1 - e^(-24/(7 * 24))
      let expected = bnToNumber(fixedFromFloat(0.1331221002));
      const result = bnToNumber(await instance.callStatic.decay(t_1, t));

      expect(expected / result).to.be.closeTo(1, 0.001);
    });
  });

  // assuming EMA_t-1 = x_t-1
  describe('#unevenRollingEma', function () {
    it('calculates exponential moving average for uneven intervals with significant difference', async function () {
      let t = input_t_2[0];
      let t_1 = input_t_3[0];
      let logReturns = input_t_2[2];
      let old_ema = input_t_3[2];

      let expected = bnToNumber(fixedFromFloat(0.00470901265));
      const result = bnToNumber(
        await instance.callStatic.unevenRollingEma(old_ema, logReturns, t_1, t),
      );

      // 0.013508 * 0.3485609425 + (1 - 0.3485609425) * 0.000001 = 0.004696433685
      expect(expected / result).to.be.closeTo(1, 0.001);
    });

    it('calculates exponential moving average for uneven intervals with small difference', async function () {
      let t = input_t_1[0];
      let t_1 = input_t_2[0];
      let logReturns = input_t_1[2];
      let old_ema = input_t_2[2];

      let expected = bnToNumber(fixedFromFloat(0.01350061575));
      const result = bnToNumber(
        await instance.callStatic.unevenRollingEma(old_ema, logReturns, t_1, t),
      );

      // -0.005104 * 0.000396746672 + (1 - 0.000396746672) * 0.013508 = 0.01350061575
      expect(expected / result).to.be.closeTo(1, 0.001);
    });

    it('calculates exponential moving average for uneven intervals with normal (daily) difference', async function () {
      let t = input_t[0];
      let t_1 = input_t_1[0];
      let logReturns = input_t[2];
      let old_ema = input_t_1[2];

      let expected = bnToNumber(fixedFromFloat(-0.005393806812));
      const result = bnToNumber(
        await instance.callStatic.unevenRollingEma(old_ema, logReturns, t_1, t),
      );

      // -0.007281 * 0.1331221002 + (1 - 0.1331221002) * -0.005104 = -0.005393806812
      expect(expected / result).to.be.closeTo(1, 0.001);
    });
  });

  // Lumyo test case
  describe('#unevenRollingEmaVariance', function () {
    it('calculates exponential moving variance for uneven intervals', async function () {
      let t = 1624439705000 / 1000;
      let t_1 = 1624439400000 / 1000;
      let logReturns = 0;
      let old_ema = 0;
      let old_emvar = fixedFromFloat(0.0001732); // 1.48 / 356 / 24
      let expected = bnToNumber(fixedFromFloat(0.000173));
      const result = await instance.callStatic.unevenRollingEmaVariance(
        old_ema,
        old_emvar,
        logReturns,
        t_1,
        t,
      );
      expect(expected / bnToNumber(result[1])).to.be.closeTo(1, 0.001);
    });
  });

  describe('#N', function () {
    it('calculates CDF approximation', async function () {
      let prob = fixedFromFloat(0.8);
      let expected = bnToNumber(fixedFromFloat(0.7881146014));
      let result = bnToNumber(await instance.callStatic.N(prob));

      // 1 - 0.3989 * e^(-0.64/2) / (0.266 + 0.64 * 0.8 + 0.33 * sqrt(0.64+3))
      expect(expected / result).to.be.closeTo(1, 0.001);

      prob = fixedFromFloat(-0.8);
      expected = bnToNumber(fixedFromFloat(1 - 0.7881146014));
      result = bnToNumber(await instance.callStatic.N(prob));

      // 1 - 0.3989 * e^(-0.64/2) / (0.266 - 0.64 * 0.8 + 0.33 * sqrt(0.64+3))
      expect(expected / result).to.be.closeTo(1, 0.001);
    });
  });

  describe('#calculateCLevel', function () {
    it('calculates C coefficient level', async function () {
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const expected_c_withdrawn = bnToNumber(fixedFromFloat(2.2255409285));
      const expected_c_added = bnToNumber(fixedFromFloat(0.4493289641));
      let result = bnToNumber(
        await instance.callStatic.calculateCLevel(
          fixedFromFloat(1),
          S0,
          S1,
          fixedFromFloat(1),
        ),
      );

      expect(expected_c_withdrawn / result).to.be.closeTo(1, 0.001);

      result = bnToNumber(
        await instance.callStatic.calculateCLevel(
          fixedFromFloat(1),
          S1,
          S0,
          fixedFromFloat(1),
        ),
      );

      expect(expected_c_added / result).to.be.closeTo(1, 0.001);
    });
  });

  describe('#bsPrice', function () {
    it('calculates European CALL option price', async function () {
      const variance = fixedFromFloat(0.16);
      const price = input_t[1];
      const strike = fixedFromFloat(55284 * 0.95);
      const maturity = fixedFromFloat(28 / 365);
      const expected = bnToNumber(fixedFromFloat(4013.677084809402));
      const result = bnToNumber(
        await instance.callStatic.bsPrice(
          variance,
          strike,
          price,
          maturity,
          true,
        ),
      );

      expect(expected / result).to.be.closeTo(1, 0.001);
    });
    it('calculates European PUT option price', async function () {
      const variance = fixedFromFloat(0.16);
      const price = input_t[1];
      const strike = fixedFromFloat(55284 * 1.05);
      const maturity = fixedFromFloat(28 / 365);
      const expected = bnToNumber(fixedFromFloat(4123.964016283215));
      const result = bnToNumber(
        await instance.callStatic.bsPrice(
          variance,
          strike,
          price,
          maturity,
          false,
        ),
      );

      expect(expected / result).to.be.closeTo(1, 0.001);
    });
    it('calculates European Call option price: 2', async function () {
      const variance = fixedFromFloat(Math.pow(1.22, 2));
      const price = fixedFromFloat(2000);
      const strike = fixedFromFloat(2500);
      const maturity = fixedFromFloat(10 / 365);
      const expected = bnToNumber(fixedFromFloat(30.69));
      const result = bnToNumber(
        await instance.callStatic.bsPrice(
          variance,
          strike,
          price,
          maturity,
          true,
        ),
      );

      expect(expected / result).to.be.closeTo(1, 0.001);
    });
  });

  describe('#quotePrice', function () {
    it('calculates European CALL option price quote ', async function () {
      const variance = fixedFromFloat(0.16);
      const price = input_t[1];
      const strike = fixedFromFloat(55284 * 0.95);
      const maturity = fixedFromFloat(28 / 365);
      const cLevel = fixedFromFloat(1);
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const steepness = fixedFromFloat(1);

      const expected = bnToNumber(
        fixedFromFloat(2.2255409285 * 4013.677084809402 * 1.5319261606),
      ); // c * bsch * slippage
      const result = bnToNumber(
        (
          await instance.callStatic.quotePrice({
            emaVarianceAnnualized64x64: variance,
            strike64x64: strike,
            spot64x64: price,
            timeToMaturity64x64: maturity,
            oldCLevel64x64: cLevel,
            oldPoolState: S0,
            newPoolState: S1,
            steepness64x64: steepness,
            isCall: true,
          })
        )[0],
      );

      expect(expected / result).to.be.closeTo(1, 0.001);
    });
  });
});
