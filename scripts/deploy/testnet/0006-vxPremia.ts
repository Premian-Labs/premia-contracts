import { ethers } from 'hardhat';
import {
  ERC20Mock__factory,
  ExchangeHelper__factory,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../../typechain';
import LZ_ENDPOINTS from '../../../constants/layerzeroEndpoints.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let lzEndpoint: string;
  if (chainId === 4) {
    lzEndpoint = LZ_ENDPOINTS.rinkeby;
  } else if (chainId === 5) {
    lzEndpoint = LZ_ENDPOINTS.goerli;
  } else if (chainId === 421611) {
    lzEndpoint = LZ_ENDPOINTS['arbitrum-rinkeby'];
  } else if (chainId === 421613) {
    lzEndpoint = LZ_ENDPOINTS['arbitrum-goerli'];
  } else {
    throw new Error('ChainId not implemented');
  }

  const premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);

  console.log('Premia : ', premia.address);
  await premia.deployed();

  const usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

  console.log('USDC : ', usdc.address);
  await usdc.deployed();

  const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();
  await exchangeHelper.deployed();

  console.log('exchange helper : ', exchangeHelper.address);

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    lzEndpoint,
    premia.address,
    usdc.address,
    exchangeHelper.address,
  );

  console.log('vxPremia impl : ', vxPremiaImpl.address);
  await vxPremiaImpl.deployed();

  const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
    vxPremiaImpl.address,
  );

  console.log('vxPremia : ', vxPremiaProxy.address);
  await vxPremiaProxy.deployed();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
