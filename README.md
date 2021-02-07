# Premia - Options Platform

https://premia.finance

## Contracts Deployed

- **FeeCalculator** : Calculate protocol fee, and apply referral + staking discount on it  
  https://etherscan.io/address/0x602B50091B0B351CA179E87aD6e006AeCEB2a6Ad
- **PremiaBondingCurve** : Premia <-> Eth bonding curve  
  _Will be deployed after PBC ends_
- **PremiaDevFund** : 3 days timelocked withdrawal for dev fund (Owned by multisig)  
  https://etherscan.io/address/0xE43147dAa592C3f88402C6E2b932DB9d97bc1C7f
- **PremiaErc20** : The Premia token  
  https://etherscan.io/token/0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70
  https://etherscan.io/address/0x81d6F46981B4fE4A6FafADDa716eE561A17761aE
- **PremiaFeeDiscount** : Lock xPremia to get protocol fee discount  
  https://etherscan.io/address/0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854
- **PremiaMaker** : Swap protocol fees to ETH, used ETH to purchase Premia on the bonding curve and send Premia to PremiaStaking contract  
  https://etherscan.io/address/0xcb81dB76Ae0a46c6e1E378E3Ade61DaB275ff96E
- **PremiaMarket** : Option market  
  https://etherscan.io/address/0x45eBD0FC72E2056adb5c864Ea6F151ad943d94af
- **PremiaMining** : Mine Premia by staking uPremia  
  https://etherscan.io/address/0xf0f16B3460512554d4D821DD482dbfb78817EC43
- **PremiaOption** : Option ERC1155 contract (One per denomination)  
  https://etherscan.io/address/0x5920cb60B1c62dC69467bf7c6EDFcFb3f98548c0
- **PremiaOptionBatch** : Batch functions to interact with PremiaOption  
  https://etherscan.io/address/0xf386D276d648E84Cbb7013Db97d952fDD0092DBC
- **PremiaPBC** : Primary Bootstrap Contribution  
  https://etherscan.io/address/0x67aEe3454d5F82344d58021179830A3bb2245C11
- **PremiaReferral** : Keep record of all Premia referrals  
  https://etherscan.io/address/0xaFcF4ca5826eD76189eA227bd863916ABf43a6Da
- **PremiaStaking** : Stake Premia, get xPremia, accumulate a share of protocol fees  
  https://etherscan.io/address/0x16f9D564Df80376C61AC914205D3fDfF7057d610
- **PremiaUncutErc20** : Non-tradable ERC20 used rewarded based on protocol fees paid, and used for Premia mining  
  https://etherscan.io/address/0x8406C6C1DB4D224C8B0cF7859c0881Ddd68D4761
- **PremiaVesting** : Founder allocation vesting contract distributing allocation over the course of a year  
  https://etherscan.io/address/0x3a00BC08F4Ee12568231dB85D077864275a495b3
  https://etherscan.io/address/0xdF69C895E7490d90b14A278Add8Aa4eC844a696a
  https://etherscan.io/address/0xD3C8Ce2793c60c9e8464FC08Ec7691613057c43C
  https://etherscan.io/address/0x1ede971F31f7630baE9f14d349273621A5145381
- **PriceProvider** : Manually updated token price provider used to calculate uPremia reward  
  https://etherscan.io/address/0x64fE6D2279c09646Bd6d265483A414d79B3D00B0