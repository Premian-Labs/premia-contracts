import { ethers } from 'hardhat';
import { expect } from 'chai';
import { describeBehaviorOfERC1155Enumerable } from '@solidstate/spec';
import { PoolBase } from '../../typechain';
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

interface PoolBaseBehaviorArgs {
  deploy: () => Promise<PoolBase>;
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
  { deploy, mintERC1155, burnERC1155 }: PoolBaseBehaviorArgs,
  skips?: string[],
) {
  describe('::PoolBase', () => {
    let deployer: SignerWithAddress;
    let instance: PoolBase;

    before(async () => {
      [deployer] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
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
  });
}
