// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ILayerZeroReceiver} from "../interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "../interfaces/ILayerZeroUserApplicationConfig.sol";
import {ILayerZeroEndpoint} from "../interfaces/ILayerZeroEndpoint.sol";
import {LzAppStorage} from "./LzAppStorage.sol";
import {BytesLib} from "../util/BytesLib.sol";

/*
 * a generic LzReceiver implementation
 */
abstract contract LzApp is
    OwnableInternal,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig
{
    using BytesLib for bytes;

    ILayerZeroEndpoint public immutable lzEndpoint;

    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);

    error LzApp__InvalidEndpointCaller();
    error LzApp__InvalidSource();
    error LzApp__NotTrustedSource();
    error LzApp__NoTrustedPathRecord();

    constructor(address endpoint) {
        lzEndpoint = ILayerZeroEndpoint(endpoint);
    }

    /**
     * @inheritdoc ILayerZeroReceiver
     */
    function lzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) public virtual {
        // lzReceive must be called by the endpoint for security
        if (msg.sender != address(lzEndpoint))
            revert LzApp__InvalidEndpointCaller();

        bytes memory trustedRemote = LzAppStorage.layout().trustedRemoteLookup[
            srcChainId
        ];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        if (
            srcAddress.length != trustedRemote.length ||
            keccak256(srcAddress) != keccak256(trustedRemote)
        ) revert LzApp__InvalidSource();

        _blockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    // abstract function - the default behaviour of LayerZero is blocking. See: NonblockingLzApp if you dont need to enforce ordered messaging
    function _blockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal virtual;

    function _lzSend(
        uint16 dstChainId,
        bytes memory payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams,
        uint256 nativeFee
    ) internal virtual {
        bytes memory trustedRemote = LzAppStorage.layout().trustedRemoteLookup[
            dstChainId
        ];
        if (trustedRemote.length == 0) revert LzApp__NotTrustedSource();
        lzEndpoint.send{value: nativeFee}(
            dstChainId,
            trustedRemote,
            payload,
            refundAddress,
            zroPaymentAddress,
            adapterParams
        );
    }

    //---------------------------UserApplication config----------------------------------------
    function getConfig(
        uint16 version,
        uint16 chainId,
        address,
        uint256 configType
    ) external view returns (bytes memory) {
        return
            lzEndpoint.getConfig(version, chainId, address(this), configType);
    }

    /**
     * @inheritdoc ILayerZeroUserApplicationConfig
     */
    function setConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType,
        bytes calldata config
    ) external onlyOwner {
        lzEndpoint.setConfig(version, chainId, configType, config);
    }

    /**
     * @inheritdoc ILayerZeroUserApplicationConfig
     */
    function setSendVersion(uint16 version) external onlyOwner {
        lzEndpoint.setSendVersion(version);
    }

    /**
     * @inheritdoc ILayerZeroUserApplicationConfig
     */
    function setReceiveVersion(uint16 version) external onlyOwner {
        lzEndpoint.setReceiveVersion(version);
    }

    /**
     * @inheritdoc ILayerZeroUserApplicationConfig
     */
    function forceResumeReceive(uint16 srcChainId, bytes calldata srcAddress)
        external
        onlyOwner
    {
        lzEndpoint.forceResumeReceive(srcChainId, srcAddress);
    }

    // allow owner to set it multiple times.
    function setTrustedRemote(uint16 srcChainId, bytes calldata srcAddress)
        external
        onlyOwner
    {
        LzAppStorage.layout().trustedRemoteLookup[srcChainId] = srcAddress;
        emit SetTrustedRemote(srcChainId, srcAddress);
    }

    function getTrustedRemoteAddress(uint16 _remoteChainId)
        external
        view
        returns (bytes memory)
    {
        bytes memory path = LzAppStorage.layout().trustedRemoteLookup[
            _remoteChainId
        ];
        if (path.length == 0) revert LzApp__NoTrustedPathRecord();
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    function setPrecrime(address _precrime) external onlyOwner {
        LzAppStorage.layout().precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    //--------------------------- VIEW FUNCTION ----------------------------------------

    function isTrustedRemote(uint16 srcChainId, bytes calldata srcAddress)
        external
        view
        returns (bool)
    {
        bytes memory trustedSource = LzAppStorage.layout().trustedRemoteLookup[
            srcChainId
        ];
        return keccak256(trustedSource) == keccak256(srcAddress);
    }
}
