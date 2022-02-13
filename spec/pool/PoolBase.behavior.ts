import { ethers } from 'hardhat';
import { expect } from 'chai';
import { describeBehaviorOfERC1155Enumerable } from '@solidstate/spec';
import { IPool, ERC20Mock } from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  formatTokenId,
  fixedFromFloat,
  fixedToNumber,
  TokenType,
} from '@premia/utils';

import {
  FEE_APY,
  ONE_YEAR,
  getLong,
  getShort,
  getStrike,
  getMaturity,
  parseOption,
  parseBase,
  parseUnderlying,
  formatBase,
  formatUnderlying,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolBaseBehaviorArgs {
  deploy: () => Promise<IPool>;
  getUnderlying: () => Promise<ERC20Mock>;
  getBase: () => Promise<ERC20Mock>;
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
  {
    deploy,
    getUnderlying,
    getBase,
    getPoolUtil,
    mintERC1155,
    burnERC1155,
  }: PoolBaseBehaviorArgs,
  skips?: string[],
) {
  describe('::PoolBase', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let instance: IPool;
    let underlying: ERC20Mock;
    let base: ERC20Mock;
    let p: PoolUtil;

    before(async () => {
      [owner, buyer, lp1, lp2] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      // TODO: don't
      p = await getPoolUtil();
      underlying = await getUnderlying();
      base = await getBase();
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
      describe('call option', () => {
        it('transfers user TVL on free liquidity transfer', async () => {
          const isCall = true;
          const amount = parseUnderlying('1');

          const sender = lp1;
          const receiver = lp2;

          const freeLiquidityTokenId = getFreeLiqTokenId(isCall);

          await p.depositLiquidity(sender, amount, isCall);

          await ethers.provider.send('evm_increaseTime', [24 * 3600 + 1]);

          const collateralAmountTransferred = amount.div(ethers.constants.Two);

          const { underlyingTVL: oldSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { underlyingTVL: oldReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance
            .connect(sender)
            .safeTransferFrom(
              sender.address,
              receiver.address,
              freeLiquidityTokenId,
              collateralAmountTransferred,
              '0x',
            );

          const { underlyingTVL: newSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { underlyingTVL: newReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newSenderTVL).to.equal(
            oldSenderTVL.sub(collateralAmountTransferred),
          );
          expect(newReceiverTVL).to.equal(
            oldReceiverTVL.add(collateralAmountTransferred),
          );
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });

        it('does not transfer TVL on reserved liquidity transfer');

        it('transfers user TVL on short token transfer', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const sender = lp1;
          const receiver = lp2;

          await p.purchaseOption(
            sender,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          await ethers.provider.send('evm_increaseTime', [24 * 3600 + 1]);

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          const contractSizeTransferred = amount.div(ethers.constants.Two);

          const { underlyingTVL: oldSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { underlyingTVL: oldReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance
            .connect(sender)
            .safeTransferFrom(
              sender.address,
              receiver.address,
              shortTokenId,
              contractSizeTransferred,
              '0x',
            );

          const { underlyingTVL: newSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { underlyingTVL: newReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newSenderTVL).to.equal(
            oldSenderTVL.sub(contractSizeTransferred),
          );
          expect(newReceiverTVL).to.equal(
            oldReceiverTVL.add(contractSizeTransferred),
          );
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });

        it('does not transfer TVL on long token transfer', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const sender = buyer;
          const receiver = lp2;

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          const contractSizeTransferred = amount.div(ethers.constants.Two);

          const { underlyingTVL: oldSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { underlyingTVL: oldReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance
            .connect(sender)
            .safeTransferFrom(
              sender.address,
              receiver.address,
              longTokenId,
              contractSizeTransferred,
              '0x',
            );

          const { underlyingTVL: newSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { underlyingTVL: newReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newSenderTVL).to.equal(oldSenderTVL);
          expect(newReceiverTVL).to.equal(oldReceiverTVL);
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });
      });

      describe('put option', () => {
        it('transfers user TVL on free liquidity transfer', async () => {
          const isCall = false;
          const amount = parseUnderlying('1');

          const sender = lp1;
          const receiver = lp2;

          const freeLiquidityTokenId = getFreeLiqTokenId(isCall);

          await p.depositLiquidity(sender, amount, isCall);

          await ethers.provider.send('evm_increaseTime', [24 * 3600 + 1]);

          const collateralAmountTransferred = amount.div(ethers.constants.Two);

          const { baseTVL: oldSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { baseTVL: oldReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance
            .connect(sender)
            .safeTransferFrom(
              sender.address,
              receiver.address,
              freeLiquidityTokenId,
              collateralAmountTransferred,
              '0x',
            );

          const { baseTVL: newSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { baseTVL: newReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newSenderTVL).to.equal(
            oldSenderTVL.sub(collateralAmountTransferred),
          );
          expect(newReceiverTVL).to.equal(
            oldReceiverTVL.add(collateralAmountTransferred),
          );
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });

        it('does not transfer TVL on reserved liquidity transfer');

        it('transfers user TVL on short token transfer', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const sender = lp1;
          const receiver = lp2;

          await p.depositLiquidity(
            sender,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          await base.mint(buyer.address, parseBase('100000'));
          await base
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_increaseTime', [24 * 3600 + 1]);

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          const contractSizeTransferred = amount.div(ethers.constants.Two);
          const collateralAmountTransferred = parseBase(
            formatUnderlying(contractSizeTransferred),
          ).mul(fixedToNumber(strike64x64));

          const { baseTVL: oldSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { baseTVL: oldReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance
            .connect(sender)
            .safeTransferFrom(
              sender.address,
              receiver.address,
              shortTokenId,
              contractSizeTransferred,
              '0x',
            );

          const { baseTVL: newSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { baseTVL: newReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newSenderTVL).to.equal(
            oldSenderTVL.sub(collateralAmountTransferred),
          );
          expect(newReceiverTVL).to.equal(
            oldReceiverTVL.add(collateralAmountTransferred),
          );
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });

        it('does not transfer TVL on long token transfer', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const sender = buyer;
          const receiver = lp2;

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          const contractSizeTransferred = amount.div(ethers.constants.Two);

          const { baseTVL: oldSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { baseTVL: oldReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance
            .connect(sender)
            .safeTransferFrom(
              sender.address,
              receiver.address,
              longTokenId,
              contractSizeTransferred,
              '0x',
            );

          const { baseTVL: newSenderTVL } =
            await instance.callStatic.getUserTVL(sender.address);
          const { baseTVL: newReceiverTVL } =
            await instance.callStatic.getUserTVL(receiver.address);
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newSenderTVL).to.equal(oldSenderTVL);
          expect(newReceiverTVL).to.equal(oldReceiverTVL);
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });
      });

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
