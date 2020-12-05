import { ethers } from 'hardhat';
import { PremiaOption__factory } from '../contractsTyped';

async function main() {
  // We get the contract to deploy
  const dai = '0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa';
  const weth = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
  const rope = '0xc427c5b9be1dfd0fab70ac42f8ce52fe77a3c51e';

  const [deployer] = await ethers.getSigners();

  const premiaOptionFactory = new PremiaOption__factory(deployer);
  const premiaOption = await premiaOptionFactory.deploy(
    'dummyURI',
    dai,
    deployer.address,
  );

  // await premiaOption.deployed();
  console.log(
    `premiaOption deployed to ${premiaOption.address} from ${deployer.address}`,
  );

  await premiaOption.setToken(
    weth,
    ethers.utils.parseEther('1'),
    ethers.utils.parseEther('10'),
  );

  console.log('WETH added');

  await premiaOption.setToken(
    rope,
    ethers.utils.parseEther('1'),
    ethers.utils.parseEther('1'),
  );

  console.log('ROPE added');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
