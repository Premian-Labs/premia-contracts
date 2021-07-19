import { expect } from 'chai';
import { describeBehaviorOfPool } from './Pool.behavior';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  OptionMath,
  OptionMath__factory,
  PoolMock,
  PoolMock__factory,
} from '../../typechain';
import { formatTokenId, TokenType } from '../utils/math';
import { ONE_ADDRESS } from '../utils/constants';

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

  let optionMath: OptionMath;
  let instance: PoolMock;

  before(async function () {
    [owner] = await ethers.getSigners();
  });

  beforeEach(async function () {
    optionMath = await new OptionMath__factory(owner).deploy();
    instance = await new PoolMock__factory(owner).deploy(
      ethers.constants.AddressZero,
      ONE_ADDRESS,
      ethers.constants.AddressZero,
      fixedFromFloat(0.01),
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
    describe('#_formatTokenId', function () {
      it('returns concatenation of maturity and strikePrice', async function () {
        const tokenType = TokenType.LongCall;
        const maturity = ethers.BigNumber.from(
          Math.floor(new Date().getTime() / 1000),
        );
        const strike64x64 = fixedFromFloat(Math.random() * 1000);
        const tokenId = formatTokenId({ tokenType, maturity, strike64x64 });

        expect(
          await instance.callStatic['formatTokenId(uint8,uint64,int128)'](
            tokenType,
            maturity,
            strike64x64,
          ),
        ).to.equal(tokenId);
      });
    });

    describe('#_parseTokenId', function () {
      it('returns parameters derived from tokenId', async function () {
        const tokenType = TokenType.LongCall;
        const maturity = ethers.BigNumber.from(
          Math.floor(new Date().getTime() / 1000),
        );
        const strike64x64 = fixedFromFloat(Math.random() * 1000);
        const tokenId = formatTokenId({ tokenType, maturity, strike64x64 });

        expect(
          await instance.callStatic['parseTokenId(uint256)'](tokenId),
        ).to.deep.equal([tokenType, maturity, strike64x64]);
      });
    });
  });
});
