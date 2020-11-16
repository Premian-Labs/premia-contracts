pragma solidity >=0.6.0;

contract ReentrancyGuarded {
  bool reentrancyLock = false;

  /* Prevent a contract function from being reentrant-called. */
  modifier reentrancyGuard {
    if (reentrancyLock) {
      revert();
    }
    reentrancyLock = true;
    _;
    reentrancyLock = false;
  }
}
