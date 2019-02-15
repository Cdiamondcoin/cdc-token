pragma solidity ^0.4.23;

import "ds-test/test.sol";
import "ds-token/base.sol";
import "./CDC.sol";

contract CDCTester {
    CDC public _cdc;

    constructor(CDC cdc) public {
        _cdc = cdc;
    }
}

contract CDCTest is DSTest {
    uint constant CDC_SUPPLY = (10 ** 7) * (10 ** 18);
    CDC cdc;
    CDCTester user;

    function setUp() public {
        cdc = new CDC();
        user = new CDCTester(cdc);
    }

    function testFailMint() public {
        cdc.mint(10 ether);
    }

    function testWeReallyGotAllTokens() public {
        cdc.transfer(user,CDC_SUPPLY);
        assertEq(cdc.balanceOf(this), 0);
    }

    function testFailSendMoreThanAvailable() public {
        cdc.transfer(user,CDC_SUPPLY + 1);
    }
}
