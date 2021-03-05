// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPremiaMining {
    function deposit(uint256 _pid, uint256 _amount) external;
}

/// @author Premia
/// @title Token to drain reward from the deprecated interaction mining contract towards the mining fund
contract PremiaMiningDrain is ERC20("MiningDrainToken", "MiningDrain") {
    IERC20 public premia = IERC20(0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70);
    IPremiaMining public premiaMining = IPremiaMining(0xf0f16B3460512554d4D821DD482dbfb78817EC43);
    address public miningFund = 0x81d6F46981B4fE4A6FafADDa716eE561A17761aE;
    uint256 public pid = 1;

    constructor() public {
        _mint(address(this), 1);
    }

    function transferReward() public {
        // Harvest pending reward
        premiaMining.deposit(pid, 0);
        premia.transfer(miningFund, premia.balanceOf(address(this)));
    }

    function deposit() public {
        _approve(address(this), address(premiaMining), 1);
        premiaMining.deposit(pid, 1);
    }
}