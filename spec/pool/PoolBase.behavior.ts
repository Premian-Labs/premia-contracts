import { ethers } from 'hardhat';
import { expect } from 'chai';
import { describeBehaviorOfERC1155Enumerable } from '@solidstate/spec';
import { IPool } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { formatTokenId, TokenType } from '@premia/utils';

import { parseOption, PoolUtil } from '../../test/pool/PoolUtil';

interface PoolBaseBehaviorArgs {
  deploy: () => Promise<IPool>;
  getPoolUtil: () => Promise<PoolUtil>;
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
  { deploy, getPoolUtil, mintERC1155, burnERC1155 }: PoolBaseBehaviorArgs,
  skips?: string[],
) {
  describe('::PoolBase', () => {
    let owner: SignerWithAddress;
    let instance: IPool;
    let p: PoolUtil;

    before(async () => {
      [owner] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      // TODO: don't
      p = await getPoolUtil();
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
      it('reverts if tokenId corresponds to locked free liquidity', async () => {
        await p.depositLiquidity(owner, parseOption('100', true), true);

        expect(
          instance
            .connect(owner)
            .safeTransferFrom(
              owner.address,
              owner.address,
              p.getFreeLiqTokenId(true),
              '1',
              ethers.utils.randomBytes(0),
            ),
        ).to.be.revertedWith('liq lock 1d');
      });

      it('reverts if tokenId corresponds to locked reserved liquidity', async () => {
        await p.depositLiquidity(owner, parseOption('100', true), true);

        expect(
          instance
            .connect(owner)
            .safeTransferFrom(
              owner.address,
              owner.address,
              p.getReservedLiqTokenId(true),
              '1',
              ethers.utils.randomBytes(0),
            ),
        ).to.be.revertedWith('liq lock 1d');
      });
    });
  });
}
