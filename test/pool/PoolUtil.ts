import { ERC20Mock, Pool } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { parseEther } from 'ethers/lib/utils';

interface PoolUtilArgs {
  pool: Pool;
  underlying: ERC20Mock;
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

  constructor(props: PoolUtilArgs) {
    this.pool = props.pool;
    this.underlying = props.underlying;
  }

  async depositLiquidity(
    lp: SignerWithAddress,
    amount: BigNumberish,
    isCall: boolean,
  ) {
    await this.underlying.mint(lp.address, amount);
    await this.underlying
      .connect(lp)
      .approve(this.pool.address, ethers.constants.MaxUint256);
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
    await this.depositLiquidity(lp, amount, isCall);

    await this.underlying.mint(buyer.address, parseEther('100'));
    await this.underlying
      .connect(buyer)
      .approve(this.pool.address, ethers.constants.MaxUint256);

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
