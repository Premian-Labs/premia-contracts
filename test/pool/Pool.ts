import { expect } from 'chai';
import { describeBehaviorOfPool } from './Pool.behavior';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Pool, PoolMock, PoolMock__factory } from '../../typechain';

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
    instance = await new PoolMock__factory(owner).deploy();
  });

  describeBehaviorOfPool(
    {
      deploy: async () => instance,
      mintERC20: (recipient, amount) =>
        instance['mint(address,uint256)'](recipient, amount),
      burnERC20: (recipient, amount) =>
        instance['burn(address,uint256)'](recipient, amount),
      mintERC1155: (recipient, tokenId, amount) =>
        instance['mint(address,uint256,uint256)'](recipient, tokenId, amount),
      burnERC1155: (recipient, tokenId, amount) =>
        instance['burn(address,uint256,uint256)'](recipient, tokenId, amount),
      supply: BigNumber.from(0),
      name: '',
      symbol: '',
      decimals: 0,
    },
    ['#supportsInterface'],
  );

  describe('__internal', function () {
    describe('#_tokenIdFor', function () {
      it('returns concatenation of maturity and strikePrice', async function () {
        const tokenType = ethers.constants.One;
        const maturity = ethers.BigNumber.from(
          Math.floor(new Date().getTime() / 1000),
        );
        const strikePrice = fixedFromFloat(Math.random() * 1000);
        const tokenId = ethers.utils.hexConcat([
          ethers.utils.hexZeroPad(tokenType.toString(), 1),
          ethers.utils.hexZeroPad('0', 7),
          ethers.utils.hexZeroPad(maturity.toString(), 8),
          ethers.utils.hexZeroPad(strikePrice.toString(), 16),
        ]);

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
        const tokenType = ethers.constants.One;
        const maturity = ethers.BigNumber.from(
          Math.floor(new Date().getTime() / 1000),
        );
        const strikePrice = fixedFromFloat(Math.random() * 1000);
        const tokenId = ethers.utils.hexConcat([
          ethers.utils.hexZeroPad(tokenType.toString(), 1),
          ethers.utils.hexZeroPad('0', 7),
          ethers.utils.hexZeroPad(maturity.toString(), 8),
          ethers.utils.hexZeroPad(strikePrice.toString(), 16),
        ]);

        expect(
          await instance.callStatic['parametersFor(uint256)'](tokenId),
        ).to.deep.equal([tokenType.toNumber(), maturity, strikePrice]);
      });
    });
  });
});
