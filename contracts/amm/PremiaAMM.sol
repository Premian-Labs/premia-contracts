// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';
import "../interface/IPremiaMiningV2.sol";
import "../interface/IPoolControllerChild.sol";

contract PremiaAMM is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
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

    enum SaleSide {Buy, Sell}

    // The oracle used to get black scholes prices on chain.
    IBlackScholesPriceGetter public blackScholesOracle;

    IPremiaMiningV2 public premiaMining;

    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Each token swap path requires a designated router to ensure liquid swapping
    mapping(address => mapping(address => IUniswapV2Router02)) public _designatedSwapRouters;

    EnumerableSet.AddressSet private _callPools;
    EnumerableSet.AddressSet private _putPools;

    uint256 constant _inverseBasisPoint = 1e4;

    uint256 public blackScholesWeight = 5e3; // 500 = 50%
    uint256 public constantProductWeight = 5e3; // 500 = 50%

    // Set a custom swap path for a token
    // collateral token -> token -> path
    mapping(address => mapping(address => address[])) customSwapPaths;

    // Default swap router to use in case no custom router has been set for a pair
    IUniswapV2Router02 public defaultSwapRouter;

    // The LTV ratio for each token usable as collateral
    mapping(address => uint256) public loanToValueRatios;

    ////////////
    // Events //
    ////////////

    event Bought(address indexed user, address indexed optionContract, uint256 indexed optionId, uint256 amount, address premiumToken, uint256 optionPrice);
    event Sold(address indexed user, address indexed optionContract, uint256 indexed optionId, uint256 amount, address premiumToken, uint256 optionPrice);

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


    /// @notice Set new weights for pricing function, total must be 1,000
    /// @param _blackScholesWeight Black scholes weighting
    /// @param _constantProductWeight Weighting based on reserves
    function setPriceWeights(uint256 _blackScholesWeight, uint256 _constantProductWeight) external onlyOwner {
        require(_blackScholesWeight + _constantProductWeight == _inverseBasisPoint);
        blackScholesWeight = _blackScholesWeight;
        constantProductWeight = _constantProductWeight;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

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

    function getCallPools() public view returns(IPremiaLiquidityPool[] memory) {
        uint256 length = _callPools.length();
        IPremiaLiquidityPool[] memory result = new IPremiaLiquidityPool[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = IPremiaLiquidityPool(_callPools.at(i));
        }

        return result;
    }

    function getPutPools() public view returns(IPremiaLiquidityPool[] memory) {
        uint256 length = _putPools.length();
        IPremiaLiquidityPool[] memory result = new IPremiaLiquidityPool[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = IPremiaLiquidityPool(_putPools.at(i));
        }

        return result;
    }

    function getCallReserves(address _optionContract, uint256 _optionId) external view returns (uint256) {
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
        return _getCallReserves(data.token, data.expiration);
    }

    function _getCallReserves(address _token, uint256 _expiration) internal view returns (uint256) {
        uint256 reserveAmount;
        IPremiaLiquidityPool[] memory callPools = getCallPools();
        for (uint256 i = 0; i < callPools.length; i++) {
            IPremiaLiquidityPool pool = callPools[i];
            reserveAmount = reserveAmount + pool.getWritableAmount(_token, _expiration);
        }

        return reserveAmount;
    }

    function getPutReserves(address _optionContract, uint256 _optionId) external view returns (uint256 reserveAmount) {
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
        return _getPutReserves(IPremiaOption(_optionContract).denominator(), data.expiration);
    }

    function _getPutReserves(address _denominator, uint256 _expiration) internal view returns (uint256) {
        uint256 reserveAmount;
        IPremiaLiquidityPool[] memory putPools = getPutPools();
        for (uint256 i = 0; i < putPools.length; i++) {
            IPremiaLiquidityPool pool = putPools[i];
            reserveAmount = reserveAmount + pool.getWritableAmount(_denominator, _expiration);
        }

        return reserveAmount;
    }

    function getCallMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256) {
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
        return _getCallMaxBuy(data.token, data.expiration);
    }

    function _getCallMaxBuy(address _token, uint256 _expiration) internal view returns (uint256) {
        uint256 maxBuy;
        IPremiaLiquidityPool[] memory callPools = getCallPools();
        for (uint256 i = 0; i < callPools.length; i++) {
            IPremiaLiquidityPool pool = callPools[i];
            uint256 reserves = pool.getWritableAmount(_token, _expiration);

            if (reserves > maxBuy) {
                maxBuy = reserves; 
            }
        }

        return maxBuy;
    }

    function getCallMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256) {
        IPremiaLiquidityPool[] memory callPools = getCallPools();
        
        uint256 maxSell;
        for (uint256 i = 0; i < callPools.length; i++) {
            IPremiaLiquidityPool pool = callPools[i];
            uint256 reserves = pool.getUnwritableAmount(_optionContract, _optionId);

            if (reserves > maxSell) {
                maxSell = reserves; 
            }
        }

        return maxSell;
    }

    function getPutMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256) {
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
        return _getPutMaxBuy(data.token, data.expiration);
    }

    function _getPutMaxBuy(address _token, uint256 _expiration) internal view returns (uint256) {
        uint256 maxBuy;
        IPremiaLiquidityPool[] memory putPools = getPutPools();
        for (uint256 i = 0; i < putPools.length; i++) {
            IPremiaLiquidityPool pool = putPools[i];
            uint256 reserves = pool.getWritableAmount(_token, _expiration);

            if (reserves > maxBuy) {
                maxBuy = reserves; 
            }
        }

        return maxBuy;
    }

    function getPutMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256) {
        IPremiaLiquidityPool[] memory putPools = getPutPools();

        uint256 maxSell;
        for (uint256 i = 0; i < putPools.length; i++) {
            IPremiaLiquidityPool pool = IPremiaLiquidityPool(putPools[i]);
            uint256 reserves = pool.getUnwritableAmount(_optionContract, _optionId);

            if (reserves > maxSell) {
                maxSell = reserves; 
            }
        }

        return maxSell;
    }

    function _getWeightedBlackScholesPrice(address _token, address _denominator, uint256 _strikePrice, uint256 _expiration, uint256 _amountIn)
        internal view returns (uint256) {
            uint256 blackScholesPriceInEth = blackScholesOracle.getBlackScholesEstimate(_token, _denominator, _strikePrice, _expiration, _amountIn);
            uint256 ethPrice = blackScholesOracle.getAssetPrice(address(WETH));
            uint256 premiumTokenPrice = blackScholesOracle.getAssetPrice(_denominator);
            uint256 blackScholesPrice = ethPrice * uint256(1e12) / premiumTokenPrice * blackScholesPriceInEth / uint256(1e12);
            return blackScholesPrice * _amountIn * _inverseBasisPoint / blackScholesWeight;
    }

    function priceOption(IPremiaOption _optionContract, uint256 _optionId, SaleSide _side, uint256 _amount) external view returns (uint256 optionPrice) {
        IPremiaOption.OptionData memory data = _optionContract.optionData(_optionId);
        return _priceOption(data.token, _optionContract.denominator(), data.strikePrice, data.expiration, data.isCall, _side, _amount);
    }

    function _priceOption(address _token, address _denominator, uint256 _strikePrice, uint256 _expiration, bool _isCall, SaleSide _side, uint256 _amount)
        internal view returns (uint256) {
            uint256 amountIn = _isCall ? _amount : _amount * _strikePrice;
            uint256 weightedBsPrice = _getWeightedBlackScholesPrice(_token, _denominator, _strikePrice, _expiration, amountIn);

            uint256 xt0 = _getCallReserves(_token, _expiration);
            uint256 yt0 = _getPutReserves(_denominator, _expiration);
            uint256 k = xt0 * yt0;

            uint256 xt1;
            uint256 yt1;
            uint256 price;

            if (_side == SaleSide.Buy) {
                if (_isCall) {
                    // User is Buying Call
                    xt1 = xt0 - amountIn;
                    price = weightedBsPrice + (k / xt1 * _inverseBasisPoint / constantProductWeight);
                    yt1 = yt0 + price;
                } else {
                    // User is Buying Put
                    yt1 = yt0 - amountIn;
                    price = weightedBsPrice + (k / yt1 * _inverseBasisPoint / constantProductWeight);
                }
            } else {
                if (_isCall) {
                    // User is Selling Call
                    yt1 = yt0 - amountIn;
                    price = weightedBsPrice + (k / yt1 * _inverseBasisPoint / constantProductWeight);
                } else {
                    // User is Selling Put
                    xt1 = xt0 - amountIn;
                    price = weightedBsPrice + (k / xt1 * _inverseBasisPoint / constantProductWeight);
                }
            }

            require(xt1 > 0 && yt1 > 0 && xt1 < k && yt1 < k, "Trade too large.");

            return price;
    }

    function _getLiquidityPool(address _token, address _denominator, uint256 _expiration, bool _isCall, uint256 _amount) internal view returns (IPremiaLiquidityPool) {
        IPremiaLiquidityPool[] memory liquidityPools = _isCall ? getCallPools() : getPutPools();

        for (uint256 i = 0; i < liquidityPools.length; i++) {
            IPremiaLiquidityPool pool = liquidityPools[i];
            uint256 amountAvailable = pool.getWritableAmount(_isCall ? _token : _denominator, _expiration);

            if (amountAvailable >= _amount && address(pool) != address(msg.sender)) {
                return pool;
            }
        }

        revert("Not enough liquidity");
    }

    //////////
    // Main //
    //////////

    function buy(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _maxPremiumAmount, address _referrer) external nonReentrant {
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
        IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data.token, IPremiaOption(_optionContract).denominator(), data.expiration, data.isCall, _amount);

        address denominator = IPremiaOption(_optionContract).denominator();
        uint256 optionPrice = _priceOption(data.token, denominator, data.strikePrice, data.expiration, data.isCall, SaleSide.Buy, _amount);

        require(optionPrice >= _maxPremiumAmount, "Price too high.");

        // The pool needs to check that the option contract is whitelisted
        liquidityPool.buyOption(msg.sender, _optionContract, _optionId, _amount, optionPrice, _referrer);
        emit Bought(msg.sender, _optionContract, _optionId, _amount, denominator, optionPrice);
    }

    function sell(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _minPremiumAmount) external nonReentrant {
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
        IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data.token, IPremiaOption(_optionContract).denominator(), data.expiration, data.isCall, _amount);

        address denominator = IPremiaOption(_optionContract).denominator();
        uint256 optionPrice = _priceOption(data.token, IPremiaOption(_optionContract).denominator(), data.strikePrice, data.expiration, data.isCall, SaleSide.Sell, _amount);

        require(optionPrice <= _minPremiumAmount, "Price too low.");

        // The pool needs to check that the option contract is whitelisted
        liquidityPool.sellOption(msg.sender, _optionContract, _optionId, _amount, optionPrice);
        emit Sold(msg.sender, _optionContract, _optionId, _amount, denominator, optionPrice);
    }

    function depositLiquidity(DepositArgs[] memory _deposits) external nonReentrant {
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

    function withdrawExpiredLiquidity(WithdrawExpiredArgs[] memory _withdrawals) external nonReentrant {
        for (uint256 i=0; i < _withdrawals.length; i++) {
            require(_callPools.contains(_withdrawals[i].pool) || _putPools.contains(_withdrawals[i].pool), "Pool not whitelisted");

            IPremiaLiquidityPool(_withdrawals[i].pool).withdrawExpiredFrom(msg.sender, _withdrawals[i].tokens);
        }
    }
}