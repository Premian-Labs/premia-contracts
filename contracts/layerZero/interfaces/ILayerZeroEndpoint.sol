// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ILayerZeroUserApplicationConfig} from "./ILayerZeroUserApplicationConfig.sol";

interface ILayerZeroEndpoint is ILayerZeroUserApplicationConfig {
    /**
     * @notice send a LayerZero message to the specified address at a LayerZero endpoint.
     * @param dstChainId - the destination chain identifier
     * @param destination - the address on destination chain (in bytes). address length/format may vary by chains
     * @param payload - a custom bytes payload to send to the destination contract
     * @param refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
     * @param zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
     * @param adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
     */
    function send(
        uint16 dstChainId,
        bytes calldata destination,
        bytes calldata payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external payable;

    /**
     * @notice used by the messaging library to publish verified payload
     * @param srcChainId - the source chain identifier
     * @param srcAddress - the source contract (as bytes) at the source chain
     * @param dstAddress - the address on destination chain
     * @param nonce - the unbound message ordering nonce
     * @param gasLimit - the gas limit for external contract execution
     * @param payload - verified payload to send to the destination contract
     */
    function receivePayload(
        uint16 srcChainId,
        bytes calldata srcAddress,
        address dstAddress,
        uint64 nonce,
        uint256 gasLimit,
        bytes calldata payload
    ) external;

    /*
     * @notice get the inboundNonce of a lzApp from a source chain which could be EVM or non-EVM chain
     * @param srcChainId - the source chain identifier
     * @param srcAddress - the source chain contract address
     */
    function getInboundNonce(
        uint16 srcChainId,
        bytes calldata srcAddress
    ) external view returns (uint64);

    /*
     * @notice get the outboundNonce from this source chain which, consequently, is always an EVM
     * @param srcAddress - the source chain contract address
     */
    function getOutboundNonce(
        uint16 dstChainId,
        address srcAddress
    ) external view returns (uint64);

    /*
     * @notice gets a quote in source native gas, for the amount that send() requires to pay for message delivery
     * @param dstChainId - the destination chain identifier
     * @param userApplication - the user app address on this EVM chain
     * @param payload - the custom message to send over LayerZero
     * @param payInZRO - if false, user app pays the protocol fee in native token
     * @param adapterParam - parameters for the adapter service, e.g. send some dust native token to dstChain
     */
    function estimateFees(
        uint16 dstChainId,
        address userApplication,
        bytes calldata payload,
        bool payInZRO,
        bytes calldata adapterParam
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    /*
     * @notice get this Endpoint's immutable source identifier
     */
    function getChainId() external view returns (uint16);

    /*
     * @notice the interface to retry failed message on this Endpoint destination
     * @param srcChainId - the source chain identifier
     * @param srcAddress - the source chain contract address
     * @param payload - the payload to be retried
     */
    function retryPayload(
        uint16 srcChainId,
        bytes calldata srcAddress,
        bytes calldata payload
    ) external;

    /*
     * @notice query if any STORED payload (message blocking) at the endpoint.
     * @param srcChainId - the source chain identifier
     * @param srcAddress - the source chain contract address
     */
    function hasStoredPayload(
        uint16 srcChainId,
        bytes calldata srcAddress
    ) external view returns (bool);

    /*
     * @notice query if the libraryAddress is valid for sending msgs.
     * @param userApplication - the user app address on this EVM chain
     */
    function getSendLibraryAddress(
        address userApplication
    ) external view returns (address);

    /*
     * @notice query if the libraryAddress is valid for receiving msgs.
     * @param userApplication - the user app address on this EVM chain
     */
    function getReceiveLibraryAddress(
        address userApplication
    ) external view returns (address);

    /*
     * @notice query if the non-reentrancy guard for send() is on
     * @return true if the guard is on. false otherwise
     */
    function isSendingPayload() external view returns (bool);

    /*
     * @notice query if the non-reentrancy guard for receive() is on
     * @return true if the guard is on. false otherwise
     */
    function isReceivingPayload() external view returns (bool);

    /*
     * @notice get the configuration of the LayerZero messaging library of the specified version
     * @param version - messaging library version
     * @param chainId - the chainId for the pending config change
     * @param userApplication - the contract address of the user application
     * @param configType - type of configuration. every messaging library has its own convention.
     */
    function getConfig(
        uint16 version,
        uint16 chainId,
        address userApplication,
        uint256 configType
    ) external view returns (bytes memory);

    /*
     * @notice get the send() LayerZero messaging library version
     * @param userApplication - the contract address of the user application
     */
    function getSendVersion(
        address userApplication
    ) external view returns (uint16);

    /*
     * @notice get the lzReceive() LayerZero messaging library version
     * @param userApplication - the contract address of the user application
     */
    function getReceiveVersion(
        address userApplication
    ) external view returns (uint16);
}
