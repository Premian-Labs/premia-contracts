import { ethers } from 'hardhat';
import {
  PremiaErc20__factory,
  VePremia__factory,
  VePremiaProxy__factory,
} from '../../../typechain';
import LZ_ENDPOINTS from '../../../constants/layerzeroEndpoints.json';
import { ZERO_ADDRESS } from '../../../test/utils/constants';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let lzEndpoint: string;
  if (chainId === 4) {
    lzEndpoint = LZ_ENDPOINTS.rinkeby;
  } else if (chainId === 421611) {
    lzEndpoint = LZ_ENDPOINTS['arbitrum-rinkeby'];
  } else {
    throw new Error('ChainId not implemented');
  }

  console.log('aa');
  const premia = await new PremiaErc20__factory(deployer).deploy();

  console.log('Premia : ', premia.address);
  await premia.deployed();

  const vePremiaImpl = await new VePremia__factory(deployer).deploy(
    lzEndpoint,
    premia.address,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
  );

  console.log('vePremia impl : ', vePremiaImpl.address);
  await vePremiaImpl.deployed();

  const vePremiaProxy = await new VePremiaProxy__factory(deployer).deploy(
    vePremiaImpl.address,
  );

  console.log('vePremia : ', vePremiaProxy.address);
  await vePremiaProxy.deployed();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
