import { ERC20Mock, Pool } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish, ethers } from 'ethers';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { fixedToNumber } from '../utils/math';
import { formatUnits, parseUnits } from 'ethers/lib/utils';

export const DECIMALS_BASE = 18;
export const DECIMALS_UNDERLYING = 8;

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

export function getTokenDecimals(isCall: boolean) {
  return isCall ? DECIMALS_UNDERLYING : DECIMALS_BASE;
}

export function parseOption(amount: string, isCall: boolean) {
  if (isCall) {
    return parseUnderlying(amount);
  } else {
    return parseBase(amount);
  }
}

export function parseUnderlying(amount: string) {
  return parseUnits(
    Number(amount).toFixed(DECIMALS_UNDERLYING),
    DECIMALS_UNDERLYING,
  );
}

export function parseBase(amount: string) {
  return parseUnits(Number(amount).toFixed(DECIMALS_BASE), DECIMALS_BASE);
}

export function formatOption(amount: BigNumberish, isCall: boolean) {
  if (isCall) {
    return formatUnderlying(amount);
  } else {
    return formatBase(amount);
  }
}

export function formatUnderlying(amount: BigNumberish) {
  return formatUnits(amount, DECIMALS_UNDERLYING);
}

export function formatBase(amount: BigNumberish) {
  return formatUnits(amount, DECIMALS_BASE);
}

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
    spot64x64: BigNumber,
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

    const quote = await this.pool.quote({
      maturity,
      strike64x64,
      spot64x64,
      amount,
      isCall,
    });

    await this.pool.connect(buyer).purchase({
      maturity,
      strike64x64,
      amount,
      maxCost: ethers.constants.MaxUint256,
      isCall,
    });

    return quote;
  }

  getMaturity(days: number) {
    return BigNumber.from(
      Math.floor(getCurrentTimestamp() / ONE_DAY) * ONE_DAY + days * ONE_DAY,
    );
  }
}
