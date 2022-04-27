import { ethers } from 'hardhat';
import { fixedFromFloat } from '@premia/utils';

import { ProxyManager__factory } from '../../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const tokens = {
    USDC: '0x95d67733109083e20d2A5fE7C4f4f112E83e44DB',
    USDT: '0x0602f860CEC555CAaFF2B43Ac66A6a20eAcA2e0A',
  };

  const oracles = {
    USDC: '0xa24de01df22b63d23Ebc1882a5E3d4ec0d907bFB',
    USDT: '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF',
  };

  const minimums = {
    USDC: fixedFromFloat('100'),
    USDT: fixedFromFloat('100'),
  };

  const premiaDiamondAddress = '0x32B3ccde9e8E8A235837F726C1F06B2B579c864B';

  const proxyManager = await ProxyManager__factory.connect(
    premiaDiamondAddress,
    deployer,
  );

  const poolAddress = await proxyManager.callStatic.deployPool(
    tokens.USDC,
    tokens.USDT,
    oracles.USDC,
    oracles.USDT,
    // minimum amounts
    minimums.USDC,
    minimums.USDT,
    50,
  );

  let poolTx = await proxyManager.deployPool(
    tokens.USDC,
    tokens.USDT,
    oracles.USDC,
    oracles.USDT,
    // minimum amounts
    minimums.USDC,
    minimums.USDT,
    50,
  );

  console.log(
    `USDT/USDC pool : ${poolAddress} (${tokens.USDC}, ${tokens.USDT}, ${
      oracles.USDC
    }, ${oracles.USDT}, ${minimums.USDC}, ${minimums.USDT}, ${50})`,
  );

  await poolTx.wait(1);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
