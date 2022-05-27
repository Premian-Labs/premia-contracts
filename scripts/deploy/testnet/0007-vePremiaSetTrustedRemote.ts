import { ethers } from 'hardhat';
import {
  ProxyUpgradeableOwnable__factory,
  VePremia,
  VePremia__factory,
} from '../../../typechain';
import CHAIN_ID from '../../../constants/layerzeroChainId.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  let vePremia: VePremia;
  let srcAddress: string;
  let srcChainId: number;

  const vePremiaAddress = {
    rinkeby: '0x20cAaf03FCAcD451E851Cce193d3fF55Fbb95A45',
    rinkebyArbitrum: '0x05bfe074FA3C34464cE26841860cd68357D7dC06',
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
