import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPoolView, PoolExercise__factory } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
  TokenType,
} from '@premia/utils';

import {
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  FEE,
  formatOption,
  formatOptionToNb,
  formatUnderlying,
  getExerciseValue,
  getTokenDecimals,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolViewBehaviorArgs {
  deploy: () => Promise<IPoolView>;
  getPoolUtil: () => Promise<PoolUtil>;
}

export function describeBehaviorOfPoolView({
  deploy,
  getPoolUtil,
}: PoolViewBehaviorArgs) {
  describe('::PoolView', () => {
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let instance: IPoolView;
    let p: PoolUtil;

    before(async () => {
      [buyer, lp1, lp2] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      // TODO: don't
      p = await getPoolUtil();
    });

    describe('#getFeeReceiverAddress', () => {
      it('returns fee receiver address');
    });

    describe('#getPoolSettings', () => {
      it('returns Pool configuration values', async () => {
        const poolSettings = await instance.callStatic.getPoolSettings();

        expect(poolSettings.underlying).to.equal(p.underlying.address);
        expect(poolSettings.base).to.equal(p.base.address);
        // TODO: oracles
        // expect(poolSettings.baseOracle).to.equal(p.baseOracle.address);
        // expect(poolSettings.underlyingOracle).to.equal(p.underlyingOracle.address);
      });
    });

    describe('#getTokenIds', () => {
      it('should correctly list existing tokenIds', async () => {
        const isCallPool = true;

        const maturity = await p.getMaturity(20);
        const strike = p.getStrike(isCallPool, 2000);
        const strike64x64 = fixedFromFloat(strike);
        const amount = parseUnderlying('1');

        await p.purchaseOption(
          lp1,
          buyer,
          amount,
          maturity,
          strike64x64,
          isCallPool,
        );

        const optionId = getOptionTokenIds(maturity, strike64x64, isCallPool);

        let tokenIds = await instance.getTokenIds();
        expect(tokenIds.length).to.eq(4);
        expect(tokenIds[0]).to.eq(p.getFreeLiqTokenId(isCallPool));
        expect(tokenIds[1]).to.eq(optionId.long);
        expect(tokenIds[2]).to.eq(optionId.short);
        expect(tokenIds[3]).to.eq(p.getReservedLiqTokenId(isCallPool));

        // await setTimestamp(maturity.add(100).toNumber());
        await ethers.provider.send('evm_setNextBlockTimestamp', [
          maturity.add(100).toNumber(),
        ]);

        const tokenId = getOptionTokenIds(maturity, strike64x64, isCallPool);

        const price = isCallPool ? strike * 0.7 : strike * 1.4;
        await p.setUnderlyingPrice(
          ethers.utils.parseUnits(price.toString(), 8),
        );

        const poolExercise = PoolExercise__factory.connect(
          instance.address,
          ethers.provider,
        );

        await poolExercise
          .connect(buyer)
          .processExpired(tokenId.long, parseUnderlying('1'));

        tokenIds = await instance.getTokenIds();
        expect(tokenIds.length).to.eq(2);
        expect(tokenIds[0]).to.eq(p.getFreeLiqTokenId(isCallPool));
        expect(tokenIds[1]).to.eq(p.getReservedLiqTokenId(isCallPool));
      });
    });

    describe('#getCLevel64x64', () => {
      it('todo');
    });

    describe('#getSteepness64x64', () => {
      it('todo');
    });

    describe('#getPrice', () => {
      it('todo');
    });

    describe('#getParametersForTokenId', () => {
      it('todo');
    });

    describe('#getMinimumAmounts', () => {
      it('todo');
    });

    describe('#getCapAmounts', () => {
      it('todo');
    });

    describe('#getUserTVL', () => {
      it('todo');
    });

    describe('#getTotalTVL', () => {
      it('todo');
    });

    describe('#getPremiaMining', () => {
      it('todo');
    });

    describe('#getDivestmentTimestamps', () => {
      it('todo');
    });
  });
}
