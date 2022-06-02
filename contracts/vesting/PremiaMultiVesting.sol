// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeOwnable} from "@solidstate/contracts/access/SafeOwnable.sol";
import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

/**
 * @author Premia
 * @title A vesting contract allowing to set multiple deposits for multiple users, with 1 year vesting
 */
contract PremiaMultiVesting is SafeOwnable {
    using SafeERC20 for IERC20;

    struct Deposit {
        uint256 amount; // Amount of tokens
        uint256 eta; // Timestamp at which tokens will unlock
    }

    IERC20 public premia;

    // User -> Deposit id -> Deposit
    mapping(address => mapping(uint256 => Deposit)) public deposits;

    // User -> Last deposit id claimed
    mapping(address => uint256) public lastClaimedDepositId;

    // User -> Id of last deposit added
    mapping(address => uint256) public depositsLength;

    event DepositAdded(
        address indexed user,
        uint256 depositId,
        uint256 amount,
        uint256 eta
    );
    event DepositClaimed(
        address indexed user,
        uint256 depositId,
        uint256 amount
    );
    event DepositCancelled(address indexed user, uint256 depositId);

    constructor(IERC20 _premia) {
        OwnableStorage.layout().owner = msg.sender;

        premia = _premia;
    }

    function addDeposits(
        address[] memory _users,
        uint256[] memory _amounts,
        uint256[] memory _vestingPeriods
    ) external onlyOwner {
        require(
            _users.length == _amounts.length &&
                _users.length == _vestingPeriods.length,
            "Array diff length"
        );

        uint256 total;
        for (uint256 i = 0; i < _users.length; ++i) {
            total += _amounts[i];
        }

        premia.safeTransferFrom(msg.sender, address(this), total);

        for (uint256 i = 0; i < _users.length; ++i) {
            if (_amounts[i] == 0) continue;

            uint256 eta = block.timestamp + _vestingPeriods[i];

            uint256 lastDepositId = depositsLength[_users[i]];
            require(
                lastDepositId == 0 ||
                    deposits[_users[i]][lastDepositId].eta < eta,
                "ETA must be > prev deposit ETA"
            );

            uint256 depositId = lastDepositId + 1;
            depositsLength[_users[i]] = depositId;

            deposits[_users[i]][depositId] = Deposit(_amounts[i], eta);

            emit DepositAdded(_users[i], depositId, _amounts[i], eta);
        }
    }

    function cancelVesting(address _user) external onlyOwner {
        uint256 lastDepositId = depositsLength[_user];

        if (lastDepositId == 0) return;

        uint256 tokenAmount;

        for (uint256 i = lastDepositId; i > 0; i--) {
            // First deposit found which is claimable
            if (deposits[_user][i].eta < block.timestamp) {
                break;
            }

            tokenAmount += deposits[_user][i].amount;

            delete deposits[_user][i];
            depositsLength[_user] -= 1;

            emit DepositCancelled(_user, i);
        }

        if (tokenAmount > 0) {
            premia.transfer(OwnableStorage.layout().owner, tokenAmount);
        }
    }

    function claimDeposits() external {
        uint256 lastIdClaimed = lastClaimedDepositId[msg.sender];

        uint256 tokenAmount;
        Deposit memory deposit = deposits[msg.sender][lastIdClaimed + 1];

        while (deposit.eta != 0 && deposit.eta < block.timestamp) {
            tokenAmount += deposit.amount;

            lastIdClaimed++;
            deposit = deposits[msg.sender][lastIdClaimed + 1];

            emit DepositClaimed(msg.sender, lastIdClaimed, tokenAmount);
        }

        if (tokenAmount > 0) {
            lastClaimedDepositId[msg.sender] = lastIdClaimed;
            premia.transfer(msg.sender, tokenAmount);
        }
    }

    function getPendingDeposits(address _user)
        external
        view
        returns (Deposit[] memory)
    {
        Deposit[] memory result = new Deposit[](
            depositsLength[_user] - lastClaimedDepositId[_user]
        );

        uint256 idx = 0;
        for (
            uint256 i = lastClaimedDepositId[_user] + 1;
            i < depositsLength[_user] + 1;
            ++i
        ) {
            result[idx] = deposits[_user][i];
            idx++;
        }

        return result;
    }
}
