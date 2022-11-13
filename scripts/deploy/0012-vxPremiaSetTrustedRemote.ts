import { ethers } from 'hardhat';
import { VxPremia, VxPremia__factory } from '../../typechain';
import CHAIN_ID from '../../constants/layerzeroChainId.json';

async function main() {
  const [deployer] = await ethers.getSigners();

  const chainId = await deployer.getChainId();

  interface Remote {
    chainId: number;
    address: string;
  }

  let vxPremia: VxPremia;
  let remoteList: Remote[] = [];

  enum Chain {
    MAINNET = 'MAINNET',
    ARBITRUM = 'ARBITRUM',
    OPTIMISM = 'OPTIMISM',
    FANTOM = 'FANTOM',
  }

  const remotes: {
    [key in Chain]: Remote;
  } = {
    [Chain.MAINNET]: {
      chainId: CHAIN_ID.ethereum,
      address: '0xF1bB87563A122211d40d393eBf1c633c330377F9',
    },
    [Chain.ARBITRUM]: { chainId: CHAIN_ID.arbitrum, address: '' },
    [Chain.OPTIMISM]: { chainId: CHAIN_ID.optimism, address: '' },
    [Chain.FANTOM]: { chainId: CHAIN_ID.fantom, address: '' },
  };

  if (chainId === 1) {
    vxPremia = VxPremia__factory.connect(
      remotes[Chain.MAINNET].address,
      deployer,
    );
    remoteList.push(remotes[Chain.ARBITRUM]);
    remoteList.push(remotes[Chain.OPTIMISM]);
    remoteList.push(remotes[Chain.FANTOM]);
  } else if (chainId === 42161) {
    vxPremia = VxPremia__factory.connect(
      remotes[Chain.ARBITRUM].address,
      deployer,
    );
    remoteList.push(remotes[Chain.MAINNET]);
    remoteList.push(remotes[Chain.OPTIMISM]);
    remoteList.push(remotes[Chain.FANTOM]);
  } else if (chainId === 10) {
    vxPremia = VxPremia__factory.connect(
      remotes[Chain.OPTIMISM].address,
      deployer,
    );
    remoteList.push(remotes[Chain.MAINNET]);
    remoteList.push(remotes[Chain.ARBITRUM]);
    remoteList.push(remotes[Chain.FANTOM]);
  } else if (chainId === 250) {
    vxPremia = VxPremia__factory.connect(
      remotes[Chain.FANTOM].address,
      deployer,
    );
    remoteList.push(remotes[Chain.MAINNET]);
    remoteList.push(remotes[Chain.ARBITRUM]);
    remoteList.push(remotes[Chain.OPTIMISM]);
  } else {
    throw new Error('ChainId not implemented');
  }

  for (const r of remoteList) {
    await vxPremia.setTrustedRemoteAddress(r.chainId, r.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
