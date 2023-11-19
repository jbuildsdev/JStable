//// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {JStable} from  "./JStable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/** 
* @title JStable Engine Contract
* @author J Builds
* @dev This is the engine contract that governs the JStable stablecoin.
*This is an overcollateralized algorithmic stablecoin that uses HBAR as collateral. At ni point
 will the value of the collateral be less than the value of the stablecoin.
* @notice This contract is the core of the J Stable system.
* It handles minting and redeeming JSTB, as well as depoisting and withdrawing collateral/ 



 */
contract JSTBEngine is ReentrancyGuard{

    //Errors
    error JSTBEngine__NeedsMoreThanZero();
    error JSTBEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength();
    error JSTBEngine__TokenNotAllowed();

    //State Variables
    mapping (address _token => address _priceFeed) private s_priceFeeds;
    mapping (address _user => uint256 _collateral) private s_collateralBalances;

    JStable private i_JSTB;

    //Modifiers 
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0)
        revert JSTBEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0))
        revert JSTBEngine__TokenNotAllowed();
        _;
    }

    //Funtions

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address _JSTBaddress) {

        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert JSTBEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength();
        }

         for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
         }

         i_JSTB = JStable(_JSTBaddress);
    }

    //External Functions

    function depositCollateralAndMintJSTB() external 
    {}
    
    /*
    * @param _tokenCollateralAddress The address of the collateral token
    * @param _amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) 
    external
     moreThanZero(_amountCollateral)
    isAllowedToken(_tokenCollateralAddress)
    nonReentrant
    {
            

    }
    


    function redeemJSTBAndWithdrawCollateral() external {}
    function redeemCollateral () external {}

    function mintJSTB() external {}

    function burnJSTB() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

}