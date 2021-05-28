import { expect } from 'chai';
import {
  describeBehaviorOfERC1155Enumerable,
  describeBehaviorOfERC20,
} from '@solidstate/spec';
import {
  ERC20Mock,
  ERC20Mock__factory,
  Pair,
  Pair__factory,
  Pool,
  Pool__factory,
} from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

interface PoolBehaviorArgs {
  deploy: () => Promise<Pool>;
  mintERC20: (
    address: string,
    amount: BigNumber,
  ) => Promise<ContractTransaction>;
  burnERC20: (
    address: string,
    amount: BigNumber,
  ) => Promise<ContractTransaction>;
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
  name: string;
  symbol: string;
  decimals: number;
  supply: BigNumber;
}

export function describeBehaviorOfPool(
  {
    deploy,
    mintERC20,
    burnERC20,
    mintERC1155,
    burnERC1155,
    name,
    symbol,
    decimals,
    supply,
  }: PoolBehaviorArgs,
  skips?: string[],
) {
  describe('::Pool', function () {
    let deployer: SignerWithAddress;
    let instance: Pool;
    let pair: Pair;
    let asset0: ERC20Mock;
    let asset1: ERC20Mock;

    before(async () => {
      [deployer] = await ethers.getSigners();
    });

    beforeEach(async function () {
      instance = await deploy();
      pair = Pair__factory.connect(await instance.getPair(), deployer);
      asset0 = ERC20Mock__factory.connect(await pair.asset0(), deployer);
      asset1 = ERC20Mock__factory.connect(await pair.asset1(), deployer);
    });

    describeBehaviorOfERC20(
      {
        deploy: async () => instance,
        mint: mintERC20,
        burn: burnERC20,
        name,
        symbol,
        decimals,
        supply,
      },
      skips,
    );

    describeBehaviorOfERC1155Enumerable(
      {
        deploy: async () => instance,
        mint: mintERC1155,
        burn: burnERC1155,
      },
      skips,
    );

    describe('#getPair', function () {
      it('returns pair address', async () => {
        const pairAddr = await instance.getPair();
        expect(pairAddr).to.eq(pair.address);

        const pools = await pair.getPools();
        expect(pools[0]).to.eq(instance.address);
      });
    });

    describe('#getUnderlying', function () {
      it('returns underlying address', async () => {
        const pools = await pair.getPools();

        const callPool = Pool__factory.connect(pools[0], deployer);
        const putPool = Pool__factory.connect(pools[1], deployer);

        const callUnderlying = await callPool.getUnderlying();
        const putUnderlying = await putPool.getUnderlying();

        expect(callUnderlying).to.eq(asset1.address);
        expect(putUnderlying).to.eq(asset0.address);
      });
    });

    describe('#quote', function () {
      it('returns price for given option parameters');
    });

    describe('#deposit', function () {
      it('returns share tokens granted to sender', async () => {
        await asset1.approve(instance.address, ethers.constants.MaxUint256);
        await expect(() => instance.deposit('100')).to.changeTokenBalance(
          asset1,
          deployer,
          -100,
        );
        expect(await instance['balanceOf(address)'](deployer.address)).to.eq(
          100,
        );
      });

      it('todo');
    });

    describe('#withdraw', function () {
      it('returns underlying tokens withdrawn by sender');

      it('todo');
    });

    describe('#purchase', function () {
      it('todo');
    });

    describe('#exercise', function () {
      describe('(uint256,uint192,uint64)', function () {
        it('todo');
      });

      describe('(uint256,uint256)', function () {
        it('todo');
      });
    });
  });
}
