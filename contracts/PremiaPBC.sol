// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';


/// @author Premia
/// @title Primary Bootstrap Contribution
///        Allow users to contribute ETH to get a share of Premia equal to their percentage of total eth contribution by the end of the PBC
contract PremiaPBC is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The premia token
    IERC20 public premia;

    // The block at which PBC will start
    uint256 public startBlock;
    // The block at which PBC will end
    uint256 public endBlock;

    // The total amount of Premia for the PBC
    uint256 public premiaTotal;
    // The total amount of eth collected
    uint256 public ethTotal;

    // The treasury address which will receive collected eth
    address payable public treasury;

    // Mapping of eth deposited by addresses
    mapping (address => uint256) public amountDeposited;
    // Mapping of addresses which already collected their Premia allocation
    mapping (address => bool) public hasCollected;

    ////////////
    // Events //
    ////////////

    event Contributed(address indexed user, uint256 amount);
    event Collected(address indexed user, uint256 amount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _premia The premia token
    /// @param _startBlock The block at which the PBC will start
    /// @param _endBlock The block at which the PBC will end
    /// @param _treasury The treasury address which will receive collected eth
    constructor(IERC20 _premia, uint256 _startBlock, uint256 _endBlock, address payable _treasury) {
        require(_startBlock < _endBlock, "EndBlock must be greater than StartBlock");
        premia = _premia;
        startBlock = _startBlock;
        endBlock = _endBlock;
        treasury = _treasury;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Add premia which will be distributed in the PBC
    /// @param _amount The amount of premia to add to the PBC
    function addPremia(uint256 _amount) external onlyOwner {
        require(block.number < endBlock, "PBC ended");

        premia.safeTransferFrom(msg.sender, address(this), _amount);
        premiaTotal += _amount;
    }

    /// @notice Send eth collected during the PBC, to the treasury address
    function sendEthToTreasury() external onlyOwner {
        treasury.transfer(address(this).balance);
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    fallback() external payable {
        _contribute();
    }

    /// @notice Deposit ETH to participate in the PBC
    function contribute() external payable {
        _contribute();
    }

    /// @notice Deposit ETH to participate in the PBC
    function _contribute() internal nonReentrant {
        require(block.number >= startBlock, "PBC not started");
        require(msg.value > 0, "No eth sent");
        require(block.number < endBlock, "PBC ended");

        amountDeposited[msg.sender] += msg.value;
        ethTotal += msg.value;
        emit Contributed(msg.sender, msg.value);
    }

    /// @notice Collect Premia allocation after PBC has ended
    function collect() external nonReentrant {
        require(block.number > endBlock, "PBC not ended");
        require(hasCollected[msg.sender] == false, "Address already collected its reward");
        require(amountDeposited[msg.sender] > 0, "Address did not contribute");

        hasCollected[msg.sender] = true;
        uint256 contribution = amountDeposited[msg.sender] * 1e12 / ethTotal;
        uint256 premiaAmount = premiaTotal * contribution / 1e12;
        _safePremiaTransfer(msg.sender, premiaAmount);
        emit Collected(msg.sender, premiaAmount);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Get the current premia price (in eth)
    /// @return The current premia price (in eth)
    function getPremiaPrice() external view returns(uint256) {
        return ethTotal * 1e18 / premiaTotal;
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /// @notice Safe premia transfer function, just in case if rounding error causes contract to not have enough PREMIAs.
    /// @param _to The address to which send premia
    /// @param _amount The amount to send
    function _safePremiaTransfer(address _to, uint256 _amount) internal {
        uint256 premiaBal = premia.balanceOf(address(this));
        if (_amount > premiaBal) {
            premia.safeTransfer(_to, premiaBal);
        } else {
            premia.safeTransfer(_to, _amount);
        }
    }
}
