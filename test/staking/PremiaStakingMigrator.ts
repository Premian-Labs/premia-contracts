import {
  IPremiaFeeDiscountOld,
  IPremiaFeeDiscountOld__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaStaking,
  PremiaStaking__factory,
  PremiaStakingMigrator,
  PremiaStakingMigrator__factory,
  VxPremia,
} from '../../typechain';
import { ethers, network } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat } from '../utils/evm';
import { deployV1 } from '../../scripts/utils/deployV1';
import { bnToNumber } from '../utils/math';

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
let vxPremia: VxPremia;

describe('PremiaStakingMigrator', () => {
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
      ethers.constants.AddressZero,
      true,
      false,
      premia.address,
    );

    vxPremia = p.vxPremia;

    migrator = await new PremiaStakingMigrator__factory(treasury).deploy(
      premia.address,
      feeDiscountOld.address,
      xPremiaOld.address,
    );

    await feeDiscountOld.connect(treasury).setNewContract(migrator.address);
  });

  afterEach(async () => {
    await resetHardhat();
  });

  it('should successfully withdraw locked tokens', async () => {
    const staker = await ethers.getSigner(
      '0x6e4be9b794b1432a8b735ef5b3040392a27b4372',
    );

    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [staker.address],
    });

    const oldPremiaBalance = await premia.balanceOf(xPremiaOld.address);

    expect(await premia.balanceOf(staker.address)).to.eq(0);

    await feeDiscountOld.connect(staker).migrateStake();

    expect(
      bnToNumber(
        oldPremiaBalance.sub(await premia.balanceOf(xPremiaOld.address)),
      ),
    ).to.almost(500);
    expect(bnToNumber(await premia.balanceOf(staker.address))).to.almost(500);
  });
});
