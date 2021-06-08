import { ERC20Mock, Pool } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';

interface PoolUtilArgs {
  pool: Pool;
}

export enum TokenType {
  FreeLiquidity = 0,
  LongCall = 1,
  ShortCall = 2,
}

const ONE_DAY = 3600 * 24;

export class PoolUtil {
  pool: Pool;

  constructor(props: PoolUtilArgs) {
    this.pool = props.pool;
  }

  async depositLiquidity(
    lp: SignerWithAddress,
    asset: ERC20Mock,
    amount: BigNumberish,
  ) {
    await asset.mint(lp.address, amount);
    await asset
      .connect(lp)
      .approve(this.pool.address, ethers.constants.MaxUint256);
    await this.pool.connect(lp).deposit(amount);
  }

  getMaturity(days: number) {
    return BigNumber.from(
      Math.floor(getCurrentTimestamp() / ONE_DAY) * ONE_DAY + days * ONE_DAY,
    );
  }
}
