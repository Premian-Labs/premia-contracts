// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

contract TimelockMultisig {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    EnumerableSet.AddressSet signers;

    uint256 internal constant AUTHORIZATION_REQUIRED = 3;
    uint256 internal constant REJECTION_REQUIRED = 2;

    address public immutable TOKEN;

    mapping(address => bool) authorized;
    mapping(address => bool) rejected;

    struct Withdrawal {
        address to;
        uint256 amount;
        uint256 eta;
    }

    Withdrawal public pendingWithdrawal;

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

    modifier isSigner() {
        require(signers.contains(msg.sender), "not signer");
        _;
    }

    constructor(address token, address[4] memory _signers) {
        TOKEN = token;

        for (uint256 i = 0; i < _signers.length; i++) {
            signers.add(_signers[i]);
        }
    }

    function startWithdraw(address to, uint256 amount) external isSigner {
        require(
            pendingWithdrawal.to == address(0) &&
                pendingWithdrawal.eta == 0 &&
                pendingWithdrawal.amount == 0,
            "pending withdrawal"
        );

        uint256 eta = block.timestamp + 7 days;
        pendingWithdrawal = Withdrawal(to, amount, eta);

        authorized[msg.sender] = true;

        emit StartWithdrawal(msg.sender, to, amount, eta);
    }

    function authorize() external isSigner {
        delete rejected[msg.sender];
        authorized[msg.sender] = true;

        emit SignAuthorization(
            msg.sender,
            pendingWithdrawal.to,
            pendingWithdrawal.amount,
            pendingWithdrawal.eta
        );

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

    function reject() external isSigner {
        delete authorized[msg.sender];
        rejected[msg.sender] = true;

        emit SignRejection(
            msg.sender,
            pendingWithdrawal.to,
            pendingWithdrawal.amount,
            pendingWithdrawal.eta
        );

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

    function doWithdraw() external isSigner {
        require(
            pendingWithdrawal.eta > 0 &&
                block.timestamp > pendingWithdrawal.eta,
            "not ready"
        );
        _withdraw();
    }

    function _reset() internal {
        delete pendingWithdrawal;

        for (uint256 i = 0; i < signers.length(); i++) {
            delete authorized[signers.at(i)];
            delete rejected[signers.at(i)];
        }
    }

    function _withdraw() internal {
        address to = pendingWithdrawal.to;
        uint256 amount = pendingWithdrawal.amount;

        _reset();

        IERC20(TOKEN).safeTransfer(to, amount);

        emit Withdraw(to, amount);
    }
}
