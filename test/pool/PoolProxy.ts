import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  FeeDiscount,
  FeeDiscount__factory,
  IPool,
  PoolMock,
  PoolMock__factory,
  Proxy__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';

import { describeBehaviorOfPoolBase } from '../../spec/pool/PoolBase.behavior';
import { describeBehaviorOfPoolExercise } from '../../spec/pool/PoolExercise.behavior';
import { describeBehaviorOfPoolIO } from '../../spec/pool/PoolIO.behavior';
import { describeBehaviorOfPoolSettings } from '../../spec/pool/PoolSettings.behavior';
import { describeBehaviorOfPoolView } from '../../spec/pool/PoolView.behavior';
import { describeBehaviorOfPoolWrite } from '../../spec/pool/PoolWrite.behavior';
import chai, { expect } from 'chai';
import { increaseTimestamp } from '../utils/evm';
import { parseUnits } from 'ethers/lib/utils';
import {
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
import { BigNumber } from 'ethers';
import { describeBehaviorOfProxy } from '@solidstate/spec';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
  TokenType,
} from '@premia/utils';
import { createUniswap, IUniswap } from '../utils/uniswap';

chai.use(chaiAlmost(0.02));

const oneMonth = 30 * 24 * 3600;

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

  let pool: IPool;
  let instance: IPool;
  let poolMock: PoolMock;
  let poolWeth: IPool;
  let p: PoolUtil;
  let premia: ERC20Mock;

  const underlyingFreeLiqToken = formatTokenId({
    tokenType: TokenType.UnderlyingFreeLiq,
    maturity: BigNumber.from(0),
    strike64x64: BigNumber.from(0),
  });
  const baseFreeLiqToken = formatTokenId({
    tokenType: TokenType.BaseFreeLiq,
    maturity: BigNumber.from(0),
    strike64x64: BigNumber.from(0),
  });

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

    pool = p.pool;
    poolMock = PoolMock__factory.connect(p.pool.address, owner);
    poolWeth = p.poolWeth;

    instance = p.pool;
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describeBehaviorOfProxy({
    deploy: async () => Proxy__factory.connect(p.pool.address, owner),
    implementationFunction: 'getPoolSettings()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPoolBase(
    {
      deploy: async () => instance,
      getUnderlying: async () => p.underlying,
      getBase: async () => p.base,
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
    getBase: async () => p.base,
    getUnderlying: async () => p.underlying,
    getFeeDiscount: async () => feeDiscount,
    getXPremia: async () => xPremia,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolIO({
    deploy: async () => instance,
    getBase: async () => p.base,
    getUnderlying: async () => p.underlying,
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
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
    getBase: async () => p.base,
    getUnderlying: async () => p.underlying,
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
  });
});
