import chai, { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  VolatilitySurfaceOracle,
  VolatilitySurfaceOracle__factory,
} from '../../typechain';
import chaiAlmost from 'chai-almost';
import { BigNumber } from 'ethers';
import { fixedFromFloat } from '@premia/utils';
import { bnToNumber } from '../utils/math';

chai.use(chaiAlmost(0.01));

describe('VolatilitySurfaceOracle', () => {
  let owner: SignerWithAddress;
  let relayer: SignerWithAddress;
  let user: SignerWithAddress;
  let oracle: VolatilitySurfaceOracle;
  let proxy: ProxyUpgradeableOwnable;

  const paramsFormatted =
    '0x00004e39fe17a216e3e08d84627da56b60f41e819453f79b02b4cb97c837c2a8';
  const params = [
    0.839159148341129, -0.05957422656606383, 0.02004706385514592,
    0.14895038484273854, 0.034026549310791646,
  ].map((el) => Math.floor(el * 10 ** 12).toString());

  beforeEach(async () => {
    [owner, relayer, user] = await ethers.getSigners();

    const impl = await new VolatilitySurfaceOracle__factory(owner).deploy();
    proxy = await new ProxyUpgradeableOwnable__factory(owner).deploy(
      impl.address,
    );
    oracle = VolatilitySurfaceOracle__factory.connect(proxy.address, owner);

    await oracle.connect(owner).addWhitelistedRelayer([relayer.address]);
  });

  describe('#parseParams', () => {
    it('should correctly parse parameters', async () => {
      const result = await oracle.formatParams(params as any);
      expect(
        (await oracle.parseParams(result)).map((el) => el.toString()),
      ).to.have.same.members(params);
    });
  });

  describe('#formatParams', () => {
    it('should correctly format parameters', async () => {
      const params = await oracle.parseParams(paramsFormatted);
      expect(await oracle.formatParams(params as any)).to.eq(paramsFormatted);
    });

    it('should fail if a variable is out of bounds', async () => {
      const newParams = [...params];
      newParams[4] = BigNumber.from(1).shl(51).toString();
      await expect(oracle.formatParams(newParams as any)).to.be.revertedWith(
        'Out of bounds',
      );
    });
  });

  describe('#getAnnualizedVolatility64x64', () => {
    // ETH surface regression primer
    const params = [
      0.9342809639050504, // intercept
      -0.13731127641216775, // M
      -0.00027206354505048273, // M^2
      0.8094657778778461, // tau
      0.06639676877520312, // M*tau
    ].map((el) => Math.floor(el * 10 ** 12));

    const base = '0x0000000000000000000000000000000000000001';
    const underlying = '0x0000000000000000000000000000000000000002';

    const prepareContractEnv = async () => {
      const paramsHex = await oracle.formatParams(params as any);

      await oracle.connect(relayer).updateParams(base, underlying, paramsHex);
    };

    it('should correctly apply coefficients to obtain IVOL surface', async () => {
      await prepareContractEnv();

      const spot = fixedFromFloat(48000);
      const strike = fixedFromFloat(60000);
      const timeToMaturity = fixedFromFloat(30 / 365);

      // 0.9342809639050504 -
      // 0.13731127641216775 * ln(48000 / 60000) / (30/365)^0.5 -
      // 0.00027206354505048273 * (ln(48000 / 60000) / (30/365)^0.5) ^ 2 +
      // 0.8094657778778461 * (30/365) +
      // 0.06639676877520312 * ln(48000 / 60000) / (30/365)^0.5 * (30/365) =
      // 1.1032750138

      const result = await oracle.getAnnualizedVolatility64x64(
        base,
        underlying,
        spot,
        strike,
        timeToMaturity,
      );
      const expected = bnToNumber(fixedFromFloat(1.1032750138));

      expect(expected / bnToNumber(result)).to.be.closeTo(1, 0.001);
    });
  });
});
