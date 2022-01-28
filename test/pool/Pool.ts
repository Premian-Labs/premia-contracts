import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  OptionMath,
  OptionMath__factory,
  PoolMock,
  PoolMock__factory,
} from '../../typechain';
import { ONE_ADDRESS } from '../utils/constants';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  TokenType,
} from '@premia/utils';

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
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      ONE_ADDRESS,
      ethers.constants.AddressZero,
      fixedFromFloat(0.01),
      fixedFromFloat(0.01),
    );
  });

  // describeBehaviorOfPoolBase(
  //   {
  //     deploy: async () => instance,
  //     getPoolUtil: async () => p,
  //     mintERC1155: (recipient, tokenId, amount) =>
  //       instance['mint(address,uint256,uint256)'](recipient, tokenId, amount),
  //     burnERC1155: (recipient, tokenId, amount) =>
  //       instance['burn(address,uint256,uint256)'](recipient, tokenId, amount),
  //   },
  //   ['#supportsInterface'],
  // );

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

        const tokenData = await instance.callStatic.parseTokenId(tokenId);

        expect(tokenData[0]).to.eq(tokenType);
        expect(tokenData[1]).to.eq(maturity);
        expect(tokenData[2]).to.eq(strike64x64);
      });
    });

    describe('#_getPriceUpdateAfter', () => {
      const ONE_HOUR = 3600;
      const SEQUENCE_DURATION = ONE_HOUR * 256;

      const BASE_TIMESTAMP = 1750 * SEQUENCE_DURATION;

      // first timestamp of sequence
      const SEQUENCE_START = BASE_TIMESTAMP;
      const SEQUENCE_MID = BASE_TIMESTAMP + ONE_HOUR * 128;
      // first timestamp of last bucket of sequence
      const SEQUENCE_END = BASE_TIMESTAMP + ONE_HOUR * 256;

      const PRICE = 1234;

      const setPriceUpdate = async (timestamp: number, price: number) => {
        await instance.setPriceUpdate(timestamp, fixedFromFloat(price));
      };

      const getPriceAfter = async (timestamp: number) => {
        return fixedToNumber(await instance.getPriceUpdateAfter(timestamp));
      };

      it('returns price update stored at beginning of sequence', async () => {
        const timestamp = SEQUENCE_START;

        await setPriceUpdate(timestamp, PRICE);

        // check timestamp in future bucket

        expect(await getPriceAfter(timestamp + ONE_HOUR)).not.to.eq(PRICE);

        // check timestamps in same bucket

        expect(await getPriceAfter(timestamp)).to.eq(PRICE);
        expect(await getPriceAfter(timestamp + ONE_HOUR - 1)).to.eq(PRICE);

        // check timestamps in previous bucket

        expect(await getPriceAfter(timestamp - 1)).to.eq(PRICE);
        expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(PRICE);

        // check timestamps earlier in same sequence

        expect(await getPriceAfter(timestamp - SEQUENCE_DURATION / 4)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_START)).to.eq(PRICE);

        // check timestamps in previous sequence

        expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );

        // check timestamps in very old sequence

        expect(
          await getPriceAfter(SEQUENCE_START - SEQUENCE_DURATION * 3),
        ).to.eq(PRICE);
        expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_DURATION * 3)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_DURATION * 3)).to.eq(
          PRICE,
        );
      });

      it('returns price update stored mid sequence', async () => {
        const timestamp = SEQUENCE_MID;

        await setPriceUpdate(timestamp, PRICE);

        // check timestamp in future bucket

        expect(await getPriceAfter(timestamp + ONE_HOUR)).not.to.eq(PRICE);

        // check timestamps in same bucket

        expect(await getPriceAfter(timestamp)).to.eq(PRICE);
        expect(await getPriceAfter(timestamp + ONE_HOUR - 1)).to.eq(PRICE);

        // check timestamps in previous bucket

        expect(await getPriceAfter(timestamp - 1)).to.eq(PRICE);
        expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(PRICE);

        // check timestamps earlier in same sequence

        expect(await getPriceAfter(timestamp - SEQUENCE_DURATION / 4)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_START)).to.eq(PRICE);

        // check timestamps in previous sequence

        expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );

        // check timestamps in very old sequence

        expect(
          await getPriceAfter(SEQUENCE_START - SEQUENCE_DURATION * 3),
        ).to.eq(PRICE);
        expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_DURATION * 3)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_DURATION * 3)).to.eq(
          PRICE,
        );
      });

      it('returns price update stored at end of sequence', async () => {
        const timestamp = SEQUENCE_END;

        await setPriceUpdate(timestamp, PRICE);

        // check timestamp in future bucket

        expect(await getPriceAfter(timestamp + ONE_HOUR)).not.to.eq(PRICE);

        // check timestamps in same bucket

        expect(await getPriceAfter(timestamp)).to.eq(PRICE);
        expect(await getPriceAfter(timestamp + ONE_HOUR - 1)).to.eq(PRICE);

        // check timestamps in previous bucket

        expect(await getPriceAfter(timestamp - 1)).to.eq(PRICE);
        expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(PRICE);

        // check timestamps earlier in same sequence

        expect(await getPriceAfter(timestamp - SEQUENCE_DURATION / 4)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_START)).to.eq(PRICE);

        // check timestamps in previous sequence

        expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_DURATION)).to.eq(
          PRICE,
        );

        // check timestamps in very old sequence

        expect(
          await getPriceAfter(SEQUENCE_START - SEQUENCE_DURATION * 3),
        ).to.eq(PRICE);
        expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_DURATION * 3)).to.eq(
          PRICE,
        );
        expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_DURATION * 3)).to.eq(
          PRICE,
        );
      });

      it('should return the first price update available', async () => {
        let { timestamp } = await ethers.provider.getBlock('latest');
        timestamp = (Math.floor(timestamp / 3600 / 256) - 1) * 3600 * 256;

        let bucket = Math.floor(timestamp / 3600);

        let offset = bucket & 255;
        expect(offset).to.eq(0);

        await setPriceUpdate(timestamp - ONE_HOUR * 10, 1);
        await setPriceUpdate(timestamp - ONE_HOUR * 2, 5);

        await setPriceUpdate(timestamp, 10);

        await setPriceUpdate(timestamp + ONE_HOUR * 50, 20);
        await setPriceUpdate(timestamp + ONE_HOUR * 255, 30);

        expect(await getPriceAfter(timestamp - ONE_HOUR * 20)).to.eq(1);
        expect(await getPriceAfter(timestamp - ONE_HOUR * 5)).to.eq(5);
        expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(10);
        expect(await getPriceAfter(timestamp)).to.eq(10);
        expect(await getPriceAfter(timestamp + ONE_HOUR)).to.eq(20);
        expect(await getPriceAfter(timestamp + ONE_HOUR * 50)).to.eq(20);
        expect(await getPriceAfter(timestamp + ONE_HOUR * 51)).to.eq(30);
      });
    });
  });

  describe('liquidity queue', () => {
    it('should add/remove from queue properly', async () => {
      let queue: number[] = [];

      const formatAddress = (value: number) => {
        return ethers.utils.hexZeroPad(ethers.utils.hexlify(value), 20);
      };
      const removeAddress = async (value: number) => {
        await instance.removeUnderwriter(formatAddress(value), true);
        queue = queue.filter((el) => el !== value);
        expect(await instance.getUnderwriter()).to.eq(
          formatAddress(queue.length ? queue[0] : 0),
        );
      };
      const addAddress = async (value: number) => {
        await instance.addUnderwriter(formatAddress(value), true);

        if (!queue.includes(value)) {
          queue.push(value);
        }

        expect(await instance.getUnderwriter()).to.eq(formatAddress(queue[0]));
      };

      let i = 1;
      while (i <= 9) {
        await addAddress(i);
        i++;
      }

      await removeAddress(3);
      await removeAddress(5);
      await addAddress(3);
      await addAddress(3);
      await addAddress(3);
      await removeAddress(1);
      await removeAddress(6);
      await removeAddress(6);
      await removeAddress(9);
      await addAddress(3);
      await addAddress(3);
      await addAddress(9);
      await addAddress(5);
      await addAddress(queue[0]);
      await addAddress(queue[0]);
      await addAddress(queue[queue.length - 1]);
      await addAddress(queue[queue.length - 1]);
      await removeAddress(queue[queue.length - 1]);
      await removeAddress(queue[queue.length - 1]);

      while (queue.length) {
        await removeAddress(queue[0]);
      }

      expect(await instance.getUnderwriter()).to.eq(
        ethers.constants.AddressZero,
      );
    });
  });
});
