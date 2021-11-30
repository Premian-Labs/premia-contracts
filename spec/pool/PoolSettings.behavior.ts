import { ethers } from 'hardhat';
import { expect } from 'chai';
import { PoolSettings, PoolView__factory } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { formatTokenId, TokenType } from '@premia/utils';

import {
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  FEE,
  formatOption,
  formatOptionToNb,
  formatUnderlying,
  getExerciseValue,
  getTokenDecimals,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolSettingsBehaviorArgs {
  deploy: () => Promise<PoolSettings>;
  getProtocolOwner: () => Promise<SignerWithAddress>;
  getNonProtocolOwner: () => Promise<SignerWithAddress>;
}

export function describeBehaviorOfPoolSettings({
  deploy,
  getProtocolOwner,
  getNonProtocolOwner,
}: PoolSettingsBehaviorArgs) {
  describe('::PoolSettings', () => {
    let protocolOwner: SignerWithAddress;
    let nonProtocolOwner: SignerWithAddress;
    let instance: PoolSettings;

    before(async () => {
      protocolOwner = await getProtocolOwner();
      nonProtocolOwner = await getNonProtocolOwner();
    });

    beforeEach(async () => {
      instance = await deploy();
    });

    describe('#setPoolCaps', () => {
      it('updates deposit caps', async () => {
        await instance.connect(protocolOwner).setPoolCaps('123', '456');

        const poolView = PoolView__factory.connect(
          instance.address,
          ethers.provider,
        );

        const caps = await poolView.callStatic.getCapAmounts();
        expect(caps.callTokenCapAmount).to.eq('456');
        expect(caps.putTokenCapAmount).to.eq('123');
      });

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            instance.connect(nonProtocolOwner).setPoolCaps('123', '456'),
          ).to.be.revertedWith('Not protocol owner');
        });
      });
    });

    describe('#setMinimumAmounts', () => {
      it('todo');

      describe('reverts if', () => {
        it('sender is not protocol owner');
      });
    });

    describe('#setSteepness64x64', () => {
      it('todo');

      it('emits UpdateSteepness event');

      describe('reverts if', () => {
        it('sender is not protocol owner');
      });
    });

    describe('#setCLevel64x64', () => {
      it('todo');

      it('emits UpdateCLevel event');

      describe('reverts if', () => {
        it('sender is not protocol owner');
      });
    });
  });
}
