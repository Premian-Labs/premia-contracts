const factory = {
  PriceConsumer: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('PriceConsumer', deployer);
    const instance = await factory.deploy();
    return await instance.deployed();
  },

  ProxyManager: async function ({ deployer }) {
    const factory = await ethers.getContractFactory('ProxyManager', deployer);
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

  Median: async function ({ deployer, facetCuts, pairImplementation, poolImplementation }) {
    const factory = await ethers.getContractFactory('Median', deployer);
    const instance = await factory.deploy(
      pairImplementation,
      poolImplementation
    );
    await instance.deployed();

    await instance.connect(deployer).diamondCut(facetCuts, ethers.constants.AddressZero, '0x');

    return instance;
  },
};

module.exports = factory;
