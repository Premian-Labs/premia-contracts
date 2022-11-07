import { ethers } from 'hardhat';
import { deployVxPremiaMocked, PoolUtil } from '../../../test/pool/PoolUtil';
import { createUniswap } from '../../../test/utils/uniswap';
import { ExchangeHelper__factory, PoolMock__factory } from '../../../typechain';

const spotPrice = 2000;

async function main() {
  const [owner, feeReceiver] = await ethers.getSigners();

  const { vxPremia, premia } = await deployVxPremiaMocked(owner);

  const exchangeHelper = await new ExchangeHelper__factory(owner).deploy();

  const uniswap = await createUniswap(owner);

  const p = await PoolUtil.deploy(
    owner,
    premia.address,
    spotPrice,
    feeReceiver.address,
    vxPremia.address,
    exchangeHelper.address,
    uniswap.weth.address,
  );

  console.log('owner: ', owner.address);
  console.log('fee receiver: ', feeReceiver.address);
  console.log('premia address: ', premia.address);
  console.log('vxPremia address: ', vxPremia.address);

  console.log('weth address: ', uniswap.weth.address);
  console.log('premia diamond: ', p.premiaDiamond.address);
  console.log('premia mining: ', p.premiaMining.address);
  console.log('ivol oracle: ', p.ivolOracle.address);

  PoolMock__factory.connect(p.pool.address, owner);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
