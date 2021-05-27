import { expect } from 'chai';
import { ethers } from 'hardhat';
import { signData } from '@solidstate/library';
import { describeBehaviorOfECDSAMultisigWallet } from '@solidstate/spec';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  MedianMultisigWallet,
  MedianMultisigWallet__factory,
} from '../../typechain';
import { BigNumberish } from 'ethers';

const quorum = ethers.constants.One;

interface SignAuthorizationArgs {
  input: string;
  type: string;
  nonce: BigNumberish;
  address: string;
}

const signAuthorization = async function (
  signer: SignerWithAddress,
  { input, type, nonce, address }: SignAuthorizationArgs,
) {
  return signData(signer, {
    values: [input],
    types: [type],
    nonce,
    address,
  });
};

describe('MedianMultisigWallet', function () {
  let owner: SignerWithAddress;
  let nonSigner: SignerWithAddress;
  let signers: SignerWithAddress[];

  let instance: MedianMultisigWallet;

  before(async function () {
    [nonSigner, ...signers] = (await ethers.getSigners()).slice(0, 4);
  });

  beforeEach(async function () {
    instance = await new MedianMultisigWallet__factory(owner).deploy(
      signers.map((s) => s.address),
      quorum,
    );
  });

  describeBehaviorOfECDSAMultisigWallet({
    deploy: async () => instance,
    getSigners: async () => signers,
    getNonSigner: async () => nonSigner,
    quorum,
    getVerificationAddress: async () => instance.address,
  });

  describe('constructor', function () {
    describe('reverts if', function () {
      it('quorum exceeds signer count', async function () {
        await expect(
          new MedianMultisigWallet__factory(owner).deploy(
            [],
            ethers.constants.One,
          ),
        ).to.be.revertedWith(
          'ECDSAMultisigWallet: insufficient signers to meet quorum',
        );
      });
    });
  });

  describe('#isValidNonce', function () {
    it('returns whether given nonce is valid for given signer', async function () {
      expect(
        await instance.callStatic.isValidNonce(
          signers[0].address,
          ethers.constants.One,
        ),
      ).to.be.true;
    });
  });

  describe('#isSigner', function () {
    it('returns whether given address is authorized signer', async function () {
      for (let signer of signers) {
        expect(await instance.callStatic.isSigner(signer.address)).to.be.true;
      }

      expect(await instance.callStatic.isSigner(nonSigner.address)).to.be.false;
    });
  });

  describe('#getQuorum', function () {
    it('returns quorum for authorization', async function () {
      expect(await instance.callStatic.getQuorum()).to.equal(quorum);
    });
  });

  describe('#invalidateNonce', function () {
    it('invalidates nonce for sender', async function () {
      const [signer] = signers;
      const nonce = ethers.constants.One;

      await instance.connect(signer).invalidateNonce(nonce);

      expect(await instance.callStatic.isValidNonce(signer.address, nonce)).to
        .be.false;
    });
  });

  describe('#addSigner', function () {
    it('adds signer to multisig', async function () {
      const nonce = ethers.constants.Zero;

      const authorization = await signAuthorization(signers[0], {
        input: nonSigner.address,
        type: 'address',
        nonce,
        address: instance.address,
      });

      await instance.addSigner(nonSigner.address, [
        { data: authorization, nonce },
      ]);

      expect(await instance.callStatic.isSigner(nonSigner.address)).to.be.true;
    });

    describe('reverts if', function () {
      it('signatures are invalid', async function () {
        await expect(
          instance.addSigner(nonSigner.address, []),
        ).to.be.revertedWith('ECDSAMultisigWallet: quorum not reached');
      });
    });
  });

  describe('#removeSigner', function () {
    it('removes signer from multisig', async function () {
      const nonce = ethers.constants.Zero;
      const accountToBeRemoved = signers[0].address;

      const authorization = await signAuthorization(signers[0], {
        input: accountToBeRemoved,
        type: 'address',
        nonce,
        address: instance.address,
      });

      await instance.removeSigner(accountToBeRemoved, [
        { data: authorization, nonce },
      ]);

      expect(await instance.callStatic.isSigner(accountToBeRemoved)).to.be
        .false;
    });

    describe('reverts if', function () {
      it('signatures are invalid', async function () {
        await expect(
          instance.addSigner(nonSigner.address, []),
        ).to.be.revertedWith('ECDSAMultisigWallet: quorum not reached');
      });
    });
  });

  describe('#setQuorum', function () {
    it('sets quorum for authorization', async function () {
      const newQuorum = quorum.add(ethers.constants.One);
      const nonce = ethers.constants.Zero;

      const authorization = await signAuthorization(signers[0], {
        input: newQuorum.toString(),
        type: 'uint256',
        nonce,
        address: instance.address,
      });

      await instance.setQuorum(newQuorum, [{ data: authorization, nonce }]);

      expect(await instance.callStatic.getQuorum()).to.equal(newQuorum);
    });

    describe('reverts if', function () {
      it('signatures are invalid', async function () {
        await expect(
          instance.setQuorum(nonSigner.address, []),
        ).to.be.revertedWith('ECDSAMultisigWallet: quorum not reached');
      });
    });
  });
});
