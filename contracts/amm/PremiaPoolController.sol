// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import "../interface/IPremiaLiquidityPool.sol";
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

    uint256 public constant _inverseBasisPoint = 1000;

    IPremiaMiningV2 public premiaMining;

    // Set a custom swap path for a token
    mapping(address => mapping(address => address[])) customSwapPaths;

    // Each token swap path requires a designated router to ensure liquid swapping
    mapping(address => mapping(address => IUniswapV2Router02)) public _designatedSwapRouters;

    // Default swap router to use in case no custom router has been set for a pair
    IUniswapV2Router02 public defaultSwapRouter;

    // The LTV ratio for each token usable as collateral
    mapping(address => uint256) public loanToValueRatios;

    EnumerableSet.AddressSet private _callPools;
    EnumerableSet.AddressSet private _putPools;

    ///////////
    // Event //
    ///////////

    event DefaultSwapRouterUpdated(IUniswapV2Router02 indexed router);
    event PairSwapRouterUpdated(address indexed tokenA, address indexed tokenB, IUniswapV2Router02 indexed router);
    event CustomSwapPathUpdated(address indexed collateralToken, address indexed token, address[] path);
    event LoanToValueRatioUpdated(address indexed collateralToken, uint256 loanToValueRatio);
    event PremiaMiningUpdated(address indexed addr);

    event CallPoolAdded(address indexed addr);
    event CallPoolRemoved(address indexed addr);
    event PutPoolAdded(address indexed addr);
    event PutPoolRemoved(address indexed addr);

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

    function addPools(address[] memory _callPoolsAddr, address[] memory _putPoolsAddr) external onlyOwner {
        for (uint256 i=0; i < _callPoolsAddr.length; i++) {
            _callPools.add(_callPoolsAddr[i]);
            emit CallPoolAdded(_callPoolsAddr[i]);
        }

        for (uint256 i=0; i < _putPoolsAddr.length; i++) {
            _putPools.add(_putPoolsAddr[i]);
            emit PutPoolAdded(_putPoolsAddr[i]);
        }
    }

    function removePools(address[] memory _callPoolsAddr, address[] memory _putPoolsAddr) external onlyOwner {
        for (uint256 i=0; i < _callPoolsAddr.length; i++) {
            _callPools.remove(_callPoolsAddr[i]);
            emit CallPoolRemoved(_callPoolsAddr[i]);
        }

        for (uint256 i=0; i < _putPoolsAddr.length; i++) {
            _putPools.remove(_putPoolsAddr[i]);
            emit PutPoolRemoved(_putPoolsAddr[i]);
        }
    }

    /// @notice Set a custom swap path for a token
    /// @param _collateralToken The collateral token
    /// @param _token The token
    /// @param _path The swap path
    function setCustomSwapPath(address _collateralToken, address _token, address[] memory _path) external onlyOwner {
        customSwapPaths[_collateralToken][_token] = _path;
        emit CustomSwapPathUpdated(_collateralToken, _token, _path);
    }

    /// @notice Set a designated router for a pair of tokens
    /// @param _tokenA The first token
    /// @param _tokenB The second token
    /// @param _router The router to swap with
    function setDesignatedSwapRouter(address _tokenA, address _tokenB, IUniswapV2Router02 _router) external onlyOwner {
        require(_tokenA != _tokenB, "Identical addresses");
        (address _tokenA, address _tokenB) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenA, _tokenB);
        require(_tokenA != address(0), 'Zero address');

        _designatedSwapRouters[_tokenA][_tokenB] = _router;
        emit PairSwapRouterUpdated(_tokenA, _tokenB, _router);
    }

    function setDefaultSwapRouter(IUniswapV2Router02 _router) external onlyOwner {
        defaultSwapRouter = _router;
        emit DefaultSwapRouterUpdated(_router);
    }

    /// @notice Set a custom loan to calue ratio for a collateral token
    /// @param _collateralToken The collateral token
    /// @param _loanToValueRatio The LTV ratio to use
    function setLoanToValueRatio(address _collateralToken, uint256 _loanToValueRatio) external onlyOwner {
        require(_loanToValueRatio <= _inverseBasisPoint);
        loanToValueRatios[_collateralToken] = _loanToValueRatio;
        emit LoanToValueRatioUpdated(_collateralToken, _loanToValueRatio);
    }

    function setPremiaMining(IPremiaMiningV2 _premiaMining) external onlyOwner {
        premiaMining = _premiaMining;
        emit PremiaMiningUpdated(address(_premiaMining));
    }

    //////////
    // View //
    //////////

    function getDesignatedSwapRouter(address _tokenA, address _tokenB) external view returns(IUniswapV2Router02) {
        require(_tokenA != _tokenB, "Identical addresses");
        (address _tokenA, address _tokenB) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenA, _tokenB);
        require(_tokenA != address(0), 'Zero address');

        IUniswapV2Router02 swapRouter = _designatedSwapRouters[_tokenA][_tokenB];

        if (address(swapRouter) == address(0)) return defaultSwapRouter;

        return swapRouter;
    }

    function getCallPools() external view returns(IPremiaLiquidityPool[] memory) {
        uint256 length = _callPools.length();
        IPremiaLiquidityPool[] memory result = new IPremiaLiquidityPool[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = IPremiaLiquidityPool(_callPools.at(i));
        }

        return result;
    }

    function getPutPools() external view returns(IPremiaLiquidityPool[] memory) {
        uint256 length = _putPools.length();
        IPremiaLiquidityPool[] memory result = new IPremiaLiquidityPool[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = IPremiaLiquidityPool(_putPools.at(i));
        }

        return result;
    }

    //////////
    // Main //
    //////////

    function deposit(DepositArgs[] memory _deposits) external nonReentrant {
        for (uint256 i=0; i < _deposits.length; i++) {
            require(_callPools.contains(_deposits[i].pool) || _putPools.contains(_deposits[i].pool), "Pool not whitelisted");

            IPremiaLiquidityPool(_deposits[i].pool).depositFrom(msg.sender, _deposits[i].tokens, _deposits[i].amounts, _deposits[i].lockExpiration);

            if (address(premiaMining) != address(0)) {
                for (uint256 j=0; j < _deposits[i].tokens.length; j++) {
                    premiaMining.deposit(msg.sender, _deposits[i].tokens[j], _deposits[i].amounts[j], _deposits[i].lockExpiration);
                }
            }
        }
    }

    function withdrawExpired(WithdrawExpiredArgs[] memory _withdrawals) external nonReentrant {
        for (uint256 i=0; i < _withdrawals.length; i++) {
            require(_callPools.contains(_withdrawals[i].pool) || _putPools.contains(_withdrawals[i].pool), "Pool not whitelisted");

            IPremiaLiquidityPool(_withdrawals[i].pool).withdrawExpiredFrom(msg.sender, _withdrawals[i].tokens);
        }
    }
}
