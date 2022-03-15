import { expect } from 'chai';
import { TimelockMultisig, TimelockMultisig__factory } from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, increaseTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';
import { ZERO_ADDRESS } from '../utils/constants';

let admin: SignerWithAddress;
let signer1: SignerWithAddress;
let signer2: SignerWithAddress;
let signer3: SignerWithAddress;
let signer4: SignerWithAddress;
let otherUser: SignerWithAddress;
let receiver: SignerWithAddress;
let timelockMultisig: TimelockMultisig;

describe('TimelockMultisig', () => {
  async function startWithdrawal(signer: SignerWithAddress) {
    await timelockMultisig
      .connect(signer)
      .startWithdraw(receiver.address, parseEther('10'));
  }

  beforeEach(async () => {
    [admin, signer1, signer2, signer3, signer4, otherUser, receiver] =
      await ethers.getSigners();

    timelockMultisig = await new TimelockMultisig__factory(admin).deploy([
      signer1.address,
      signer2.address,
      signer3.address,
      signer4.address,
    ]);

    await admin.sendTransaction({
      to: timelockMultisig.address,
      value: parseEther('100'),
    });
  });

  it('should fail initiating withdrawal if not signer', async () => {
    await expect(startWithdrawal(otherUser)).to.be.revertedWith('not signer');
  });

  it('should fail starting withdrawal if a withdrawal is pending', async () => {
    await startWithdrawal(signer1);

    await expect(startWithdrawal(signer1)).to.be.revertedWith(
      'pending withdrawal',
    );
  });

  it('should successfully initiate withdrawal', async () => {
    await startWithdrawal(signer1);
    const pendingWithdrawal = await timelockMultisig.pendingWithdrawal();

    expect(pendingWithdrawal.to).to.eq(receiver.address);
    expect(pendingWithdrawal.amount).to.eq(parseEther('10'));
  });

  it('should fail transferring ETH if timelock not passed', async () => {
    await startWithdrawal(signer1);
    await increaseTimestamp(6 * 24 * 3600);

    await expect(
      timelockMultisig.connect(signer1).doWithdraw(),
    ).to.be.revertedWith('not ready');
  });

  it('should successfully transfer ETH after timelock passed', async () => {
    await startWithdrawal(signer1);
    await increaseTimestamp(7 * 24 * 3600 + 1);

    await expect(() =>
      timelockMultisig.connect(signer1).doWithdraw(),
    ).to.changeEtherBalance(receiver, parseEther('10'));
  });

  it('should instantly transfer ETH if 3/4 authorize', async () => {
    await startWithdrawal(signer1);
    await timelockMultisig.connect(signer3).authorize();
    await expect(() =>
      timelockMultisig.connect(signer4).authorize(),
    ).to.changeEtherBalance(receiver, parseEther('10'));

    const pendingWithdrawal = await timelockMultisig.pendingWithdrawal();
    expect(pendingWithdrawal.to).to.eq(ZERO_ADDRESS);
    expect(pendingWithdrawal.amount).to.eq(0);
  });

  it('should reject transfer if 2/4 reject', async () => {
    await startWithdrawal(signer1);
    await timelockMultisig.connect(signer2).reject();
    await timelockMultisig.connect(signer3).reject();

    const pendingWithdrawal = await timelockMultisig.pendingWithdrawal();
    expect(pendingWithdrawal.to).to.eq(ZERO_ADDRESS);
    expect(pendingWithdrawal.amount).to.eq(0);
    expect(await getEthBalance(timelockMultisig.address)).to.eq(
      parseEther('100'),
    );
  });
});
