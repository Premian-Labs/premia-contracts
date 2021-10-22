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

chai.use(chaiAlmost(0.01));

describe('VolatilitySurfaceOracle', () => {
  let owner: SignerWithAddress;
  let relayer: SignerWithAddress;
  let user: SignerWithAddress;
  let oracle: VolatilitySurfaceOracle;
  let proxy: ProxyUpgradeableOwnable;

  const coefficientsFormatted =
    '0x00004e39fe17a216e3e08d84627da56b60f41e819453f79b02b4cb97c837c2a8';
  const coefficients = [
    0.839159148341129, -0.05957422656606383, 0.02004706385514592,
    0.14895038484273854, 0.034026549310791646,
  ].map((el) => Math.floor(el * 10 ** 10).toString());

  console.log(coefficients);

  beforeEach(async () => {
    [owner, relayer, user] = await ethers.getSigners();

    const impl = await new VolatilitySurfaceOracle__factory(owner).deploy();
    proxy = await new ProxyUpgradeableOwnable__factory(owner).deploy(
      impl.address,
    );
    oracle = VolatilitySurfaceOracle__factory.connect(proxy.address, owner);

    await oracle.connect(owner).addWhitelistedRelayer([relayer.address]);
  });

  describe('#parseVolatilitySurfaceCoefficients', () => {
    it('should correctly parse coefficients', async () => {
      const result = await oracle.formatVolatilitySurfaceCoefficients(
        coefficients as any,
      );
      expect(
        (await oracle.parseVolatilitySurfaceCoefficients(result)).map((el) =>
          el.toString(),
        ),
      ).to.have.same.members(coefficients);
    });
  });

  describe('#formatVolatilitySurfaceCoefficients', () => {
    it('should correctly format coefficients', async () => {
      const coefficients = await oracle.parseVolatilitySurfaceCoefficients(
        coefficientsFormatted,
      );
      expect(
        await oracle.formatVolatilitySurfaceCoefficients(coefficients as any),
      ).to.eq(coefficientsFormatted);
    });

    it('should fail if a variable is out of bounds', async () => {
      const newCoefficients = [...coefficients];
      newCoefficients[4] = BigNumber.from(1).shl(51).toString();
      await expect(
        oracle.formatVolatilitySurfaceCoefficients(newCoefficients as any),
      ).to.be.revertedWith('Out of bounds');
    });
  });

  // Plot coefficients
  // https://storage.cloud.google.com/ivol-interpolation/ivol_surface_BTC_call_2021-09-04-19%3A03%3A27.html
  describe('#getAnnualizedVolatility64x64', () => {
    const coefficients = [
      0.839159148341129, -0.05957422656606383, 0.02004706385514592,
      0.14895038484273854, 0.034026549310791646,
    ].map((el) => Math.floor(el * 10 ** 10));
    const baseToken = '0x0000000000000000000000000000000000000001';
    const underlyingToken = '0x0000000000000000000000000000000000000002';

    const prepareContractEnv = async () => {
      const coefficientsHex = await oracle.formatVolatilitySurfaceCoefficients(
        coefficients as any,
      );

      await oracle
        .connect(relayer)
        .updateVolatilitySurfaces(
          [baseToken],
          [underlyingToken],
          [coefficientsHex],
        );
    };

    // it('should correctly apply coefficients to obtain IVOL CALL surface', async () => {
    //   await prepareContractEnv();
    //
    //   const moneyness = fixedFromFloat(1.1);
    //   const timeToMaturity = fixedFromFloat(14);
    //   const isCall = true;
    //
    //   const result = await oracle.getAnnualizedVolatility64x64(
    //     baseToken,
    //     underlyingToken,
    //     moneyness,
    //     timeToMaturity,
    //     isCall,
    //   );
    //   const expected = bnToNumber(fixedFromFloat(0.7784));
    //
    //   expect(expected / bnToNumber(result)).to.be.closeTo(1, 0.001);
    // });
    //
    // // https://storage.cloud.google.com/ivol-interpolation/ivol_surface_BTC_put_2021-09-04-19%3A06%3A20.html
    // it('should correctly apply coefficients to obtain IVOL PUT surface', async () => {
    //   await prepareContractEnv();
    //
    //   const moneyness = fixedFromFloat(0.8);
    //   const timeToMaturity = fixedFromFloat(60);
    //   const isCall = false;
    //
    //   const result = await oracle.getAnnualizedVolatility64x64(
    //     baseToken,
    //     underlyingToken,
    //     moneyness,
    //     timeToMaturity,
    //     isCall,
    //   );
    //   const expected = bnToNumber(fixedFromFloat(0.8691));
    //
    //   expect(expected / bnToNumber(result)).to.be.closeTo(1, 0.001);
    // });
  });
});
