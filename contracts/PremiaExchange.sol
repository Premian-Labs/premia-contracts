pragma solidity >=0.6.0;

import './exchange/Exchange.sol';

contract PremiaExchange is Exchange {
  string public constant name = 'Premia Exchange';

  string public constant version = '0.1';

  string public constant codename = 'Lolwut';

  /**
   * @dev Initialize a PremiaExchange instance
   * @param registryAddress Address of the registry instance which this Exchange instance will use
   * @param tokenAddress Address of the token used for protocol fees
   */
  constructor(
    ProxyRegistry registryAddress,
    TokenTransferProxy tokenTransferProxyAddress,
    ERC20 tokenAddress,
    address protocolFeeAddress
  ) public {
    registry = registryAddress;
    tokenTransferProxy = tokenTransferProxyAddress;
    exchangeToken = tokenAddress;
    protocolFeeRecipient = protocolFeeAddress;
    owner = msg.sender;
  }
}
