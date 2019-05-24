pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-token/base.sol";
import "./Cdc.sol";

contract CdcTester {
    Cdc public _cdc;

    constructor(Cdc cdc) public {
        _cdc = cdc;
    }
}

contract CdcTest is DSTest {
    uint constant Cdc_SUPPLY = (10 ** 7) * (10 ** 18);
    Cdc cdc;
    CdcTester user;

    function setUp() public {
        cdc = new Cdc();
        user = new CdcTester(cdc);
    }

    function testMint() public {
        cdc.mint(10 ether);
    }

    function testWeReallyGotAllTokens() public {
        cdc.transfer(user, Cdc_SUPPLY);
        assertEq(cdc.balanceOf(this), 0);
    }

    function testFailSendMoreThanAvailable() public {
        cdc.transfer(user, Cdc_SUPPLY + 1);
    }
}
