import { ethers } from 'hardhat';
import { VxPremia, VxPremia__factory } from '../../../typechain';
import CHAIN_ID from '../../../constants/layerzeroChainId.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let vxPremia: VxPremia;
  let remoteAddress: string;
  let localAddress: string;
  let srcChainId: number;

  const vxPremiaAddress = {
    goerli: '0x67Dbd61479d4D79739BC0CEC27944A010c0C5A62',
    goerliArbitrum: '0x832c33dEB9D6Bd69B15379126d44A67232FE7561',
  };

  if (chainId === 5) {
    vxPremia = VxPremia__factory.connect(vxPremiaAddress.goerli, deployer);
    remoteAddress = vxPremiaAddress.goerliArbitrum;
    localAddress = vxPremiaAddress.goerli;
    srcChainId = CHAIN_ID['arbitrum-goerli'];
  } else if (chainId === 421613) {
    vxPremia = VxPremia__factory.connect(
      vxPremiaAddress.goerliArbitrum,
      deployer,
    );
    remoteAddress = vxPremiaAddress.goerli;
    localAddress = vxPremiaAddress.goerliArbitrum;
    srcChainId = CHAIN_ID.goerli;
  } else {
    throw new Error('ChainId not implemented');
  }

  await vxPremia.setTrustedRemoteAddress(srcChainId, remoteAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
