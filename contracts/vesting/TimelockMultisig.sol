// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";

contract TimelockMultisig {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet signers;

    uint256 internal constant AUTHORIZATION_REQUIRED = 3;
    uint256 internal constant REJECTION_REQUIRED = 2;

    mapping(address => bool) authorized;
    mapping(address => bool) rejected;

    address to;
    uint256 amount;
    uint256 eta;

    event StartWithdrawal(
        address indexed signer,
        address to,
        uint256 amount,
        uint256 eta
    );

    event SignAuthorization(
        address indexed signer,
        address to,
        uint256 amount,
        uint256 eta
    );

    event SignRejection(
        address indexed signer,
        address to,
        uint256 amount,
        uint256 eta
    );

    event Withdraw(address indexed to, uint256 amount);

    event RejectionSuccess();

    event AuthorizationSuccess();

    receive() external payable {}

    constructor(address[4] memory _signers) {
        for (uint256 i = 0; i < _signers.length; i++) {
            signers.add(_signers[i]);
        }
    }

    function startWithdraw(address _to, uint256 _amount) external {
        require(signers.contains(msg.sender), "not signer");
        require(
            to == address(0) && eta == 0 && amount == 0,
            "pending withdrawal"
        );

        to = _to;
        amount = _amount;
        eta = block.timestamp + 7 days;

        delete rejected[msg.sender];
        authorized[msg.sender] = true;

        emit StartWithdrawal(msg.sender, _to, _amount, eta);
    }

    function authorize() external {
        require(signers.contains(msg.sender), "not signer");
        delete rejected[msg.sender];
        authorized[msg.sender] = true;

        emit SignAuthorization(msg.sender, to, amount, eta);

        uint256 authorizationCount;
        for (uint256 i = 0; i < signers.length(); i++) {
            if (authorized[signers.at(i)]) {
                authorizationCount++;
            }

            if (authorizationCount == AUTHORIZATION_REQUIRED) {
                emit AuthorizationSuccess();
                _withdraw();
                return;
            }
        }
    }

    function reject() external {
        require(signers.contains(msg.sender), "not signer");
        delete authorized[msg.sender];
        rejected[msg.sender] = true;

        emit SignRejection(msg.sender, to, amount, eta);

        uint256 rejectionCount;
        for (uint256 i = 0; i < signers.length(); i++) {
            if (rejected[signers.at(i)]) {
                rejectionCount++;
            }

            if (rejectionCount == REJECTION_REQUIRED) {
                emit RejectionSuccess();
                _reset();
                return;
            }
        }
    }

    function doWithdraw() external {
        require(eta > 0 && block.timestamp > eta, "not ready");
        _withdraw();
    }

    function _reset() internal {
        delete to;
        delete amount;
        delete eta;

        for (uint256 i = 0; i < signers.length(); i++) {
            delete authorized[signers.at(i)];
            delete rejected[signers.at(i)];
        }
    }

    function _withdraw() internal {
        address _to = to;
        uint256 _amount = amount;

        _reset();

        (bool success, ) = _to.call{value: _amount}("");
        require(success, "transfer failed");

        emit Withdraw(_to, _amount);
    }
}
