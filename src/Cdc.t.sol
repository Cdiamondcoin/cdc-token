pragma solidity ^0.5.11;

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
        cdc = new Cdc("BR,VS,G,0.05", "CDC");
        user = new CdcTester(cdc);
    }

    function testDiamondType() public {
        assertEq(cdc.cccc(), "BR,VS,G,0.05");
    }

    function testSymbol() public {
        assertEq(cdc.symbol(), "CDC");
    }

    function testMint() public {
        cdc.mint(10 ether);
        assertEq(cdc.totalSupply(), 10 ether);
    }

    function testWeReallyGotAllTokens() public {
        cdc.mint(address(this), Cdc_SUPPLY);
        cdc.transfer(address(user), Cdc_SUPPLY);
        assertEq(cdc.balanceOf(address(this)), 0);
        assertEq(cdc.balanceOf(address(user)), Cdc_SUPPLY);
    }

    function testFailSendMoreThanAvailable() public {
        cdc.mint(address(this), Cdc_SUPPLY);
        cdc.transfer(address(user), Cdc_SUPPLY + 1);
    }
}
