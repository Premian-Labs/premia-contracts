import { task } from 'hardhat/config';

export const RINKEBY_WETH = '0xc778417e063141139fce010982780140aa0cd5ab';

task('upgrade-pool-implementation').setAction(async function (args, hre) {
  // Leave imports here so that we can run hardhat compile even if typechain folder has not been generated  yet
  const {
    ProxyManager__factory,
    Pool,
    PoolTradingCompetition,
    PoolTradingCompetition__factory,
  } = require('../typechain');

  const [deployer] = await hre.ethers.getSigners();

  const weth = RINKEBY_WETH;

  let pool: typeof Pool | typeof PoolTradingCompetition;
  pool = await new PoolTradingCompetition__factory(deployer).deploy(
    weth,
    deployer.address,
    0,
    260,
  );

  const proxyManager = ProxyManager__factory.connect(
    '0x82D11b95b01bA7847b32d6d1503875FF922a1ecB',
    deployer,
  );

  console.log('set pool imp');

  const poolTx = await proxyManager.setPoolImplementation(pool.address);

  await poolTx.wait(1);

  // const pools: any = {
  //   WETH: {
  //     address: '0xECcd128D7E1941aE26F6E5787B55Ac4Bf726E3bE',
  //     wipeList: [
  //       '0xFBB8495A691232Cb819b84475F57e76aa9aBb6f1',
  //       '0x14BB96792BC2058D59AF8b098F1C4fF69267968f',
  //       '0x0F11a0aD3b93fC9838b663511C44598335055f85',
  //       '0x15afE19e6D49f83ab077072C6Cbd8D4E5A10304C',
  //       '0x573C2AA43D3cD14501Ec116fDC83020Fd479Bb5E',
  //       '0x3e1D118f53818D24C5afdb4D61c948fe7Dc196e4',
  //       '0xdBC6B78d05Cec356AD592E02c07585998d76Df55',
  //       '0x5C2acAE2bfBf75B7a2f045DC7f4326bc4f0B048D',
  //       '0xA0a6B1A7914079003258C6b627c215BeAb719E06',
  //       '0x6d343059ee8c25388F20FEDda364D0849683C4e3',
  //       '0x6bdddcf0a6b91d39D39DF9baB7C1D54B11e7140F',
  //       '0x1ED7248A9338e09b75AB5710D2A88F49f38259Be',
  //       '0xBa9B51b8d0ade90296203625d653332367a08087',
  //       '0xB1Adc3a1298819C6b1D18C2af1081f04B8d53176',
  //       '0x3806410847af6cC861D8457b1E4aC029778AAf20',
  //       '0x329b90Dd19E3Ca381E5c05E071C276401D3c03C6',
  //       '0x303f80DdEEd78a48100CeC7158bd152fB2545bD3',
  //       '0x9B11C9C4D15aa569A740e9C45D2B043099125763',
  //       '0x1f516633C1f6407c6f0Dd28bDC242a566B2A7f65',
  //       '0x7e5161ebbB67e6D47D23F0c88Bc2552d1F76B478',
  //       '0xd99687Ba7Bd3D8A96AD3d4a7A9f15493750c5bDB',
  //       '0x0660459b2b658B232f3dB6ADfF5580e7558F60E6',
  //       '0x0f1025f754b3eb32ab3105127b563084BFa03A6F',
  //       '0x02019B5e3aFc37710cCbF12e6B9De3328CF615A8',
  //       '0x825a1dba359F784DFB364cFAB458Ec44889C9AF2',
  //       '0x0C5a369BE6D584D6B054494A22d71B61eF1Fe9aF',
  //       '0xB26D90D66E046f2c72bd038F42151ACECB17238D',
  //       '0xc13eC844Eb19D6A72DDD5F2779484BA35279A817',
  //       '0xE5b831a4Be169D36cAE0a1394b070D2d8a05b244',
  //       '0x8bb18f1eeB8d170F4edfE2C5D008986171B4e572',
  //       '0x3e8168fFB61C2dFd8DA9B8621A1B7a2ce52672F0',
  //       '0x5F138d29017E1953477D2337b2a4d15EE6bF41Ad',
  //       '0x55E250cF9a5C3938AcD3062554206656fcbb77A9',
  //       '0xa560d704935Dfa40ad8E1B46e27b219e52D49d4c',
  //       '0xA6Cd4976bB57b96FFedB8709417Ef57bd4812ba7',
  //       '0x26b94A72D2Aa4197441BF7B4c2C80dfB8F34cBC8',
  //     ],
  //   },
  //   WBTC: {
  //     address: '0x079F7D948cBe81dCec78E32D5Dc6b89345116669',
  //     wipeList: [
  //       '0xFBB8495A691232Cb819b84475F57e76aa9aBb6f1',
  //       '0x14BB96792BC2058D59AF8b098F1C4fF69267968f',
  //       '0x0F11a0aD3b93fC9838b663511C44598335055f85',
  //       '0x15afE19e6D49f83ab077072C6Cbd8D4E5A10304C',
  //       '0x573C2AA43D3cD14501Ec116fDC83020Fd479Bb5E',
  //       '0x3e1D118f53818D24C5afdb4D61c948fe7Dc196e4',
  //       '0xdBC6B78d05Cec356AD592E02c07585998d76Df55',
  //       '0x5C2acAE2bfBf75B7a2f045DC7f4326bc4f0B048D',
  //       '0xA0a6B1A7914079003258C6b627c215BeAb719E06',
  //       '0x6d343059ee8c25388F20FEDda364D0849683C4e3',
  //       '0x6bdddcf0a6b91d39D39DF9baB7C1D54B11e7140F',
  //       '0x1ED7248A9338e09b75AB5710D2A88F49f38259Be',
  //       '0xBa9B51b8d0ade90296203625d653332367a08087',
  //       '0xB1Adc3a1298819C6b1D18C2af1081f04B8d53176',
  //       '0x3806410847af6cC861D8457b1E4aC029778AAf20',
  //       '0x329b90Dd19E3Ca381E5c05E071C276401D3c03C6',
  //       '0x303f80DdEEd78a48100CeC7158bd152fB2545bD3',
  //       '0x9B11C9C4D15aa569A740e9C45D2B043099125763',
  //       '0x1f516633C1f6407c6f0Dd28bDC242a566B2A7f65',
  //       '0x7e5161ebbB67e6D47D23F0c88Bc2552d1F76B478',
  //       '0xd99687Ba7Bd3D8A96AD3d4a7A9f15493750c5bDB',
  //       '0x0660459b2b658B232f3dB6ADfF5580e7558F60E6',
  //       '0x0f1025f754b3eb32ab3105127b563084BFa03A6F',
  //       '0x02019B5e3aFc37710cCbF12e6B9De3328CF615A8',
  //       '0x825a1dba359F784DFB364cFAB458Ec44889C9AF2',
  //       '0x0C5a369BE6D584D6B054494A22d71B61eF1Fe9aF',
  //       '0xB26D90D66E046f2c72bd038F42151ACECB17238D',
  //       '0xc13eC844Eb19D6A72DDD5F2779484BA35279A817',
  //       '0xE5b831a4Be169D36cAE0a1394b070D2d8a05b244',
  //       '0x8bb18f1eeB8d170F4edfE2C5D008986171B4e572',
  //       '0x3e8168fFB61C2dFd8DA9B8621A1B7a2ce52672F0',
  //       '0x5F138d29017E1953477D2337b2a4d15EE6bF41Ad',
  //     ],
  //   },
  //   LINK: {
  //     address: '0x15a13893ae5eF2189347C7912d49D0FBb3CB4f76',
  //     wipeList: [
  //       '0xFBB8495A691232Cb819b84475F57e76aa9aBb6f1',
  //       '0x14BB96792BC2058D59AF8b098F1C4fF69267968f',
  //       '0x0F11a0aD3b93fC9838b663511C44598335055f85',
  //       '0x15afE19e6D49f83ab077072C6Cbd8D4E5A10304C',
  //       '0x573C2AA43D3cD14501Ec116fDC83020Fd479Bb5E',
  //       '0x3e1D118f53818D24C5afdb4D61c948fe7Dc196e4',
  //       '0xdBC6B78d05Cec356AD592E02c07585998d76Df55',
  //       '0x5C2acAE2bfBf75B7a2f045DC7f4326bc4f0B048D',
  //       '0xA0a6B1A7914079003258C6b627c215BeAb719E06',
  //       '0x6d343059ee8c25388F20FEDda364D0849683C4e3',
  //       '0x6bdddcf0a6b91d39D39DF9baB7C1D54B11e7140F',
  //       '0x1ED7248A9338e09b75AB5710D2A88F49f38259Be',
  //       '0xBa9B51b8d0ade90296203625d653332367a08087',
  //       '0xB1Adc3a1298819C6b1D18C2af1081f04B8d53176',
  //       '0x3806410847af6cC861D8457b1E4aC029778AAf20',
  //       '0x329b90Dd19E3Ca381E5c05E071C276401D3c03C6',
  //       '0x303f80DdEEd78a48100CeC7158bd152fB2545bD3',
  //       '0x9B11C9C4D15aa569A740e9C45D2B043099125763',
  //       '0x1f516633C1f6407c6f0Dd28bDC242a566B2A7f65',
  //       '0x7e5161ebbB67e6D47D23F0c88Bc2552d1F76B478',
  //       '0xd99687Ba7Bd3D8A96AD3d4a7A9f15493750c5bDB',
  //       '0x0660459b2b658B232f3dB6ADfF5580e7558F60E6',
  //       '0x0f1025f754b3eb32ab3105127b563084BFa03A6F',
  //     ],
  //   },
  // };

  // for (const k of Object.keys(pools)) {
  //   const p = PoolTradingCompetition__factory.connect(
  //     pools[k].address,
  //     deployer,
  //   );
  //   await (await p.fixLiquidityQueue(pools[k].wipeList)).wait();
  // }
  //
  // console.log('done');

  // await (
  //   await proxyManager.setPoolImplementation(
  //     '0x469F20d6baab0cAD20576be2Ba60624cF6D94b56',
  //   )
  // ).wait();
  // console.log('done');
});
