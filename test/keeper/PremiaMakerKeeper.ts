import chai, { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock__factory,
  PoolMock__factory,
  PremiaMakerKeeper,
  PremiaMakerKeeper__factory,
  UniswapV2Pair,
} from '../../typechain';
import { DECIMALS_BASE, DECIMALS_UNDERLYING, PoolUtil } from '../pool/PoolUtil';
import { ZERO_ADDRESS } from '../utils/constants';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import {
  createUniswap,
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
} from '../utils/uniswap';
import { deployV1, IPremiaContracts } from '../../scripts/utils/deployV1';
import chaiAlmost from 'chai-almost';
import { bnToNumber } from '../utils/math';

chai.use(chaiAlmost(0.01));

describe('PremiaMakerKeeper', () => {
  let owner: SignerWithAddress;
  let lp: SignerWithAddress;
  let treasury: SignerWithAddress;
  let keeper: PremiaMakerKeeper;
  let contracts: IPremiaContracts;
  let uniswap: IUniswap;
  let p: PoolUtil;
  let pairBase: UniswapV2Pair;
  let pairUnderlying: UniswapV2Pair;

  const spotPrice = 2000;

  beforeEach(async () => {
    [owner, lp, treasury] = await ethers.getSigners();

    contracts = await deployV1(owner, treasury.address, true);

    p = await PoolUtil.deploy(
      owner,
      (
        await new ERC20Mock__factory(owner).deploy('PREMIA', 18)
      ).address,
      spotPrice,
      contracts.premiaMaker,
      ZERO_ADDRESS,
    );
    keeper = await new PremiaMakerKeeper__factory(owner).deploy(
      contracts.premiaMaker.address,
      p.premiaDiamond.address,
    );

    uniswap = await createUniswap(owner, contracts.premia, undefined);

    pairBase = await createUniswapPair(
      owner,
      uniswap.factory,
      p.base.address,
      uniswap.weth.address,
    );

    pairUnderlying = await createUniswapPair(
      owner,
      uniswap.factory,
      p.underlying.address,
      uniswap.weth.address,
    );

    await depositUniswapLiquidity(
      lp,
      uniswap.weth.address,
      pairBase,
      (await pairBase.token0()) === uniswap.weth.address
        ? parseUnits('100', 18)
        : parseUnits('100000', DECIMALS_BASE),
      (await pairBase.token1()) === uniswap.weth.address
        ? parseUnits('100', 18)
        : parseUnits('100000', DECIMALS_BASE),
    );

    await depositUniswapLiquidity(
      lp,
      uniswap.weth.address,
      pairUnderlying,
      (await pairUnderlying.token0()) === uniswap.weth.address
        ? parseUnits('100', 18)
        : parseUnits('100', DECIMALS_UNDERLYING),
      (await pairUnderlying.token1()) === uniswap.weth.address
        ? parseUnits('100', 18)
        : parseUnits('100', DECIMALS_UNDERLYING),
    );

    await depositUniswapLiquidity(
      lp,
      uniswap.weth.address,
      uniswap.premiaWeth as UniswapV2Pair,
      parseEther('1000'),
      parseEther('1000'),
    );

    await contracts.premiaMaker.addWhitelistedRouters([uniswap.router.address]);
  });

  it('should successfully detect if there is work to do or not', async () => {
    // No work to do
    let result = await keeper.checkUpkeep(
      ethers.utils.defaultAbiCoder.encode(
        ['address'],
        [uniswap.router.address],
      ),
    );

    expect(result.upkeepNeeded).to.be.false;

    // Still no work to do because amount under min value threshold
    const poolMock = PoolMock__factory.connect(p.pool.address, owner);
    await poolMock.mint(
      contracts.premiaMaker.address,
      p.getReservedLiqTokenId(true),
      parseUnits('0.001', DECIMALS_UNDERLYING),
    );

    result = await keeper.checkUpkeep(
      ethers.utils.defaultAbiCoder.encode(
        ['address'],
        [uniswap.router.address],
      ),
    );

    expect(result.upkeepNeeded).to.be.false;

    // Work to do for underlying because now above threshold
    await poolMock.mint(
      contracts.premiaMaker.address,
      p.getReservedLiqTokenId(true),
      parseUnits('100', DECIMALS_UNDERLYING),
    );

    result = await keeper.checkUpkeep(
      ethers.utils.defaultAbiCoder.encode(
        ['address'],
        [uniswap.router.address],
      ),
    );

    expect(result.upkeepNeeded).to.be.true;

    let decodedData = ethers.utils.defaultAbiCoder.decode(
      ['address', 'address', 'address[]'],
      result.performData,
    );

    expect(decodedData[0]).to.eq(p.pool.address);
    expect(decodedData[1]).to.eq(uniswap.router.address);
    expect(decodedData[2].length).to.eq(1);
    expect(decodedData[2][0]).to.eq(p.underlying.address);

    // Work to do for underlying + base
    await poolMock.mint(
      contracts.premiaMaker.address,
      p.getReservedLiqTokenId(false),
      parseUnits('10000', DECIMALS_BASE),
    );

    result = await keeper.checkUpkeep(
      ethers.utils.defaultAbiCoder.encode(
        ['address'],
        [uniswap.router.address],
      ),
    );

    expect(result.upkeepNeeded).to.be.true;

    decodedData = ethers.utils.defaultAbiCoder.decode(
      ['address', 'address', 'address[]'],
      result.performData,
    );

    expect(decodedData[0]).to.eq(p.pool.address);
    expect(decodedData[1]).to.eq(uniswap.router.address);
    expect(decodedData[2].length).to.eq(2);
    expect(decodedData[2][0]).to.eq(p.base.address);
    expect(decodedData[2][1]).to.eq(p.underlying.address);
  });

  it('should successfully perform upkeep', async () => {
    const poolMock = PoolMock__factory.connect(p.pool.address, owner);
    await p.underlying.mint(
      p.pool.address,
      parseUnits('100', DECIMALS_UNDERLYING),
    );
    await p.base.mint(p.pool.address, parseUnits('10000', DECIMALS_BASE));

    await poolMock.mint(
      contracts.premiaMaker.address,
      p.getReservedLiqTokenId(true),
      parseUnits('100', DECIMALS_UNDERLYING),
    );
    await poolMock.mint(
      contracts.premiaMaker.address,
      p.getReservedLiqTokenId(false),
      parseUnits('10000', DECIMALS_BASE),
    );

    const result = await keeper.checkUpkeep(
      ethers.utils.defaultAbiCoder.encode(
        ['address'],
        [uniswap.router.address],
      ),
    );

    expect(
      bnToNumber(await contracts.premia.balanceOf(contracts.xPremia.address)),
    ).to.eq(0);
    await keeper.performUpkeep(result.performData);
    expect(
      bnToNumber(await contracts.premia.balanceOf(contracts.xPremia.address)),
    ).to.almost(49.07);
  });
});
