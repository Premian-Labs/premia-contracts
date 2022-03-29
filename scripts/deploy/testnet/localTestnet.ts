import { ethers } from 'hardhat';
import { PoolUtil } from '../../../test/pool/PoolUtil';
import { createUniswap } from '../../../test/utils/uniswap';
import {
  ERC20Mock__factory,
  FeeDiscount__factory,
  PoolMock__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';

const spotPrice = 2000;

async function main() {
  const [owner, feeReceiver] = await ethers.getSigners();

  const erc20Factory = new ERC20Mock__factory(owner);

  const premia = await erc20Factory.deploy('PREMIA', 18);
  const xPremia = await erc20Factory.deploy('xPREMIA', 18);

  const feeDiscountImpl = await new FeeDiscount__factory(owner).deploy(
    xPremia.address,
  );
  const feeDiscountProxy = await new ProxyUpgradeableOwnable__factory(
    owner,
  ).deploy(feeDiscountImpl.address);

  const feeDiscount = FeeDiscount__factory.connect(
    feeDiscountProxy.address,
    owner,
  );

  const uniswap = await createUniswap(owner);

  const p = await PoolUtil.deploy(
    owner,
    premia.address,
    spotPrice,
    feeReceiver,
    feeDiscount.address,
    uniswap.factory.address,
    uniswap.weth.address,
  );

  console.log('owner: ', owner.address);
  console.log('fee receiver: ', feeReceiver.address);
  console.log('premia address: ', premia.address);
  console.log('x-premia address: ', xPremia.address);

  console.log('weth address: ', uniswap.weth.address);
  console.log('fee discount: ', feeDiscount.address);
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