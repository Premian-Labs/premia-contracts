// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {NonblockingLzApp} from "../../lzApp/NonblockingLzApp.sol";
import {IOFTCore} from "./IOFTCore.sol";
import {ERC165, IERC165} from "@solidstate/contracts/introspection/ERC165.sol";
import {BytesLib} from "../../util/BytesLib.sol";

abstract contract OFTCore is NonblockingLzApp, ERC165, IOFTCore {
    using BytesLib for bytes;

    // packet type
    uint16 public constant PT_SEND = 0;

    constructor(address lzEndpoint) NonblockingLzApp(lzEndpoint) {}

    function estimateSendFee(
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        bool useZro,
        bytes memory adapterParams
    ) public view virtual override returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for send()
        bytes memory payload = abi.encode(
            PT_SEND,
            abi.encodePacked(msg.sender),
            toAddress,
            amount
        );
        return
            lzEndpoint.estimateFees(
                dstChainId,
                address(this),
                payload,
                useZro,
                adapterParams
            );
    }

    function sendFrom(
        address from,
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) public payable virtual override {
        _send(
            from,
            dstChainId,
            toAddress,
            amount,
            refundAddress,
            zroPaymentAddress,
            adapterParams
        );
    }

    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal virtual override {
        uint16 packetType;
        assembly {
            packetType := mload(add(payload, 32))
        }

        if (packetType == PT_SEND) {
            _sendAck(srcChainId, srcAddress, nonce, payload);
        } else {
            revert("OFTCore: unknown packet type");
        }
    }

    function _send(
        address from,
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal virtual {
        _debitFrom(from, dstChainId, toAddress, amount);

        bytes memory payload = abi.encode(
            PT_SEND,
            abi.encodePacked(from),
            toAddress,
            amount
        );

        _lzSend(
            dstChainId,
            payload,
            refundAddress,
            zroPaymentAddress,
            adapterParams,
            msg.value
        );

        emit SendToChain(from, dstChainId, toAddress, amount);
    }

    function _sendAck(
        uint16 srcChainId,
        bytes memory,
        uint64,
        bytes memory payload
    ) internal virtual {
        (, bytes memory from, bytes memory toAddressBytes, uint256 amount) = abi
            .decode(payload, (uint16, bytes, bytes, uint256));

        address to = toAddressBytes.toAddress(0);

        _creditTo(srcChainId, to, amount);
        emit ReceiveFromChain(srcChainId, from, to, amount);
    }

    function _debitFrom(
        address from,
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount
    ) internal virtual;

    function _creditTo(
        uint16 srcChainId,
        address toAddress,
        uint256 amount
    ) internal virtual;
}
