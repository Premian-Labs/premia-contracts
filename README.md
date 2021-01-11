**FeeCalculator.sol** - Calculate protocol fee, and apply referral + staking discount on it

**PremiaBondingCurve.sol** - Premia <-> Eth bonding curve 

**PremiaErc20.sol** - The Premia token

**PremiaFeeDiscount.sol** - Lock xPremia to get protocol fee discount

**PremiaMaker.sol** - Swap protocol fees to ETH, used ETH to purchase Premia on the bonding curve and send Premia to PremiaStaking contract

**PremiaMarket.sol** - Option market

**PremiaMining.sol** - Mine Premia by staking uPremia

**PremiaOption.sol** - Option ERC1155 contract (One per denomination)

**PremiaPBS.sol** - Primary Bootstrap Contribution

**PremiaReferral.sol** - Keep record of all Premia referrals

**PremiaStaking.sol** - Stake Premia, get xPremia, accumulate a share of protocol fees

**PremiaUncutErc20.sol** - Non-tradable ERC20 used rewarded based on protocol fees paid, and used for Premia mining

**PremiaVesting.sol** - Founder allocation vesting contract distributing allocation over the course of a year

**PriceProvider.sol** - Manually updated token price provider used to calculate uPremia reward