pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "ds-token/token.sol";
import "./CdcExchange.sol";
import "./Cdc.sol";

contract Dpt is DSToken {
    constructor() DSToken('DPT') public {
        uint totalSupply_ = (10 ** 7) * (10 ** 18);
        super.mint(totalSupply_);
        transfer(owner, totalSupply_);
    }

    // copied from DPT production token
    function burn(address _who, uint256 _value) public {
        require(_value <= _balances[_who], "dpt-token-insufficient-balance");

        _balances[_who] = sub(_balances[_who], _value);
        _supply = sub(_supply, _value);
    }
}

contract CdcExchangeTester {
    CdcExchange public _exchange;
    Dpt public _dpt;

    constructor(CdcExchange exchange, Dpt dpt) public {
        _exchange = exchange;
        _dpt = dpt;
    }

    function doBuyTokensWithFee(uint amount) public payable {
        _exchange.buyTokensWithFee.value(amount)();
    }

    function doDptApprove(address to, uint amount) public {
        _dpt.approve(to, amount);
    }

    function () external payable {
    }
}

contract CdcExchangeTest is DSTest, DSMath, CdcExchangeEvents {
    uint constant Cdc_SUPPLY = (10 ** 7) * (10 ** 18);
    Cdc cdc;
    Dpt dpt;
    CdcExchange exchange;
    CdcExchangeTester user;
    MedianizerLike feed;
    uint etherBalance;
    uint sendEth;
    uint ethCdcRate = 30 ether;

    function setUp() public {
        cdc = new Cdc();
        dpt = new Dpt();
        feed = new MedianizerLike(0.01 ether, true);
        exchange = new CdcExchange(cdc, dpt, feed, address(this));
        user = new CdcExchangeTester(exchange, dpt);
        cdc.approve(exchange, uint(-1));
        dpt.approve(exchange, uint(-1));
        require(cdc.balanceOf(this) == Cdc_SUPPLY);
        require(dpt.balanceOf(this) == Cdc_SUPPLY);
        require(address(this).balance >= 1000 ether);
        address(user).transfer(1000 ether);
        etherBalance = address(this).balance;
    }

    function () external payable {
    }

    function testSetEthCdcRate() public {
        exchange.setEthCdcRate(ethCdcRate);
        assertEq(exchange.ethCdcRate(), ethCdcRate);
    }

    function testSetFee() public {
        uint fee = 0.01 ether;
        exchange.setFee(fee);
        assertEq(exchange.fee(), fee);
    }

    function testSetPriceFeed() public {
        MedianizerLike newFeed = new MedianizerLike(0.01 ether, true);
        exchange.setPriceFeed(newFeed);
        assertEq(exchange.priceFeed(), newFeed);
    }

    function testSetDptSeller() public {
        exchange.setDptSeller(user);
        assertEq(exchange.dptSeller(), user);
    }

    function testSetManualDptRate() public {
        exchange.setManualDptRate(false);
        assertTrue(!exchange.manualDptRate());
    }

    function testBuyTokensWithFee() public {
        uint current_balance = address(this).balance;
        uint user_current_balance = address(user).balance;
        uint fee = 1 ether;
        uint sentEth = 1.01 ether;

        exchange.setEthCdcRate(100 ether);
        exchange.setFee(fee);

        user.doBuyTokensWithFee(sentEth);
        // ETH balance have to be correct
        assertEq(address(this).balance, add(current_balance, sentEth));
        assertEq(address(user).balance, sub(user_current_balance, sentEth));
        // DPT have to be burned
        assertEq(dpt.balanceOf(this), sub(Cdc_SUPPLY, fee));
        assertEq(dpt.totalSupply(), sub(Cdc_SUPPLY, fee));
        // 100 CDC have to transfered to user
        assertEq(cdc.balanceOf(user), 100 ether);
    }

    function testBuyTokensWithFeeUserHasDpt() public {
        uint current_balance = address(this).balance;
        uint user_current_balance = address(user).balance;
        uint fee = 1 ether;
        uint sentEth = 1 ether;

        exchange.setEthCdcRate(100 ether);
        exchange.setFee(fee);

        dpt.push(user, fee);
        user.doDptApprove(exchange, fee);

        user.doBuyTokensWithFee(sentEth);
        // ETH balance have to be correct
        assertEq(address(this).balance, add(current_balance, sentEth));
        assertEq(address(user).balance, sub(user_current_balance, sentEth));
        // DPT have to be burned
        assertEq(dpt.balanceOf(user), 0);
        assertEq(dpt.totalSupply(), sub(Cdc_SUPPLY, fee));
        // 100 CDC have to transfered to user
        assertEq(cdc.balanceOf(user), 100 ether);
    }

    function testBuyTokensWithFeeUserHasHalfOfDpt() public {
        uint current_balance = address(this).balance;
        uint user_current_balance = address(user).balance;
        uint fee = 2 ether;
        uint user_dpt_amount = 1 ether;
        uint sentEth = 1.01 ether;

        exchange.setEthCdcRate(100 ether);
        exchange.setFee(fee);

        dpt.push(user, user_dpt_amount);
        user.doDptApprove(exchange, user_dpt_amount);

        user.doBuyTokensWithFee(sentEth);
        // ETH balance have to be correct
        assertEq(address(this).balance, add(current_balance, sentEth));
        assertEq(address(user).balance, sub(user_current_balance, sentEth));
        // DPT have to be burned => 0.5 have to be taken from user and 0.5 from seller
        assertEq(dpt.balanceOf(user), 0);
        assertEq(dpt.totalSupply(), sub(Cdc_SUPPLY, fee));
        // 100 CDC have to transfered to user
        assertEq(cdc.balanceOf(user), 100 ether);
    }

    function testFailBuyTokensWithFeeDueInvalidFeed() public {
        uint sentEth = 1.01 ether;

        feed.setValid(false);
        exchange.setManualDptRate(false);
        user.doBuyTokensWithFee(sentEth);
    }
}
