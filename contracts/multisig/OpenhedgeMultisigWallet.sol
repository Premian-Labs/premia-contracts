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
   * @notice return whether given address is authorized signer
   * @param account address to query
   * @return whether address is signer
   */
  function isSigner (
    address account
  ) external view returns (bool) {
    return ECDSAMultisigWalletStorage.layout().isSigner(account);
  }

  /**
   * @notice get quorum for authorization
   * @return quorum
   */
  function getQuorum () external view returns (uint) {
    return ECDSAMultisigWalletStorage.layout().quorum;
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
   * @param parameters structured call parameters (target, data, value, delegate)
   * @param signatures array of structured signature data (signature, nonce)
   */
  function addSigner (
    Parameters memory parameters,
    Signature[] memory signatures
  ) external {
    _verifySignatures(parameters, signatures);

    bytes memory data = parameters.data;
    address account;

    assembly {
      account := mload(add(data, 20))
    }

    ECDSAMultisigWalletStorage.layout().addSigner(account);
  }

  /**
   * @notice remove account as signer
   * @param parameters structured call parameters (target, data, value, delegate)
   * @param signatures array of structured signature data (signature, nonce)
   */
  function removeSigner (
    Parameters memory parameters,
    Signature[] memory signatures
  ) external {
    _verifySignatures(parameters, signatures);

    bytes memory data = parameters.data;
    address account;

    assembly {
      account := mload(add(data, 20))
    }

    ECDSAMultisigWalletStorage.layout().removeSigner(account);
  }

  /**
   * @notice set quorum needed to sign
   * @param parameters structured call parameters (target, data, value, delegate)
   * @param signatures array of structured signature data (signature, nonce)
   */
  function setQuorum (
    Parameters memory parameters,
    Signature[] memory signatures
    ) external {
    _verifySignatures(parameters, signatures);

    bytes memory data = parameters.data;
    uint size;

    assembly {
      size := mload(add(data, 32))
    }

    ECDSAMultisigWalletStorage.layout().setQuorum(size >> (256 - data.length * 8));
  }
}
