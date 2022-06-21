import { ethers } from 'hardhat';
import { PoolUtil } from '../../../test/pool/PoolUtil';
import { createUniswap } from '../../../test/utils/uniswap';
import {
  ERC20Mock__factory,
  ExchangeHelper__factory,
  PoolMock__factory,
  VePremia__factory,
  VePremiaProxy__factory,
} from '../../../typechain';

const spotPrice = 2000;

async function main() {
  const [owner, feeReceiver] = await ethers.getSigners();

  const erc20Factory = new ERC20Mock__factory(owner);

  const premia = await erc20Factory.deploy('PREMIA', 18);

  const vePremiaImpl = await new VePremia__factory(owner).deploy(
    ethers.constants.AddressZero,
    premia.address,
  );

  const vePremiaProxy = await new VePremiaProxy__factory(owner).deploy(
    vePremiaImpl.address,
  );

  const vePremia = VePremia__factory.connect(vePremiaProxy.address, owner);

  const exchangeHelper = await new ExchangeHelper__factory(owner).deploy();

  const uniswap = await createUniswap(owner);

  const p = await PoolUtil.deploy(
    owner,
    premia.address,
    spotPrice,
    feeReceiver,
    vePremia.address,
    exchangeHelper.address,
    uniswap.weth.address,
  );

  console.log('owner: ', owner.address);
  console.log('fee receiver: ', feeReceiver.address);
  console.log('premia address: ', premia.address);
  console.log('vePremia address: ', vePremia.address);

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
