pragma solidity >=0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract TokenRecipient {
  event ReceivedEther(address indexed sender, uint256 amount);
  event ReceivedTokens(
    address indexed from,
    uint256 value,
    address indexed token,
    bytes extraData
  );

  /**
   * @dev Receive tokens and generate a log event
   * @param from Address from which to transfer tokens
   * @param value Amount of tokens to transfer
   * @param token Address of token
   * @param extraData Additional data to log
   */
  function receiveApproval(
    address from,
    uint256 value,
    address token,
    bytes extraData
  ) public {
    IERC20 t = IERC20(token);
    require(t.transferFrom(from, this, value));
    emit ReceivedTokens(from, value, token, extraData);
  }

  /**
   * @dev Receive Ether and generate a log event
   */
  fallback() public payable {
    emit ReceivedEther(msg.sender, msg.value);
  }
}
