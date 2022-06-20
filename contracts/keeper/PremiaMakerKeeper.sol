// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {Ownable} from "@solidstate/contracts/access/Ownable.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@solidstate/contracts/token/ERC1155/IERC1155.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {IKeeperCompatible} from "../interfaces/IKeeperCompatible.sol";
import {IPremiaMaker} from "../interfaces/IPremiaMaker.sol";
import {IProxyManager} from "../core/IProxyManager.sol";
import {IPoolView} from "../pool/IPoolView.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

contract PremiaMakerKeeper is IKeeperCompatible, Ownable {
    address internal immutable PREMIA_MAKER;
    address internal immutable PREMIA_DIAMOND;

    uint256 public minConvertValueInEth = 1e18; // 1 ETH

    constructor(address _premiaMaker, address _premiaDiamond) {
        PREMIA_MAKER = _premiaMaker;
        PREMIA_DIAMOND = _premiaDiamond;
    }

    function setMinConvertValueInEth(uint256 _minConvertValueInEth)
        external
        onlyOwner
    {
        minConvertValueInEth = _minConvertValueInEth;
    }

    /**
     * @notice method that is simulated by the keepers to see if any work actually
     * needs to be performed. This method does does not actually need to be
     * executable, and since it is only ever simulated it can consume lots of gas.
     * @dev To ensure that it is never called, you may want to add the
     * cannotExecute modifier from KeeperBase to your implementation of this
     * method.
     * @param checkData specified in the upkeep registration so it is always the
     * same for a registered upkeep. This can easily be broken down into specific
     * arguments using `abi.decode`, so multiple upkeeps can be registered on the
     * same contract and easily differentiated by the contract.
     * @return upkeepNeeded boolean to indicate whether the keeper should call
     * performUpkeep or not.
     * @return performData bytes that the keeper should call performUpkeep with, if
     * upkeep is needed. If you would like to encode data to decode later, try
     * `abi.encode`.
     */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address[] memory pools = IProxyManager(PREMIA_DIAMOND).getPoolList();

        uint256 baseReservedTokenId = PoolStorage.formatTokenId(
            PoolStorage.TokenType.BASE_RESERVED_LIQ,
            0,
            0
        );
        uint256 underlyingReservedTokenId = PoolStorage.formatTokenId(
            PoolStorage.TokenType.UNDERLYING_RESERVED_LIQ,
            0,
            0
        );

        address router = abi.decode(checkData, (address));

        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];

            PoolStorage.PoolSettings memory pSettings = IPoolView(pool)
                .getPoolSettings();
            address feeReceiver = IPoolView(pool).getFeeReceiverAddress();

            uint256 baseEthValue;
            uint256 underlyingEthValue;

            {
                uint256 baseFee = IERC1155(pool).balanceOf(
                    feeReceiver,
                    baseReservedTokenId
                );
                uint256 underlyingFee = IERC1155(pool).balanceOf(
                    feeReceiver,
                    underlyingReservedTokenId
                );

                // Calculate total amount in premia maker contract after withdrawal
                uint256 baseTotal = IERC20(pSettings.base).balanceOf(
                    PREMIA_MAKER
                ) + baseFee;
                uint256 underlyingTotal = IERC20(pSettings.underlying)
                    .balanceOf(PREMIA_MAKER) + underlyingFee;

                baseEthValue = _getEthValue(router, pSettings.base, baseTotal);
                underlyingEthValue = _getEthValue(
                    router,
                    pSettings.underlying,
                    underlyingTotal
                );
            }

            uint256 nbToConvert;
            if (baseEthValue > minConvertValueInEth) nbToConvert++;
            if (underlyingEthValue > minConvertValueInEth) nbToConvert++;

            address[] memory tokensToConvert;
            if (nbToConvert > 0) {
                tokensToConvert = new address[](nbToConvert);
                uint256 j;

                if (baseEthValue > minConvertValueInEth) {
                    tokensToConvert[j] = pSettings.base;
                    j++;
                }

                if (underlyingEthValue > minConvertValueInEth) {
                    tokensToConvert[j] = pSettings.underlying;
                }

                return (true, abi.encode(pool, router, tokensToConvert));
            }
        }

        return (false, "");
    }

    /**
     * @notice method that is actually executed by the keepers, via the registry.
     * The data returned by the checkUpkeep simulation will be passed into
     * this method to actually be executed.
     * @dev The input to this method should not be trusted, and the caller of the
     * method should not even be restricted to any single registry. Anyone should
     * be able call it, and the input should be validated, there is no guarantee
     * that the data passed in is the performData returned from checkUpkeep. This
     * could happen due to malicious keepers, racing keepers, or simply a state
     * change while the performUpkeep transaction is waiting for confirmation.
     * Always validate the data passed in.
     * @param performData is the data which was passed back from the checkData
     * simulation. If it is encoded, it can easily be decoded into other types by
     * calling `abi.decode`. This data should not be trusted, and should be
     * validated against the contract's current state.
     */
    function performUpkeep(bytes calldata performData) external {
        (address pool, address router, address[] memory tokens) = abi.decode(
            performData,
            (address, address, address[])
        );

        IPremiaMaker(PREMIA_MAKER).withdrawFeesAndConvert(pool, router, tokens);
    }

    function _getEthValue(
        address _router,
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        if (_amount == 0) return 0;

        address nativeToken = IUniswapV2Router02(_router).WETH();
        if (_token == nativeToken) return _amount;

        address[] memory path = IPremiaMaker(PREMIA_MAKER).getCustomPath(
            _token
        );

        if (path.length == 0) {
            path = new address[](2);
            path[0] = _token;
            path[1] = nativeToken;
        }

        uint256[] memory amounts = IUniswapV2Router02(_router).getAmountsOut(
            _amount,
            path
        );

        return amounts[1];
    }
}
