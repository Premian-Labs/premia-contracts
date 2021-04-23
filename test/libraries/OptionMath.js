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

// [timestamp, rounded price USD]
const raw = [
  [1616603200000,55300], // Wed Mar 24 2021 16:26:40 GMT+0000
  [1616623200000,55222], // Wed Mar 24 2021 22:00:00 GMT+0000
  [1616803200000,55973], // Sat Mar 27 2021 00:00:00 GMT+0000
  [1616803300000,55688], // Sat Mar 27 2021 00:01:40 GMT+0000
  [1616889600000,55284], // Sun Mar 28 2021 00:00:00 GMT+0000
];

const input = raw.map(([x,y]) => [new Date(x), fixedFromFloat(y)]);

let [input_t, input_t_1, input_t_2, input_t_3, input_t_4] = input.reverse();

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
      let expected = fixedFromFloat(1.0);

      // 1 - 0.3989 * e^(-0.64/2) / (0.266 + 0.64 * 0.8 + 0.33 * sqrt(0.64+3))
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

  describe('#unevenRollingEma', function () {
    it('calculates exponential moving average for uneven intervals with significant difference', async function (){
      let t = input_t_2[0];
      let t_1 = input_t_3[0];
      let p = input_t_2[1];
      let p_1 = input_t_3[1];
      let old_ema = input_t_4[1];
      let expected = fixedFromFloat(1.0);

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
      let old_ema = input_t_3[1];
      let expected = fixedFromFloat(1.0);

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
      let old_ema = input_t_2[1];
      let expected = fixedFromFloat(1.0);

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
    it('calculates CDF approximation', async function () {
      void 0;
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
