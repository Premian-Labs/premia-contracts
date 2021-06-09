import { ERC20Mock, Pool } from '../../typechain';
import { parseEther } from 'ethers/lib/utils';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import {
  bnToNumber,
  fixedFromFloat,
  fixedToNumber,
  getTokenIdFor,
} from '../utils/math';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { PoolUtil, TokenType } from './PoolUtil';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

interface PoolProxyPurchaseArgs {
  pool: () => Pool;
  poolUtil: () => PoolUtil;
  owner: () => SignerWithAddress;
  buyer: () => SignerWithAddress;
  lp: () => SignerWithAddress;
  underlying: () => ERC20Mock;
  base: () => ERC20Mock;
  isCall: boolean;
  spotPrice: number;
}

export function describeBehaviorOfPoolProxyPurchase(
  args: PoolProxyPurchaseArgs,
) {
  let pool: Pool;
  let poolUtil: PoolUtil;
  let owner: SignerWithAddress;
  let buyer: SignerWithAddress;
  let lp: SignerWithAddress;
  let underlying: ERC20Mock;
  let base: ERC20Mock;
  let isCall: boolean;
  let spotPrice: number;

  beforeEach(() => {
    pool = args.pool();
    poolUtil = args.poolUtil();
    owner = args.owner();
    buyer = args.buyer();
    lp = args.lp();
    underlying = args.underlying();
    base = args.base();
    isCall = args.isCall;
    spotPrice = args.spotPrice;
  });

  const getToken = () => {
    return isCall ? underlying : base;
  };

  const getLong = () => {
    return isCall ? TokenType.LongCall : TokenType.LongPut;
  };

  const getShort = () => {
    return isCall ? TokenType.ShortCall : TokenType.ShortPut;
  };

  const getStrike = () => {
    return isCall ? spotPrice * 1.25 : spotPrice * 0.75;
  };

  const getMaxCost = () => {
    return isCall ? parseEther('0.21') : parseEther('147');
  };

  describe(args.isCall ? 'call' : 'put', () => {
    it('should revert if using a maturity less than 1 day in the future', async () => {
      await poolUtil.depositLiquidity(owner, parseEther('100'), isCall);
      const maturity = getCurrentTimestamp() + 10 * 3600;
      const strike64x64 = fixedFromFloat(1.5);

      await expect(
        pool.connect(buyer).purchase({
          maturity,
          strike64x64,
          amount: parseEther('1'),
          maxCost: parseEther('100'),
          isCall,
        }),
      ).to.be.revertedWith('Pool: maturity < 1 day');
    });

    it('should revert if using a maturity more than 28 days in the future', async () => {
      await poolUtil.depositLiquidity(owner, parseEther('100'), isCall);
      const maturity = poolUtil.getMaturity(30);
      const strike64x64 = fixedFromFloat(1.5);

      await expect(
        pool.connect(buyer).purchase({
          maturity,
          strike64x64,
          amount: parseEther('1'),
          maxCost: parseEther('100'),
          isCall,
        }),
      ).to.be.revertedWith('Pool: maturity > 28 days');
    });

    it('should revert if using a maturity not corresponding to end of UTC day', async () => {
      await poolUtil.depositLiquidity(owner, parseEther('100'), isCall);
      const maturity = poolUtil.getMaturity(10).add(3600);
      const strike64x64 = fixedFromFloat(1.5);

      await expect(
        pool.connect(buyer).purchase({
          maturity,
          strike64x64,
          amount: parseEther('1'),
          maxCost: parseEther('100'),
          isCall,
        }),
      ).to.be.revertedWith('Pool: maturity not end UTC day');
    });

    it('should revert if using a strike > 2x spot', async () => {
      await poolUtil.depositLiquidity(owner, parseEther('100'), isCall);
      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(spotPrice * 2.01);

      await expect(
        pool.connect(buyer).purchase({
          maturity,
          strike64x64,
          amount: parseEther('1'),
          maxCost: parseEther('100'),
          isCall,
        }),
      ).to.be.revertedWith('Pool: strike > 2x spot');
    });

    it('should revert if using a strike < 0.5x spot', async () => {
      await poolUtil.depositLiquidity(owner, parseEther('100'), isCall);
      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(spotPrice * 0.49);

      await expect(
        pool.connect(buyer).purchase({
          maturity,
          strike64x64,
          amount: parseEther('1'),
          maxCost: parseEther('100'),
          isCall,
        }),
      ).to.be.revertedWith('Pool: strike < 0.5x spot');
    });

    it('should revert if cost is above max cost', async () => {
      await poolUtil.depositLiquidity(owner, parseEther('100'), isCall);
      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(getStrike());

      await getToken().mint(buyer.address, parseEther('100'));
      await getToken()
        .connect(buyer)
        .approve(pool.address, ethers.constants.MaxUint256);

      await expect(
        pool.connect(buyer).purchase({
          maturity,
          strike64x64,
          amount: parseEther('1'),
          maxCost: parseEther('0.01'),
          isCall,
        }),
      ).to.be.revertedWith('Pool: excessive slippage');
    });

    it('should successfully purchase an option', async () => {
      await poolUtil.depositLiquidity(lp, parseEther('100'), isCall);

      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(getStrike());

      const purchaseAmountNb = 10;
      const purchaseAmount = parseEther(purchaseAmountNb.toString());

      const quote = await pool.quote({
        maturity,
        strike64x64,
        spot64x64: fixedFromFloat(spotPrice),
        amount: purchaseAmount,
        isCall,
      });

      console.log(fixedToNumber(quote.baseCost64x64));

      const mintAmount = parseEther('1000');
      await getToken().mint(buyer.address, mintAmount);
      await getToken()
        .connect(buyer)
        .approve(pool.address, ethers.constants.MaxUint256);

      await pool.connect(buyer).purchase({
        maturity,
        strike64x64,
        amount: purchaseAmount,
        maxCost: getMaxCost(),
        isCall,
      });

      const newBalance = await getToken().balanceOf(buyer.address);

      expect(bnToNumber(newBalance)).to.almost(
        bnToNumber(mintAmount) - fixedToNumber(quote.baseCost64x64),
      );

      const shortTokenId = getTokenIdFor({
        tokenType: getShort(),
        maturity,
        strike64x64,
      });
      const longTokenId = getTokenIdFor({
        tokenType: getLong(),
        maturity,
        strike64x64,
      });

      expect(bnToNumber(await pool.balanceOf(lp.address, 0))).to.almost(
        100 - purchaseAmountNb + fixedToNumber(quote.baseCost64x64),
      );

      expect(await pool.balanceOf(lp.address, longTokenId)).to.eq(0);
      expect(await pool.balanceOf(lp.address, shortTokenId)).to.eq(
        purchaseAmount,
      );

      expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(
        purchaseAmount,
      );
      expect(await pool.balanceOf(buyer.address, shortTokenId)).to.eq(0);
    });

    it('should successfully purchase an option from multiple LP intervals', async () => {
      const signers = await ethers.getSigners();

      let amountInPool = BigNumber.from(0);
      for (const signer of signers) {
        if (signer.address == buyer.address) continue;

        await poolUtil.depositLiquidity(signer, parseEther('1'), isCall);
        amountInPool = amountInPool.add(parseEther('1'));
      }

      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(getStrike());

      // 10 intervals used
      const purchaseAmountNb = 10;
      const purchaseAmount = parseEther(purchaseAmountNb.toString());

      const quote = await pool.quote({
        maturity,
        strike64x64,
        spot64x64: fixedFromFloat(spotPrice),
        amount: purchaseAmount,
        isCall,
      });

      await getToken().mint(buyer.address, parseEther('1000'));
      await getToken()
        .connect(buyer)
        .approve(pool.address, ethers.constants.MaxUint256);

      const shortTokenId = getTokenIdFor({
        tokenType: getShort(),
        maturity,
        strike64x64,
      });
      const longTokenId = getTokenIdFor({
        tokenType: getLong(),
        maturity,
        strike64x64,
      });

      const tx = await pool.connect(buyer).purchase({
        maturity,
        strike64x64,
        amount: purchaseAmount,
        maxCost: getMaxCost(),
        isCall,
      });

      expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(
        purchaseAmount,
      );

      let i = 0;
      for (const s of signers) {
        if (s.address === buyer.address) continue;

        let expectedAmount = 0;

        if (i < purchaseAmountNb) {
          if (i < purchaseAmountNb - 1) {
            // For all underwriter before last intervals, we add premium which is automatically reinvested
            expectedAmount =
              1 + fixedToNumber(quote.baseCost64x64) / purchaseAmountNb;
          } else {
            // For underwriter of the last interval, we subtract baseCost,
            // as previous intervals were > 1 because of reinvested premium
            expectedAmount = 1 - fixedToNumber(quote.baseCost64x64);
          }
        }

        expect(
          bnToNumber(await pool.balanceOf(s.address, shortTokenId)),
        ).to.almost(expectedAmount);

        i++;
      }

      const r = await tx.wait(1);
      console.log('GAS', r.gasUsed.toString());
    });
  });
}
