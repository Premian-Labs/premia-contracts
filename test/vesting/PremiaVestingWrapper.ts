import { expect } from 'chai';
import {
  PremiaErc20,
  PremiaErc20__factory,
  PremiaVesting,
  PremiaVesting__factory,
  PremiaVestingWrapper,
  PremiaVestingWrapper__factory,
} from '../../typechain';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { increaseTimestamp, resetHardhat } from '../utils/evm';
import { formatEther, parseEther } from 'ethers/lib/utils';

let owner: SignerWithAddress;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let premia: PremiaErc20;
let premiaVesting: PremiaVesting;
let premiaVestingWrapper: PremiaVestingWrapper;

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 13366880;
const ONE_DAY = 24 * 3600;
const VESTED_PREMIA = 2500000;

describe('PremiaVesting', () => {
  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    [admin, user1] = await ethers.getSigners();

    // Impersonate owner
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0xc340b7a2a70d7e08f25435cb97f3b25a45002e6c'],
    });

    owner = await ethers.getSigner(
      '0xc340b7a2a70d7e08f25435cb97f3b25a45002e6c',
    );

    premiaVesting = PremiaVesting__factory.connect(
      '0x3a00bc08f4ee12568231db85d077864275a495b3',
      owner,
    );

    premia = PremiaErc20__factory.connect(
      '0x6399c842dd2be3de30bf99bc7d1bbf6fa3650e70',
      owner,
    );

    premiaVestingWrapper = await new PremiaVestingWrapper__factory(
      admin,
    ).deploy(premia.address, premiaVesting.address);

    await premiaVesting.transferOwnership(premiaVestingWrapper.address);
    await premiaVestingWrapper.connect(admin).transferOwnership(user1.address);
  });

  afterEach(async () => {
    await resetHardhat();
  });

  it('should successfully withdraw over 2 years', async () => {
    expect(await premia.balanceOf(user1.address)).to.eq(0);

    await increaseTimestamp(ONE_DAY);
    await premiaVestingWrapper.connect(user1).withdraw();

    expect(
      Number(formatEther(await premia.balanceOf(user1.address))),
    ).to.almost(VESTED_PREMIA / 730, 0.2);

    await increaseTimestamp(ONE_DAY);
    await premiaVestingWrapper.connect(user1).withdraw();

    expect(
      Number(formatEther(await premia.balanceOf(user1.address))),
    ).to.almost((VESTED_PREMIA / 730) * 2, 0.2);

    await increaseTimestamp(ONE_DAY * 363);
    await premiaVestingWrapper.connect(user1).withdraw();

    expect(
      Number(formatEther(await premia.balanceOf(user1.address))),
    ).to.almost(VESTED_PREMIA / 2, 0.2);

    await increaseTimestamp(ONE_DAY * 370);
    await premiaVestingWrapper.connect(user1).withdraw();

    expect(await premia.balanceOf(user1.address)).to.eq(
      parseEther(VESTED_PREMIA.toString()),
    );
  });
});
