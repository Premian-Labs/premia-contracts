import { ethers } from 'hardhat';
import { VePremia, VePremia__factory } from '../../../typechain';
import CHAIN_ID from '../../../constants/layerzeroChainId.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let vePremia: VePremia;
  let srcAddress: string;
  let srcChainId: number;

  const vePremiaAddress = {
    rinkeby: '0x35C853A4dA06124C08eb00A345818accF7906391',
    rinkebyArbitrum: '0x4BD51e75141634919870661b439769D361F3103c',
  };

  if (chainId === 4) {
    vePremia = VePremia__factory.connect(vePremiaAddress.rinkeby, deployer);
    srcAddress = vePremiaAddress.rinkebyArbitrum;
    srcChainId = CHAIN_ID['arbitrum-rinkeby'];
  } else if (chainId === 421611) {
    vePremia = VePremia__factory.connect(
      vePremiaAddress.rinkebyArbitrum,
      deployer,
    );
    srcAddress = vePremiaAddress.rinkeby;
    srcChainId = CHAIN_ID.rinkeby;
  } else {
    throw new Error('ChainId not implemented');
  }

  await vePremia.setTrustedRemote(srcChainId, srcAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
