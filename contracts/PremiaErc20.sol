pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PremiaErc20 is ERC20 {
    constructor(uint256 amount) public ERC20("Premia", "PREM") {
        _mint(msg.sender, amount);
    }
}