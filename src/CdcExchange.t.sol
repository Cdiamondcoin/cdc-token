pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "ds-token/token.sol";
import "./Cdc.sol";
import "./CdcExchange.sol";
import "./Crematorium.sol";


contract TestCdcFinance {
    uint fee;

    function calculateFee(address sender, uint value) external view returns (uint) {
        return fee;
    }

    function setFee(uint fee_) public {
        fee = fee_;
    }
}

contract TestMedianizerLike {
    bytes32 public rate;
    bool public feedValid;

    constructor(uint rate_, bool feedValid_) public {
        rate = bytes32(rate_);
        feedValid = feedValid_;
    }

    function setRate(uint rate_) public {
        rate = bytes32(rate_);
    }

    function setValid(bool feedValid_) public {
        feedValid = feedValid_;
    }

    function peek() external view returns (bytes32, bool) {
        return (rate, feedValid);
    }
}

contract CdcExchangeTester {
    CdcExchange public _exchange;
    DSToken public _dpt;

    constructor(CdcExchange exchange, DSToken dpt) public {
        _exchange = exchange;
        _dpt = dpt;
    }

    function doBuyTokensWithFee(uint amount) public payable {
        _exchange.buyTokensWithFee.value(amount)();
    }

    function doDptApprove(address to, uint amount) public {
        _dpt.approve(to, amount);
    }

    function doSetFee(uint fee_) public {
        _exchange.setFee(fee_);
    }

    function doSetEthPriceFeed(address feed) public {
        _exchange.setEthPriceFeed(feed);
    }

    function doSetDptPriceFeed(address feed) public {
        _exchange.setDptPriceFeed(feed);
    }

    function doSetDptSeller(address seller) public {
        _exchange.setDptSeller(seller);
    }

    function doSetManualDptRate(bool value) public {
        _exchange.setManualDptRate(value);
    }

    function doSetManualCdcRate(bool value) public {
        _exchange.setManualCdcRate(value);
    }

    function doSetManualEthRate(bool value) public {
        _exchange.setManualEthRate(value);
    }

    function doSetDptUsdRate(uint rate) public {
        _exchange.setDptUsdRate(rate);
    }

    function doSetCdcUsdRate(uint rate) public {
        _exchange.setCdcUsdRate(rate);
    }

    function doSetEthUsdRate(uint rate) public {
        _exchange.setEthUsdRate(rate);
    }

    function doSetCfo(address cfo) public {
        _exchange.setCfo(cfo);
    }

    function () external payable {
    }
}

contract CdcExchangeTest is DSTest, DSMath, CdcExchangeEvents {
    uint constant CDC_SUPPLY = (10 ** 7) * (10 ** 18);

    Cdc cdc;
    DSToken dpt;
    CdcExchange exchange;

    CdcExchangeTester user;

    TestMedianizerLike ethPriceFeed;
    TestMedianizerLike dptPriceFeed;
    TestMedianizerLike cdcPriceFeed;

    Crematorium crematorium;
    TestCdcFinance cfo;

    uint etherBalance;
    uint sendEth;
    uint ethCdcRate = 30 ether;

    function setUp() public {
        cdc = new Cdc();
        dpt = new DSToken("DPT");
        dpt.mint(CDC_SUPPLY);

        ethPriceFeed = new TestMedianizerLike(300 ether, true);
        dptPriceFeed = new TestMedianizerLike(3 ether, true);
        cdcPriceFeed = new TestMedianizerLike(30 ether, true);

        crematorium = new Crematorium(dpt);
        exchange = new CdcExchange(cdc, dpt, ethPriceFeed, dptPriceFeed, cdcPriceFeed, address(this), crematorium);
        user = new CdcExchangeTester(exchange, dpt);
        cfo = new TestCdcFinance();

        cdc.approve(exchange, uint(-1));
        dpt.approve(exchange, uint(-1));

        address(user).transfer(1000 ether);
        etherBalance = address(this).balance;
    }

    function () external payable {
    }

    // Here place tests for buyTokensWithFee

    function testCalculateFee() public {
        // By default fee should be equal to init value
        assertEq(exchange.calculateFee(address(this), 1 ether), exchange.fee());
    }

    function testSetFee() public {
        uint newFee = 0.1 ether;
        exchange.setFee(newFee);
        assertEq(exchange.fee(), newFee);
    }

    function testFailNonOwnerSetFee() public {
        uint newFee = 0.1 ether;
        user.doSetFee(newFee);
    }

    function testSetEthPriceFeed() public {
        exchange.setEthPriceFeed(address(this));
        assertEq(exchange.ethPriceFeed(), address(this));
    }

    function testFailWrongAddressSetEthPriceFeed() public {
        exchange.setEthPriceFeed(address(0));
    }

    function testFailNonOwnerSetEthPriceFeed() public {
        user.doSetEthPriceFeed(address(this));
    }

    function testSetDptPriceFeed() public {
        exchange.setDptPriceFeed(address(this));
        assertEq(exchange.dptPriceFeed(), address(this));
    }

    function testFailWrongAddressSetDptPriceFeed() public {
        exchange.setDptPriceFeed(address(0));
    }

    function testFailNonOwnerSetDptPriceFeed() public {
        user.doSetDptPriceFeed(address(this));
    }

    function testSetDptSeller() public {
        dpt.transfer(address(user), 100 ether);
        exchange.setDptSeller(address(user));
        assertEq(exchange.dptSeller(), address(user));
    }

    function testFailWrongAddressSetDptSeller() public {
        exchange.setDptSeller(address(0));
    }

    function testFailNonOwnerSetDptSeller() public {
        dpt.transfer(address(user), 100 ether);
        user.doSetDptSeller(address(user));
    }

    function testSetManualDptRate() public {
        exchange.setManualDptRate(false);
        assertTrue(!exchange.manualDptRate());
    }

    function testFailNonOwnerSetManualDptRate() public {
        user.doSetManualDptRate(false);
    }

    function testSetManualCdcRate() public {
        exchange.setManualCdcRate(false);
        assertTrue(!exchange.manualCdcRate());
    }

    function testFailNonOwnerSetManualCdcRate() public {
        user.doSetManualCdcRate(false);
    }

    function testSetManualEthRate() public {
        exchange.setManualEthRate(false);
        assertTrue(!exchange.manualEthRate());
    }

    function testFailNonOwnerSetManualEthRate() public {
        user.doSetManualEthRate(false);
    }

    function testSetCfo() public {
        exchange.setCfo(address(cfo));
    }

    function testFailWrongAddressSetCfo() public {
        exchange.setCfo(address(0));
    }

    function testFailNonOwnerSetCfo() public {
        user.doSetCfo(address(user));
    }

    function testSetDptUsdRate() public {
        uint newRate = 5 ether;
        exchange.setDptUsdRate(newRate);
        assertEq(exchange.dptUsdRate(), newRate);
    }

    function testFailIncorectRateSetDptUsdRate() public {
        exchange.setDptUsdRate(0);
    }

    function testFailNonOwnerSetDptUsdRate() public {
        uint newRate = 5 ether;
        user.doSetDptUsdRate(newRate);
    }

    function testSetCdcUsdRate() public {
        uint newRate = 5 ether;
        exchange.setCdcUsdRate(newRate);
        assertEq(exchange.cdcUsdRate(), newRate);
    }

    function testFailIncorectRateSetCdcUsdRate() public {
        exchange.setCdcUsdRate(0);
    }

    function testFailNonOwnerSetCdcUsdRate() public {
        uint newRate = 5 ether;
        user.doSetCdcUsdRate(newRate);
    }

    function testSetEthUsdRate() public {
        uint newRate = 5 ether;
        exchange.setEthUsdRate(newRate);
        assertEq(exchange.ethUsdRate(), newRate);
    }

    function testFailIncorectRateSetEthUsdRate() public {
        exchange.setEthUsdRate(0);
    }

    function testFailNonOwnerSetEthUsdRate() public {
        uint newRate = 5 ether;
        user.doSetEthUsdRate(newRate);
    }

    function testFailInvalidEthFeedAndManualDisabledBuyTokensWithFee() public {
        uint sentEth = 1 ether;

        exchange.setManualEthRate(false);
        ethPriceFeed.setValid(false);
        user.doBuyTokensWithFee(sentEth);
    }

    function testFailInvalidDptFeedAndManualDisabledBuyTokensWithFee() public {
        uint sentEth = 1 ether;

        exchange.setManualDptRate(false);
        dptPriceFeed.setValid(false);
        user.doBuyTokensWithFee(sentEth);
    }

    function testFailInvalidCdcFeedAndManualDisabledBuyTokensWithFee() public {
        uint sentEth = 1 ether;

        exchange.setManualCdcRate(false);
        cdcPriceFeed.setValid(false);
        user.doBuyTokensWithFee(sentEth);
    }

    // function testBuyTokensWithFee() public {
    //     uint current_balance = address(this).balance;
    //     uint user_current_balance = address(user).balance;
    //     uint fee = 1 ether;
    //     uint sentEth = 1.01 ether;

    //     exchange.setEthCdcRate(100 ether);
    //     exchange.setFee(fee);

    //     user.doBuyTokensWithFee(sentEth);
    //     // ETH balance have to be correct
    //     assertEq(address(this).balance, add(current_balance, sentEth));
    //     assertEq(address(user).balance, sub(user_current_balance, sentEth));
    //     // DPT fee have to be transfered to crematorium
    //     assertEq(dpt.balanceOf(this), sub(CDC_SUPPLY, fee));
    //     assertEq(dpt.balanceOf(crematorium), fee);
    //     // 100 CDC have to transfered to user
    //     assertEq(cdc.balanceOf(user), 100 ether);
    // }

    // function testBuyTokensWithFeeUserHasDpt() public {
    //     uint current_balance = address(this).balance;
    //     uint user_current_balance = address(user).balance;
    //     uint fee = 1 ether;
    //     uint sentEth = 1 ether;

    //     exchange.setEthCdcRate(100 ether);
    //     exchange.setFee(fee);

    //     dpt.push(user, fee);
    //     user.doDptApprove(exchange, fee);

    //     user.doBuyTokensWithFee(sentEth);
    //     // ETH balance have to be correct
    //     assertEq(address(this).balance, add(current_balance, sentEth));
    //     assertEq(address(user).balance, sub(user_current_balance, sentEth));
    //     // DPT fee have to be transfered to crematorium
    //     assertEq(dpt.balanceOf(user), 0);
    //     assertEq(dpt.balanceOf(crematorium), fee);
    //     // 100 CDC have to transfered to user
    //     assertEq(cdc.balanceOf(user), 100 ether);
    // }

    // function testBuyTokensWithFeeUserHasHalfOfDpt() public {
    //     uint current_balance = address(this).balance;
    //     uint user_current_balance = address(user).balance;
    //     uint fee = 2 ether;
    //     uint user_dpt_amount = 1 ether;
    //     uint sentEth = 1.01 ether;

    //     exchange.setEthCdcRate(100 ether);
    //     exchange.setFee(fee);

    //     dpt.push(user, user_dpt_amount);
    //     user.doDptApprove(exchange, user_dpt_amount);

    //     user.doBuyTokensWithFee(sentEth);
    //     // ETH balance have to be correct
    //     assertEq(address(this).balance, add(current_balance, sentEth));
    //     assertEq(address(user).balance, sub(user_current_balance, sentEth));
    //     // DPT have to be transfered to crematorium => 0.5 have to be taken from user and 0.5 from seller
    //     assertEq(dpt.balanceOf(user), 0);
    //     assertEq(dpt.balanceOf(crematorium), fee);
    //     // 100 CDC have to transfered to user
    //     assertEq(cdc.balanceOf(user), 100 ether);
    // }

    // function testFailBuyTokensWithFeeDueInvalidFeed() public {
    //     uint sentEth = 1.01 ether;

    //     feed.setValid(false);
    //     exchange.setManualDptRate(false);
    //     user.doBuyTokensWithFee(sentEth);
    // }
}
