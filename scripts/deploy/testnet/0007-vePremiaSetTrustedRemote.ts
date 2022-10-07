import { ethers } from 'hardhat';
import { VePremia, VePremia__factory } from '../../../typechain';
import CHAIN_ID from '../../../constants/layerzeroChainId.json';
import { solidityPack } from 'ethers/lib/utils';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let vePremia: VePremia;
  let remoteAddress: string;
  let localAddress: string;
  let srcChainId: number;

  const vePremiaAddress = {
    goerli: '0x67Dbd61479d4D79739BC0CEC27944A010c0C5A62',
    goerliArbitrum: '0x832c33dEB9D6Bd69B15379126d44A67232FE7561',
  };

  if (chainId === 5) {
    vePremia = VePremia__factory.connect(vePremiaAddress.goerli, deployer);
    remoteAddress = vePremiaAddress.goerliArbitrum;
    localAddress = vePremiaAddress.goerli;
    srcChainId = CHAIN_ID['arbitrum-goerli'];
  } else if (chainId === 421613) {
    vePremia = VePremia__factory.connect(
      vePremiaAddress.goerliArbitrum,
      deployer,
    );
    remoteAddress = vePremiaAddress.goerli;
    localAddress = vePremiaAddress.goerliArbitrum;
    srcChainId = CHAIN_ID.goerli;
  } else {
    throw new Error('ChainId not implemented');
  }

  await vePremia.setTrustedRemoteAddress(srcChainId, remoteAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
