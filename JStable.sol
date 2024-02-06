// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/*
* @title JStable
* @author Jbuilds.dev
* Collateral: LINK
* Minting: algorithic
* Stability: 1 USD
* This is the ERC token minted to be the stablecoin goverened by the JStable engine contract. 
*/

contract JStable  is ERC20Burnable, Ownable{
    error JStable_MustBeMoreThanZero();
    error JStable_BurnAmountExceedsBalance();
    error JStable_NotZeroAddress();



    constructor(address _owner) ERC20("JStable", "JSTB") Ownable(_owner){
  
       
    }
    function burn(uint256 _amount) public override onlyOwner {
 
        uint256 balance = balanceOf(msg.sender);

        if (_amount > balance) {
            revert JStable_BurnAmountExceedsBalance();
        }

        if (_amount <= 0) {
            revert JStable_MustBeMoreThanZero();
        }

        super.burn(_amount);
    }

 function mint(address _to, uint256 _amount) external onlyOwner returns (bool _response) {
    if (_to == address(0)) {
      revert JStable_NotZeroAddress();
    }

      if (_amount <= 0) {
        revert JStable_MustBeMoreThanZero();
      }

      _mint(_to, _amount);
      return true;
    }
}
