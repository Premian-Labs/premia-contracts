import { expect } from 'chai';
import {
  PremiaErc20,
  PremiaErc20__factory,
  PremiaVesting__factory,
  PremiaVestingTransfer__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { parseEther } from 'ethers/lib/utils';

let deployer: SignerWithAddress;
let premia: PremiaErc20;

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 16997000;

const mainnetDeployer = '0xC7f8D87734aB2cbf70030aC8aa82abfe3e8126cb';

const oldContracts = [
  '0x3a00BC08F4Ee12568231dB85D077864275a495b3',
  '0xdF69C895E7490d90b14A278Add8Aa4eC844a696a',
  '0xD3C8Ce2793c60c9e8464FC08Ec7691613057c43C',
  '0x1ede971F31f7630baE9f14d349273621A5145381',
];
const newContracts = [
  '0x084D8a46E7dC0C0739198D47aF6ca3a8AAF4D99A',
  '0xEfC8b553453B9c4Cc0Af044D3B3E8482841aFa3d',
  '0xc2F6c4cC599840F2b1576cac43FE4D9C160263fe',
  '0xD4fb04AD53b3eBE47A0b16577d2e6594e602583F',
];

const owners = [
  '0xC340B7A2A70d7e08F25435CB97F3B25A45002e6C',
  '0xfCF7c21910A878b5A31D31bA29789C3ff235fC17',
  '0x50CC6BE786aeF59EaD19fa4438dFe139D6837822',
  '0xDEAD5D3c486AcE753c839e2EB27BacdabBA06dD6',
];

describe('PremiaVestingTransfer', () => {
  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    [deployer] = await ethers.getSigners();

    premia = PremiaErc20__factory.connect(
      '0x6399c842dd2be3de30bf99bc7d1bbf6fa3650e70',
      deployer,
    );
  });

  it('should successfully transfer vesting', async () => {
    let i = 0;
    for (const owner of owners) {
      const transferContract = await new PremiaVestingTransfer__factory(
        deployer,
      ).deploy(oldContracts[i], newContracts[i]);

      await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [mainnetDeployer],
      });

      const mainnetDeployerSigner = await ethers.getSigner(mainnetDeployer);

      await ProxyUpgradeableOwnable__factory.connect(
        newContracts[i],
        mainnetDeployerSigner,
      ).transferOwnership(owner);

      await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [owner],
      });

      const ownerSigner = await ethers.getSigner(owner);

      await ProxyUpgradeableOwnable__factory.connect(
        oldContracts[i],
        ownerSigner,
      ).transferOwnership(transferContract.address);

      await network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [owner],
      });

      await transferContract.connect(deployer).transfer();

      expect(await premia.balanceOf(oldContracts[i])).to.equal(0);
      expect(await premia.balanceOf(newContracts[i])).to.equal(
        parseEther('2500000'),
      );

      await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [owner],
      });

      const newContract = await PremiaVesting__factory.connect(
        newContracts[i],
        ownerSigner,
      );

      const balanceBefore = await premia.balanceOf(owner);
      await newContract.withdraw(owner, parseEther('100000'));
      const balanceAfter = await premia.balanceOf(owner);

      expect(balanceAfter.sub(balanceBefore)).to.equal(parseEther('100000'));

      await network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [owner],
      });

      i++;
    }
  });
});
