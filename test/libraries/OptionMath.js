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
  [1613952000000,54207.3203125],
  [1614038400000,48824.42578125],
  [1614124800000,49705.33203125],
  [1614211200000,47093.8515625],
  [1614297600000,46339.76171875],
  [1614384000000,46188.453125],
  [1614470400000,45137.76953125],
  [1614556800000,49631.2421875],
  [1614643200000,48378.98828125],
  [1614729600000,50538.2421875],
  [1614816000000,48561.16796875],
  [1614902400000,48927.3046875],
  [1614988800000,48912.3828125],
  [1615075200000,51206.69140625],
  [1615161600000,52246.5234375],
  [1615248000000,54824.1171875],
  [1615334400000,56008.55078125],
  [1615420800000,57805.12109375],
  [1615507200000,57332.08984375],
  [1615593600000,61243.0859375],
  [1615680000000,59302.31640625],
  [1615766400000,55907.19921875],
  [1615852800000,56804.90234375],
  [1615939200000,58870.89453125],
  [1616025600000,57858.921875],
  [1616112000000,58346.65234375],
  [1616198400000,58313.64453125],
  [1616284800000,57523.421875],
  [1616371200000,54529.14453125],
  [1616457600000,54738.9453125],
  [1616544000000,52774.265625],
  [1616630400000,51704.16015625],
  [1616716800000,55137.3125],
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
      const ema_t_1 = fixedFromFloat(0.1);
      const emvar_t_1 = fixedFromFloat(0.2);
      const expected = fixedFromFloat(0.1750175349);

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
    it('calculates d1 in Black-Scholes', async function f() {
      const price = input_t[1];
      const strike = fixedFromFloat(55973.51171875 * 0.9);
      const variance = fixedFromFloat(0.175);
      const maturity = fixedFromFloat(28 / 365);
      const expected = fixedFromFloat(-0.8514075553);

      // let strike price = 0.9 of stock price. then:
      // d1 = (ln(0.9) + (28/365) * 0.175 * 0.5) / sqrt(28/365 * 0.175) = -0.8514075553
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
    it('calculates CDF approximation', async function f() {
      const prob = fixedFromFloat(-0.8514075553);
      const expected = fixedFromFloat(0.8027285019);
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
    it('calculates supply-demand percentage change (signed)', async function f() {
      const S0 = fixedFromFloat(100);
      const S1 = fixedFromFloat(20);
      const expected_supply_withdrawn = fixedFromFloat(-0.8);
      const expected_supply_added = fixedFromFloat(0.8);
      //
      // expect(
      //   await instance.callStatic.Xt(
      //     S0,
      //     S0
      //   )
      // ).to.be.closeTo(
      //   0,
      //   0.0001
      // );

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
  describe('#slippageCoefficient', function () {
    it('todo');
  });

  describe('#bsPrice', function () {
    it('put / call ITM, put / call OTM, cherk `require case - Promise must be rejected`');
  });

  describe('#calculateCLevel', function () {
    it('calculates C coefficient level (also covers calcTradingDelta implicitly)');
  });
});
