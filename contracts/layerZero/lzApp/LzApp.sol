// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ILayerZeroReceiver} from "../interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "../interfaces/ILayerZeroUserApplicationConfig.sol";
import {ILayerZeroEndpoint} from "../interfaces/ILayerZeroEndpoint.sol";
import {LzAppStorage} from "./LzAppStorage.sol";

/*
 * a generic LzReceiver implementation
 */
abstract contract LzApp is
    OwnableInternal,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig
{
    ILayerZeroEndpoint public immutable lzEndpoint;

    event SetTrustedRemote(uint16 srcChainId, bytes srcAddress);

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
        require(
            msg.sender == address(lzEndpoint),
            "LzApp: invalid endpoint caller"
        );

        LzAppStorage.Layout storage l = LzAppStorage.layout();

        bytes memory trustedRemote = l.trustedRemoteLookup[srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        require(
            srcAddress.length == trustedRemote.length &&
                keccak256(srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );

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
        bytes memory adapterParams
    ) internal virtual {
        LzAppStorage.Layout storage l = LzAppStorage.layout();

        bytes memory trustedRemote = l.trustedRemoteLookup[dstChainId];
        require(
            trustedRemote.length != 0,
            "LzApp: destination chain is not a trusted source"
        );
        lzEndpoint.send{value: msg.value}(
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
        LzAppStorage.Layout storage l = LzAppStorage.layout();
        l.trustedRemoteLookup[srcChainId] = srcAddress;
        emit SetTrustedRemote(srcChainId, srcAddress);
    }

    //--------------------------- VIEW FUNCTION ----------------------------------------

    function isTrustedRemote(uint16 srcChainId, bytes calldata srcAddress)
        external
        view
        returns (bool)
    {
        LzAppStorage.Layout storage l = LzAppStorage.layout();
        bytes memory trustedSource = l.trustedRemoteLookup[srcChainId];
        return keccak256(trustedSource) == keccak256(srcAddress);
    }
}
