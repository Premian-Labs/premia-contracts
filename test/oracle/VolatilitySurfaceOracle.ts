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

  const coefficientsFormatted =
    '0x00004e39fe17a216e3e08d84627da56b60f41e819453f79b02b4cb97c837c2a8';
  const coefficients = [
    '10012',
    '-125022',
    '3000257',
    '3543433',
    '-1234085',
    '999912',
    '3312254',
    '-1654611',
    '6671332',
    '3654312',
  ];

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
      newCoefficients[9] = BigNumber.from(1).shl(24).toString();
      await expect(
        oracle.formatVolatilitySurfaceCoefficients(newCoefficients as any),
      ).to.be.revertedWith('Out of bounds');
    });
  });

  // Plot coefficients
  // https://storage.cloud.google.com/ivol-interpolation/ivol_surface_BTC_CALL_2021-08-21-18%3A01%3A41.html
  describe('#getAnnualizedVolatility64x64', () => {
    const callCoefficients = [
      573259, 79175, -82771, 2973, 12430, 79726, -281, -31181, -61379, 21505,
    ];
    const putCoefficients = [
      4507234, -571066, 336376, -4661, -705933, 4058762, -800272, 713995,
      -1262768, -274367,
    ];
    const baseToken = '0x0000000000000000000000000000000000000001';
    const underlyingToken = '0x0000000000000000000000000000000000000002';

    const prepareContractEnv = async () => {
      const callCoefficientsHex =
        await oracle.formatVolatilitySurfaceCoefficients(
          callCoefficients as any,
        );

      const putCoefficientsHex =
        await oracle.formatVolatilitySurfaceCoefficients(
          putCoefficients as any,
        );

      const coefficients = [
        {
          baseToken: baseToken,
          underlyingToken: underlyingToken,
          callCoefficients: callCoefficientsHex,
          putCoefficients: putCoefficientsHex,
        },
      ];

      await oracle.connect(relayer).updateVolatilitySurfaces(coefficients);
    };

    it('should correctly apply coefficients to obtain IVOL CALL surface', async () => {
      await prepareContractEnv();

      const strikeToSpotRatio = fixedFromFloat(1.3);
      const timeToMaturity = fixedFromFloat(14);
      const isCall = true;

      const result = await oracle.getAnnualizedVolatility64x64(
        baseToken,
        underlyingToken,
        strikeToSpotRatio,
        timeToMaturity,
        isCall,
      );
      const expected = bnToNumber(fixedFromFloat(0.898));

      expect(expected / bnToNumber(result)).to.be.closeTo(1, 0.001);
    });

    // https://storage.cloud.google.com/ivol-interpolation/ivol_surface_BTC_PUT_2021-08-21-18%3A01%3A41.html
    it('should correctly apply coefficients to obtain IVOL PUT surface', async () => {
      await prepareContractEnv();

      const strikeToSpotRatio = fixedFromFloat(0.2);
      const timeToMaturity = fixedFromFloat(14);
      const isCall = false;

      const result = await oracle.getAnnualizedVolatility64x64(
        baseToken,
        underlyingToken,
        strikeToSpotRatio,
        timeToMaturity,
        isCall,
      );
      const expected = bnToNumber(fixedFromFloat(2.7));

      expect(expected / bnToNumber(result)).to.be.closeTo(1, 0.001);
    });
  });
});
