import { ethers } from 'hardhat';
import { VxPremia__factory, VxPremiaProxy__factory } from '../../../typechain';
import LZ_ENDPOINTS from '../../../constants/layerzeroEndpoints.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let lzEndpoint: string;
  let premia: string;
  let usdc: string;
  let exchangeHelper: string;
  let vxPremiaProxyAddress: string;

  if (chainId === 5) {
    lzEndpoint = LZ_ENDPOINTS.goerli;
    premia = '0x527a26e0c6cb50D146E177461bF5a6d754f8d8Ff';
    usdc = '0x7071c84BACA68b52E3e558020E1E4b17A8A48184';
    exchangeHelper = '0x06f087bEbF6B18e5d24907f8FE339864B96E98C6';
    vxPremiaProxyAddress = '0x67Dbd61479d4D79739BC0CEC27944A010c0C5A62';
  } else if (chainId === 421613) {
    lzEndpoint = LZ_ENDPOINTS['arbitrum-goerli'];
    premia = '0xAF9ED4B3301bD338038f4a3795792c48fF858293';
    usdc = '0xaa792dD20f926286C1b52DB03d880BDd6699CAEf';
    exchangeHelper = '0xb95b1DDDF83314F4548F55D4398c114C67e8F774';
    vxPremiaProxyAddress = '0x832c33dEB9D6Bd69B15379126d44A67232FE7561';
  } else {
    throw new Error('ChainId not implemented');
  }

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    lzEndpoint,
    premia,
    usdc,
    exchangeHelper,
  );

  console.log('vxPremia impl : ', vxPremiaImpl.address);
  await vxPremiaImpl.deployed();

  const proxy = VxPremiaProxy__factory.connect(vxPremiaProxyAddress, deployer);

  await proxy.setImplementation(vxPremiaImpl.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
