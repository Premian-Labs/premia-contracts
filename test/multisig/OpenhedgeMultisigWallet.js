const { expect } = require('chai');
const signData = require('@solidstate/library/sign_data.js');

const describeBehaviorOfECDSAMultisigWallet = require('@solidstate/spec/multisig/ECDSAMultisigWallet.behavior.js');

const quorum = ethers.constants.One;

const signAuthorization = async function (signer, { input, type, nonce, address }) {
  return signData(
    signer,
    {
      values: [input],
      types: [type],
      nonce,
      address,
    }
  );
};

describe('OpenhedgeMultisigWallet', function () {
  let owner;
  let nonSigner;
  let signers;

  let factory;
  let instance;

  before(async function () {
    [nonSigner, ...signers] = (await ethers.getSigners()).slice(0, 4);
  });

  beforeEach(async function () {
    factory = await ethers.getContractFactory('OpenhedgeMultisigWallet', owner);
    instance = await factory.deploy(
      signers.map(s => s.address),
      quorum
    );
    await instance.deployed();
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfECDSAMultisigWallet({
    deploy: () => instance,
    getSigners: () => signers,
    getNonSigner: () => nonSigner,
    quorum,
    getVerificationAddress: () => instance.address,
  });

  describe('constructor', function () {
    describe('reverts if', function () {
      it('quorum exceeds signer count', async function () {
        await expect(
          factory.deploy([], ethers.constants.One)
        ).to.be.revertedWith(
          'ECDSAMultisigWallet: insufficient signers to meet quorum'
        );
      });
    });
  });

  describe('#isValidNonce', function () {
    it('returns whether given nonce is valid for given signer', async function () {
      expect(
        await instance.callStatic.isValidNonce(
          signers[0].address,
          ethers.constants.One
        )
      ).to.be.true;
    });
  });

  describe('#isSigner', function () {
    it('returns whether given address is authorized signer', async function () {
      for (let signer of signers) {
        expect(
          await instance.callStatic.isSigner(signer.address)
        ).to.be.true;
      }

      expect(
        await instance.callStatic.isSigner(nonSigner.address)
      ).to.be.false;
    });
  });

  describe('#getQuorum', function () {
    it('returns quorum for authorization', async function () {
      expect(
        await instance.callStatic.getQuorum()
      ).to.equal(
        quorum
      );
    });
  });

  describe('#invalidateNonce', function () {
    it('invalidates nonce for sender', async function () {
      const [signer] = signers;
      const nonce = ethers.constants.One;

      await instance.connect(signer).invalidateNonce(nonce);

      expect(
        await instance.callStatic.isValidNonce(
          signer.address,
          nonce
        )
      ).to.be.false;
    });
  });

  describe('#addSigner', function () {
    it('adds signer to multisig', async function() {
      const nonce = ethers.constants.Zero;

      const authorization = await signAuthorization(
        signers[0],
        {
          input: nonSigner.address,
          type: 'address',
          nonce,
          address: instance.address,
        }
      );

      await instance.addSigner(
        nonSigner.address,
        [
          [authorization, nonce],
        ]
      );

      expect(
        await instance.callStatic.isSigner(nonSigner.address)
      ).to.be.true;
    });

    describe('reverts if', function () {
      it('signatures are invalid', async function() {
        await expect(
          instance.addSigner(
            nonSigner.address,
            []
          )
        ).to.be.revertedWith(
          'ECDSAMultisigWallet: quorum not reached'
        );
      });
    });
  });

  describe('#removeSigner', function () {
    it('removes signer from multisig', async function() {
      const nonce = ethers.constants.Zero;
      const accountToBeRemoved = signers[0].address;

      const authorization = await signAuthorization(
        signers[0],
        {
          input: accountToBeRemoved,
          type: 'address',
          nonce,
          address: instance.address,
        }
      );

      await instance.removeSigner(
        accountToBeRemoved,
        [
          [authorization, nonce],
        ]
      );

      expect(
        await instance.callStatic.isSigner(accountToBeRemoved)
      ).to.be.false;
    });

    describe('reverts if', function () {
      it('signatures are invalid', async function() {
        await expect(
          instance.addSigner(
            nonSigner.address,
            []
          )
        ).to.be.revertedWith(
          'ECDSAMultisigWallet: quorum not reached'
        );
      });
    });
  });

  describe('#setQuorum', function () {
    it('sets quorum for authorization', async function () {
      const newQuorum = quorum.add(ethers.constants.One);
      const nonce = ethers.constants.Zero;

      const authorization = await signAuthorization(
        signers[0],
        {
          input: newQuorum,
          type: 'uint256',
          nonce,
          address: instance.address,
        }
      );

      await instance.setQuorum(
        newQuorum,
        [
          [authorization, nonce],
        ]
      );

      expect(
        await instance.callStatic.getQuorum()
      ).to.equal(
        newQuorum
      );
    });

    describe('reverts if', function () {
      it('signatures are invalid', async function () {
        await expect(
          instance.setQuorum(
            nonSigner.address,
            []
          )
        ).to.be.revertedWith(
          'ECDSAMultisigWallet: quorum not reached'
        );
      });
    });
  });
});
