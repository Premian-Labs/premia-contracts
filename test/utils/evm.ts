import { ethers } from 'hardhat';
import { ONE_WEEK } from './constants';

export async function setTimestamp(timestamp: number) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [timestamp]);
  await ethers.provider.send('evm_mine', []);
}

export async function setTimestampPostExpiration() {
  await setTimestamp(new Date().getTime() / 1000 + ONE_WEEK);
}
