import { ethers } from 'hardhat';
import {
  ChainlinkWrapper__factory,
  ChainlinkWrapperProxy__factory,
} from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  const chainlinkWrapperProxy = '';
  const setImplementation = true;

  let uniswapV3Factory: string;
  let ethUSDOracle: string;

  let tokenIn: string;
  let tokenOut: string;

  if (chainId === 42161) {
    // Arbitrum addresses
    uniswapV3Factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
    ethUSDOracle = '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612';

    tokenIn = '0x912CE59144191C1204E64559FE8253a0e49E6548';
    tokenOut = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1';
  } else {
    throw new Error('ChainId not implemented');
  }

  //////////////////////////

  const implementation = await new ChainlinkWrapper__factory(deployer).deploy(
    uniswapV3Factory,
    ethUSDOracle,
    tokenIn,
    tokenOut,
  );

  await implementation.deployed();

  console.log(`ChainlinkWrapper impl : ${implementation.address}`);

  if (setImplementation) {
    const proxy = ChainlinkWrapperProxy__factory.connect(
      chainlinkWrapperProxy,
      deployer,
    );

    await (await proxy.setImplementation(implementation.address)).wait();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
