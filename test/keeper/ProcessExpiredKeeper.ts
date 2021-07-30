import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock__factory,
  ProcessExpiredKeeper,
  ProcessExpiredKeeper__factory,
} from '../../typechain';
import { parseOption, parseUnderlying, PoolUtil } from '../pool/PoolUtil';
import { increaseTimestamp } from '../utils/evm';
import { ZERO_ADDRESS } from '../utils/constants';
import { fixedFromFloat, getOptionTokenIds } from '../utils/math';

describe('ProcessExpiredKeeper', () => {
  let owner: SignerWithAddress;
  let lp: SignerWithAddress;
  let buyer: SignerWithAddress;
  let feeReceiver: SignerWithAddress;
  let expKeeper: ProcessExpiredKeeper;
  let p: PoolUtil;

  const spotPrice = 2000;

  beforeEach(async () => {
    [owner, lp, buyer, feeReceiver] = await ethers.getSigners();

    p = await PoolUtil.deploy(
      owner,
      (
        await new ERC20Mock__factory(owner).deploy('PREMIA', 18)
      ).address,
      spotPrice,
      feeReceiver.address,
      ZERO_ADDRESS,
    );
    expKeeper = await new ProcessExpiredKeeper__factory(owner).deploy(
      p.premiaDiamond.address,
    );
  });

  it('should not detect any option to process', async () => {
    const r = await expKeeper.callStatic.checkUpkeep('0x00');
    expect(r.upkeepNeeded).to.be.false;
    expect(r.performData).to.eq('0x');
  });

  it('should detect expired option to process', async () => {
    const isCall = true;

    await p.depositLiquidity(
      lp,
      parseOption(isCall ? '100' : '100000', isCall),
      isCall,
    );

    const maturity = await p.getMaturity(10);
    const strike64x64 = fixedFromFloat(p.getStrike(isCall, spotPrice));

    const purchaseAmountNb = 10;
    const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

    const quote = await p.pool.quote(
      buyer.address,
      maturity,
      strike64x64,
      purchaseAmount,
      isCall,
    );

    const mintAmount = parseOption('1000', isCall);
    const tokenIds = getOptionTokenIds(maturity, strike64x64, isCall);
    await p.getToken(isCall).mint(buyer.address, mintAmount);
    await p
      .getToken(isCall)
      .connect(buyer)
      .approve(p.pool.address, ethers.constants.MaxUint256);

    await p.pool
      .connect(buyer)
      .purchase(
        maturity,
        strike64x64,
        purchaseAmount,
        isCall,
        p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
      );

    await increaseTimestamp(15 * 24 * 3600);

    const supply = await p.pool.totalSupply(tokenIds.long);
    const r = await expKeeper.callStatic.checkUpkeep('0x00');
    expect(r.upkeepNeeded).to.be.true;
    expect(r.performData).to.eq(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint256'],
        [p.pool.address, tokenIds.long, supply],
      ),
    );
  });

  it('should process multiple expired option', async () => {
    const isCall = true;

    await p.depositLiquidity(
      lp,
      parseOption(isCall ? '100' : '100000', isCall),
      isCall,
    );

    const strike64x64 = fixedFromFloat(p.getStrike(isCall, spotPrice));

    const purchaseAmountNb = 10;
    const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

    const mintAmount = parseOption('1000', isCall);
    const tokenIds1 = getOptionTokenIds(
      await p.getMaturity(10),
      strike64x64,
      isCall,
    );
    const tokenIds2 = getOptionTokenIds(
      await p.getMaturity(9),
      strike64x64,
      isCall,
    );
    await p.getToken(isCall).mint(buyer.address, mintAmount);
    await p
      .getToken(isCall)
      .connect(buyer)
      .approve(p.pool.address, ethers.constants.MaxUint256);

    let quote = await p.pool.quote(
      buyer.address,
      await p.getMaturity(10),
      strike64x64,
      purchaseAmount,
      isCall,
    );

    await p.pool
      .connect(buyer)
      .purchase(
        await p.getMaturity(10),
        strike64x64,
        purchaseAmount,
        isCall,
        p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
      );

    quote = await p.pool.quote(
      buyer.address,
      await p.getMaturity(10),
      strike64x64,
      purchaseAmount,
      isCall,
    );

    await p.pool
      .connect(buyer)
      .purchase(
        await p.getMaturity(9),
        strike64x64,
        purchaseAmount,
        isCall,
        p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
      );

    await increaseTimestamp(15 * 24 * 3600);

    let supply = await p.pool.totalSupply(tokenIds1.long);
    let r = await expKeeper.callStatic.checkUpkeep('0x00');
    expect(r.upkeepNeeded).to.be.true;
    expect(r.performData).to.eq(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint256'],
        [p.pool.address, tokenIds1.long, supply],
      ),
    );

    expect(await p.pool.totalSupply(tokenIds1.long)).to.be.gt(0);
    await expKeeper.performUpkeep(r.performData);
    expect(await p.pool.totalSupply(tokenIds1.long)).to.eq(0);

    supply = await p.pool.totalSupply(tokenIds2.long);
    r = await expKeeper.callStatic.checkUpkeep('0x00');
    expect(r.upkeepNeeded).to.be.true;
    expect(r.performData).to.eq(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint256'],
        [p.pool.address, tokenIds2.long, supply],
      ),
    );

    expect(await p.pool.totalSupply(tokenIds2.long)).to.be.gt(0);
    await expKeeper.performUpkeep(r.performData);
    expect(await p.pool.totalSupply(tokenIds2.long)).to.eq(0);

    r = await expKeeper.callStatic.checkUpkeep('0x00');
    expect(r.upkeepNeeded).to.be.false;
    expect(r.performData).to.eq('0x');
  });
});
