import fs from 'fs';
import rimraf from 'rimraf';

rimraf.sync('./abi');

if (!fs.existsSync('./abi')) {
  fs.mkdirSync('./abi');
}

fs.copyFileSync(
  './artifacts/contracts/PremiaErc20.sol/PremiaErc20.json',
  './abi/PremiaErc20.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaFeeDiscount.sol/PremiaFeeDiscount.json',
  './abi/PremiaFeeDiscount.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaFluxErc20.sol/PremiaFluxErc20.json',
  './abi/PremiaFluxErc20.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaMarket.sol/PremiaMarket.json',
  './abi/PremiaMarket.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaMining.sol/PremiaMining.json',
  './abi/PremiaMining.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaOption.sol/PremiaOption.json',
  './abi/PremiaOption.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaReferral.sol/PremiaReferral.json',
  './abi/PremiaReferral.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaStaking.sol/PremiaStaking.json',
  './abi/PremiaStaking.json',
);
fs.copyFileSync(
  './artifacts/contracts/PremiaVesting.sol/PremiaVesting.json',
  './abi/PremiaVesting.json',
);

// Test contracts
fs.copyFileSync(
  './artifacts/contracts/test/TestErc20.sol/TestErc20.json',
  './abi/TestErc20.json',
);
fs.copyFileSync(
  './artifacts/contracts/test/TestPremiaFeeDiscount.sol/TestPremiaFeeDiscount.json',
  './abi/TestPremiaFeeDiscount.json',
);
fs.copyFileSync(
  './artifacts/contracts/test/TestFlashLoan.sol/TestFlashLoan.json',
  './abi/TestFlashLoan.json',
);

rimraf.sync('./contractsTyped');
