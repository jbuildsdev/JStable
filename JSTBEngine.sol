//// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {JStable} from  "./JStable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/** 
* @title JStable Engine Contract
* @author J Builds
* @dev This is the engine contract that governs the JStable stablecoin.
*This is an overcollateralized algorithmic stablecoin that uses LINK as collateral. At no point
 will the value of the collateral be less than the value of the stablecoin.
* @notice This contract is the core of the J Stable system.
* It handles minting and redeeming JSTB, as well as depoisting and withdrawing collateral/ 



 */
contract JSTBEngine is ReentrancyGuard{
    ///////////////
    /////Errors///
    //////////////
    error JSTBEngine__NeedsMoreThanZero();
    error JSTBEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength();
    error JSTBEngine__TokenNotAllowed();
    error JSTBEngine__TransferFailed();
    error JSTBEngine__BadHealthFactor(uint256 _healthFactor);
    error JSTBEngune__MintFailed();

    ///////////////
    //State Variables///
    //////////////
    
    mapping (address _user => uint256 collateral) private s_collateralBalances;
    mapping (address _user => uint256 amountJstbMinted) private s_JstbMinted;
    address  private s_collateralTokenAddress;
    address private s_priceFeedAddress;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;

    uint256 private constant ADDITIONAL_PRICE_FEED_PRECISION = 1e10;
       uint256 private constant PRECISION = 1e18;


    JStable private i_JSTB;



    ///////////////
    /////Modifiers///
    //////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0)
        revert JSTBEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (_tokenAddress != s_collateralTokenAddress)
        revert JSTBEngine__TokenNotAllowed();
        _;
    }

    ///////////////
    /////Events///
    //////////////

    event CollateralDesposited(address indexed _user, address indexed _tokenAddress, uint256 indexed _amount);



     ///////////////
    /////Functions///
    //////////////

    constructor(address  _tokenAddress, address  _priceFeedAddress, address _JSTBaddress) {

       s_collateralTokenAddress = _tokenAddress;
         s_priceFeedAddress = _priceFeedAddress;
    

         i_JSTB = JStable(_JSTBaddress);
    }

   ///////////////
    /////External Functions///
    //////////////

    function depositCollateralAndMintJSTB() external 
    {}
    
    /*
    * @notice follows CEI pattern
    * @param _tokenCollateralAddress The address of the collateral token
    * @param _amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) 
    external
     moreThanZero(_amountCollateral)
    isAllowedToken(_tokenCollateralAddress)
    nonReentrant
    {
        s_collateralBalances[msg.sender] += _amountCollateral;
        emit CollateralDesposited(msg.sender, _tokenCollateralAddress, _amountCollateral);  
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);  

        if (!success) {
            revert JSTBEngine__TransferFailed();
        }

    }
    


    function redeemJSTBAndWithdrawCollateral() external {}
    function redeemCollateral () external {}


    /**
     * 
     * @param _amountJstbToMint The amount of JSTB stablecoin to mint
     * @notice The amount of collateral deposited must have a greater value than the amount of JSTB minted
     * @notice follows CEI pattern
     */
    function mintJSTB(uint256 _amountJstbToMint) external moreThanZero(_amountJstbToMint) nonReentrant {
        s_JstbMinted[msg.sender] += _amountJstbToMint;
        _revertIfHealthFactorIsBad(msg.sender);
        bool minted = i_JSTB.mint(msg.sender, _amountJstbToMint);
        if (!minted) {
            revert JSTBEngune__MintFailed();
        }
    }

    function burnJSTB() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

      ///////////////
    /////Private and Internal Functions///
    ////////////// 

    function _getAccountInformation (address _user) private view returns (uint256 totalJstbMinted, uint256 collatervalValueInUsd){

        totalJstbMinted = s_JstbMinted[_user];
        collatervalValueInUsd = getAccountCollateralValueInUsd(_user);
        return (totalJstbMinted, collatervalValueInUsd);

    }
    /**
     * 
     * @param _user The address of the user who's debt position health factor is being calculated
     *  Health Factor refers to how close the position is to being liquidated
     * If the Health Factor is below 1 then the position can be liquidated by anyone
     */
    function _healthFactor(address _user) private view  returns (uint256 healthFactor){
        (uint256 totalJstbMinted, uint256 collatervalValueInUsd) = _getAccountInformation(_user);
        uint256 collateralAdjustedForThreshold = (collatervalValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
         healthFactor = collateralAdjustedForThreshold * PRECISION / totalJstbMinted;
        return healthFactor;
    }


    //check if health factor is below 1 and revert if it is (Do they have enough collateral to cover their debt?)
    function _revertIfHealthFactorIsBad(address _user) private view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert JSTBEngine__BadHealthFactor(userHealthFactor);
        }


    }

      ///////////////
    /////Public and External View Functions ///
    ////////////// 

    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 collateralValueInUsd) {
        //get the amount of collateral deposited by the user and find its value in USD
        uint256 balance = s_collateralBalances[_user];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeedAddress);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * balance * ADDITIONAL_PRICE_FEED_PRECISION) / PRECISION);


        }


    }


