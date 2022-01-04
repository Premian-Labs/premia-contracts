import { ethers } from 'hardhat';
import { expect } from 'chai';
import { describeBehaviorOfERC1155Enumerable } from '@solidstate/spec';
import { IPool, ERC20Mock } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { formatTokenId, TokenType } from '@premia/utils';

import {
  parseOption,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
} from '../../test/pool/PoolUtil';

interface PoolBaseBehaviorArgs {
  deploy: () => Promise<IPool>;
  getUnderlying: () => Promise<ERC20Mock>;
  mintERC1155: (
    address: string,
    id: BigNumber,
    amount: BigNumber,
  ) => Promise<ContractTransaction>;
  burnERC1155: (
    address: string,
    id: BigNumber,
    amount: BigNumber,
  ) => Promise<ContractTransaction>;
}

export function describeBehaviorOfPoolBase(
  { deploy, getUnderlying, mintERC1155, burnERC1155 }: PoolBaseBehaviorArgs,
  skips?: string[],
) {
  describe('::PoolBase', () => {
    let owner: SignerWithAddress;
    let instance: IPool;
    let underlying: ERC20Mock;

    before(async () => {
      [owner] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      underlying = await getUnderlying();
    });

    describeBehaviorOfERC1155Enumerable(
      {
        deploy: async () => instance,
        mint: mintERC1155,
        burn: burnERC1155,
        tokenId: BigNumber.from(
          formatTokenId({
            tokenType: TokenType.LongCall,
            strike64x64: BigNumber.from(0),
            maturity: BigNumber.from(0),
          }),
        ),
      },
      skips,
    );

    // TODO: ERC165 behavior

    describe('#name', () => {
      it('returns token collection name');
    });

    describe('#safeTransferFrom', () => {
      describe('reverts if', () => {
        it('tokenId corresponds to locked free liquidity', async () => {
          const isCall = true;
          const amount = parseOption('100', isCall);

          await underlying.mint(owner.address, amount);
          await underlying
            .connect(owner)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance.connect(owner).deposit(amount, isCall);

          await expect(
            instance
              .connect(owner)
              .safeTransferFrom(
                owner.address,
                owner.address,
                getFreeLiqTokenId(isCall),
                '1',
                '0x',
              ),
          ).to.be.revertedWith('liq lock 1d');
        });

        it('tokenId corresponds to locked reserved liquidity', async () => {
          const isCall = true;
          const amount = parseOption('100', isCall);

          await underlying.mint(owner.address, amount);
          await underlying
            .connect(owner)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance.connect(owner).deposit(amount, isCall);

          await expect(
            instance
              .connect(owner)
              .safeTransferFrom(
                owner.address,
                owner.address,
                getReservedLiqTokenId(isCall),
                '1',
                '0x',
              ),
          ).to.be.revertedWith('liq lock 1d');
        });
      });
    });
  });
}
