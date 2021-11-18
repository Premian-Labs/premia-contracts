// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@solidstate/contracts/token/ERC20/ERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";
import {ERC20Permit} from "@solidstate/contracts/token/ERC20/permit/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPremiaStaking} from "./IPremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";

contract PremiaStaking is IPremiaStaking, ERC20, ERC20Permit {
    using SafeERC20 for IERC20;

    address private immutable PREMIA;

    event Deposit(address indexed user, uint256 amount);
    event StartWithdrawal(
        address indexed user,
        uint256 premiaAmount,
        uint256 startDate
    );
    event Withdrawal(address indexed user, uint256 amount);

    constructor(address premia) {
        PREMIA = premia;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        IERC2612(PREMIA).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        deposit(amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function deposit(uint256 amount) public override {
        // Gets the amount of Premia locked in the contract
        uint256 totalPremia = _getStakedPremiaAmount();

        // Gets the amount of xPremia in existence
        uint256 totalShares = _totalSupply();
        // If no xPremia exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalPremia == 0) {
            _mint(msg.sender, amount);
        }
        // Calculate and mint the amount of xPremia the Premia is worth. The ratio will change overtime, as xPremia is burned/minted and Premia deposited + gained from fees / withdrawn.
        else {
            uint256 what = (amount * totalShares) / totalPremia;
            _mint(msg.sender, what);
        }

        // Lock the Premia in the contract
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function startWithdraw(uint256 amount) external override {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        // Gets the amount of xPremia in existence
        uint256 totalShares = _totalSupply();

        // Calculates the amount of Premia the xPremia is worth
        uint256 what = (amount * _getStakedPremiaAmount()) / totalShares;
        _burn(msg.sender, amount);
        l.pendingWithdrawal += what;

        l.withdrawals[msg.sender].amount += what;
        l.withdrawals[msg.sender].startDate = block.timestamp;

        emit StartWithdrawal(msg.sender, what, block.timestamp);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function withdraw() external override {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 startDate = l.withdrawals[msg.sender].startDate;

        require(startDate > 0, "No pending withdrawal");
        require(
            block.timestamp > startDate + l.withdrawalDelay,
            "Withdrawal still pending"
        );

        uint256 amount = l.withdrawals[msg.sender].amount;

        l.pendingWithdrawal -= amount;
        delete l.withdrawals[msg.sender];

        IERC20(PREMIA).safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getWithdrawalDelay() external view override returns (uint256) {
        return PremiaStakingStorage.layout().withdrawalDelay;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getXPremiaToPremiaRatio()
        external
        view
        override
        returns (uint256)
    {
        return (_getStakedPremiaAmount() * 1e18) / _totalSupply();
    }

    function getPendingWithdrawal(address user)
        external
        view
        override
        returns (PremiaStakingStorage.Withdrawal memory)
    {
        return PremiaStakingStorage.layout().withdrawals[user];
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getStakedPremiaAmount() external view override returns (uint256) {
        return _getStakedPremiaAmount();
    }

    function _getStakedPremiaAmount() internal view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return IERC20(PREMIA).balanceOf(address(this)) - l.pendingWithdrawal;
    }
}
