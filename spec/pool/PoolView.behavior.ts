import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPoolView, PoolExercise__factory } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fixedFromFloat, getOptionTokenIds } from '@premia/utils';

import { parseBase, parseUnderlying, PoolUtil } from '../../test/pool/PoolUtil';

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

    describe('#getLiquidityQueuePosition', () => {
      it('should correctly return liquidity queue position', async () => {
        const signers = await ethers.getSigners();

        await p.depositLiquidity(signers[0], parseUnderlying('100'), true);
        await p.depositLiquidity(signers[1], parseUnderlying('50'), true);
        await p.depositLiquidity(signers[2], parseUnderlying('75'), true);
        await p.depositLiquidity(signers[3], parseUnderlying('200'), true);

        await p.depositLiquidity(signers[0], parseBase('10000'), false);
        await p.depositLiquidity(signers[1], parseBase('5000'), false);
        await p.depositLiquidity(signers[2], parseBase('7500'), false);
        await p.depositLiquidity(signers[3], parseBase('20000'), false);

        let result = await instance.getLiquidityQueuePosition(
          signers[2].address,
          true,
        );
        expect(result.liquidityBeforePosition).to.eq(parseUnderlying('150'));
        expect(result.positionSize).to.eq(parseUnderlying('75'));

        result = await instance.getLiquidityQueuePosition(
          signers[3].address,
          false,
        );
        expect(result.liquidityBeforePosition).to.eq(parseBase('22500'));
        expect(result.positionSize).to.eq(parseBase('20000'));

        result = await instance.getLiquidityQueuePosition(
          signers[0].address,
          true,
        );
        expect(result.liquidityBeforePosition).to.eq(0);
        expect(result.positionSize).to.eq(parseUnderlying('100'));

        // Not in queue
        result = await instance.getLiquidityQueuePosition(
          signers[5].address,
          true,
        );
        expect(result.liquidityBeforePosition).to.eq(parseUnderlying('425'));
        expect(result.positionSize).to.eq(0);
      });
    });
  });
}
