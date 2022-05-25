// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {NonblockingLzApp} from "../../lzApp/NonblockingLzApp.sol";
import {IOFTCore} from "./IOFTCore.sol";
import {ERC165, IERC165} from "@solidstate/contracts/introspection/ERC165.sol";

abstract contract OFTCore is NonblockingLzApp, ERC165, IOFTCore {
    constructor(address lzEndpoint) NonblockingLzApp(lzEndpoint) {}

    function estimateSendFee(
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        bool useZro,
        bytes memory adapterParams
    ) public view virtual override returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for send()
        bytes memory payload = abi.encode(toAddress, amount);
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
        // decode and load the toAddress
        (bytes memory toAddressBytes, uint256 amount) = abi.decode(
            payload,
            (bytes, uint256)
        );
        address toAddress;
        assembly {
            toAddress := mload(add(toAddressBytes, 20))
        }

        _creditTo(srcChainId, toAddress, amount);

        emit ReceiveFromChain(srcChainId, srcAddress, toAddress, amount, nonce);
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

        bytes memory payload = abi.encode(toAddress, amount);
        _lzSend(
            dstChainId,
            payload,
            refundAddress,
            zroPaymentAddress,
            adapterParams
        );

        uint64 nonce = lzEndpoint.getOutboundNonce(dstChainId, address(this));
        emit SendToChain(from, dstChainId, toAddress, amount, nonce);
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
