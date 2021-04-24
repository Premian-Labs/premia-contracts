const { expect } = require('chai');

const fixedFromBigNumber = function (bn) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const fixedFromFloat = function (float) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(
    ethers.BigNumber.from(`${ integer }${ decimal }`)
  ).div(
    ethers.BigNumber.from(`1${ '0'.repeat(decimal.length) }`)
  );
};
/*
  Pricing feed mock:
  [unix timestamp, rounded price in USD, log returns]
*/
const raw = [
  [1616543600000,55222,  0.000001], // Tue Mar 23 2021 23:53:20 GMT+0000
  [1616803000000,55973,  0.013508], // Fri Mar 26 2021 23:56:40 GMT+0000
  [1616803200000,55688, -0.005104], // Sat Mar 27 2021 00:00:00 GMT+0000
  [1616889600000,55284, -0.007281], // Sun Mar 28 2021 00:00:00 GMT+0000
];

const input = raw.map(([x,y, log_returns]) =>
  [ethers.BigNumber.from(Math.floor(x / 1000)), fixedFromFloat(y), fixedFromFloat(log_returns)]);

let [input_t, input_t_1, input_t_2, input_t_3] = input.reverse();

describe('OptionMath', function () {
  let instance;

  before(async function () {
    const factory = await ethers.getContractFactory('OptionMathMock');
    instance = await factory.deploy();
    await instance.deployed();
  });

  describe('#decay', function () {
    it('calculates exponential decay', async function (){
      let t = input_t[0];
      let t_1 = input_t_1[0];
      let expected = fixedFromFloat(0.1331221002);

      expect(
        expected / await instance.callStatic.decay(
          t_1,
          t
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  // assuming EMA_t-1 = x_t-1
  describe('#unevenRollingEma', function () {
    it('calculates exponential moving average for uneven intervals with significant difference', async function (){
      let t = input_t_2[0];
      let t_1 = input_t_3[0];
      let p = input_t_2[1];
      let p_1 = input_t_3[1];
      let old_ema = input_t_3[2];
      let expected = fixedFromFloat(0.00470901265);

      // 0.013508 * 0.3485609425 + (1 - 0.3485609425) * 0.000001 = 0.00470901265
      expect(
        expected / await instance.callStatic.unevenRollingEma(
          old_ema,
          p_1,
          p,
          t_1,
          t
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });

    it('calculates exponential moving average for uneven intervals with small significant difference', async function (){
      let t = input_t_1[0];
      let t_1 = input_t_2[0];
      let p = input_t_1[1];
      let p_1 = input_t_2[1];
      let old_ema = input_t_2[2];
      let expected = fixedFromFloat(0.01350209255);

      // -0.005104 * 0.0003174 + (1 - 0.0003174) * 0.013508 = 0.01350209255
      expect(
        expected / await instance.callStatic.unevenRollingEma(
          old_ema,
          p_1,
          p,
          t_1,
          t
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });

    it('calculates exponential moving average for uneven intervals with normal (daily) significant difference', async function (){
      let t = input_t[0];
      let t_1 = input_t_1[0];
      let p = input_t[1];
      let p_1 = input_t_1[1];
      let old_ema = input_t_1[2];
      let expected = fixedFromFloat(-0.005393806812);

      // -0.007281 * 0.1331221002 + (1 - 0.1331221002) * -0.005104 = -0.005393806812
      expect(
        expected / await instance.callStatic.unevenRollingEma(
          old_ema,
          p_1,
          p,
          t_1,
          t
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#unevenRollingEmaVariance', function () {
    it('calculates exponential moving variance for uneven intervals', async function (){
      let t = input_t_2[0];
      let t_1 = input_t_3[0];
      let p = input_t_2[1];
      let p_1 = input_t_3[1];
      let old_ema = input_t_3[2];
      let old_emvar = fixedFromFloat(0.000001); // ~ 0
      let expected = fixedFromFloat(0.00004207718281);

      // (1 - 0.3485609425) * (0.000001 + 0.3485609425 * (0.013508-0.000001)^2) = 0.00004207718281
      expect(
        expected / await instance.callStatic.unevenRollingEmaVariance(
          old_ema,
          old_emvar,
          p_1,
          p,
          t_1,
          t
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#N', function () {
    it('calculates CDF approximation', async function () {
      let prob = fixedFromFloat(0.8);
      let expected = fixedFromFloat(0.7881146014);

      // 1 - 0.3989 * e^(-0.64/2) / (0.266 + 0.64 * 0.8 + 0.33 * sqrt(0.64+3))
      expect(
        expected / await instance.callStatic.N(
          prob
        )
      ).to.be.closeTo(
        1,
        0.001
      );

      prob = fixedFromFloat(-0.8);
      expected = fixedFromFloat(1 - 0.7881146014);

      // 1 - 0.3989 * e^(-0.64/2) / (0.266 - 0.64 * 0.8 + 0.33 * sqrt(0.64+3))
      expect(
        expected / await instance.callStatic.N(
          prob
        )
      ).to.be.closeTo(
        1,
        0.001
      );

    });
  });

  describe('#calculateCLevel', function () {
    it('calculates C coefficient level', async function (){
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const expected_c_withdrawn = fixedFromFloat(2.2255409285);
      const expected_c_added = fixedFromFloat(0.4493289641);

      expect(
        expected_c_withdrawn / await instance.callStatic.calculateCLevel(
          fixedFromFloat(1),
          S0,
          S1,
          fixedFromFloat(1)
        )
      ).to.be.closeTo(
        1,
        0.001
      );

      expect(
        expected_c_added / await instance.callStatic.calculateCLevel(
          fixedFromFloat(1),
          S1,
          S0,
          fixedFromFloat(1)
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#bsPrice', function () {
    it('calculates European CALL option price', async function (){
      const variance = fixedFromFloat(0.16);
      const price =  input_t[1];
      const strike = fixedFromFloat(55284 * 0.95);
      const maturity = fixedFromFloat(28 / 365);
      const expected = fixedFromFloat(4013.677084809402);

      expect(
        expected / await instance.callStatic.bsPrice(
          variance,
          strike,
          price,
          maturity,
          true
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
    it('calculates European PUT option price', async function (){
      const variance = fixedFromFloat(0.16);
      const price =  input_t[1];
      const strike = fixedFromFloat(55284 * 1.05);
      const maturity = fixedFromFloat(28 / 365);
      const expected = fixedFromFloat(4123.964016283215);

      expect(
        expected / await instance.callStatic.bsPrice(
          variance,
          strike,
          price,
          maturity,
          false
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#quotePrice', function () {
    it('calculates European CALL option price quote ', async function (){
      const variance = fixedFromFloat(0.16);
      const price =  input_t[1];
      const strike = fixedFromFloat(55284 * 0.95);
      const maturity = fixedFromFloat(28 / 365);
      const cLevel = fixedFromFloat(1);
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const steepness = fixedFromFloat(1);

      const expected = fixedFromFloat(2.2255409285 * 4013.677084809402 * 1.5319261606); // c * bsch * slippage

      expect(
        expected / (await instance.callStatic.quotePrice(
          variance,
          strike,
          price,
          maturity,
          cLevel,
          S0,
          S1,
          steepness,
          true
        ))[0]
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });
});
