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
    rinkeby: '0x35C853A4dA06124C08eb00A345818accF7906391',
    rinkebyArbitrum: '0x4BD51e75141634919870661b439769D361F3103c',
    goerli: '0x67Dbd61479d4D79739BC0CEC27944A010c0C5A62',
    goerliArbitrum: '0x832c33dEB9D6Bd69B15379126d44A67232FE7561',
  };

  if (chainId === 4) {
    vePremia = VePremia__factory.connect(vePremiaAddress.rinkeby, deployer);
    remoteAddress = vePremiaAddress.rinkebyArbitrum;
    localAddress = vePremiaAddress.rinkeby;
    srcChainId = CHAIN_ID['arbitrum-rinkeby'];
  } else if (chainId === 5) {
    vePremia = VePremia__factory.connect(vePremiaAddress.goerli, deployer);
    remoteAddress = vePremiaAddress.goerliArbitrum;
    localAddress = vePremiaAddress.goerli;
    srcChainId = CHAIN_ID['arbitrum-goerli'];
  } else if (chainId === 421611) {
    vePremia = VePremia__factory.connect(
      vePremiaAddress.rinkebyArbitrum,
      deployer,
    );
    remoteAddress = vePremiaAddress.rinkeby;
    localAddress = vePremiaAddress.rinkebyArbitrum;
    srcChainId = CHAIN_ID.rinkeby;
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

  const trustedRemote = solidityPack(
    ['address', 'address'],
    [remoteAddress, localAddress],
  );
  await vePremia.setTrustedRemoteAddress(srcChainId, trustedRemote);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
