const { expect } = require('chai');

const describeBehaviorOfECDSAMultisigWallet = require('@solidstate/contracts/test/multisig/ECDSAMultisigWallet.behavior.js');

const quorum = ethers.constants.One;

const getSigners = async function () {
  return (await ethers.getSigners()).slice(0, 3);
};

const getNonSigner = async function () {
  return (await ethers.getSigners())[3];
};

const signAuthorization = async function (signer, { target, data, value, delegate, nonce, address }) {
  const types = ['address', 'bytes', 'uint256', 'bool', 'uint256', 'address'];
  const values = [target, data, value, delegate, nonce, address];

  const hash = ethers.utils.solidityKeccak256(types, values);

  const signature = await signer.signMessage(ethers.utils.arrayify(hash));
  return ethers.utils.arrayify(signature);
};

describe('OpenhedgeMultisigWallet', function () {
  let owner;

  let factory;
  let instance;

  beforeEach(async function () {
    factory = await ethers.getContractFactory('OpenhedgeMultisigWallet', owner);
    instance = await factory.deploy(
      (await getSigners()).map(s => s.address),
      quorum
    );
    await instance.deployed();
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfECDSAMultisigWallet({
    deploy: () => instance,
    getSigners,
    getNonSigner,
    quorum,
    signAuthorization,
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
