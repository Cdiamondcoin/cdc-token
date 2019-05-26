pragma solidity ^0.4.25;

import "ds-token/token.sol";

/**
 * @title Cdc
 * @dev Cdc coin.
 */
contract Cdc is DSToken {
    string public constant name = "Certified Diamond Coin";
    bytes32 public constant symbol = "CDC";
    uint8 public constant decimals = 18 ;

    /**
    * @dev Constructor that gives msg.sender all of existing tokens.
    */
    constructor() DSToken(symbol) public {
        uint totalSupply_ = mul(10 ** 7, (10 ** uint(decimals)));
        super.mint(totalSupply_);
        transfer(owner, totalSupply_);
    }
}
