pragma solidity ^0.4.25;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "ds-token/token.sol";
import "./Cdc.sol";
import "./CdcExchange.sol";
import "./Burner.sol";

// Contract to test internals CdcExchange functions
contract ExposedCdcExchange is CdcExchange {
    constructor(
        address cdc_,
        address dpt_,
        address ethPriceFeed_,
        address dptPriceFeed_,
        address cdcPriceFeed_,
        address liquidityContract_,
        address burner_,
        uint dptUsdRate_,
        uint cdcUsdRate_,
        uint ethUsdRate_
    ) public CdcExchange(
        cdc_,
        dpt_,
        ethPriceFeed_,
        dptPriceFeed_,
        cdcPriceFeed_,
        liquidityContract_,
        burner_,
        dptUsdRate_,
        cdcUsdRate_,
        ethUsdRate_
    ) {
        // nothing to do
    }

    function _updateRates() public {
        updateRates();
    }
}

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

    function doTransfer(address to, uint amount) public {
        _dpt.transfer(to, amount);
    }

    function () external payable {
    }
}

contract CdcExchangeTester {
    ExposedCdcExchange public _exchange;
    DSToken public _dpt;

    constructor(ExposedCdcExchange exchange, DSToken dpt) public {
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

    function doSetCdcPriceFeed(address feed) public {
        _exchange.setCdcPriceFeed(feed);
    }

    function doSetLiquidityContract(address seller) public {
        _exchange.setLiquidityContract(seller);
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
    ExposedCdcExchange exchange;

    DptTester liquidityContract;
    CdcExchangeTester user;

    TestMedianizerLike ethPriceFeed;
    TestMedianizerLike dptPriceFeed;
    TestMedianizerLike cdcPriceFeed;

    Burner burner;
    TestCdcFinance cfo;

    // test variables
    uint ownerBalance;
    uint userBalance;
    uint liquidityContractBalance;

    uint fee = 3 ether; // USD
    uint dptUsdRate = 3 ether;
    uint cdcUsdRate = 30 ether;
    uint ethUsdRate = 300 ether;

    function setUp() public {
        cdc = new Cdc();
        dpt = new DSToken("DPT");
        dpt.mint(CDC_SUPPLY);

        ethPriceFeed = new TestMedianizerLike(ethUsdRate, true);
        dptPriceFeed = new TestMedianizerLike(dptUsdRate, true);
        cdcPriceFeed = new TestMedianizerLike(cdcUsdRate, true);

        burner = new Burner(dpt);
        liquidityContract = new DptTester(dpt);
        exchange = new ExposedCdcExchange(
            cdc, dpt,
            ethPriceFeed, dptPriceFeed, cdcPriceFeed,
            liquidityContract, burner,
            dptUsdRate, cdcUsdRate, ethUsdRate
        );
        exchange.setFee(fee);
        user = new CdcExchangeTester(exchange, dpt);
        cfo = new TestCdcFinance();

        cdc.approve(exchange, uint(-1));
        dpt.approve(exchange, uint(-1));
        // Prepare seller of DPT fees
        dpt.transfer(liquidityContract, INITIAL_BALANCE);
        liquidityContract.doApprove(exchange, uint(-1));

        address(user).transfer(INITIAL_BALANCE);

        ownerBalance = address(this).balance;
        userBalance = address(user).balance;
        liquidityContractBalance = address(liquidityContract).balance;
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

    function testFailNonOwnerSetPriceFeed() public {
        user.doSetDptPriceFeed(address(this));
    }

    function testSetCdcPriceFeed() public {
        exchange.setCdcPriceFeed(address(this));
        assertEq(exchange.cdcPriceFeed(), address(this));
    }

    function testFailWrongAddressSetCdcPriceFeed() public {
        exchange.setCdcPriceFeed(address(0));
    }

    function testFailNonOwnerSetCdcPriceFeed() public {
        user.doSetCdcPriceFeed(address(this));
    }

    function testSetLiquidityContract() public {
        dpt.transfer(address(user), 100 ether);
        exchange.setLiquidityContract(address(user));
        assertEq(exchange.liquidityContract(), address(user));
    }

    function testFailWrongAddressSetLiquidityContract() public {
        exchange.setLiquidityContract(address(0));
    }

    function testFailNonOwnerSetLiquidityContract() public {
        dpt.transfer(address(user), 100 ether);
        user.doSetLiquidityContract(address(user));
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
        assertEq(exchange.cfo(), address(cfo));
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

        uint feeDpt = wdiv(fee, dptUsdRate);
        uint feeEth = wdiv(fee, ethUsdRate);
        // DPT (eq fee in USD) must be sold from liquidityContract balance
        assertEq(dpt.balanceOf(address(liquidityContract)), sub(INITIAL_BALANCE, feeDpt));
        // DPT fee have to be transfered to burner
        assertEq(dpt.balanceOf(burner), feeDpt);

        // ETH (minus ETH for DPT fee) must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, feeEth)));
        // ETH for DPT fee must be sent to liquidityContract balance from user balance
        assertEq(address(liquidityContract).balance, add(liquidityContractBalance, feeEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), wdiv(sub(wmul(sentEth, ethUsdRate), fee), cdcUsdRate));
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

        uint feeDpt = wdiv(fee, dptUsdRate);
        // DPT balance of liquidityContract must be untouched
        assertEq(dpt.balanceOf(address(liquidityContract)), INITIAL_BALANCE);
        // DPT fee have to be transfered to burner from user
        assertEq(dpt.balanceOf(burner), feeDpt);
        assertEq(dpt.balanceOf(user), sub(INITIAL_BALANCE, feeDpt));

        // ETH must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sentEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), wdiv(wmul(sentEth, ethUsdRate), cdcUsdRate));
    }

    /**
    * @dev User has DPT but less than fee. Send ETH, get CDC, buy remained DPT fee
    */
    function testBuyTokensWithFeeUserHasInsufficientDpt() public {
        uint sentEth = 1 ether;
        uint userDptBalance = 0.5 ether;
        exchange.setFee(fee);

        // setup user dpt balance
        dpt.transfer(user, userDptBalance);
        user.doDptApprove(exchange, uint(-1));

        user.doBuyTokensWithFee(sentEth);

        uint feeDpt = wdiv(fee, dptUsdRate);
        // DPT must be sold from liquidityContract balance
        assertEq(dpt.balanceOf(address(liquidityContract)), sub(INITIAL_BALANCE, sub(feeDpt, userDptBalance)));
        // DPT fee have to be transfered to burner
        assertEq(dpt.balanceOf(burner), feeDpt);
        assertEq(dpt.balanceOf(user), 0);

        uint buyableFeeUsd = wmul(sub(feeDpt, userDptBalance), dptUsdRate);
        uint buyableFeeEth = wdiv(buyableFeeUsd, ethUsdRate);
        // ETH must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, buyableFeeEth)));
        // ETH for DPT fee must be sent to liquidityContract
        assertEq(address(liquidityContract).balance, add(liquidityContractBalance, buyableFeeEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), 9.95 ether);
    }

    /**
    * @dev LiquidityContract has insufficient amount of DPT
    * User send ETH and must get money back
    */
    function testFailBuyTokensWithFeeLiquidityContractHasInsufficientDpt() public {
        uint sentEth = 1 ether;

        // reset liquidityContract balance
        liquidityContract.doTransfer(address(this), INITIAL_BALANCE);
        user.doBuyTokensWithFee(sentEth);
    }

    /**
    * @dev ethPriceFeed is invlid, manual ethUsdRate must be taken
    */
    function testBuyTokensWithFeeWithManualEthUsdRate() public {
        uint sentEth = 1 ether;
        ethUsdRate = 400 ether;
        exchange.setEthUsdRate(ethUsdRate);
        ethPriceFeed.setValid(false);

        user.doBuyTokensWithFee(sentEth);

        uint feeDpt = wdiv(fee, dptUsdRate);
        uint feeEth = wdiv(fee, ethUsdRate);
        // DPT (eq fee in USD) must be sold from liquidityContract balance
        assertEq(dpt.balanceOf(address(liquidityContract)), sub(INITIAL_BALANCE, feeDpt));
        // DPT fee have to be transfered to burner
        assertEq(dpt.balanceOf(burner), feeDpt);

        // ETH (minus ETH for DPT fee) must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, feeEth)));
        // ETH for DPT fee must be sent to liquidityContract balance from user balance
        assertEq(address(liquidityContract).balance, add(liquidityContractBalance, feeEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), wdiv(sub(wmul(sentEth, ethUsdRate), fee), cdcUsdRate));
    }

    /**
    * @dev dptPriceFeed is invlid, manual dptUsdRate must be taken
    */
    function testBuyTokensWithFeeWithManualDptUsdRate() public {
        uint sentEth = 1 ether;
        dptUsdRate = 9.99 ether;
        exchange.setDptUsdRate(dptUsdRate);
        dptPriceFeed.setValid(false);

        user.doBuyTokensWithFee(sentEth);

        uint feeDpt = wdiv(fee, dptUsdRate);
        uint feeEth = wdiv(fee, ethUsdRate);
        // DPT (eq fee in USD) must be sold from liquidityContract balance
        assertEq(dpt.balanceOf(address(liquidityContract)), sub(INITIAL_BALANCE, feeDpt));
        // DPT fee have to be transfered to burner
        assertEq(dpt.balanceOf(burner), feeDpt);

        // ETH (minus ETH for DPT fee) must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, feeEth)));
        // ETH for DPT fee must be sent to liquidityContract balance from user balance
        assertEq(address(liquidityContract).balance, add(liquidityContractBalance, feeEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), wdiv(sub(wmul(sentEth, ethUsdRate), fee), cdcUsdRate));
    }

    /**
    * @dev cdcPriceFeed is invlid, manual cdcUsdRate must be taken
    */
    function testBuyTokensWithFeeWithManualCdcUsdRate() public {
        uint sentEth = 1 ether;
        cdcUsdRate = 40 ether;
        exchange.setCdcUsdRate(cdcUsdRate);
        cdcPriceFeed.setValid(false);

        user.doBuyTokensWithFee(sentEth);

        uint feeDpt = wdiv(fee, dptUsdRate);
        uint feeEth = wdiv(fee, ethUsdRate);
        // DPT (eq fee in USD) must be sold from liquidityContract balance
        assertEq(dpt.balanceOf(address(liquidityContract)), sub(INITIAL_BALANCE, feeDpt));
        // DPT fee have to be transfered to burner
        assertEq(dpt.balanceOf(burner), feeDpt);

        // ETH (minus ETH for DPT fee) must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sub(sentEth, feeEth)));
        // ETH for DPT fee must be sent to liquidityContract balance from user balance
        assertEq(address(liquidityContract).balance, add(liquidityContractBalance, feeEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), wdiv(sub(wmul(sentEth, ethUsdRate), fee), cdcUsdRate));
    }

    /**
    * @dev Transaction should be failed on sending 0 ETH
    */
    function testFailBuyTokensWithFeeSendZeroEth() public {
        uint sentEth = 0;
        user.doBuyTokensWithFee(sentEth);
    }

    /**
    * @dev Buy tokens with zero fee
    */
    function testBuyTokensWithFeeWhenFeeIsZero() public {
        uint sentEth = 1 ether;
        exchange.setFee(0);

        user.doBuyTokensWithFee(sentEth);

        // DPT balance of liquidityContract must be untouched
        assertEq(dpt.balanceOf(address(liquidityContract)), INITIAL_BALANCE);
        // Nothing should be burned
        assertEq(dpt.balanceOf(burner), 0);

        // ETH must be sent to owner balance from user balance
        assertEq(address(this).balance, add(ownerBalance, sentEth));
        // ETH on user balance
        assertEq(address(user).balance, sub(userBalance, sentEth));

        // CDC must be transfered to user
        assertEq(cdc.balanceOf(user), wdiv(wmul(sentEth, ethUsdRate), cdcUsdRate));
    }

    /**
    * @dev Buy tokens with max eth value
    */
    function testFailBuyTokensWithFeeWhenAmountMax() public {
        uint sentEth = uint(-1);
        // User does not have any CDC
        assertEq(cdc.balanceOf(user), 0);

        user.doBuyTokensWithFee(sentEth);
    }

    function testUpdateRates() public {
        cdcUsdRate = 40 ether;
        dptUsdRate = 12 ether;
        ethUsdRate = 500 ether;
        cdcPriceFeed.setRate(cdcUsdRate);
        dptPriceFeed.setRate(dptUsdRate);
        ethPriceFeed.setRate(ethUsdRate);

        exchange._updateRates();

        assertEq(exchange.cdcUsdRate(), cdcUsdRate);
        assertEq(exchange.dptUsdRate(), dptUsdRate);
        assertEq(exchange.ethUsdRate(), ethUsdRate);
    }
}
