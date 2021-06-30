import { ethers } from 'hardhat';
import { Pool__factory } from '../../typechain';
import { parseTokenId } from '../../test/utils/math';
import { BigNumber } from 'ethers';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';

const WETH_POOL = '0xECcd128D7E1941aE26F6E5787B55Ac4Bf726E3bE';
const WBTC_POOL = '0x079F7D948cBe81dCec78E32D5Dc6b89345116669';
const LINK_POOL = '0x15a13893ae5eF2189347C7912d49D0FBb3CB4f76';

async function main() {
  const [deployer] = await ethers.getSigners();

  const now = getCurrentTimestamp();
  console.log(now);

  for (const poolAddress of [WETH_POOL, WBTC_POOL, LINK_POOL]) {
    const pool = Pool__factory.connect(poolAddress, deployer);

    const filter = pool.filters.Purchase();
    const data = await pool.queryFilter(filter);

    const toProcess: { [tokenId: string]: BigNumber } = {};

    for (const el of data) {
      const tokenId = el.args.longTokenId.toHexString();
      const { maturity } = parseTokenId(tokenId);

      if (!toProcess[tokenId] && now > maturity.toNumber()) {
        const amount = await pool.totalSupply(tokenId);
        if (amount.gt(0)) {
          toProcess[tokenId] = amount;
        }
      }
    }

    console.log(toProcess);

    for (const tokenId of Object.keys(toProcess)) {
      await pool.processExpired(tokenId, toProcess[tokenId]);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
