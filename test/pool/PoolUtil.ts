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
  FreeLiquidity = 0,
  LongCall = 1,
  ShortCall = 2,
}

const ONE_DAY = 3600 * 24;

export class PoolUtil {
  pool: Pool;
  underlying: ERC20Mock;

  constructor(props: PoolUtilArgs) {
    this.pool = props.pool;
    this.underlying = props.underlying;
  }

  async depositLiquidity(lp: SignerWithAddress, amount: BigNumberish) {
    await this.underlying.mint(lp.address, amount);
    await this.underlying
      .connect(lp)
      .approve(this.pool.address, ethers.constants.MaxUint256);
    await this.pool.connect(lp).deposit(amount);
  }

  async purchaseOption(
    lp: SignerWithAddress,
    buyer: SignerWithAddress,
    amount: BigNumber,
    maturity: BigNumber,
    strikePrice: BigNumber,
  ) {
    await this.depositLiquidity(lp, amount);

    await this.underlying.mint(buyer.address, parseEther('100'));
    await this.underlying
      .connect(buyer)
      .approve(this.pool.address, ethers.constants.MaxUint256);

    await this.pool
      .connect(buyer)
      .purchase(maturity, strikePrice, amount, ethers.constants.MaxUint256);
  }

  getMaturity(days: number) {
    return BigNumber.from(
      Math.floor(getCurrentTimestamp() / ONE_DAY) * ONE_DAY + days * ONE_DAY,
    );
  }
}
