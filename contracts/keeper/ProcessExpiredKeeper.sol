// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import {IProxyManager} from "../core/IProxyManager.sol";
import {IPool} from "../pool/IPool.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

contract ProcessExpiredKeeper is KeeperCompatibleInterface {
    address private immutable PREMIA_DIAMOND;

    constructor(address premiaDiamond) {
        PREMIA_DIAMOND = premiaDiamond;
    }

    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address[] memory poolList = IProxyManager(PREMIA_DIAMOND).getPoolList();

        for (uint256 i = 0; i < poolList.length; i++) {
            IPool pool = IPool(poolList[i]);

            uint256[] memory tokenIds = pool.getTokenIds();

            uint256[] memory filtered = new uint256[](tokenIds.length);
            uint256 resultCount;

            for (uint256 j = 0; j < tokenIds.length; j++) {
                (
                    PoolStorage.TokenType tokenType,
                    uint64 maturity,

                ) = PoolStorage.parseTokenId(tokenIds[j]);

                if (
                    (tokenType != PoolStorage.TokenType.LONG_CALL &&
                        tokenType != PoolStorage.TokenType.LONG_PUT) ||
                    (maturity > block.timestamp)
                ) {
                    filtered[j] = 0;
                    continue;
                }

                filtered[j] = tokenIds[j];
                resultCount++;
            }

            if (resultCount > 0) {
                uint256[] memory result = new uint256[](resultCount);
                uint256 currentIndex;
                for (uint256 j = 0; j < filtered.length; j++) {
                    if (filtered[j] == 0) continue;
                    filtered[currentIndex] = filtered[j];
                    currentIndex++;
                }

                return (true, abi.encode(poolList[i], result));
            }
        }

        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        (address poolAddress, uint256[] memory toProcess) = abi.decode(
            performData,
            (address, uint256[])
        );

        IPool pool = IPool(poolAddress);
        for (uint256 i = 0; i < toProcess.length; i++) {
            pool.processAllExpired(toProcess[i]);
        }
    }
}
