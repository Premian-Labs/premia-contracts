import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool, PoolMock, PoolMock__factory } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fixedFromFloat, fixedToBn, getOptionTokenIds } from '@premia/utils';
import {
  getTokenDecimals,
  parseBase,
  parseUnderlying,
  getStrike,
  getMaturity,
  PoolUtil,
} from '../../test/pool/PoolUtil';
import { bnToNumber } from '../../test/utils/math';

interface PoolSellBehaviorArgs {
  deploy: () => Promise<IPool>;
  getPoolUtil: () => Promise<PoolUtil>;
}

export function describeBehaviorOfPoolSell({
  deploy,
  getPoolUtil,
}: PoolSellBehaviorArgs) {
  describe('::PoolSell', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let thirdParty: SignerWithAddress;
    let feeReceiver: SignerWithAddress;
    let p: PoolUtil;

    let instance: IPool;
    let poolMock: PoolMock;

    before(async () => {
      [owner, buyer, lp1, lp2, thirdParty] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      p = await getPoolUtil();
      feeReceiver = p.feeReceiver;
      poolMock = PoolMock__factory.connect(p.pool.address, owner);
    });

    describe('#sell', () => {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should correctly sell option back to the pool', async () => {
            const initialTokenAmount = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

            await instance.connect(lp1).setBuybackEnabled(true, isCall);

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            const quote = await p.purchaseOption(
              lp1,
              buyer,
              parseUnderlying('1'),
              maturity,
              strike64x64,
              isCall,
            );

            expect(
              bnToNumber(
                await p.getToken(isCall).balanceOf(buyer.address),
                getTokenDecimals(isCall),
              ),
            ).to.almost(
              bnToNumber(
                initialTokenAmount
                  .sub(fixedToBn(quote.baseCost64x64, getTokenDecimals(isCall)))
                  .sub(fixedToBn(quote.feeCost64x64, getTokenDecimals(isCall))),
                getTokenDecimals(isCall),
              ),
            );

            const sellQuote = await instance
              .connect(buyer)
              .sellQuote(
                buyer.address,
                maturity,
                strike64x64,
                fixedFromFloat(2000),
                parseUnderlying('1'),
                isCall,
              );

            await instance
              .connect(buyer)
              .sell(maturity, strike64x64, isCall, parseUnderlying('1'));

            expect(
              bnToNumber(
                await p.getToken(isCall).balanceOf(buyer.address),
                getTokenDecimals(isCall),
              ),
            ).to.almost(
              bnToNumber(
                initialTokenAmount
                  .sub(fixedToBn(quote.baseCost64x64, getTokenDecimals(isCall)))
                  .sub(fixedToBn(quote.feeCost64x64, getTokenDecimals(isCall)))
                  .add(
                    fixedToBn(
                      sellQuote.baseCost64x64,
                      getTokenDecimals(isCall),
                    ).sub(
                      fixedToBn(
                        sellQuote.feeCost64x64,
                        getTokenDecimals(isCall),
                      ),
                    ),
                  ),
                getTokenDecimals(isCall),
              ),
            );
          });

          it('should fail selling back to the pool if no buyer available', async () => {
            await instance.connect(lp1).setBuybackEnabled(false, isCall);

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            await p.purchaseOption(
              lp1,
              buyer,
              parseUnderlying('1'),
              maturity,
              strike64x64,
              isCall,
            );

            await expect(
              instance
                .connect(buyer)
                .sell(maturity, strike64x64, isCall, parseUnderlying('1')),
            ).to.be.revertedWith('0x11');
          });
        });
      }
    });

    describe('#setBuybackEnabled', () => {
      it('should correctly enable/disable buyback', async () => {
        expect(await instance.isBuybackEnabled(lp1.address, true)).to.be.false;
        await instance.connect(lp1).setBuybackEnabled(true, true);
        expect(await instance.isBuybackEnabled(lp1.address, true)).to.be.true;
        await instance.connect(lp1).setBuybackEnabled(false, true);
        expect(await instance.isBuybackEnabled(lp1.address, true)).to.be.false;
      });
    });
  });
}
