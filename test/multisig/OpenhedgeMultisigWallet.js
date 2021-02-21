const { expect } = require('chai');

const describeBehaviorOfECDSAMultisigWallet = require('@solidstate/contracts/test/multisig/ECDSAMultisigWallet.behavior.js');

const quorum = ethers.constants.One;

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
  });

  describe('#isValidNonce', function () {
    it('retuns whether given nonce is valid for given signer', async function () {
      expect(
        await instance.callStatic.isValidNonce(
          signers[0].address,
          ethers.constants.One
        )
      ).to.be.true;
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
    it('todo');

    describe('reverts if', function () {
      it('todo');
    });
  });

  describe('#removeSigner', function () {
    it('todo');

    describe('reverts if', function () {
      it('todo');
    });
  });

  describe('#setQuorum', function () {
    it('todo');

    describe('reverts if', function () {
      it('todo');
    });
  });

  describe('constructor', function () {
    describe('reverts if', function () {
      it('quorum exceeds signer count', async function () {
        await expect(
          factory.deploy([], ethers.constants.One)
        ).to.be.revertedWith(
          'OpenhedgeMultisigWallet: not enough signers to meet quorum'
        );
      });
    });
  });
});
