// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";

import {IProxyManager} from "./IProxyManager.sol";
import {ProxyManagerStorage} from "./ProxyManagerStorage.sol";
import {PoolProxy} from "../pool/PoolProxy.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {IPoolView} from "../pool/IPoolView.sol";
import {IPremiaMining} from "../mining/IPremiaMining.sol";

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Premia as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
    using ProxyManagerStorage for ProxyManagerStorage.Layout;

    address private immutable DIAMOND;

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

    constructor(address diamond) {
        DIAMOND = diamond;
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
     * @notice deploy PoolProxy contracts for the pair
     * @param base base token
     * @param underlying underlying token
     * @param baseOracle Chainlink price aggregator for base
     * @param underlyingOracle Chainlink price aggregator for underlying
     * @param baseMinimum64x64 64x64 fixed point representation of minimum base currency amount
     * @param underlyingMinimum64x64 64x64 fixed point representation of minimum underlying currency amount
     * @param basePoolCap64x64 64x64 fixed point representation of pool-wide base currency deposit cap
     * @param underlyingPoolCap64x64 64x64 fixed point representation of pool-wide underlying currency deposit cap
     * @param miningAllocPoints alloc points attributed per pool (call and put) for liquidity mining
     * @return deployment address
     */
    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        int128 baseMinimum64x64,
        int128 underlyingMinimum64x64,
        int128 basePoolCap64x64,
        int128 underlyingPoolCap64x64,
        uint256 miningAllocPoints
    ) external onlyOwner returns (address) {
        ProxyManagerStorage.Layout storage l = ProxyManagerStorage.layout();

        require(
            l.getPool(base, underlying) == address(0),
            "ProxyManager: Pool already exists"
        );

        address pool = address(
            new PoolProxy(
                DIAMOND,
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                baseMinimum64x64,
                underlyingMinimum64x64,
                basePoolCap64x64,
                underlyingPoolCap64x64,
                INITIAL_C_LEVEL_64x64
            )
        );
        l.setPool(base, underlying, underlyingOracle);

        l.poolList.push(pool);

        IPremiaMining(IPoolView(DIAMOND).getPremiaMining()).addPool(
            pool,
            miningAllocPoints
        );

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
