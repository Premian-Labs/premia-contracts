// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";

import {IProxyManager} from "./IProxyManager.sol";
import {ProxyManagerStorage} from "./ProxyManagerStorage.sol";
import {PoolProxy} from "../pool/PoolProxy.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Premia as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
    using ProxyManagerStorage for ProxyManagerStorage.Layout;

    // 64x64 fixed point representation of 2e
    int128 private constant INITIAL_C_LEVEL_64x64 = 0x56fc2a2c515da32ea;

    event DeployPool(
        address indexed base,
        address indexed underlying,
        int128 indexed initialCLevel64x64,
        address baseOracle,
        address underlyingOracle,
        address pool
    );

    /**
     * @notice get address of Pool implementation contract for forwarding via PoolProxy
     * @return implementation address
     */
    function getPoolImplementation() external view override returns (address) {
        return ProxyManagerStorage.layout().poolImplementation;
    }

    /**
     * @notice get address of Pool contract for given assets
     * @param base base token
     * @param underlying underlying token
     * @return pool address (zero address if pool does not exist)
     */
    function getPool(address base, address underlying)
        external
        view
        returns (address)
    {
        return ProxyManagerStorage.layout().getPool(base, underlying);
    }

    /**
     * @notice get address list of all Pool contracts
     * @return list of pool addresses
     */
    function getPoolList() external view override returns (address[] memory) {
        return ProxyManagerStorage.layout().poolList;
    }

    /**
     * @notice set address of Pool implementation contract
     * @param poolImplementation Pool implementation address
     */
    function setPoolImplementation(address poolImplementation)
        external
        onlyOwner
    {
        ProxyManagerStorage.layout().poolImplementation = poolImplementation;
    }

    /**
     * @notice deploy PoolProxy contracts for the pair
     * @param base base token
     * @param underlying underlying token
     * @param baseOracle Chainlink price aggregator for base
     * @param underlyingOracle Chainlink price aggregator for underlying
     * TODO: unrestrict
     * @return deployment address
     */
    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        int128 emaVarianceAnnualized64x64
    ) external onlyOwner returns (address) {
        ProxyManagerStorage.Layout storage l = ProxyManagerStorage.layout();

        require(
            l.getPool(base, underlying) == address(0),
            "ProxyManager: Pool already exists"
        );

        address pool = address(
            new PoolProxy(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                emaVarianceAnnualized64x64,
                INITIAL_C_LEVEL_64x64
            )
        );
        l.setPool(base, underlying, underlyingOracle);

        l.poolList.push(pool);

        emit DeployPool(
            base,
            underlying,
            INITIAL_C_LEVEL_64x64,
            baseOracle,
            underlyingOracle,
            pool
        );

        return pool;
    }
}
