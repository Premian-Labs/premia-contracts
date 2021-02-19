const factory = {
  DiamondCuttable: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('DiamondCuttable', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  DiamondFacet: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('DiamondFacet', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  DiamondLoupe: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('DiamondLoupe', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  SafeOwnable: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('SafeOwnable', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  Pair: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('Pair', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  Pool: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('Pool', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  Openhedge: async function ({ deployer, facetCuts, pairImplementation, poolImplementation }) {
    const factory = await ethers.getContractFactory('Openhedge', deployer);
    const instance = await factory.deploy(
      facetCuts,
      pairImplementation,
      poolImplementation
    );
    return await instance.deployed();
  },
};

module.exports = factory;
