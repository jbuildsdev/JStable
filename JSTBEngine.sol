// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {JStable} from "./JStable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/** 
* @title JStable Engine Contract
* @author J Builds
* @dev This is the engine contract that governs the JStable stablecoin.
*This is an overcollateralized algorithmic stablecoin that uses ETH as collateral. At no point
 will the value of the collateral be less than the value of the stablecoin.
* @notice This contract is the core of the J Stable system.
* It handles minting and redeeming JSTB, as well as depoisting and withdrawing collateral
* TODO: Refactor code to compare health factor to (MIN_HEALTH_FACTOR*PRECISION). Our health factor now works but loses all precision.
  Health factor should be 1e18 times the actual value to keep precision
* TODO: Make a test contract with a function to change collateral value to test liquidation


 */
contract JSTBEngine is ReentrancyGuard {
    ///////////////
    /////Errors///
    //////////////
    error JSTBEngine__NeedsMoreThanZero();
    error JSTBEngine__TransferFailed();
    error JSTBEngine__BadHealthFactor(uint256 _healthFactor);
    error JSTBEngine__MintFailed();
    error JSTBEngine__HealthFactorOK();

    ////////////////////
    //State Variables///
    ///////////////////

    mapping(address _user => uint256 collateral) private s_collateralBalances;
    mapping(address _user => uint256 amountJstbMinted) private s_JstbMinted;
    address private s_priceFeedAddress; //price feed for ETH/USD
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus for liquidators
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;
    uint256 private constant ADDITIONAL_PRICE_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    JStable private i_JSTB;

    /////////////////
    /////Modifiers///
    ////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) revert JSTBEngine__NeedsMoreThanZero();
        _;
    }

    ///////////////
    /////Events///
    //////////////

    event CollateralDesposited(address indexed _user, uint256 indexed _amount);
    event CollateralRedeemed(
        address indexed _redeemedFrom,
        address indexed _redeemTo,
        uint256 indexed _amount
    );

    /////////////////
    /////FUNCTIONS///
    ////////////////

    constructor(address _priceFeedAddress, address _JSTBaddress) {
        s_priceFeedAddress = _priceFeedAddress;

        i_JSTB = JStable(_JSTBaddress);
    }

    //////////////////////////
    /////External Functions///
    //////////////////////////

    /**
     * @notice follows CEI pattern

     * @param _amountJstbToMint The amount of JSTB stablecoin to mint
     * @notice This function will deposit collatral and mint JSTB in one transaction. The amount of collateral deposited must have a greater value than the amount of JSTB minted, as determined by the price feed and the liquidation threshold
     */

    // function depositCollateralAndMintJSTB(uint256 _amountJstbToMint) external {
    //     depositCollateral();
    //     mintJSTB(_amountJstbToMint);
    // }

    /**
     * @notice follows CEI pattern
     * @param _amountCollateral The amount of collateral to withdraw
     * @param _amountJstbToBurn The amount of JSTB stablecoin to burn
     * @notice This function will withdraw collateral and burn JSTB.
     * The amount of collateral withdrawn must have a greater value than the amount of JSTB burned, as determined by the price feed and the liquidation threshold
     * @notice After the withdrawal and burning, the user's health factor will be checked. If it is below 1, the transaction will revert
     */

    function burnJstbAndRedeemCollateral(
        uint256 _amountCollateral,
        uint256 _amountJstbToBurn
    ) external {
        _burnJSTB(msg.sender, msg.sender, _amountJstbToBurn);
        _redeemCollateral(msg.sender, msg.sender, _amountCollateral);
        _revertIfHealthFactorIsBad(msg.sender);
    }

    function redeemCollateral(
        uint256 _amountCollateral
    ) external moreThanZero(_amountCollateral) {
        _redeemCollateral(msg.sender, msg.sender, _amountCollateral);
        _revertIfHealthFactorIsBad(msg.sender);
    }

    function burnJstb(uint256 _amountJstbToBurn) external {
        _burnJSTB(msg.sender, msg.sender, _amountJstbToBurn);
        _revertIfHealthFactorIsBad(msg.sender); //This should never hit since burning JSTB decreases debt and increases health factor
    }

    /**
     * @notice follows CEI pattern
     * @param _user The user who is being liquidated. Their health factor is below 1.
     * @param _debtToCover The amount of debt the liquidator is covering in the unhealthy position. The position can be partially liquidated or fully liquidated.
     * @notice This function allows a liquidator to burn their JSTB and withdraw collateral from the unhealthy position.
     * This allows the liquidator to profit from the liquidation by receiving the collateral at a discount to market price.
     * Incentivizing liquidation pegs the coin to 1 USD and keeps the protocol over collateralized.
     * @notice If the price were to gap down the protocol may break and become under collateralized
     */
    function liquidate(
        address _user,
        uint256 _debtToCover
    ) external moreThanZero(_debtToCover) nonReentrant {
        if (_healthFactor(_user) >= MINIMUM_HEALTH_FACTOR) {
            revert JSTBEngine__HealthFactorOK();
        }

        uint256 ethAmountFromDebtToCover = getEthAmountFromUsd(_debtToCover);

        uint256 bonusCollateral = (ethAmountFromDebtToCover *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        _redeemCollateral(
            _user,
            msg.sender,
            ethAmountFromDebtToCover + bonusCollateral
        );
        _burnJSTB(_user, msg.sender, _debtToCover);
    } //TODO: add a treasury address that gets leftover collateral from liquidations

    ///////////////////////////////////////
    /////Public Functions ////////////////
    /////////////////////////////////////

    /**
     *
     * @param _amountJstbToMint The amount of JSTB stablecoin to mint
     * @notice The amount of collateral deposited must have a greater value than the amount of JSTB minted
     * @notice Be aware of precision. The amount of collateral deposited must be in wei
     */
    function mintJSTB(
        uint256 _amountJstbToMint
    ) public moreThanZero(_amountJstbToMint) nonReentrant {
        s_JstbMinted[msg.sender] += _amountJstbToMint;
        _revertIfHealthFactorIsBad(msg.sender);
        bool minted = i_JSTB.mint(msg.sender, _amountJstbToMint);
        if (!minted) {
            revert JSTBEngine__MintFailed();
        }
    }

    /**
     * @notice follows CEI pattern
     * @notice This function receives ETH from the user and updates their collateral balance. This is used to mint JSTB stablecoin
 
     */

    function depositCollateral() public payable nonReentrant {
        uint256 amountCollateral = msg.value;
        require(amountCollateral > 0, "Must deposit more than 0 collateral");
        s_collateralBalances[msg.sender] += amountCollateral; //add the collateral to the user's balance
        emit CollateralDesposited(msg.sender, amountCollateral);
    }

    ///////////////////////////////////////
    /////Private  Functions///////////////
    /////////////////////////////////////

    /**
     *@param _from The address of the user who's collateral is being redeemed
     *@param _to The address of the user who the collateral is being sent to. This can be the collateral's owner or a liquidator
     *@param _amount The amount of collateral to redeem
     */

    function _redeemCollateral(
        address _from,
        address _to,
        uint256 _amount
    ) private nonReentrant {
        require(
            s_collateralBalances[_from] >= _amount,
            "Insufficient collateral balance"
        );

        s_collateralBalances[_from] -= _amount;
        emit CollateralRedeemed(_from, _to, _amount);

        // Transfer ETH directly to the recipient
        (bool success, ) = _to.call{value: _amount}("");
        if (!success) {
            revert JSTBEngine__TransferFailed();
        }
    }

    /**
     *@param _amountJstbToBurn The amount of JSTB stablecoin to burn
     *
     *@dev Caustion: This is an internal function. This function does not check if the user has enough JSTB to burn. This must be done before calling this function
     *@dev A user can burn JSTB when withdrawing collateral, or to improve their health factor
     */
    function _burnJSTB(
        address _onBehalfOf,
        address _jstbFrom,
        uint256 _amountJstbToBurn
    ) private moreThanZero(_amountJstbToBurn) nonReentrant {
        s_JstbMinted[_onBehalfOf] -= _amountJstbToBurn;

        bool success = i_JSTB.transferFrom(
            _jstbFrom,
            address(this),
            _amountJstbToBurn
        );

        if (!success) {
            revert JSTBEngine__TransferFailed();
        }

        i_JSTB.burn(_amountJstbToBurn);
    }

    ///////////////////////////
    ///Private View Functions//
    //////////////////////////

    function _getAccountInformation(
        address _user
    )
        private
        view
        returns (uint256 totalJstbMinted, uint256 collateralValueInUsd)
    {
        totalJstbMinted = s_JstbMinted[_user];
        collateralValueInUsd = getAccountCollateralValueInUsd(_user);
        return (totalJstbMinted, collateralValueInUsd);
    }

    /**
     *
     * @param _user The address of the user who's debt position health factor is being calculated
     *  Health Factor refers to how close the position is to being liquidated
     * If the Health Factor is below MINIMUM_HEALTH_FACTOR then the position can be liquidated by anyone
     */
    function _healthFactor(
        address _user
    ) private view returns (uint256 healthFactor) {
        (
            uint256 totalJstbMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(_user);
        return _calculateHealthFactor(totalJstbMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(
        uint256 _totalJstbMinted,
        uint256 _collateralValueInUsd
    ) internal pure returns (uint256 healthFactor) {
        if (_totalJstbMinted == 0) {
            // Handle the case where no JSTB has been minted
            return type(uint256).max; // Return the maximum value for an unsigned integer
        }
        uint256 collateralAdjustedForThreshold = (_collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        healthFactor = collateralAdjustedForThreshold / _totalJstbMinted;
        return healthFactor;
    }

    //check if health factor is below 1 and revert if it is (Do they have enough collateral to cover their debt?)
    function _revertIfHealthFactorIsBad(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert JSTBEngine__BadHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////
    /////Public and External View Functions ///
    ////////////// ///////////////////////////

    function calculateHealthFactor(
        uint256 _totalJstbMinted,
        uint256 _collateralValueInUsd
    ) external pure returns (uint256 healthFactor) {
        return _calculateHealthFactor(_totalJstbMinted, _collateralValueInUsd);
    }

    function getAccountInformation(
        address _user
    )
        external
        view
        returns (uint256 totalJstbMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(_user);
    }

    function getCollateralBalanceOfUser(
        address _user
    ) external view returns (uint256) {
        return s_collateralBalances[_user];
    }

    function getAccountCollateralValueInUsd(
        address _user
    ) public view returns (uint256 collateralValueInUsd) {
        //get the amount of collateral deposited by the user and find its value in USD
        uint256 balance = s_collateralBalances[_user];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeedAddress
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price) * balance * ADDITIONAL_PRICE_FEED_PRECISION) /
            PRECISION);
    } //returns a value that is 1e18 times the actual value in USD

    function getUserOverCollateralizationRatio(
        address _user
    ) external view returns (uint256) {
        uint256 collateralValueInUsd = getAccountCollateralValueInUsd(_user);
        uint256 totalJstbMinted = s_JstbMinted[_user];
        if (totalJstbMinted == 0) {
            // Handle the case where no JSTB has been minted
            return type(uint256).max; // Return the maximum value for an unsigned integer
        }
        return (collateralValueInUsd) / totalJstbMinted;
    }

    function getEthAmountFromUsd(
        uint256 _amountInUsd
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeedAddress
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((_amountInUsd * PRECISION) /
            (uint256(price) * ADDITIONAL_PRICE_FEED_PRECISION));
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    function getCollateralTokenPriceFeed() external view returns (address) {
        return s_priceFeedAddress;
    }

    function getJstable() external view returns (address) {
        return address(i_JSTB);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalPriceFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_PRICE_FEED_PRECISION;
    }
}
