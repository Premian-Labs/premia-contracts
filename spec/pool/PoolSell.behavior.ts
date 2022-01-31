import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool, PoolMock, PoolMock__factory } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fixedFromFloat, fixedToBn, getOptionTokenIds } from '@premia/utils';
import {
  getTokenDecimals,
  parseBase,
  parseUnderlying,
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

    describe.only('#sell', () => {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should correctly sell option back to the pool', async () => {
            await instance.connect(lp1).setBuyBackEnabled(true);

            const maturity = await p.getMaturity(10);
            const strike64x64 = fixedFromFloat(p.getStrike(isCall, 2000));

            const quote = await p.purchaseOption(
              lp1,
              buyer,
              parseUnderlying('1'),
              maturity,
              strike64x64,
              isCall,
            );

            const initialTokenAmount = isCall
              ? parseUnderlying('100')
              : parseBase('10000');

            const tokenIds = getOptionTokenIds(maturity, strike64x64, isCall);

            const buyers = await instance.getBuyers(tokenIds.short);

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
              .sell(
                maturity,
                strike64x64,
                isCall,
                parseUnderlying('1'),
                buyers.buyers,
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
            await instance.connect(lp1).setBuyBackEnabled(false);

            const maturity = await p.getMaturity(10);
            const strike64x64 = fixedFromFloat(p.getStrike(isCall, 2000));

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
                .sell(maturity, strike64x64, isCall, parseUnderlying('1'), [
                  lp1.address,
                ]),
            ).to.be.revertedWith('no sell liq');
          });
        });
      }
    });

    describe('#setBuybackEnabled', () => {
      it('should correctly enable/disable buyback', async () => {
        expect(await instance.isBuyBackEnabled(lp1.address)).to.be.false;
        await instance.connect(lp1).setBuyBackEnabled(true);
        expect(await instance.isBuyBackEnabled(lp1.address)).to.be.true;
        await instance.connect(lp1).setBuyBackEnabled(false);
        expect(await instance.isBuyBackEnabled(lp1.address)).to.be.false;
      });
    });

    describe('#getBuyers', () => {
      it('should return list of underwriters with buyback enabled', async () => {
        const maturity = await p.getMaturity(10);
        const isCall = true;
        const spotPrice = 2000;
        const strike64x64 = fixedFromFloat(p.getStrike(isCall, spotPrice));

        const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

        await poolMock.mint(lp1.address, tokenId.short, parseUnderlying('1'));
        await poolMock.mint(lp2.address, tokenId.short, parseUnderlying('2'));
        await poolMock.mint(
          thirdParty.address,
          tokenId.short,
          parseUnderlying('3'),
        );
        await poolMock.mint(buyer.address, tokenId.short, parseUnderlying('4'));
        await poolMock.mint(
          feeReceiver.address,
          tokenId.short,
          parseUnderlying('5'),
        );

        await instance.connect(lp2).setBuyBackEnabled(true);
        await instance.connect(buyer).setBuyBackEnabled(true);

        const result = await instance.getBuyers(tokenId.short);
        expect(result.buyers).to.deep.eq([lp2.address, buyer.address]);
        expect(result.amounts).to.deep.eq([
          parseUnderlying('2'),
          parseUnderlying('4'),
        ]);
      });
    });
  });
}
