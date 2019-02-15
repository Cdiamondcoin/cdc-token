pragma solidity ^0.4.23;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "./CDCEXCHANGE.sol";
import "./CDC.sol";

contract TestMedianizerLike {
    bytes32 public ethUsdRate;
    bool public feedValid;

    constructor(uint ethUsdRate_, bool feedValid_) public {
        ethUsdRate = bytes32(ethUsdRate_);
        feedValid = feedValid_;
    }

    function setEthUsdRate(uint ethUsdRate_) public {
        ethUsdRate = bytes32(ethUsdRate_);
    }

    function setValid(bool feedValid_) public {
        feedValid = feedValid_;
    }

    function peek() external view returns (bytes32, bool) {
        return (ethUsdRate,feedValid);
    }
}

contract CDCEXCHANGETester {
    CDCEXCHANGE public _exchange;

    constructor(CDCEXCHANGE exchange) public {
        _exchange = exchange;
    }

    function doBuyTokens(uint amount) public {
        _exchange.buyTokens.value(amount)();
    }

    function () external payable {
    }
}

contract CDCEXCHANGETest is DSTest, DSMath, CDCEXCHANGEEvents {
    uint constant CDC_SUPPLY = (10 ** 7) * (10 ** 18);
    CDC cdc;
    CDC dpt;
    TestMedianizerLike feed;
    CDCEXCHANGE exchange;
    CDCEXCHANGETester user;
    uint etherBalance ;
    uint sendEth;
    uint ethUsdRate = 317.96 ether;
    uint cdcUsdRate = 3.5 ether;

    function setUp() public {
        cdc = new CDC();
        dpt = new CDC();
        feed = new TestMedianizerLike(ethUsdRate, true);
        exchange = new CDCEXCHANGE(cdc, dpt, feed, cdcUsdRate, ethUsdRate);
        user = new CDCEXCHANGETester(exchange);
        cdc.approve(exchange, uint(-1));
        require(cdc.balanceOf(this) == CDC_SUPPLY);
        require(address(this).balance >= 1000 ether);
        address(user).transfer(1000 ether);
        etherBalance = address(this).balance;
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
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
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
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
    }

    function testFailBuyTokensZeroAmount() public {
        sendEth = 0 ether;
        user.doBuyTokens(sendEth);
    }

    function testBuyTokensSetCdcUsdRate() public {
        sendEth = 10 ether;
        cdcUsdRate = 5 ether;
        exchange.setCdcRate(cdcUsdRate);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
    }

    function testFailBuyTokensSetZeroCdcUsdRate() public {
        exchange.setCdcRate(0);
    }

    function testBuyTokensSetEthUsdRate() public {
        sendEth = 10 ether;
        ethUsdRate = 300 ether;
        feed.setEthUsdRate(ethUsdRate);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
    }

    function testBuyTokensSetEthUsdAndCdcUsdRate() public {
        sendEth = 10 ether;
        ethUsdRate = 300 ether;
        cdcUsdRate = 5 ether;
        exchange.setCdcRate(cdcUsdRate);
        feed.setEthUsdRate(ethUsdRate);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
    }

    function testBuyTenTokensSetEthUsdAndCdcUsdRateStatic() public {
        exchange.setCdcRate(5 ether);
        feed.setEthUsdRate(20 ether);
        user.doBuyTokens(10.5 ether);
        assertEq(cdc.balanceOf(user), 42 ether);
    }

    function testBuyTokenSetManualEthUsdRateUpdate() public {
        sendEth = 10 ether;
        ethUsdRate = 300 ether;
        feed.setValid(false);
        exchange.setManualUsdRate(true);
        exchange.setEthRate(ethUsdRate);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
    }

    function testFailBuyTokenSetManualEthUsdRateUpdateIfManuaUsdRatelIsFalse() public {
        sendEth = 10 ether;
        ethUsdRate = 300 ether;
        exchange.setEthRate(ethUsdRate);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(this),CDC_SUPPLY - (wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate)));
    }

    function testInvalidFeedDoesNotUpdateEthUsdRate() public {
        sendEth = 134 ether;
        uint feedEthUsdRate = 1400 ether; //should not equal to `ethUsdRate` if you want a reasonable test
        exchange.setManualUsdRate(true);
        feed.setValid(false);
        feed.setEthUsdRate(feedEthUsdRate);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(user), wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate));
    }

    function testFailInvalidFeedFailsIfManualUpdateIsFalse() public {
        sendEth = 134 ether;
        exchange.setManualUsdRate(false);
        feed.setValid(false);
        user.doBuyTokens(sendEth);
    }

    function testSetFeed() public {
        sendEth = 10 ether;
        ethUsdRate = 2000 ether;
        TestMedianizerLike feed1 = new TestMedianizerLike(ethUsdRate, true);
        exchange.setPriceFeed(feed1);
        user.doBuyTokens(sendEth);
        assertEq(cdc.balanceOf(user), wdiv(wmul(ethUsdRate, sendEth), cdcUsdRate));
    }

    function testFailSetZeroAddressFeed() public {
        TestMedianizerLike feed1;
        exchange.setPriceFeed(feed1);
    }

    function testFailZeroTokenGetPrice() public view {
        exchange.getPrice(0);
    }

    function testValidGetPriceWithFeedPrice() public {
        ethUsdRate = 350 ether;
        cdcUsdRate = 3.5 ether;
        assertEq(exchange.getPrice(100), 1);
    }

    function testGetPriceDecimalWithFeedPrice() public {
        ethUsdRate = 350 ether;
        cdcUsdRate = 3.5 ether;
        feed.setEthUsdRate(ethUsdRate);
        assertEq(exchange.getPrice(275 ether), 2.75 ether);
    }

    function testGetPriceDecimalMoreAfterCommaWithFeedPrice() public {
        ethUsdRate = 299.99 ether;
        cdcUsdRate = 3.5 ether;
        feed.setEthUsdRate(ethUsdRate);
        assertEq(exchange.getPrice(32 ether), 0.373345778192606420 ether);
    }

    function testGetPriceWithManualRate() public {
        ethUsdRate = 157.5 ether;
        cdcUsdRate = 3.5 ether;
        feed.setValid(false);
        exchange.setEthRate(ethUsdRate);
        exchange.setManualUsdRate(true);
        assertEq(exchange.getPrice(31 ether), 0.688888888888888889 ether);
    }

    function testFailGetPriceWithInvalidFeedAndDisabledManualRate() public {
        exchange.setManualUsdRate(false);
        feed.setValid(false);
        exchange.getPrice(100);
    }
}
