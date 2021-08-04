import { expect } from 'chai';
import {
  ERC20Mock,
  IPremiaBondingCurve,
  IPremiaBondingCurve__factory,
  PremiaBondingCurveDeprecation,
  PremiaBondingCurveDeprecation__factory,
  PremiaDevFund,
  PremiaDevFund__factory,
  PremiaErc20,
  PremiaErc20__factory,
} from '../typechain';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { increaseTimestamp } from './utils/evm';
import { formatEther, parseEther } from 'ethers/lib/utils';

let multisig: SignerWithAddress;
let premia: PremiaErc20;
let deprecationContract: PremiaBondingCurveDeprecation;
let bondingCurve: IPremiaBondingCurve;
let timelock: PremiaDevFund;

const ALCHEMY_KEY = process.env.ALCHEMY_KEY;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`;
const blockNumber = 12739250;

describe('PremiaDevFund', () => {
  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    premia = await PremiaErc20__factory.connect(
      '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70',
      multisig,
    );

    // Impersonate multisig
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0'],
    });
    multisig = await ethers.getSigner(
      '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0',
    );

    bondingCurve = IPremiaBondingCurve__factory.connect(
      '0xF49e0FDBf4839afAeb825EB448AA24B1C43E946b',
      multisig,
    );

    timelock = await new PremiaDevFund__factory(multisig).deploy(
      premia.address,
    );

    deprecationContract = await new PremiaBondingCurveDeprecation__factory(
      multisig,
    ).deploy(premia.address, timelock.address);
  });

  it('should correctly deprecate bonding curve', async () => {
    await bondingCurve
      .connect(multisig)
      .startUpgrade(deprecationContract.address);

    expect(
      await premia.connect(multisig).balanceOf(bondingCurve.address),
    ).to.eq(parseEther('25000000'));

    // Go through the 7 days delay for the upgrade
    await increaseTimestamp(7 * 24 * 3600 + 10);

    await bondingCurve.connect(multisig).doUpgrade({ gasLimit: 5000000 });

    expect(
      await premia.connect(multisig).balanceOf(bondingCurve.address),
    ).to.eq(0);

    expect(await premia.connect(multisig).balanceOf(timelock.address)).to.eq(
      parseEther('25000000'),
    );
  });
});
