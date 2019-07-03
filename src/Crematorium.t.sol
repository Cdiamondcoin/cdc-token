pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./Crematorium.sol";

contract TokenUser {
    DSToken token;

    constructor(DSToken token_) public {
        token = token_;
    }
}

contract CrematoriumTest is DSTest {
    uint constant initialBalance = 1000;

    DSToken token;
    TokenUser user;
    Crematorium creamatorioum;
    address self;

    function setUp() public {
        token = new DSToken("DPT");
        token.mint(initialBalance);
        user = new TokenUser(token);
        creamatorioum = new Crematorium(token);
        // To burn creamatorioum have to be owner of token
        token.setOwner(address(creamatorioum));
        self = address(this);
    }

    function testValidBurn() public {
        uint sentAmount = 250;
        token.transfer(creamatorioum, sentAmount);
        creamatorioum.burn(sentAmount);
        assertEq(token.totalSupply(), initialBalance - sentAmount);
    }

    function testValidAllBurn() public {
        uint sentAmount = 250;
        token.transfer(creamatorioum, sentAmount);
        creamatorioum.burnAll();
        assertEq(token.totalSupply(), initialBalance - sentAmount);
    }
}
