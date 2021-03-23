// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import "./PremiaLiquidityPool.sol";
import "../interface/IPoolControllerChild.sol";
import "../interface/IPremiaMiningV2.sol";

contract PremiaPoolController is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct DepositArgs {
        address pool;
        address[] tokens;
        uint256[] amounts;
        uint256 lockExpiration;
    }

    struct WithdrawExpiredArgs {
        address pool;
        address[] tokens;
    }

    struct Permissions {
      bool canBorrow;
      bool canWrite;
      bool isWhitelistedToken;
      bool isWhitelistedPool;
    }

    uint256 public constant _inverseBasisPoint = 1000;

    IPremiaMiningV2 public premiaMining;

    // Mapping of addresses with special permissions (Contracts who can borrow / write or whitelisted routers / tokens)
    mapping(address => Permissions) public permissions;

    // Set a custom swap path for a token
    mapping(address => mapping(address => address[])) public customSwapPaths;

    // Each token swap path requires a designated router to ensure liquid swapping
    mapping(address => mapping(address => IUniswapV2Router02)) public designatedSwapRouters;

    // The LTV ratio for each token usable as collateral
    mapping(address => uint256) loanToValueRatios;

    PremiaLiquidityPool[] public callPools;
    PremiaLiquidityPool[] public putPools;

    ///////////
    // Event //
    ///////////

    event PermissionsUpdated(address indexed addr, bool canBorrow, bool canWrite, bool isWhitelistedToken, bool isWhitelistedPool);
    event PremiaMiningUpdated(address indexed _addr);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function upgradeController(IPoolControllerChild[] memory _children, address _newController) external onlyOwner {
        for (uint256 i=0; i < _children.length; i++) {
            _children[i].upgradeController(_newController);
        }
    }

    function setPermissions(address[] memory _addr, Permissions[] memory _permissions) external onlyOwner {
        require(_addr.length == _permissions.length, "Arrays diff length");

        for (uint256 i=0; i < _addr.length; i++) {
            permissions[_addr[i]] = _permissions[i];

            emit PermissionsUpdated(_addr[i], 
                                    _permissions[i].canBorrow, 
                                    _permissions[i].canWrite, 
                                    _permissions[i].isWhitelistedToken, 
                                    _permissions[i].isWhitelistedPool);
        }
    }
    
    /// @notice Set a custom swap path for a token
    /// @param _collateralToken The collateral token
    /// @param _token The token
    /// @param _path The swap path
    function setCustomSwapPath(address _collateralToken, address _token, address[] memory _path) external onlyOwner {
        customSwapPaths[_collateralToken][_token] = _path;
    }

    /// @notice Set a designated router for a pair of tokens
    /// @param _tokenA The first token
    /// @param _tokenB The second token
    /// @param _router The router to swap with
    function setDesignatedSwapRouter(address _tokenA, address _tokenB, IUniswapV2Router02 _router) external onlyOwner {
        designatedSwapRouters[_tokenA][_tokenB] = _router;
        designatedSwapRouters[_tokenB][_tokenA] = _router;
    }

    /// @notice Set a custom loan to calue ratio for a collateral token
    /// @param _collateralToken The collateral token
    /// @param _loanToValueRatio The LTV ratio to use
    function setLoanToValueRatio(address _collateralToken, uint256 _loanToValueRatio) external onlyOwner {
        require(_loanToValueRatio <= _inverseBasisPoint);
        loanToValueRatios[_collateralToken] = _loanToValueRatio;
    }

    function setPremiaMining(IPremiaMiningV2 _premiaMining) external onlyOwner {
        premiaMining = _premiaMining;
        emit PremiaMiningUpdated(address(_premiaMining));
    }

    //////////
    // View //
    //////////

    function getPermissions(address _user) external view returns (Permissions memory) {
        return permissions[_user];
    }

    function getCustomSwapPath(address _fromToken, address _toToken) external view returns (address[] memory) {
        return customSwapPaths[_fromToken][_toToken];
    }

    function getDesignedSwapRouter(address _fromToken, address _toToken) external view returns (IUniswapV2Router02) {
        return designatedSwapRouters[_fromToken][_toToken];
    }

    function getLoanToValueRatio(address _token) external view returns (uint256) {
        return loanToValueRatios[_token];
    }

    function getCallPools() external view returns (PremiaLiquidityPool[] memory) {
        return callPools;
    }

    function getPutPools() external view returns (PremiaLiquidityPool[] memory) {
        return putPools;
    }

    //////////
    // Main //
    //////////

    function deposit(DepositArgs[] memory _deposits) external nonReentrant {
        for (uint256 i=0; i < _deposits.length; i++) {
            require(permissions[_deposits[i].pool].isWhitelistedPool, "Pool not whitelisted");

            PremiaLiquidityPool(_deposits[i].pool).depositFrom(msg.sender, _deposits[i].tokens, _deposits[i].amounts, _deposits[i].lockExpiration);

            if (address(premiaMining) != address(0)) {
                for (uint256 j=0; j < _deposits[i].tokens.length; j++) {
                    premiaMining.deposit(msg.sender, _deposits[i].tokens[j], _deposits[i].amounts[j], _deposits[i].lockExpiration);
                }
            }
        }
    }

    function withdrawExpired(WithdrawExpiredArgs[] memory _withdrawals) external nonReentrant {
        for (uint256 i=0; i < _withdrawals.length; i++) {
            require(permissions[_withdrawals[i].pool].isWhitelistedPool, "Pool not whitelisted");

            PremiaLiquidityPool(_withdrawals[i].pool).withdrawExpiredFrom(msg.sender, _withdrawals[i].tokens);
        }
    }
}
