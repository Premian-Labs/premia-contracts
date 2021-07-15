// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable, OwnableStorage} from "@solidstate/contracts/access/Ownable.sol";
import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";

import {TradingCompetitionERC20} from "./TradingCompetitionERC20.sol";

contract TradingCompetitionSwap is Ownable {
    // token -> oracle
    mapping(address => address) public oracles;

    event Swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    //

    constructor() {
        OwnableStorage.layout().owner = msg.sender;
    }

    function setOracle(address _token, address _oracle) external onlyOwner {
        oracles[_token] = _oracle;
    }

    // Swap functions

    function getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) public view returns (uint256) {
        uint256 tokenInPrice = uint256(
            AggregatorInterface(oracles[_tokenIn]).latestAnswer()
        );
        uint256 tokenOutPrice = uint256(
            AggregatorInterface(oracles[_tokenOut]).latestAnswer()
        );

        return (((_amountIn * tokenInPrice) / tokenOutPrice) * 99) / 100;
        // 1% fee burnt
    }

    function getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) public view returns (uint256) {
        uint256 tokenInPrice = uint256(
            AggregatorInterface(oracles[_tokenIn]).latestAnswer()
        );
        uint256 tokenOutPrice = uint256(
            AggregatorInterface(oracles[_tokenOut]).latestAnswer()
        );

        return (((_amountOut * tokenOutPrice) / tokenInPrice) * 100) / 99;
        // 1% fee burnt
    }

    function swapTokenFrom(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external {
        uint256 amountOut = getAmountOut(_tokenIn, _tokenOut, _amountIn);

        TradingCompetitionERC20(_tokenIn).burn(msg.sender, _amountIn);
        TradingCompetitionERC20(_tokenOut).mint(msg.sender, amountOut);

        emit Swap(_tokenIn, _tokenOut, _amountIn, amountOut);
    }

    function swapTokenTo(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external {
        uint256 amountIn = getAmountIn(_tokenIn, _tokenOut, _amountOut);

        TradingCompetitionERC20(_tokenIn).burn(msg.sender, amountIn);
        TradingCompetitionERC20(_tokenOut).mint(msg.sender, _amountOut);

        emit Swap(_tokenIn, _tokenOut, amountIn, _amountOut);
    }
}
