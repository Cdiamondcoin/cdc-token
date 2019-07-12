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

contract DptTester {
    DSToken public _dpt;

    constructor(DSToken dpt) public {
        _dpt = dpt;
    }

    function doApprove(address to, uint amount) public {
        _dpt.approve(to, amount);
    }

    function () external payable {
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
    uint constant INITIAL_BALANCE = 1000 ether;

    Cdc cdc;
    DSToken dpt;
    CdcExchange exchange;

    DptTester dptSeller;
    CdcExchangeTester user;

    TestMedianizerLike ethPriceFeed;
    TestMedianizerLike dptPriceFeed;
    TestMedianizerLike cdcPriceFeed;

    Crematorium crematorium;
    TestCdcFinance cfo;

    // test variables
    uint ownerBalance;
    uint userBalance;
    uint dptSellerBalance;

    uint fee = 3 ether; // USD
    uint ethUsdRate = 300 ether;
    uint dptUsdRate = 3 ether;
    uint cdcUsdRate = 30 ether;

    function setUp() public {
        cdc = new Cdc();
        dpt = new DSToken("DPT");
        dpt.mint(CDC_SUPPLY);

        ethPriceFeed = new TestMedianizerLike(ethUsdRate, true);
        dptPriceFeed = new TestMedianizerLike(dptUsdRate, true);
        cdcPriceFeed = new TestMedianizerLike(cdcUsdRate, true);

        crematorium = new Crematorium(dpt);
        dptSeller = new DptTester(dpt);
        exchange = new CdcExchange(cdc, dpt, ethPriceFeed, dptPriceFeed, cdcPriceFeed, dptSeller, crematorium);
        user = new CdcExchangeTester(exchange, dpt);
        cfo = new TestCdcFinance();

        cdc.approve(exchange, uint(-1));
        dpt.approve(exchange, uint(-1));
        // Prepare seller of DPT fees
        dpt.transfer(dptSeller, INITIAL_BALANCE);
        dptSeller.doApprove(exchange, uint(-1));

        address(user).transfer(INITIAL_BALANCE);

        ownerBalance = address(this).balance;
        userBalance = address(user).balance;
        dptSellerBalance = address(dptSeller).balance;
    }

    function () external payable {
    }

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

    /**
    * @dev User does not has any DPT and send only ETH and get CDC
    */
    function testBuyTokensWithFee() public {
        uint sentEth = 1 ether;
        exchange.setFee(fee);

        user.doBuyTokensWithFee(sentEth);

        uint feeInDpt = wdiv(fee, dptUsdRate);
        uint feeInEth = wdiv(fee, ethUsdRate);
        // DPT (eq fee in USD) must be sold from dptSeller balance
        assertEq(dpt.balanceOf(address(dptSeller)), sub(INITIAL_BALANCE, feeInDpt));
        // DPT fee have to be transfered to crematorium
        assertEq(dpt.balanceOf(crematorium), feeInDpt);

        // ETH (minus ETH for DPT fee) must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, feeInEth)));
        // ETH for DPT fee must be sent to dptSeller balance from user balance
        assertEq(address(dptSeller).balance, add(dptSellerBalance, feeInEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), 9.9 ether);
    }

    /**
    * @dev User has DPT. Send ETH and get CDC for all amount of ETH and minus fee on DPT balance
    */
    function testBuyTokensWithFeeUserHasDpt() public {
        uint sentEth = 1 ether;
        exchange.setFee(fee);

        // setup user dpt balance
        dpt.transfer(user, INITIAL_BALANCE);
        user.doDptApprove(exchange, uint(-1));

        user.doBuyTokensWithFee(sentEth);

        uint feeInDpt = wdiv(fee, dptUsdRate);
        // DPT balance of dptSeller must be untouched
        assertEq(dpt.balanceOf(address(dptSeller)), INITIAL_BALANCE);
        // DPT fee have to be transfered to crematorium from user
        assertEq(dpt.balanceOf(crematorium), feeInDpt);
        assertEq(dpt.balanceOf(user), sub(INITIAL_BALANCE, feeInDpt));

        // ETH must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sentEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), 10 ether);
    }

    /**
    * @dev User has DPT but less than fee. Send ETH, get CDC, buy remained DPT fee
    */
    function testBuyTokensWithFeeUserHasInsufficientlyDpt() public {
        uint sentEth = 1 ether;
        uint userDptBalance = 0.5 ether;
        exchange.setFee(fee);

        // setup user dpt balance
        dpt.transfer(user, userDptBalance);
        user.doDptApprove(exchange, uint(-1));

        user.doBuyTokensWithFee(sentEth);

        uint feeInDpt = wdiv(fee, dptUsdRate);
        // DPT must be sold from dptSeller balance
        assertEq(dpt.balanceOf(address(dptSeller)), sub(INITIAL_BALANCE, sub(feeInDpt, userDptBalance)));
        // DPT fee have to be transfered to crematorium
        assertEq(dpt.balanceOf(crematorium), feeInDpt);
        assertEq(dpt.balanceOf(user), 0);

        uint buyableFeeInUsd = wmul(sub(feeInDpt, userDptBalance), dptUsdRate);
        uint buyableFeeInEth = wdiv(buyableFeeInUsd, ethUsdRate);
        // ETH must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, buyableFeeInEth)));
        // ETH for DPT fee must be sent to dptSeller
        assertEq(address(dptSeller).balance, add(dptSellerBalance, buyableFeeInEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), 9.95 ether);
    }
}
