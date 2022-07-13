import { ethers } from 'hardhat';
import { VePremia__factory, VePremiaProxy__factory } from '../../../typechain';
import LZ_ENDPOINTS from '../../../constants/layerzeroEndpoints.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let lzEndpoint: string;
  let premia: string;
  let usdc: string;
  let exchangeHelper: string;
  let vePremiaProxyAddress: string;

  if (chainId === 4) {
    lzEndpoint = LZ_ENDPOINTS.rinkeby;
    premia = '0x2A9C2aC82ac8fcE5f6664d460BD058fC6fEF0Cee';
    usdc = '0x0f0F970d76C79b5cf641c7798234Acd375E42e94';
    exchangeHelper = '0x28007C6fe4bDa4c1A92116fa3C648f00A054f47e';
    vePremiaProxyAddress = '0x35C853A4dA06124C08eb00A345818accF7906391';
  } else if (chainId === 421611) {
    lzEndpoint = LZ_ENDPOINTS['arbitrum-rinkeby'];
    premia = '0x9531E20AE7f79FaB7391A1a9125ba02fC897F1ff';
    usdc = '0x8777aC154FA0195eee9fAa55B73eBF2CF60Fc23f';
    exchangeHelper = '0x5B5dF12D0a02641CC9bB92e90d0b5DfB97aCB5bE';
    vePremiaProxyAddress = '0x4BD51e75141634919870661b439769D361F3103c';
  } else {
    throw new Error('ChainId not implemented');
  }

  const vePremiaImpl = await new VePremia__factory(deployer).deploy(
    lzEndpoint,
    premia,
    usdc,
    exchangeHelper,
  );

  console.log('vePremia impl : ', vePremiaImpl.address);
  await vePremiaImpl.deployed();

  const proxy = VePremiaProxy__factory.connect(vePremiaProxyAddress, deployer);

  await proxy.setImplementation(vePremiaImpl.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
