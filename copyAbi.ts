import fs from 'fs';
import rimraf from 'rimraf';

rimraf.sync('./abi');

if (!fs.existsSync('./abi')) {
  fs.mkdirSync('./abi');
}

fs.copyFileSync(
  './artifacts/contracts/core/Median.sol/Median.json',
  './abi/Median.json',
);
fs.copyFileSync(
  './artifacts/contracts/core/ProxyManager.sol/ProxyManager.json',
  './abi/ProxyManager.json',
);
fs.copyFileSync(
  './artifacts/contracts/pair/Pair.sol/Pair.json',
  './abi/Pair.json',
);
fs.copyFileSync(
  './artifacts/contracts/pool/Pool.sol/Pool.json',
  './abi/Pool.json',
);

rimraf.sync('./typechain');
