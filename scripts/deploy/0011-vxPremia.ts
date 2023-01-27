import { ethers } from 'hardhat';
import { VxPremia__factory, VxPremiaProxy__factory } from '../../typechain';
import LZ_ENDPOINTS from '../../constants/layerzeroEndpoints.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let premiaDiamond: string;
  let lzEndpoint: string;
  let premia: string;
  let usdc: string;
  let exchangeHelper: string;

  if (chainId === 1) {
    premiaDiamond = '0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350';
    lzEndpoint = LZ_ENDPOINTS.ethereum;
    premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
    usdc = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
    exchangeHelper = '0x380Eb51db6FE77a8876cB0735164cB8AF7f80Cb5';
  } else if (chainId === 42161) {
    premiaDiamond = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    lzEndpoint = LZ_ENDPOINTS.arbitrum;
    premia = '0x51fc0f6660482ea73330e414efd7808811a57fa2';
    usdc = '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8';
    exchangeHelper = '0xD8A0D357171beBC63CeA559c4e9CD182c1bf25ef';
  } else if (chainId === 10) {
    premiaDiamond = '0x48D49466CB2EFbF05FaA5fa5E69f2984eDC8d1D7';
    lzEndpoint = LZ_ENDPOINTS.optimism;
    premia = '0x374Ad0f47F4ca39c78E5Cc54f1C9e426FF8f231A';
    usdc = '0x7f5c764cbc14f9669b88837ca1490cca17c31607';
    exchangeHelper = '0x834c025fa5eb6726803a2d67f160fcfabc49a174';
  } else if (chainId === 250) {
    premiaDiamond = '0xD9e169e31394efccd78CC0b63a8B09B4D71b705E';
    lzEndpoint = LZ_ENDPOINTS.fantom;
    premia = '0x3028b4395F98777123C7da327010c40f3c7Cc4Ef';
    usdc = '0x04068DA6C83AFCFA0e13ba15A6696662335D5B75';
    exchangeHelper = '0x5Af7a354C9C35B58b4278aB0e1E934fab01b26Ab';
  } else {
    throw new Error('ChainId not implemented');
  }

  console.log('LZ Endpoint : ', lzEndpoint);
  console.log('Premia : ', premia);
  console.log('USDC : ', usdc);
  console.log('ExchangeHelper : ', exchangeHelper);

  const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
    premiaDiamond,
    lzEndpoint,
    premia,
    usdc,
    exchangeHelper,
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
