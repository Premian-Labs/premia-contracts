import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool, PoolMock, PoolMock__factory } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fixedFromFloat, getOptionTokenIds } from '@premia/utils';
import { parseUnderlying, PoolUtil } from '../../test/pool/PoolUtil';

interface PoolSellBehaviorArgs {
  deploy: () => Promise<IPool>;
  getPoolUtil: () => Promise<PoolUtil>;
}

export function describeBehaviorOfPoolSell({
  deploy,
  getPoolUtil,
}: PoolSellBehaviorArgs) {
  describe('::PoolSell', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let thirdParty: SignerWithAddress;
    let feeReceiver: SignerWithAddress;
    let p: PoolUtil;

    let instance: IPool;
    let poolMock: PoolMock;

    before(async () => {
      [owner, buyer, lp1, lp2, thirdParty] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      p = await getPoolUtil();
      feeReceiver = p.feeReceiver;
      poolMock = PoolMock__factory.connect(p.pool.address, owner);
    });

    describe('#setPoolCaps', () =>
      it('should updates pool caps if owner', async () => {
        expect(
          instance.connect(lp1).setPoolCaps('123', '456'),
        ).to.be.revertedWith('Not protocol owner');

        await instance.connect(owner).setPoolCaps('123', '456');
        const caps = await instance.getCapAmounts();
        expect(caps.callTokenCapAmount).to.eq('456');
        expect(caps.putTokenCapAmount).to.eq('123');
      }));

    describe('#getBuyers', () => {
      it('should return list of underwriters with buyback enabled', async () => {
        const maturity = await p.getMaturity(10);
        const isCall = true;
        const spotPrice = 2000;
        const strike64x64 = fixedFromFloat(p.getStrike(isCall, spotPrice));

        const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

        await poolMock.mint(lp1.address, tokenId.short, parseUnderlying('1'));
        await poolMock.mint(lp2.address, tokenId.short, parseUnderlying('2'));
        await poolMock.mint(
          thirdParty.address,
          tokenId.short,
          parseUnderlying('3'),
        );
        await poolMock.mint(buyer.address, tokenId.short, parseUnderlying('4'));
        await poolMock.mint(
          feeReceiver.address,
          tokenId.short,
          parseUnderlying('5'),
        );

        await instance.connect(lp2).setBuyBackEnabled(true);
        await instance.connect(buyer).setBuyBackEnabled(true);

        const result = await instance.getBuyers(tokenId.short);
        expect(result.buyers).to.deep.eq([lp2.address, buyer.address]);
        expect(result.amounts).to.deep.eq([
          parseUnderlying('2'),
          parseUnderlying('4'),
        ]);
      });
    });
  });
}
