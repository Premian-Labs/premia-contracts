import fs from 'fs';

if (!fs.existsSync('./abi')) {
  fs.mkdirSync('./abi');
}

fs.copyFileSync(
  './artifacts/contracts/PremiaErc20.sol/PremiaErc20.json',
  './abi/PremiaErc20.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaOption.sol/PremiaOption.json',
  './abi/PremiaOption.json',
);
fs.copyFileSync(
  './artifacts/contracts/TestErc20.sol/TestErc20.json',
  './abi/TestErc20.json',
);
