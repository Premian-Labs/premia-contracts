import { expect } from 'chai';
import { describeBehaviorOfPool } from './Pool.behavior';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Pool, PoolMock, PoolMock__factory } from '../../typechain';
import { getTokenIdFor } from '../utils/math';
import { TokenType } from './PoolUtil';

const fixedFromBigNumber = function (bn: BigNumber) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const fixedFromFloat = function (float: number) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(BigNumber.from(`${integer}${decimal}`)).div(
    BigNumber.from(`1${'0'.repeat(decimal.length)}`),
  );
};

describe('Pool', function () {
  let owner: SignerWithAddress;

  let instance: PoolMock;

  before(async function () {
    [owner] = await ethers.getSigners();
  });

  beforeEach(async function () {
    instance = await new PoolMock__factory(owner).deploy(
      ethers.constants.AddressZero,
    );
  });

  describeBehaviorOfPool(
    {
      deploy: async () => instance,
      mintERC1155: (recipient, tokenId, amount) =>
        instance['mint(address,uint256,uint256)'](recipient, tokenId, amount),
      burnERC1155: (recipient, tokenId, amount) =>
        instance['burn(address,uint256,uint256)'](recipient, tokenId, amount),
    },
    ['#supportsInterface'],
  );

  describe('__internal', function () {
    describe('#_tokenIdFor', function () {
      it('returns concatenation of maturity and strikePrice', async function () {
        const tokenType = TokenType.LongCall;
        const maturity = ethers.BigNumber.from(
          Math.floor(new Date().getTime() / 1000),
        );
        const strikePrice = fixedFromFloat(Math.random() * 1000);
        const tokenId = getTokenIdFor({ tokenType, maturity, strikePrice });

        expect(
          await instance.callStatic['tokenIdFor(uint8,uint64,int128)'](
            tokenType,
            maturity,
            strikePrice,
          ),
        ).to.equal(tokenId);
      });
    });

    describe('#_parametersFor', function () {
      it('returns parameters derived from tokenId', async function () {
        const tokenType = TokenType.LongCall;
        const maturity = ethers.BigNumber.from(
          Math.floor(new Date().getTime() / 1000),
        );
        const strikePrice = fixedFromFloat(Math.random() * 1000);
        const tokenId = getTokenIdFor({ tokenType, maturity, strikePrice });

        expect(
          await instance.callStatic['parametersFor(uint256)'](tokenId),
        ).to.deep.equal([tokenType, maturity, strikePrice]);
      });
    });
  });
});
