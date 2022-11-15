// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILayerZeroUserApplicationConfig {
    /*
     * @notice set the configuration of the LayerZero messaging library of the specified version
     * @param version - messaging library version
     * @param chainId - the chainId for the pending config change
     * @param configType - type of configuration. every messaging library has its own convention.
     * @param config - configuration in the bytes. can encode arbitrary content.
     */
    function setConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType,
        bytes calldata config
    ) external;

    /*
     * @notice set the send() LayerZero messaging library version to version
     * @param version - new messaging library version
     */
    function setSendVersion(uint16 version) external;

    /*
     * @notice set the lzReceive() LayerZero messaging library version to version
     * @param version - new messaging library version
     */
    function setReceiveVersion(uint16 version) external;

    /*
     * @notice Only when the UA needs to resume the message flow in blocking mode and clear the stored payload
     * @param srcChainId - the chainId of the source chain
     * @param srcAddress - the contract address of the source contract at the source chain
     */
    function forceResumeReceive(
        uint16 srcChainId,
        bytes calldata srcAddress
    ) external;
}
