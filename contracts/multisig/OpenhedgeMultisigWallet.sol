// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/multisig/ECDSAMultisigWallet.sol';

/**
 * @title Openhedge team wallet
 */
contract OpenhedgeMultisigWallet is ECDSAMultisigWallet {
  using ECDSAMultisigWalletStorage for ECDSAMultisigWalletStorage.Layout;

  constructor (
    address[] memory signers,
    uint quorum
  ) {
    require(
      quorum < signers.length,
      'OpenhedgeMultisigWallet: not enough signers to meet quorum'
    );

    ECDSAMultisigWalletStorage.Layout storage l = ECDSAMultisigWalletStorage.layout();

    for (uint i; i < signers.length; i++) {
      l.addSigner(signers[i]);
    }

    l.setQuorum(quorum);
  }

  /**
   * @notice get whether nonce is valid for given address
   * @param account address to query
   * @param nonce nonce to query
   * @return nonce validity
   */
  function isValidNonce (
    address account,
    uint nonce
  ) external view returns (bool) {
    return !ECDSAMultisigWalletStorage.layout().isInvalidNonce(account, nonce);
  }

  /**
   * @notice set nonce as invalid for sender
   * @param nonce nonce to invalidate
   */
  function invalidateNonce (
    uint nonce
  ) external {
    ECDSAMultisigWalletStorage.layout().setInvalidNonce(msg.sender, nonce);
  }

  /**
   * @notice set account as signer
   * @param parameters struct of parameters, address of target, bytes data, uint value to send with, bool delegate
   * @param signatures array of signatures
   */
  function addSigner (
    Parameters memory parameters,
    Signature[] memory signatures
  ) external {
    _verifySignatures(parameters, signatures);
    address account;
    bytes memory data = parameters.data;
    assembly {
      account := mload(add(data, 20))
    }
    ECDSAMultisigWalletStorage.layout().addSigner(account);
  }

  /**
   * @notice remove account as signer
   * @param parameters struct of parameters, address of target, bytes data, uint value to send with, bool delegate
   * @param signatures array of signatures
   */
  function removeSigner (
    Parameters memory parameters,
    Signature[] memory signatures
  ) external {
    _verifySignatures(parameters, signatures);
    address account;
    bytes memory data = parameters.data;
    assembly {
      account := mload(add(data, 20))
    }
    ECDSAMultisigWalletStorage.layout().removeSigner(account);
  }

  /**
   * @notice set quorum needed to sign
   * @param parameters struct of parameters, address of target, bytes data, uint value to send with, bool delegate
   * @param signatures array of signatures
   */
  function setQuorum (
    Parameters memory parameters,
    Signature[] memory signatures
  ) external {
    _verifySignatures(parameters, signatures);
    // Below code doesn't function as expected
    // assembly {
    //   size := mload(add(parameters.data, 32))
    // }
    // ECDSAMultisigWalletStorage.layout().setQuorum(size);
  }
}
