pragma solidity ^0.4.25;

import "ds-math/math.sol";
import "ds-auth/auth.sol";
import "ds-token/token.sol";
import "ds-stop/stop.sol";
import "ds-note/note.sol";


/**
* @dev Contract to getting ETH/USD price
*/
contract MedianizerLike {
    function peek() external view returns (bytes32, bool);
}

/**
* @dev Contract to calculating fee by user and sended amount
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
    event LogBuyDptFee(address sender, uint ethValue, uint rate, uint fee);

    event LogDptSellerChange(address dptSeller);
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
    uint public dptUsdRate;                 //how many USD 1 DPT cost. 18 digit precision
    uint public cdcUsdRate;                 //how many USD 1 CDC cost. 18 digit precision
    uint public ethUsdRate;                 //how many USD 1 ETH cost. 18 digit precision
    bool public manualEthRate = true;       //allow to use/set manually setted DPT/USD rate
    bool public manualDptRate = true;       //allow to use/set manually setted CDC/USD rate
    bool public manualCdcRate = true;       //allow to use/set manually setted CDC/USD rate

    uint public fee = 0.5 ether;            //fee in USD on buying CDC
    CdcFinance public cfo;                  //CFO of CDC contract

    address public dptSeller;               //from this address user buy DPT fee
    address public crematorium;             //contract where DPT as fee are stored before be burned

    constructor(
        address cdc_,
        address dpt_,
        address ethPriceFeed_,
        address dptPriceFeed_,
        address cdcPriceFeed_,
        address dptSeller_,
        address crematorium_
    ) public {
        cdc = DSToken(cdc_);
        dpt = DSToken(dpt_);
        ethPriceFeed = MedianizerLike(ethPriceFeed_);
        dptPriceFeed = MedianizerLike(dptPriceFeed_);
        cdcPriceFeed = MedianizerLike(cdcPriceFeed_);
        dptSeller = dptSeller_;
        crematorium = crematorium_;
    }

    /**
    * @dev Fallback function is used to buy tokens.
    */
    function () external payable {
        buyTokensWithFee();
    }

    /**
    * @dev Тoken purchase with fee. User have to approve DPT before (if it has already)
    * otherwise transaction w'll fail
    */
    function buyTokensWithFee() public payable stoppable returns (uint tokens) {
        require(msg.value != 0, "Invalid amount");

        // Getting rates from price feeds
        updateRates();

        uint ethAmountToBuyCdc = msg.value;
        // Get fee in USD
        fee = calculateFee(msg.sender, msg.value);

        // TODO: move to function?
        if (fee > 0) {
            // Convert to DPT
            uint feeInDpt = wdiv(fee, dptUsdRate);
            // Take fee in DPT from user balance
            feeInDpt = takeFeeInDptFromUser(msg.sender, feeInDpt);

            // insufficient funds of DPT => user has to buy remained fee by ETH
            if (feeInDpt > 0) {
                uint feeEth = buyDptFee(wmul(feeInDpt, dptUsdRate));
                ethAmountToBuyCdc = sub(ethAmountToBuyCdc, feeEth);
            }

            // "burn" DPT fee
            dpt.transfer(crematorium, fee);
        }

        // send CDC to user
        tokens = sellCdc(msg.sender, ethAmountToBuyCdc);

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
    * @dev Set the DPT seller with balance > 0
    */
    function setDptSeller(address dptSeller_) public auth {
        require(dptSeller_ != 0x0, "Wrong address");
        require(dpt.balanceOf(dptSeller_) > 0, "Insufficient funds of DPT");
        dptSeller = dptSeller_;
        emit LogDptSellerChange(dptSeller);
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


    // internals functions

    /**
    * @dev Get ETH/USD rate from priceFeed.
    * Revert transaction if not valid feed and manual value not allowed
    */
    function updateEthUsdRate() internal {
        bool feedValid;
        bytes32 ethUsdRateBytes;

        // receive ETH/DPT price
        (ethUsdRateBytes, feedValid) = ethPriceFeed.peek();

        // if feed is valid, load ETH/USD rate from it
        if (feedValid) {
            ethUsdRate = uint(ethUsdRateBytes);
        } else {
            // if feed invalid revert if manualEthRate is NOT allowed
            require(manualEthRate, "Manual rate not allowed");
        }
    }

    /**
    * @dev Get DPT/USD rate from priceFeed.
    * Revert transaction if not valid feed and manual value not allowed
    */
    function updateDptUsdRate() internal {
        bool feedValid;
        bytes32 dptUsdRateBytes;

        // receive DPT/USD price
        (dptUsdRateBytes, feedValid) = dptPriceFeed.peek();

        // if feed is valid, load DPT/USD rate from it
        if (feedValid) {
            dptUsdRate = uint(dptUsdRateBytes);
        } else {
            // if feed invalid revert if manualEthRate is NOT allowed
            require(manualDptRate, "Manual rate not allowed");
        }
    }

    /**
    * @dev Get CDC/USD rate from priceFeed.
    * Revert transaction if not valid feed and manual value not allowed
    */
    function updateCdcUsdRate() internal {
        bool feedValid;
        bytes32 cdcUsdRateBytes;

        // receive DPT/USD price
        (cdcUsdRateBytes, feedValid) = cdcPriceFeed.peek();

        // if feed is valid, load DPT/USD rate from it
        if (feedValid) {
            cdcUsdRate = uint(cdcUsdRateBytes);
        } else {
            // if feed invalid revert if manualEthRate is NOT allowed
            require(manualCdcRate, "Manual rate not allowed");
        }
    }

    function updateRates() internal {
        updateEthUsdRate();
        updateDptUsdRate();
        updateCdcUsdRate();
    }

    /**
    * @dev User buy fee_ in DPT by ETH with actual ETH/USD rate from dptSeller.
    * @param fee_ the fee in USD
    * @return the amount of sold fee in ETH
    */
    function buyDptFee(uint fee_) internal returns (uint ethAmount) {
        // calculate fee in ETH
        ethAmount = wdiv(fee_, ethUsdRate);
        // user pays for fee
        address(dptSeller).transfer(ethAmount);
        // transfer bought fee to contract, this fee will be burned
        dpt.transferFrom(dptSeller, address(this), fee_);

        emit LogBuyDptFee(msg.sender, ethAmount, ethUsdRate, fee_);
        return ethAmount;
    }

    /**
    * @dev Take fee in DPT from user if it has any
    * @param feeInDpt the fee amount in DPT
    * @return the remained fee amount in DPT
    */
    function takeFeeInDptFromUser(address user, uint feeInDpt) internal returns (uint remainFee) {
        uint dptUserBalance = dpt.balanceOf(user);

        // Not any DPT on balance
        if (dptUserBalance <= 0) {
            remainFee = feeInDpt;
        // User has enough DPT to fee
        } else if (dptUserBalance >= feeInDpt) {
            remainFee = 0;
            // transfer to contract for future burn
            dpt.transferFrom(user, address(this), feeInDpt);
        // User has less DPT than required
        } else {
            remainFee = sub(feeInDpt, dptUserBalance);
            // transfer to contract for future burn
            dpt.transferFrom(user, address(this), dptUserBalance);
        }
        return remainFee;
    }

    /**
    * @dev Calculate and transfer CDC tokens to user. Transfer ETH to owner for CDC
    * @return sold token amount
    */
    function sellCdc(address user, uint ethAmount) internal returns (uint tokens) {
        tokens = wdiv(wmul(ethAmount, ethUsdRate), cdcUsdRate);
        cdc.transferFrom(owner, user, tokens);
        address(owner).transfer(ethAmount);
        return tokens;
    }
}
