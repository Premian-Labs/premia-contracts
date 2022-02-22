import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  FeeDiscount,
  FeeDiscount__factory,
  IPool,
  Proxy__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';

import { describeBehaviorOfPoolBase } from '../../spec/pool/PoolBase.behavior';
import { describeBehaviorOfPoolExercise } from '../../spec/pool/PoolExercise.behavior';
import { describeBehaviorOfPoolIO } from '../../spec/pool/PoolIO.behavior';
import { describeBehaviorOfPoolSettings } from '../../spec/pool/PoolSettings.behavior';
import { describeBehaviorOfPoolView } from '../../spec/pool/PoolView.behavior';
import { describeBehaviorOfPoolWrite } from '../../spec/pool/PoolWrite.behavior';
import { describeBehaviorOfPoolSell } from '../../spec/pool/PoolSell.behavior';
import chai, { expect } from 'chai';
import { increaseTimestamp } from '../utils/evm';
import { parseUnits } from 'ethers/lib/utils';
import {
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  formatOption,
  formatOptionToNb,
  getExerciseValue,
  parseOption,
  parseUnderlying,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
  getStrike,
  getMaturity,
  getMaxCost,
  PoolUtil,
} from './PoolUtil';
import chaiAlmost from 'chai-almost';
import { describeBehaviorOfProxy } from '@solidstate/spec';
import {
  fixedFromFloat,
  fixedToNumber,
  getOptionTokenIds,
} from '@premia/utils';
import {
  createUniswap,
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
} from '../utils/uniswap';

chai.use(chaiAlmost(0.02));

describe('PoolProxy', function () {
  let snapshotId: number;

  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let buyer: SignerWithAddress;
  let thirdParty: SignerWithAddress;
  let feeReceiver: SignerWithAddress;
  let uniswap: IUniswap;

  let xPremia: ERC20Mock;
  let feeDiscount: FeeDiscount;

  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let instance: IPool;
  let poolWeth: IPool;
  let p: PoolUtil;
  let premia: ERC20Mock;

  const spotPrice = 2000;

  before(async function () {
    [owner, lp1, lp2, buyer, thirdParty, feeReceiver] =
      await ethers.getSigners();

    const erc20Factory = new ERC20Mock__factory(owner);

    premia = await erc20Factory.deploy('PREMIA', 18);
    xPremia = await erc20Factory.deploy('xPREMIA', 18);

    const feeDiscountImpl = await new FeeDiscount__factory(owner).deploy(
      xPremia.address,
    );
    const feeDiscountProxy = await new ProxyUpgradeableOwnable__factory(
      owner,
    ).deploy(feeDiscountImpl.address);
    feeDiscount = FeeDiscount__factory.connect(feeDiscountProxy.address, owner);

    uniswap = await createUniswap(owner);

    p = await PoolUtil.deploy(
      owner,
      premia.address,
      spotPrice,
      feeReceiver,
      feeDiscount.address,
      uniswap.factory.address,
      uniswap.weth.address,
    );

    poolWeth = p.poolWeth;

    base = p.base;
    underlying = p.underlying;

    instance = p.pool;

    // mint ERC20 tokens and set approvals

    for (const signer of await ethers.getSigners()) {
      await base.mint(signer.address, ethers.utils.parseEther('1000000000'));
      await base
        .connect(signer)
        .approve(instance.address, ethers.constants.MaxUint256);

      await underlying.mint(
        signer.address,
        ethers.utils.parseEther('1000000000'),
      );
      await underlying
        .connect(signer)
        .approve(instance.address, ethers.constants.MaxUint256);
    }

    // setup Uniswap

    const pairBase = await createUniswapPair(
      owner,
      uniswap.factory,
      base.address,
      uniswap.weth.address,
    );

    const pairUnderlying = await createUniswapPair(
      owner,
      uniswap.factory,
      underlying.address,
      uniswap.weth.address,
    );

    await depositUniswapLiquidity(
      lp2,
      uniswap.weth.address,
      pairBase,
      (await pairBase.token0()) === uniswap.weth.address
        ? ethers.utils.parseUnits('100', 18)
        : ethers.utils.parseUnits('100000', DECIMALS_BASE),
      (await pairBase.token1()) === uniswap.weth.address
        ? ethers.utils.parseUnits('100', 18)
        : ethers.utils.parseUnits('100000', DECIMALS_BASE),
    );

    await depositUniswapLiquidity(
      lp2,
      uniswap.weth.address,
      pairUnderlying,
      (await pairUnderlying.token0()) === uniswap.weth.address
        ? ethers.utils.parseUnits('100', 18)
        : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
      (await pairUnderlying.token1()) === uniswap.weth.address
        ? ethers.utils.parseUnits('100', 18)
        : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
    );
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describeBehaviorOfProxy({
    deploy: async () => Proxy__factory.connect(instance.address, owner),
    implementationFunction: 'getPoolSettings()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPoolBase(
    {
      deploy: async () => instance,
      getBase: async () => base,
      getUnderlying: async () => underlying,
      getPoolUtil: async () => p,
      // mintERC1155: (recipient, tokenId, amount) =>
      //   instance['mint(address,uint256,uint256)'](recipient, tokenId, amount),
      // burnERC1155: (recipient, tokenId, amount) =>
      //   instance['burn(address,uint256,uint256)'](recipient, tokenId, amount),
      mintERC1155: undefined as any,
      burnERC1155: undefined as any,
    },
    // TODO: don't skip
    ['::ERC1155Enumerable'],
  );

  describeBehaviorOfPoolExercise({
    deploy: async () => instance,
    getBase: async () => base,
    getUnderlying: async () => underlying,
    getFeeDiscount: async () => feeDiscount,
    getXPremia: async () => xPremia,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolIO({
    deploy: async () => instance,
    getBase: async () => base,
    getUnderlying: async () => underlying,
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
  });

  describeBehaviorOfPoolSell({
    deploy: async () => instance,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolSettings({
    deploy: async () => instance,
    getProtocolOwner: async () => owner,
    getNonProtocolOwner: async () => thirdParty,
  });

  describeBehaviorOfPoolView({
    deploy: async () => instance,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolWrite({
    deploy: async () => instance,
    getBase: async () => base,
    getUnderlying: async () => underlying,
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
  });
});
