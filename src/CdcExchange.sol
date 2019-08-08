pragma solidity ^0.4.25;

import "ds-math/math.sol";
import "ds-auth/auth.sol";
import "ds-token/token.sol";
import "ds-stop/stop.sol";
import "ds-note/note.sol";


/**
* @dev Contract to get ETH/USD price
*/
contract MedianizerLike {
    function peek() external view returns (bytes32, bool);
}

/**
* @dev Contract to calculate user fee based on amount
*/
contract CdcFinance {
    function calculateFee(address sender, uint value) external view returns (uint);
}

/**
 * @title Cdc
 * @dev Cdc Exchange contract.
 */
contract CdcExchangeEvents {
    event LogBuyToken(
        address owner,
        address sender,
        uint ethValue,
        uint cdcValue,
        uint rate
    );
    event LogBuyTokenWithFee(
        address owner,
        address sender,
        uint ethValue,
        uint cdcValue,
        uint rate,
        uint fee
    );
    event LogBuyDptFee(address sender, uint ethValue, uint ethUsdRate, uint dptUsdRate, uint fee);

    event LogLiquidityContractChange(address liquidityContract);
    event LogSetFee(uint fee);

    event LogSetEthUsdRate(uint rate);
    event LogSetCdcUsdRate(uint rate);
    event LogSetDptUsdRate(uint rate);

    event LogSetManualCdcRate(bool value);
    event LogSetManualDptRate(bool value);
    event LogSetManualEthRate(bool value);

    event LogSetEthPriceFeed(address priceFeed);
    event LogSetDptPriceFeed(address priceFeed);
    event LogSetCdcPriceFeed(address priceFeed);
    event LogSetCfo(address cfo);
}

contract CdcExchange is DSAuth, DSStop, DSMath, CdcExchangeEvents {
    DSToken public cdc;                     //CDC token contract
    DSToken public dpt;                     //DPT token contract

    MedianizerLike public ethPriceFeed;     //address of the ETH/USD price feed
    MedianizerLike public dptPriceFeed;     //address of the DPT/USD price feed
    MedianizerLike public cdcPriceFeed;     //address of the CDC/USD price feed

    uint public dptUsdRate;                 //price of 1 DPT in USD. 18 digit precision
    uint public cdcUsdRate;                 //price of 1 CDC in USD. 18 digit precision
    uint public ethUsdRate;                 //price of 1 ETH in USD. 18 digit precision
    bool public manualEthRate = true;       //allow to ETH/USD rate manually if feed is invalid
    bool public manualDptRate = true;       //allow to DPT/USD rate manually if feed is invalid
    bool public manualCdcRate = true;       //allow to CDC/USD rate manually if feed is invalid

    uint public fee = 0.5 ether;            //fee in USD on buying CDC
    CdcFinance public cfo;                  //fee calculator contract

    address public liquidityContract;       //contract providing DPT liquidity to pay for fee
    address public burner;                  //contract where accured fee of DPT is stored before being burned

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
    ) public {
        cdc = DSToken(cdc_);
        dpt = DSToken(dpt_);
        ethPriceFeed = MedianizerLike(ethPriceFeed_);
        dptPriceFeed = MedianizerLike(dptPriceFeed_);
        cdcPriceFeed = MedianizerLike(cdcPriceFeed_);
        liquidityContract = liquidityContract_;
        burner = burner_;
        dptUsdRate = dptUsdRate_;
        cdcUsdRate = cdcUsdRate_;
        ethUsdRate = ethUsdRate_;
    }

    /**
    * @dev Fallback function to buy tokens.
    */
    function () external payable {
        buyTokensWithFee();
    }

    /**
    * @dev Тoken purchase with fee. (If user has DPT he must approve this contract,
    * otherwise transaction will fail.)
    */
    function buyTokensWithFee() public payable stoppable returns (uint tokens) {
        require(msg.value != 0, "Invalid amount");
        updateRates();                                           // Getting rates from price feeds
        uint amountEthToBuyCdc = msg.value;
        fee = calculateFee(msg.sender, msg.value);               // Get fee in USD
        if (fee > 0) {
            amountEthToBuyCdc = takeFee(fee, amountEthToBuyCdc); // take or sell fee and return remaining ETH amount to buy CDC
        }
        tokens = sellCdc(msg.sender, amountEthToBuyCdc);         // send CDC to user
        emit LogBuyTokenWithFee(owner, msg.sender, msg.value, tokens, cdcUsdRate, fee);
        return tokens;
    }

    /**
    * @dev Ability to delegate fee calculating to external contract.
    * @return the fee amount in USD
    */
    function calculateFee(address sender, uint value) public view returns (uint) {
        if (cfo == CdcFinance(0)) {
            return fee;
        } else {
            return cfo.calculateFee(sender, value);
        }
    }

    /**
    * @dev Set the fee to buying CDC
    */
    function setFee(uint fee_) public auth {
        fee = fee_;
        emit LogSetFee(fee);
    }

    /**
    * @dev Set the ETH/USD price feed
    */
    function setEthPriceFeed(address ethPriceFeed_) public auth {
        require(ethPriceFeed_ != 0x0, "Wrong PriceFeed address");
        ethPriceFeed = MedianizerLike(ethPriceFeed_);
        emit LogSetEthPriceFeed(ethPriceFeed);
    }

    /**
    * @dev Set the DPT/USD price feed
    */
    function setDptPriceFeed(address dptPriceFeed_) public auth {
        require(dptPriceFeed_ != 0x0, "Wrong PriceFeed address");
        dptPriceFeed = MedianizerLike(dptPriceFeed_);
        emit LogSetDptPriceFeed(dptPriceFeed);
    }

    /**
    * @dev Set the CDC/USD price feed
    */
    function setCdcPriceFeed(address cdcPriceFeed_) public auth {
        require(cdcPriceFeed_ != 0x0, "Wrong PriceFeed address");
        cdcPriceFeed = MedianizerLike(cdcPriceFeed_);
        emit LogSetCdcPriceFeed(cdcPriceFeed);
    }

    /**
    * @dev Set the DPT liquidity providing contract with balance > 0
    */
    function setLiquidityContract(address liquidityContract_) public auth {
        require(liquidityContract_ != 0x0, "Wrong address");
        require(dpt.balanceOf(liquidityContract_) > 0, "Insufficient funds of DPT");
        liquidityContract = liquidityContract_;
        emit LogLiquidityContractChange(liquidityContract);
    }

    /**
    * @dev Set manual feed update
    *
    * If `manualDptRate` is true, then `buyDptFee()` will calculate the DPT amount based on latest valid `dptUsdRate`,
    * so `dptEthRate` must be updated by admins if priceFeed fails to provide valid price data.
    *
    * If manualEthRate is false, then buyDptFee() will simply revert if priceFeed does not provide valid price data.
    */
    function setManualDptRate(bool manualDptRate_) public auth {
        manualDptRate = manualDptRate_;
        emit LogSetManualDptRate(manualDptRate);
    }

    function setManualCdcRate(bool manualCdcRate_) public auth {
        manualCdcRate = manualCdcRate_;
        emit LogSetManualCdcRate(manualCdcRate);
    }

    function setManualEthRate(bool manualEthRate_) public auth {
        manualEthRate = manualEthRate_;
        emit LogSetManualEthRate(manualEthRate);
    }

    function setCfo(address cfo_) public auth {
        require(cfo_ != 0x0, "Wrong address");
        cfo = CdcFinance(cfo_);
        emit LogSetCfo(cfo);
    }

    function setDptUsdRate(uint dptUsdRate_) public auth {
        require(dptUsdRate_ > 0, "Rate have to be larger than 0");
        dptUsdRate = dptUsdRate_;
        emit LogSetDptUsdRate(dptUsdRate);
    }

    function setCdcUsdRate(uint cdcUsdRate_) public auth {
        require(cdcUsdRate_ > 0, "Rate have to be larger than 0");
        cdcUsdRate = cdcUsdRate_;
        emit LogSetCdcUsdRate(cdcUsdRate);
    }

    function setEthUsdRate(uint ethUsdRate_) public auth {
        require(ethUsdRate_ > 0, "Rate have to be larger than 0");
        ethUsdRate = ethUsdRate_;
        emit LogSetEthUsdRate(ethUsdRate);
    }


    // internal functions

    /**
    * @dev Get CDC/USD rate from priceFeed 
    * Revert transaction if not valid feed and manual value not allowed
    */
    function updateUsdRate(MedianizerLike priceFeed, bool manualRate, uint currentRate) internal view returns (uint usdRate) {
        bool feedValid;
        bytes32 usdRateBytes;

        (usdRateBytes, feedValid) = priceFeed.peek();          // receive DPT/USD price
        if (feedValid) {                                       // if feed is valid, load DPT/USD rate from it
            usdRate = uint(usdRateBytes);
        } else {
            require(manualRate, "Manual rate not allowed");    // if feed invalid revert if manualEthRate is NOT allowed
            usdRate = currentRate;
        }
    }

    function updateRates() internal {
        ethUsdRate = updateUsdRate(ethPriceFeed, manualEthRate, ethUsdRate);
        dptUsdRate = updateUsdRate(dptPriceFeed, manualDptRate, dptUsdRate);
        cdcUsdRate = updateUsdRate(cdcPriceFeed, manualCdcRate, cdcUsdRate);
    }

    /**
    * @dev Taking fee from user. If user has DPT takes it, if there is none buys it for user.
    * @return the amount of remaining ETH after buying fee if it was required
    */
    function takeFee(uint feeUsd, uint amountEth) internal returns(uint remainingEth) {
        remainingEth = amountEth;
        uint feeDpt = wdiv(feeUsd, dptUsdRate);                          // Convert to DPT
        uint remainingFeeDpt = takeFeeInDptFromUser(msg.sender, feeDpt); // Take fee in DPT from user balance
        if (remainingFeeDpt > 0) {                                       // insufficient funds of DPT => user has to buy remaining fee by ETH
            uint feeEth = buyDptFee(remainingFeeDpt);
            remainingEth = sub(remainingEth, feeEth);
        }

        return remainingEth;
    }

    /**
    * @dev Buy fee in DPT from liquidityContract for ETH using current DPT/USD and ETH/USD rates.
    * @return the amount of sold fee in ETH
    */
    function buyDptFee(uint feeDpt) internal returns (uint amountEth) {
        uint feeUsd = wmul(feeDpt, dptUsdRate);
        amountEth = wdiv(feeUsd, ethUsdRate);                // calculate fee in ETH
        address(liquidityContract).transfer(amountEth);      // user pays for fee
        dpt.transferFrom(liquidityContract, burner, feeDpt); // transfer bought fee to burner

        emit LogBuyDptFee(msg.sender, amountEth, ethUsdRate, dptUsdRate, feeUsd);
        return amountEth;
    }

    /**
    * @dev Take fee in DPT from user if it has any
    * @param feeDpt the fee amount in DPT
    * @return the remaining fee amount in DPT
    */
    function takeFeeInDptFromUser(address user, uint feeDpt) internal returns (uint remainingFee) {
        uint dptUserBalance = dpt.balanceOf(user);
        uint minDpt = min(feeDpt, dptUserBalance);              // calculate how much DPT user has to buy

        remainingFee = sub(feeDpt, minDpt);
        if (minDpt > 0) dpt.transferFrom(user, burner, minDpt); // DPT transfer to burner 
        return remainingFee;
    }

    /**
    * @dev Calculate and transfer CDC tokens to user. Transfer ETH to owner for CDC
    * @return sold token amount
    */
    function sellCdc(address user, uint amountEth) internal returns (uint tokens) {
        tokens = wdiv(wmul(amountEth, ethUsdRate), cdcUsdRate);
        cdc.transferFrom(owner, user, tokens);
        address(owner).transfer(amountEth);
        return tokens;
    }
}
