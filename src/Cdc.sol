pragma solidity ^0.5.11;

import "ds-token/token.sol";

/**
 * @title Cdc
 * @dev Cdc coin.
 */
contract Cdc is DSToken {
    string public constant name = "Certified Diamond Coin";
    uint8 public constant decimals = 18 ;
    bytes32 public cccc;

    /**
    * @dev Constructor that gives msg.sender all of existing tokens.
    */
    constructor(bytes32 cccc_, bytes32 symbol_) DSToken(symbol_) public {
        cccc = cccc_;
    }
}
