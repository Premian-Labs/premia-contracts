// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

import "./interface/IKeeperCompatible.sol";
import "./interface/IERC20Extended.sol";
import "./interface/IPremiaMaker.sol";
import "./interface/IPremiaOption.sol";

contract PremiaMakerKeeper is IKeeperCompatible, Ownable {
  IPremiaMaker public premiaMaker = IPremiaMaker(0xcb81dB76Ae0a46c6e1E378E3Ade61DaB275ff96E);
  IPremiaOption public premiaOptionDai = IPremiaOption(0x5920cb60B1c62dC69467bf7c6EDFcFb3f98548c0);

  uint256 minConvertValueInEth = 1e18; // 1 ETH

  function setMinConvertValueInEth(uint256 _minConvertValueInEth) external onlyOwner {
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
  function checkUpkeep(bytes calldata checkData) external view override returns (bool upkeepNeeded, bytes memory performData) {
    (IUniswapV2Router02 router) = abi.decode(checkData, (IUniswapV2Router02));
    address[] memory potentialTokens = premiaOptionDai.tokens();
    address weth = router.WETH();

    address token;
    for (uint256 i = 0; i < potentialTokens.length; i++) {
      token = potentialTokens[i];
      uint256 balance = IERC20(token).balanceOf(address(premiaMaker));
      uint256 convertValueInEth;

      if (token != weth) {
          address[] memory path = premiaMaker.customPath(token);

          if (path.length == 0) {
              path = new address[](2);
              path[0] = token;
              path[1] = weth;
          }

          uint256[] memory amounts = router.getAmountsOut(balance, path);

          convertValueInEth = amounts[1];
      } else {
          convertValueInEth = balance;
      }

      if (convertValueInEth > minConvertValueInEth) {
          return (true, abi.encode(token, router));
      }
    }

    return (false, abi.encode(token, router));
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
  function performUpkeep(bytes calldata performData) external override {
    (address token, IUniswapV2Router02 router) = abi.decode(performData, (address, IUniswapV2Router02));
    premiaMaker.convert(router, token);
  }
}

