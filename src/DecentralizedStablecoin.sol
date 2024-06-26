// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Burnable , ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


// This is the ERC20 contract which is going to be govered my dsc engine contract.

/*
* @title DecentralizedStableCoin
* @author Madhav Gupta
* Collateral: Exogenous
* Minting (Stability Mechanism): Decentralized (Algorithmic)
* Value (Relative Stability): Anchored (Pegged to USD)
* Collateral Type: Crypto
*/

contract DecentralizedStablecoin is ERC20Burnable , Ownable{


    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__NotZeroAddress() ;


    constructor() ERC20("DecentralizedStablecoin","DSC") Ownable(msg.sender) {}


    function burn(uint256 _amount) public override onlyOwner{

        uint256 balance = balanceOf(msg.sender);

        if(_amount > balance){
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        if(_amount < 0){
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }

        super.burn(_amount);


    }

    function mint(address to , uint256 amount) external onlyOwner returns(bool){

         if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }

        _mint(to,amount);
        return true;
    }

}