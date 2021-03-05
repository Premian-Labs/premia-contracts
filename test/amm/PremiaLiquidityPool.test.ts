import { expect } from 'chai';
import {
  PremiaLiquidityPool, PremiaLiquidityPool__factory,
} from '../../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat, setTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let liqPool: PremiaLiquidityPool;

describe('PremiaLiquidityPool', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1] = await ethers.getSigners();
    liqPool = await new PremiaLiquidityPool__factory(admin).deploy();
  });
});
