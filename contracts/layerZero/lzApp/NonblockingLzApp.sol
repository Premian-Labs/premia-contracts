// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {LzApp} from "./LzApp.sol";
import {NonblockingLzAppStorage} from "./NonblockingLzAppStorage.sol";
import {ExcessivelySafeCall} from "../util/ExcessivelySafeCall.sol";

/*
 * the default LayerZero messaging behaviour is blocking, i.e. any failed message will block the channel
 * this abstract class try-catch all fail messages and store locally for future retry. hence, non-blocking
 * NOTE: if the srcAddress is not configured properly, it will still block the message pathway from (srcChainId, srcAddress)
 */
abstract contract NonblockingLzApp is LzApp {
    using ExcessivelySafeCall for address;

    constructor(address endpoint) LzApp(endpoint) {}

    event MessageFailed(
        uint16 srcChainId,
        bytes srcAddress,
        uint64 nonce,
        bytes payload,
        bytes reason
    );
    event RetryMessageSuccess(
        uint16 srcChainId,
        bytes srcAddress,
        uint64 nonce,
        bytes32 payloadHash
    );

    // overriding the virtual function in LzReceiver
    function _blockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal virtual override {
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(
                this.nonblockingLzReceive.selector,
                srcChainId,
                srcAddress,
                nonce,
                payload
            )
        );
        // try-catch all errors/exceptions
        if (!success) {
            NonblockingLzAppStorage.layout().failedMessages[srcChainId][
                srcAddress
            ][nonce] = keccak256(payload);
            emit MessageFailed(srcChainId, srcAddress, nonce, payload, reason);
        }
    }

    function nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) public virtual {
        // only internal transaction
        require(
            msg.sender == address(this),
            "NonblockingLzApp: caller must be LzApp"
        );
        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    // override this function
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal virtual;

    function retryMessage(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) public payable virtual {
        NonblockingLzAppStorage.Layout storage l = NonblockingLzAppStorage
            .layout();

        // assert there is message to retry
        bytes32 payloadHash = l.failedMessages[srcChainId][srcAddress][nonce];
        require(
            payloadHash != bytes32(0),
            "NonblockingLzApp: no stored message"
        );
        require(
            keccak256(payload) == payloadHash,
            "NonblockingLzApp: invalid payload"
        );
        // clear the stored message
        delete l.failedMessages[srcChainId][srcAddress][nonce];
        // execute the message. revert if it fails again
        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
        emit RetryMessageSuccess(srcChainId, srcAddress, nonce, payloadHash);
    }

    function failedMessages(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce
    ) external view returns (bytes32) {
        return
            NonblockingLzAppStorage.layout().failedMessages[srcChainId][
                srcAddress
            ][nonce];
    }
}
