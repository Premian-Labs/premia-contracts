// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

contract TimelockMultisig {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    EnumerableSet.AddressSet signers;

    uint256 internal constant AUTHORIZATION_REQUIRED_INSTANT = 3;
    uint256 internal constant AUTHORIZATION_REQUIRED_EXPEDITED = 2;
    uint256 internal constant REJECTION_REQUIRED = 2;

    address public immutable TOKEN;
    address public immutable PANIC_ADDRESS;

    mapping(address => bool) authorized;
    mapping(address => bool) rejected;

    bool private hasPanicked;

    uint256[] private rejectionTimestamps;

    struct Withdrawal {
        address to;
        uint256 amount;
        uint256 createdAt;
    }

    Withdrawal public pendingWithdrawal;

    event StartWithdrawal(
        address indexed signer,
        address to,
        uint256 amount,
        uint256 createdAt
    );

    event SignAuthorization(
        address indexed signer,
        address to,
        uint256 amount,
        uint256 createdAt
    );

    event SignRejection(
        address indexed signer,
        address to,
        uint256 amount,
        uint256 createdAt
    );

    event Withdraw(address indexed to, uint256 amount);

    event RejectionSuccess();

    event AuthorizationSuccess();

    modifier isSigner() {
        require(signers.contains(msg.sender), "not signer");
        _;
    }

    modifier hasPendingWithdrawal(bool status) {
        require(
            (pendingWithdrawal.createdAt > 0) == status,
            "invalid pending withdrawal status"
        );
        _;
    }

    constructor(
        address token,
        address panicAddress,
        address[4] memory _signers
    ) {
        TOKEN = token;
        PANIC_ADDRESS = panicAddress;

        for (uint256 i = 0; i < _signers.length; i++) {
            signers.add(_signers[i]);
        }
    }

    function startWithdraw(
        address to,
        uint256 amount
    ) external isSigner hasPendingWithdrawal(false) {
        uint256 createdAt = block.timestamp;
        pendingWithdrawal = Withdrawal(to, amount, createdAt);

        authorized[msg.sender] = true;

        emit StartWithdrawal(msg.sender, to, amount, createdAt);
    }

    function authorize() external isSigner hasPendingWithdrawal(true) {
        delete rejected[msg.sender];
        authorized[msg.sender] = true;

        emit SignAuthorization(
            msg.sender,
            pendingWithdrawal.to,
            pendingWithdrawal.amount,
            pendingWithdrawal.createdAt
        );

        if (_canWithdraw()) {
            emit AuthorizationSuccess();
            _withdraw();
        }
    }

    function reject() external isSigner hasPendingWithdrawal(true) {
        delete authorized[msg.sender];
        rejected[msg.sender] = true;

        emit SignRejection(
            msg.sender,
            pendingWithdrawal.to,
            pendingWithdrawal.amount,
            pendingWithdrawal.createdAt
        );

        uint256 rejectionCount;
        for (uint256 i = 0; i < signers.length(); i++) {
            if (rejected[signers.at(i)]) {
                rejectionCount++;
            }

            if (rejectionCount == REJECTION_REQUIRED) {
                emit RejectionSuccess();
                _reset();

                if (!hasPanicked) {
                    rejectionTimestamps.push(block.timestamp);

                    uint256 length = rejectionTimestamps.length;

                    if (length >= 3) {
                        if (length >= 4) {
                            delete rejectionTimestamps[length - 4];
                        }

                        if (
                            rejectionTimestamps[length - 3] >
                            block.timestamp - 10 days
                        ) {
                            hasPanicked = true;
                            IERC20(TOKEN).safeTransfer(
                                PANIC_ADDRESS,
                                IERC20(TOKEN).balanceOf(address(this)) / 4
                            );
                        }
                    }
                }

                return;
            }
        }
    }

    function doWithdraw() external isSigner hasPendingWithdrawal(true) {
        require(_canWithdraw(), "not ready");
        _withdraw();
    }

    function _canWithdraw() internal view returns (bool) {
        if (pendingWithdrawal.createdAt + 7 days < block.timestamp) return true;

        uint256 authorizationCount;

        for (uint256 i = 0; i < signers.length(); i++) {
            if (authorized[signers.at(i)]) authorizationCount++;
        }

        if (authorizationCount >= AUTHORIZATION_REQUIRED_INSTANT) return true;

        if (
            authorizationCount >= AUTHORIZATION_REQUIRED_EXPEDITED &&
            pendingWithdrawal.createdAt + 2 days < block.timestamp
        ) return true;

        return false;
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
