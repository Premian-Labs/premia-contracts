import {
  IPremiaFeeDiscountOld,
  IPremiaFeeDiscountOld__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaStaking,
  PremiaStaking__factory,
  PremiaStakingMigrator,
  PremiaStakingMigrator__factory,
  VePremia,
} from '../../typechain';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat } from '../utils/evm';
import { deployV1 } from '../../scripts/utils/deployV1';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 13639700;

let premia: PremiaErc20;
let migrator: PremiaStakingMigrator;
let xPremiaOld: PremiaStaking;
let feeDiscountOld: IPremiaFeeDiscountOld;
let vePremia: VePremia;

describe('PremiaStakingWithFeeDiscount', () => {
  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    [admin, user1] = await ethers.getSigners();

    // Impersonate owner
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0xc22fae86443aeed038a4ed887bba8f5035fd12f0'],
    });

    treasury = await ethers.getSigner(
      '0xc22fae86443aeed038a4ed887bba8f5035fd12f0',
    );

    premia = PremiaErc20__factory.connect(
      '0x6399c842dd2be3de30bf99bc7d1bbf6fa3650e70',
      treasury,
    );

    //
    xPremiaOld = PremiaStaking__factory.connect(
      '0x16f9d564df80376c61ac914205d3fdff7057d610',
      treasury,
    );

    feeDiscountOld = IPremiaFeeDiscountOld__factory.connect(
      '0xf5aae75d1ad6fdd62cce66137f2674c96feda854',
      treasury,
    );

    //

    const p = await deployV1(
      treasury,
      treasury.address,
      ethers.constants.AddressZero,
      true,
      false,
      premia.address,
    );

    vePremia = p.vePremia;

    migrator = await new PremiaStakingMigrator__factory(treasury).deploy(
      premia.address,
      feeDiscountOld.address,
      xPremiaOld.address,
      vePremia.address,
    );

    await feeDiscountOld.connect(treasury).setNewContract(vePremia.address);
  });

  afterEach(async () => {
    await resetHardhat();
  });

  // ToDo : Update migrate tests

  // it('should successfully migrate locked tokens', async () => {
  //   const staker = await ethers.getSigner(
  //     '0x6e4be9b794b1432a8b735ef5b3040392a27b4372',
  //   );
  //
  //   await network.provider.request({
  //     method: 'hardhat_impersonateAccount',
  //     params: [staker.address],
  //   });
  //
  //   await feeDiscountOld.connect(staker).migrateStake();
  //   expect(bnToNumber(await premia.balanceOf(xPremia.address))).to.almost(500);
  //   expect(bnToNumber(await xPremia.balanceOf(xPremia.address))).to.almost(500);
  //
  //   const userInfo = await xPremia.getUserInfo(staker.address);
  //   expect(bnToNumber(userInfo.balance)).to.almost(500);
  //   expect(userInfo.stakePeriod).to.eq(15552000);
  //   expect(userInfo.lockedUntil).to.eq(1652794739);
  // });

  // it('should successfully migrate old xPremia to new xPremia', async () => {
  //   const staker = await ethers.getSigner(
  //     '0xb45b74eb35790d20e5f4225b0ac49d5bb074696e',
  //   );
  //
  //   await network.provider.request({
  //     method: 'hardhat_impersonateAccount',
  //     params: [staker.address],
  //   });
  //
  //   await premia.connect(treasury).approve(xPremia.address, 1000);
  //   await xPremia.connect(treasury).deposit(1000);
  //   await premia.connect(treasury).transfer(xPremia.address, 1000);
  //
  //   const xPremiaOldAmount = await xPremiaOld.balanceOf(staker.address);
  //   await xPremiaOld
  //     .connect(staker)
  //     .approve(xPremia.address, parseEther('1000000'));
  //   await xPremia.connect(staker).migrateWithoutLock(xPremiaOldAmount);
  //
  //   expect(await xPremiaOld.balanceOf(staker.address)).to.eq(0);
  //
  //   expect(bnToNumber(await xPremia.balanceOf(staker.address))).to.almost(
  //     117281.23,
  //   );
  //   expect(bnToNumber(await premia.balanceOf(xPremia.address))).to.almost(
  //     234562.46,
  //   );
  // });
});
