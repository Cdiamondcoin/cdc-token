pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "./CDCEXCHANGE.sol";
import "./CDC.sol";


contract CDCEXCHANGETester {
    CDCEXCHANGE public _exchange;
    ERC20 public _dpt;

    constructor(CDCEXCHANGE exchange, ERC20 dpt) public {
        _exchange = exchange;
        _dpt = dpt;
    }

    function doBuyTokens(uint amount) public {
        _exchange.buyTokens.value(amount)();
    }

    function doBuyTokensWithFee(uint amount) public {
        _exchange.buyTokensWithFee.value(amount)();
    }

    function doApprove(address recipient, uint amount) public {
        _dpt.approve(recipient, amount);
    }

    function () external payable {
    }
}

contract CDCEXCHANGETest is DSTest, DSMath, CDCEXCHANGEEvents {
    uint constant CDC_SUPPLY = (10 ** 7) * (10 ** 18);
    CDC cdc;
    ERC20 dpt;
    CDCEXCHANGE exchange;
    CDCEXCHANGETester user;
    uint etherBalance;
    uint sendEth;
    uint rate = 0.5 ether;

    function setUp() public {
        cdc = new CDC();
        dpt = new CDC();
        exchange = new CDCEXCHANGE(cdc, dpt, rate);
        user = new CDCEXCHANGETester(exchange, dpt);
        cdc.approve(exchange, uint(-1));
        require(cdc.balanceOf(this) == CDC_SUPPLY);
        require(dpt.balanceOf(this) == CDC_SUPPLY);
        require(address(this).balance >= 1000 ether);
        address(user).transfer(1000 ether);
        etherBalance = address(this).balance;

        // transfer fee (0.015) DPT to user for further CDC buy
        dpt.transfer(user, exchange.fee());
        user.doApprove(exchange, exchange.fee());
    }

    function () external payable {
    }

    function buyTokens(uint sendValue) private {
        exchange.buyTokens.value(sendValue)();
    }

    function testWeBuyTenTokens() public {
        sendEth = 10 ether;
        buyTokens(sendEth);
    }

    function testOthersBuyTenTokens() public {
        sendEth = 10 ether;
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - 20 ether);
    }

    function testFailBuyTenTokensIfExchangeStopped() public {
        sendEth = 10 ether;
        exchange.stop();
        buyTokens(sendEth);
    }

    function testCDCEXCHANGECanBeRestarted() public {
        sendEth = 10 ether;
        exchange.stop();
        exchange.start();
        buyTokens(sendEth);
    }

    function testFailIfNoValueTransferred() public {
        buyTokens(0 ether);
    }

    function testFailBuyMaxTokensIfExchangeStopped() public {
        //uint(-1) is the largest unsigned integer that can be represented with uint256
        buyTokens(uint(-1));
    }

    function testEthSentToOwner() public {
        sendEth = 10 ether;
        user.doBuyTokens(sendEth);
        assertEq(etherBalance + sendEth, address(this).balance);
    }

    function testBuyTokens() public {
        sendEth = 10 ether;
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this), CDC_SUPPLY - 20 ether);
        assertEq(cdc.balanceOf(user), 20 ether);
    }

    function testBuyTokensSetRate() public {
        sendEth = 0.18447 ether;
        exchange.setRate(sendEth);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this), CDC_SUPPLY - 1 ether);
        assertEq(cdc.balanceOf(user), 1 ether);
    }

    function testFailBuyTokensZeroAmount() public {
        sendEth = 0 ether;
        user.doBuyTokens(sendEth);
    }

    function testBuyTokensWithFee() public {
        sendEth = 10 ether;
        user.doBuyTokensWithFee(sendEth);
        // CDC Balance of owner must be -20
        assertEq(cdc.balanceOf(this), CDC_SUPPLY - 20 ether);
        // CDC Balance of user must be +20
        assertEq(cdc.balanceOf(user), 20 ether);
        // DPT Balance of user must be -0.015 (fee amount)
        assertEq(dpt.balanceOf(user), 0);
        // DPT Balance of owner must be +0.015 (fee amount)
        assertEq(dpt.balanceOf(this), CDC_SUPPLY);
    }
}
