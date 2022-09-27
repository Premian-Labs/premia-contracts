import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

interface PoolSettingsBehaviorArgs {
  getProtocolOwner: () => Promise<SignerWithAddress>;
  getNonProtocolOwner: () => Promise<SignerWithAddress>;
}

export function describeBehaviorOfPoolSettings(
  deploy: () => Promise<IPool>,
  { getProtocolOwner, getNonProtocolOwner }: PoolSettingsBehaviorArgs,
) {
  describe('::PoolSettings', () => {
    let protocolOwner: SignerWithAddress;
    let nonProtocolOwner: SignerWithAddress;
    let instance: IPool;

    before(async () => {
      protocolOwner = await getProtocolOwner();
      nonProtocolOwner = await getNonProtocolOwner();
    });

    beforeEach(async () => {
      instance = await deploy();
    });

    describe('#setMinimumAmounts', () => {
      it('todo');

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            instance
              .connect(nonProtocolOwner)
              .setMinimumAmounts(ethers.constants.Zero, ethers.constants.Zero),
          ).to.be.revertedWith('Not protocol owner');
        });
      });
    });

    describe('#setSteepness64x64', () => {
      it('todo');

      it('emits UpdateSteepness event');

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            instance
              .connect(nonProtocolOwner)
              .setSteepness64x64(ethers.constants.Zero, false),
          ).to.be.revertedWith('Not protocol owner');
        });
      });
    });

    describe('#setCLevel64x64', () => {
      it('todo');

      it('emits UpdateCLevel event');

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            instance
              .connect(nonProtocolOwner)
              .setCLevel64x64(ethers.constants.Zero, false),
          ).to.be.revertedWith('Not protocol owner');
        });
      });
    });

    describe('#setSpotOffset64x64', () => {
      it('emits UpdateSpotOffset event', async () => {
        const offset = ethers.constants.Two;

        await expect(instance.connect(protocolOwner).setSpotOffset64x64(offset))
          .to.emit(instance, 'UpdateSpotOffset')
          .withArgs(offset);
      });

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            instance
              .connect(nonProtocolOwner)
              .setSpotOffset64x64(ethers.constants.Zero),
          ).to.be.revertedWith('Not protocol owner');
        });

        it('offset is negative', async () => {
          await expect(
            instance
              .connect(protocolOwner)
              .setSpotOffset64x64(ethers.constants.NegativeOne),
          ).to.be.revertedWith('too low');
        });

        it('offset exceeds maximum', async () => {
          await expect(
            instance
              .connect(protocolOwner)
              .setSpotOffset64x64(ethers.constants.Two.pow(64)),
          ).to.be.revertedWith('too high');
        });
      });
    });
  });
}
