const fs = require('fs');
const rimraf = require('rimraf');

rimraf.sync('./abi');

if (!fs.existsSync('./abi')) {
  fs.mkdirSync('./abi');
}

fs.mkdirSync('./abi/core');
fs.mkdirSync('./abi/libraries');
fs.mkdirSync('./abi/pair');
fs.mkdirSync('./abi/pool');

fs.copyFileSync(
  './artifacts/contracts/core/Median.sol/Median.json',
  './abi/core/Median.json'
);

fs.copyFileSync(
  './artifacts/contracts/core/ProxyManager.sol/ProxyManager.json',
  './abi/core/ProxyManager.json'
);

fs.copyFileSync(
  './artifacts/contracts/core/ProxyManagerStorage.sol/ProxyManagerStorage.json',
  './abi/core/ProxyManagerStorage.json'
);

fs.copyFileSync(
  './artifacts/contracts/libraries/ABDKMath64x64Token.sol/ABDKMath64x64Token.json',
  './abi/libraries/ABDKMath64x64Token.json'
);

fs.copyFileSync(
  './artifacts/contracts/libraries/OptionMath.sol/OptionMath.json',
  './abi/libraries/OptionMath.json'
);

fs.copyFileSync(
  './artifacts/contracts/pair/Pair.sol/Pair.json',
  './abi/pair/Pair.json'
);

fs.copyFileSync(
  './artifacts/contracts/pair/PairProxy.sol/PairProxy.json',
  './abi/pair/PairProxy.json'
);

fs.copyFileSync(
  './artifacts/contracts/pair/PairStorage.sol/PairStorage.json',
  './abi/pair/PairStorage.json'
);

fs.copyFileSync(
  './artifacts/contracts/pool/Pool.sol/Pool.json',
  './abi/pool/Pool.json'
);

fs.copyFileSync(
  './artifacts/contracts/pool/PoolProxy.sol/PoolProxy.json',
  './abi/pool/PoolProxy.json'
);

fs.copyFileSync(
  './artifacts/contracts/pool/PoolStorage.sol/PoolStorage.json',
  './abi/pool/PoolStorage.json'
);

rimraf.sync('./contractsTyped');
