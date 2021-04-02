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

const raw = [
  [1616803200000,55973.51171875],
  [1616889600000,55284.28125],
];

const input = raw.map(([x,y]) => [new Date(x), fixedFromFloat(y)]);

let [input_t, input_t_1] = input.reverse();

describe('OptionMath', function () {
  let instance;

  before(async function () {
    const factory = await ethers.getContractFactory('OptionMathMock');
    instance = await factory.deploy();
    await instance.deployed();
  });

  describe('#logreturns', function () {
    it('returns the natural log returns for a given day', async function () {
      let expected = fixedFromFloat(-0.012389950714774214);
      expect(
        expected / await instance.callStatic.logreturns(
          input_t[1],
          input_t_1[1]
        )
      ).to.be.closeTo(
        1,
        0.001
      );

      expected = fixedFromFloat(0.012389950714774214);
      expect(
        expected / await instance.callStatic.logreturns(
          input_t_1[1],
          input_t[1]
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#rollingEma', function () {
    it('return the rolling ema value', async function () {
      const ema_t_1 = fixedFromFloat(0.1);

      expect(
        await instance.callStatic.rollingEma(
          ema_t_1,
          ema_t_1,
          ethers.BigNumber.from(14)
        )
      ).to.be.closeTo(
        ema_t_1,
        1
      );

      const logReturn_t = fixedFromFloat(-0.01239);
      const expected = fixedFromFloat(0.08501466667);

      expect(
        expected / await instance.callStatic.rollingEma(
          logReturn_t,
          ema_t_1,
          ethers.BigNumber.from(14)
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#rollingEmaVariance', function () {
    it('return the rolling variance value', async function () {
      const logReturn_t = fixedFromFloat(-0.01239);
      const ema_t_1 = fixedFromFloat(0.3);
      const emvar_t_1 = fixedFromFloat(0.1);
      const expected = fixedFromFloat(0.09967833495);

      // (1 - 2/15) * 0.1 + 2/15 * (-0.01239 - 0.3)^2
      expect(
        expected / await instance.callStatic.rollingEmaVariance(
          logReturn_t,
          ema_t_1,
          emvar_t_1,
          ethers.BigNumber.from(14)
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

  describe('#d1', function () {
    it('calculates d1 in Black-Scholes', async function () {
      const price =  input_t[1];
      const strike = fixedFromFloat(55284.28125 * 0.95); // input_t * 0.9
      const variance = fixedFromFloat(0.16);
      const maturity = fixedFromFloat(28 / 365);
      const expected = fixedFromFloat(0.5183801513);

      // let strike price = 0.9 of stock price. then:
      // d1 = (ln(1/0.95) + (28/365) * 0.16 * 0.5) / sqrt(28/365 * 0.16) = 0.5183801513

      expect(
        expected / await instance.callStatic.d1(
          variance,
          strike,
          price,
          maturity
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

  describe('#Xt', function () {
    it('calculates supply-demand percentage change (signed)', async function () {
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const expected_supply_withdrawn = fixedFromFloat(-0.8);
      const expected_supply_added = fixedFromFloat(0.8);

      expect(
        expected_supply_withdrawn / await instance.callStatic.Xt(
          S0,
          S1
        )
      ).to.be.closeTo(
        1,
        0.001
      );

      expect(
        expected_supply_added / await instance.callStatic.Xt(
          S1,
          S0
        )
      ).to.be.closeTo(
        1,
        0.001
      );

    });
  });

  describe('#calculateCLevel', function () {
    it('calculates C coefficient level (also covers calcTradingDelta implicitly)', async function (){
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

  describe('#slippageCoefficient', function () {
    it('calculates slippage correction coefficient level', async function (){
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const expected = fixedFromFloat(1.5319261606);

      // (1 - e^(-(20-100)/100))/((20-100)/100) = 1.5319261606
      expect(
        expected / await instance.callStatic.slippageCoefficient(
          S0,
          S1,
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
      const strike = fixedFromFloat(55284.28125 * 0.95);
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
      const strike = fixedFromFloat(55284.28125 * 1.05);
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
      const strike = fixedFromFloat(55284.28125 * 0.95);
      const maturity = fixedFromFloat(28 / 365);
      const cLevel = fixedFromFloat(1);
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const steepness = fixedFromFloat(1);

      const expected = fixedFromFloat(2.2255409285 * 4013.677084809402 * 1.5319261606); // c * bsch * slippage

      expect(
        expected / await instance.callStatic.quotePrice(
          variance,
          strike,
          price,
          maturity,
          cLevel,
          S0,
          S1,
          steepness,
          true
        )
      ).to.be.closeTo(
        1,
        0.001
      );
    });
  });

});
