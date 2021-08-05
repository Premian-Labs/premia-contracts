import {
  ERC20Mock,
  ERC20Mock__factory,
  IPool,
  IPool__factory,
  OptionMath__factory,
  PoolExercise__factory,
  PoolIO__factory,
  PremiaMining,
  PremiaMining__factory,
  PremiaMiningProxy__factory,
  PoolMock__factory,
  PoolView__factory,
  PoolWrite__factory,
  Premia,
  Premia__factory,
  ProxyManager__factory,
  WETH9,
  WETH9__factory,
} from '../../typechain';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from 'ethers';
import { increaseTimestamp } from '../utils/evm';
import { formatUnits, parseEther, parseUnits } from 'ethers/lib/utils';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { diamondCut } from '../../scripts/utils/diamond';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  TokenType,
} from '@premia/utils';

export const DECIMALS_BASE = 18;
export const DECIMALS_UNDERLYING = 8;
export const SYMBOL_BASE = 'SYMBOL_BASE';
export const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';
export const FEE = 0.01;
export const MIN_APY = 0.3;

interface PoolUtilArgs {
  premiaDiamond: Premia;
  pool: IPool;
  poolWeth: IPool;
  underlying: ERC20Mock;
  weth: WETH9;
  base: ERC20Mock;
  baseOracle: MockContract;
  underlyingOracle: MockContract;
  premiaMining: PremiaMining;
}

const ONE_DAY = 3600 * 24;

export function getTokenDecimals(isCall: boolean) {
  return isCall ? DECIMALS_UNDERLYING : DECIMALS_BASE;
}

export function parseOption(amount: string, isCall: boolean) {
  if (isCall) {
    return parseUnderlying(amount);
  } else {
    return parseBase(amount);
  }
}

export function parseUnderlying(amount: string) {
  return parseUnits(
    Number(amount).toFixed(DECIMALS_UNDERLYING),
    DECIMALS_UNDERLYING,
  );
}

export function parseBase(amount: string) {
  return parseUnits(Number(amount).toFixed(DECIMALS_BASE), DECIMALS_BASE);
}

export function formatOption(amount: BigNumberish, isCall: boolean) {
  if (isCall) {
    return formatUnderlying(amount);
  } else {
    return formatBase(amount);
  }
}

export function formatOptionToNb(amount: BigNumberish, isCall: boolean) {
  return Number(formatOption(amount, isCall));
}

export function formatUnderlying(amount: BigNumberish) {
  return formatUnits(amount, DECIMALS_UNDERLYING);
}

export function formatBase(amount: BigNumberish) {
  return formatUnits(amount, DECIMALS_BASE);
}

export function getExerciseValue(
  price: number,
  strike: number,
  amount: number,
  isCall: boolean,
) {
  if (isCall) {
    return ((price - strike) * amount) / price;
  } else {
    return (strike - price) * amount;
  }
}

export class PoolUtil {
  premiaDiamond: Premia;
  pool: IPool;
  poolWeth: IPool;
  underlying: ERC20Mock;
  weth: WETH9;
  base: ERC20Mock;
  baseOracle: MockContract;
  underlyingOracle: MockContract;
  premiaMining: PremiaMining;

  constructor(props: PoolUtilArgs) {
    this.premiaDiamond = props.premiaDiamond;
    this.pool = props.pool;
    this.poolWeth = props.poolWeth;
    this.underlying = props.underlying;
    this.weth = props.weth;
    this.base = props.base;
    this.baseOracle = props.baseOracle;
    this.underlyingOracle = props.underlyingOracle;
    this.premiaMining = props.premiaMining;
  }

  static async deploy(
    deployer: SignerWithAddress,
    premia: string,
    priceUnderlying: number,
    feeReceiver: string,
    premiaFeeDiscount: string,
  ) {
    const erc20Factory = new ERC20Mock__factory(deployer);

    const base = await erc20Factory.deploy(SYMBOL_BASE, DECIMALS_BASE);
    await base.deployed();
    let underlying = await erc20Factory.deploy(
      SYMBOL_UNDERLYING,
      DECIMALS_UNDERLYING,
    );
    await underlying.deployed();

    let weth;

    if ((network as any).config.forking?.enabled) {
      weth = WETH9__factory.connect(
        '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
        deployer,
      );
    } else {
      weth = await new WETH9__factory(deployer).deploy();
    }

    //

    const optionMath = await new OptionMath__factory(deployer).deploy();

    const premiaDiamond = await new Premia__factory(deployer).deploy();
    const poolDiamond = await new Premia__factory(deployer).deploy();

    //

    const premiaMiningImpl = await new PremiaMining__factory(deployer).deploy(
      premiaDiamond.address,
      premia,
    );

    const premiaMiningProxy = await new PremiaMiningProxy__factory(
      deployer,
    ).deploy(premiaMiningImpl.address, parseEther('4000'));

    const premiaMining = PremiaMining__factory.connect(
      premiaMiningProxy.address,
      deployer,
    );

    //

    const proxyManagerFactory = new ProxyManager__factory(deployer);
    const proxyManager = await proxyManagerFactory.deploy(poolDiamond.address);
    await diamondCut(premiaDiamond, proxyManager.address, proxyManagerFactory);

    //////////////////////////////////////////////

    let registeredSelectors = [
      poolDiamond.interface.getSighash('supportsInterface(bytes4)'),
    ];

    const poolWriteFactory = new PoolWrite__factory(
      { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
      deployer,
    );
    const poolWriteImpl = await poolWriteFactory.deploy(
      weth.address,
      premiaMining.address,
      feeReceiver,
      premiaFeeDiscount,
      fixedFromFloat(FEE),
    );
    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolWriteImpl.address,
        poolWriteFactory,
        registeredSelectors,
      ),
    );

    //////////////////////////////////////////////

    const poolMockFactory = new PoolMock__factory(deployer);
    const poolMockImpl = await poolMockFactory.deploy(
      weth.address,
      premiaMining.address,
      feeReceiver,
      premiaFeeDiscount,
      fixedFromFloat(FEE),
    );
    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolMockImpl.address,
        poolMockFactory,
        registeredSelectors,
      ),
    );

    //////////////////////////////////////////////

    const poolExerciseFactory = new PoolExercise__factory(
      { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
      deployer,
    );
    const poolExerciseImpl = await poolExerciseFactory.deploy(
      weth.address,
      premiaMining.address,
      feeReceiver,
      premiaFeeDiscount,
      fixedFromFloat(FEE),
    );
    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolExerciseImpl.address,
        poolExerciseFactory,
        registeredSelectors,
      ),
    );

    //////////////////////////////////////////////

    const poolViewFactory = new PoolView__factory(deployer);
    const poolViewImpl = await poolViewFactory.deploy(
      weth.address,
      premiaMining.address,
      feeReceiver,
      premiaFeeDiscount,
      fixedFromFloat(FEE),
    );
    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolViewImpl.address,
        poolViewFactory,
        registeredSelectors,
      ),
    );

    //////////////////////////////////////////////

    const poolIOFactory = new PoolIO__factory(
      { ['contracts/libraries/OptionMath.sol:OptionMath']: optionMath.address },
      deployer,
    );
    const poolIOImpl = await poolIOFactory.deploy(
      weth.address,
      premiaMining.address,
      feeReceiver,
      premiaFeeDiscount,
      fixedFromFloat(FEE),
    );
    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolIOImpl.address,
        poolIOFactory,
        registeredSelectors,
      ),
    );
    //////////////////////////////////////////////
    //////////////////////////////////////////////

    const manager = ProxyManager__factory.connect(
      premiaDiamond.address,
      deployer,
    );

    const baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    const underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.decimals.returns(8);
    await underlyingOracle.mock.decimals.returns(8);
    await baseOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await underlyingOracle.mock.latestAnswer.returns(
      parseUnits(priceUnderlying.toString(), 8),
    );

    let tx = await manager.deployPool(
      base.address,
      underlying.address,
      baseOracle.address,
      underlyingOracle.address,
      // minimum amounts
      fixedFromFloat(100),
      fixedFromFloat(0.1),
      // deposit caps
      fixedFromFloat(1000000),
      fixedFromFloat(1000000),
      fixedFromFloat(1.22 * 1.22),
      100,
    );

    let events = (await tx.wait()).events;
    let poolAddress = events![events!.length - 1].args!.pool;
    const pool = IPool__factory.connect(poolAddress, deployer);
    const poolView = PoolView__factory.connect(poolAddress, deployer);

    //

    tx = await manager.deployPool(
      base.address,
      weth.address,
      baseOracle.address,
      underlyingOracle.address,
      // minimum amounts
      fixedFromFloat(100),
      fixedFromFloat(0.1),
      // deposit caps
      fixedFromFloat(1000000),
      fixedFromFloat(1000000),
      fixedFromFloat(1.1),
      100,
    );

    events = (await tx.wait()).events;
    poolAddress = events![events!.length - 1].args!.pool;
    const poolWeth = IPool__factory.connect(poolAddress, deployer);

    //

    underlying = ERC20Mock__factory.connect(
      (await poolView.getPoolSettings()).underlying,
      deployer,
    );

    return new PoolUtil({
      premiaDiamond,
      pool,
      poolWeth,
      underlying,
      weth,
      base,
      baseOracle,
      underlyingOracle,
      premiaMining: premiaMining,
    });
  }

  async setUnderlyingPrice(price: BigNumber) {
    await this.underlyingOracle.mock.latestAnswer.returns(price);
  }

  getToken(isCall: boolean) {
    return isCall ? this.underlying : this.base;
  }

  getTokenDecimals(isCall: boolean) {
    return isCall ? DECIMALS_UNDERLYING : DECIMALS_BASE;
  }

  getLong(isCall: boolean) {
    return isCall ? TokenType.LongCall : TokenType.LongPut;
  }

  getShort(isCall: boolean) {
    return isCall ? TokenType.ShortCall : TokenType.ShortPut;
  }

  getStrike(isCall: boolean, spotPrice: number) {
    return isCall ? spotPrice * 1.25 : spotPrice * 0.75;
  }

  getMaxCost(
    baseCost64x64: BigNumber,
    feeCost64x64: BigNumber,
    isCall: boolean,
  ) {
    if (isCall) {
      return parseUnderlying(
        (
          (fixedToNumber(baseCost64x64) + fixedToNumber(feeCost64x64)) *
          1.03
        ).toString(),
      );
    } else {
      return parseBase(
        (
          (fixedToNumber(baseCost64x64) + fixedToNumber(feeCost64x64)) *
          1.03
        ).toString(),
      );
    }
  }

  async getMinPrice(collateralAmount: number, maturity: number) {
    let { timestamp } = await ethers.provider.getBlock('latest');

    return (
      (collateralAmount * (MIN_APY * (maturity - timestamp))) /
      (365 * 24 * 3600)
    );
  }

  getFreeLiqTokenId(isCall: boolean) {
    if (isCall) {
      return formatTokenId({
        tokenType: TokenType.UnderlyingFreeLiq,
        maturity: BigNumber.from(0),
        strike64x64: BigNumber.from(0),
      });
    } else {
      return formatTokenId({
        tokenType: TokenType.BaseFreeLiq,
        maturity: BigNumber.from(0),
        strike64x64: BigNumber.from(0),
      });
    }
  }

  getReservedLiqTokenId(isCall: boolean) {
    if (isCall) {
      return formatTokenId({
        tokenType: TokenType.UnderlyingReservedLiq,
        maturity: BigNumber.from(0),
        strike64x64: BigNumber.from(0),
      });
    } else {
      return formatTokenId({
        tokenType: TokenType.BaseReservedLiq,
        maturity: BigNumber.from(0),
        strike64x64: BigNumber.from(0),
      });
    }
  }

  async depositLiquidity(
    lp: SignerWithAddress,
    amount: BigNumberish,
    isCall: boolean,
  ) {
    if (isCall) {
      await this.underlying.mint(lp.address, amount);
      await this.underlying
        .connect(lp)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    } else {
      await this.base.mint(lp.address, amount);
      await this.base
        .connect(lp)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    }

    await PoolIO__factory.connect(this.pool.address, lp)
      .connect(lp)
      .deposit(amount, isCall);

    await increaseTimestamp(300);
  }

  async writeOption(
    operator: SignerWithAddress,
    underwriter: SignerWithAddress,
    longReceiver: SignerWithAddress,
    maturity: BigNumber,
    strike64x64: BigNumber,
    amount: BigNumber,
    isCall: boolean,
  ) {
    const toMint = isCall ? parseUnderlying('1') : parseBase('2');

    await this.getToken(isCall).mint(underwriter.address, toMint);
    await this.getToken(isCall)
      .connect(underwriter)
      .approve(this.pool.address, ethers.constants.MaxUint256);
    await this.pool
      .connect(operator)
      .writeFrom(
        underwriter.address,
        longReceiver.address,
        maturity,
        strike64x64,
        amount,
        isCall,
      );
  }

  async purchaseOption(
    lp: SignerWithAddress,
    buyer: SignerWithAddress,
    amount: BigNumber,
    maturity: BigNumber,
    strike64x64: BigNumber,
    isCall: boolean,
  ) {
    await this.depositLiquidity(
      lp,
      isCall
        ? amount
        : parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
      isCall,
    );

    if (isCall) {
      await this.underlying.mint(buyer.address, parseUnderlying('100'));
      await this.underlying
        .connect(buyer)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    } else {
      await this.base.mint(buyer.address, parseBase('10000'));
      await this.base
        .connect(buyer)
        .approve(this.pool.address, ethers.constants.MaxUint256);
    }

    const quote = await this.pool.quote(
      buyer.address,
      maturity,
      strike64x64,
      amount,
      isCall,
    );

    await this.pool
      .connect(buyer)
      .purchase(
        maturity,
        strike64x64,
        amount,
        isCall,
        ethers.constants.MaxUint256,
      );

    return quote;
  }

  async getMaturity(days: number) {
    const { timestamp } = await ethers.provider.getBlock('latest');

    return BigNumber.from(
      Math.floor(timestamp / ONE_DAY) * ONE_DAY + days * ONE_DAY,
    );
  }
}
