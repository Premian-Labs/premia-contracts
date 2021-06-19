import { ERC20Mock, Pool } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { fixedToNumber } from '../utils/math';
import {
  formatBase,
  formatUnderlying,
  parseBase,
  parseUnderlying,
} from './PoolProxy';

interface PoolUtilArgs {
  pool: Pool;
  underlying: ERC20Mock;
  base: ERC20Mock;
}

export enum TokenType {
  UnderlyingFreeLiq = 0,
  BaseFreeLiq = 1,
  LongCall = 2,
  ShortCall = 3,
  LongPut = 4,
  ShortPut = 5,
}

const ONE_DAY = 3600 * 24;

export class PoolUtil {
  pool: Pool;
  underlying: ERC20Mock;
  base: ERC20Mock;

  constructor(props: PoolUtilArgs) {
    this.pool = props.pool;
    this.underlying = props.underlying;
    this.base = props.base;
  }

  async depositLiquidity(
    lp: SignerWithAddress,
    amount: BigNumberish,
    isCall: boolean,
  ) {
    if (isCall) {
      await this.underlying.mint(lp.address, amount);
      await this.underlying
        .connect(lp)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    } else {
      await this.base.mint(lp.address, amount);
      await this.base
        .connect(lp)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    }

    await this.pool.connect(lp).deposit(amount, isCall);
  }

  async purchaseOption(
    lp: SignerWithAddress,
    buyer: SignerWithAddress,
    amount: BigNumber,
    maturity: BigNumber,
    strike64x64: BigNumber,
    isCall: boolean,
  ) {
    await this.depositLiquidity(
      lp,
      isCall
        ? amount
        : parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
      isCall,
    );

    if (isCall) {
      await this.underlying.mint(buyer.address, parseUnderlying('100'));
      await this.underlying
        .connect(buyer)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    } else {
      await this.base.mint(buyer.address, parseBase('10000'));
      await this.base
        .connect(buyer)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    }

    await this.pool.connect(buyer).purchase({
      maturity,
      strike64x64,
      amount,
      maxCost: ethers.constants.MaxUint256,
      isCall,
    });
  }

  getMaturity(days: number) {
    return BigNumber.from(
      Math.floor(getCurrentTimestamp() / ONE_DAY) * ONE_DAY + days * ONE_DAY,
    );
  }
}
