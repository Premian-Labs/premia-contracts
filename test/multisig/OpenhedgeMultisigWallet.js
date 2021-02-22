const { expect } = require('chai');

const describeBehaviorOfECDSAMultisigWallet = require('@solidstate/contracts/test/multisig/ECDSAMultisigWallet.behavior.js');

const quorum = ethers.constants.One;

const signAuthorization = async function (signer, { target, data, value, delegate, nonce, address }) {
  const types = ['address', 'bytes', 'uint256', 'bool', 'uint256', 'address'];
  const values = [target, data, value, delegate, nonce, address];

  const hash = ethers.utils.solidityKeccak256(types, values);

  const signature = await signer.signMessage(ethers.utils.arrayify(hash));
  return ethers.utils.arrayify(signature);
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
    it('sets quorum for authorization', async function () {
      const newQuorum = quorum.add(ethers.constants.One);

      const target = ethers.constants.AddressZero;
      const data = ethers.utils.zeroPad(newQuorum, 32);
      const value = ethers.constants.Zero;
      const delegate = false;
      const address = instance.address;
      const nonce = ethers.constants.Zero;

      const authorization = await signAuthorization(
        signers[0],
        {
          target,
          data,
          value,
          delegate,
          nonce,
          address,
        }
      );

      await instance.setQuorum(
        [target, data, value, delegate],
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
