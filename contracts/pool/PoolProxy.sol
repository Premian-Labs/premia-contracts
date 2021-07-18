// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";
import {ERC165Storage} from "@solidstate/contracts/introspection/ERC165Storage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IDiamondLoupe} from "@solidstate/contracts/proxy/diamond/IDiamondLoupe.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/IERC20Metadata.sol";
import {IERC1155} from "@solidstate/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@solidstate/contracts/introspection/IERC165.sol";

import {IProxyManager} from "../core/IProxyManager.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title Upgradeable proxy with centrally controlled Pool implementation
 */
contract PoolProxy is Proxy {
    using PoolStorage for PoolStorage.Layout;
    using ERC165Storage for ERC165Storage.Layout;

    address private immutable DIAMOND;

    constructor(
        address diamond,
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        int128 emaVarianceAnnualized64x64,
        int128 initialCLevel64x64
    ) {
        DIAMOND = diamond;
        OwnableStorage.layout().owner = msg.sender;

        {
            PoolStorage.Layout storage l = PoolStorage.layout();

            l.base = base;
            l.underlying = underlying;

            l.setOracles(baseOracle, underlyingOracle);

            l.baseDecimals = IERC20Metadata(base).decimals();
            l.underlyingDecimals = IERC20Metadata(underlying).decimals();
            l.cLevelBase64x64 = initialCLevel64x64;
            l.cLevelUnderlying64x64 = initialCLevel64x64;

            int128 newPrice64x64 = l.fetchPriceUpdate();
            l.setPriceUpdate(block.timestamp, newPrice64x64);

            l.emaVarianceAnnualized64x64 = emaVarianceAnnualized64x64;

            l.updatedAt = block.timestamp;
        }

        {
            ERC165Storage.Layout storage l = ERC165Storage.layout();
            l.setSupportedInterface(type(IERC165).interfaceId, true);
            l.setSupportedInterface(type(IERC1155).interfaceId, true);
        }
    }

    function _getImplementation() internal view override returns (address) {
        return IDiamondLoupe(DIAMOND).facetAddress(msg.sig);
    }
}
