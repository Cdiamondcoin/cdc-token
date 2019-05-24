pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "./CdcExchange.sol";
import "./Cdc.sol";


contract CdcExchangeTester {
    CdcExchange public _exchange;
    ERC20 public _dpt;

    constructor(CdcExchange exchange, ERC20 dpt) public {
        _exchange = exchange;
        _dpt = dpt;
    }

    function doBuyTokens(uint amount) public {
        _exchange.buyTokens.value(amount)();
    }

    function doBuyTokensWithFee(uint amount) public payable {
        _exchange.buyTokensWithFee.value(amount)();
    }

    function doApprove(address recipient, uint amount) public {
        _dpt.approve(recipient, amount);
    }

    function () external payable {
    }
}

contract CdcExchangeTest is DSTest, DSMath, CdcExchangeEvents {
    uint constant Cdc_SUPPLY = (10 ** 7) * (10 ** 18);
    Cdc cdc;
    ERC20 dpt;
    CdcExchange exchange;
    CdcExchangeTester user;
    uint etherBalance;
    uint sendEth;
    uint rate = 0.5 ether;

    function setUp() public {
        cdc = new Cdc();
        dpt = new Cdc();
        exchange = new CdcExchange(cdc, dpt, rate);
        user = new CdcExchangeTester(exchange, dpt);
        cdc.approve(exchange, uint(-1));
        require(cdc.balanceOf(this) == Cdc_SUPPLY);
        require(dpt.balanceOf(this) == Cdc_SUPPLY);
        require(address(this).balance >= 1000 ether);
        address(user).transfer(1000 ether);
        etherBalance = address(this).balance;

        // transfer fee (0.015) DPT to user for further Cdc buy
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
        assertEq(cdc.balanceOf(this),Cdc_SUPPLY - 20 ether);
    }

    function testFailBuyTenTokensIfExchangeStopped() public {
        sendEth = 10 ether;
        exchange.stop();
        buyTokens(sendEth);
    }

    function testCdcExchangeCanBeRestarted() public {
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
        assertEq(cdc.balanceOf(this), Cdc_SUPPLY - 20 ether);
        assertEq(cdc.balanceOf(user), 20 ether);
    }

    function testBuyTokensSetRate() public {
        sendEth = 0.18447 ether;
        exchange.setRate(sendEth);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this), Cdc_SUPPLY - 1 ether);
        assertEq(cdc.balanceOf(user), 1 ether);
    }

    function testFailBuyTokensZeroAmount() public {
        sendEth = 0 ether;
        user.doBuyTokens(sendEth);
    }

    function testBuyTokensWithFee() public {
        sendEth = 10 ether;
        user.doBuyTokensWithFee(sendEth);

        // Cdc Balance of owner must be -20
        assertEq(cdc.balanceOf(this), Cdc_SUPPLY - 20 ether);
        // Cdc Balance of user must be +20
        assertEq(cdc.balanceOf(user), 20 ether);
        // DPT Balance of user must be -0.015 (fee amount)
        assertEq(dpt.balanceOf(user), 0);
        // DPT Balance of owner must be +0.015 (fee amount)
        assertEq(dpt.balanceOf(this), Cdc_SUPPLY);
    }

    function testFee() public {
        assertEq(exchange.fee(), 0.015 ether);
        exchange.setFee(1 ether);
        assertEq(exchange.fee(), 1 ether);
    }
}
