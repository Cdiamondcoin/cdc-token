pragma solidity ^0.4.25;

import "ds-math/math.sol";
import "ds-auth/auth.sol";
import "ds-token/token.sol";
import "ds-stop/stop.sol";
import "ds-note/note.sol";


contract MedianizerLikeEvents {
    event LogValidStatus(bool feedValid);
    event LogdptEthRate(uint dptEthRate);
}

/**
 * @title MedianizerLike
 * @dev MedianizerLike contract to getting/setting manual ethDpt rate.
 */
contract MedianizerLike is DSAuth, MedianizerLikeEvents {
    bytes32 public dptEthRate;
    bool public feedValid;

    constructor(uint dptEthRate_, bool feedValid_) public {
        dptEthRate = bytes32(dptEthRate_);
        feedValid = feedValid_;
    }

    function setdptEthRate(uint dptEthRate_) public auth {
        dptEthRate = bytes32(dptEthRate_);
        emit LogdptEthRate(dptEthRate_);
    }

    function setValid(bool feedValid_) public auth {
        feedValid = feedValid_;
        emit LogValidStatus(feedValid_);
    }

    function peek() external view returns (bytes32, bool) {
        return (dptEthRate, feedValid);
    }
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
    event LogBuyDptFee(address owner, address sender, uint ethValue, uint rate, uint fee);
    event LogDptSellerChange(address oldSeller, address newSeller);
}

contract CdcExchange is DSAuth, DSStop, DSMath, CdcExchangeEvents {
    DSToken public cdc;                       //CDC token contract
    DSToken public dpt;                       //DPT token contract
    uint public ethCdcRate = 100 ether;     //how many CDC 1 ETH cost. 18 digit precision
    uint public dptEthRate = 0.01 ether;    //how many ETH 1 DPT cost. 18 digit precision
    uint public fee = 0.015 ether;          //fee in DPT on buying CDC via dApp
    MedianizerLike public priceFeed;            //address of the price feed
    address public dptSeller;               //from this address user buy DPT fee
    bool public manualDptRate = true;       //allow set ETH/DPT rate manually

    /**
    * @dev Constructor
    */
    constructor(address cdc_, address dpt_, address priceFeed_, address dptSeller_) public {
        cdc = DSToken(cdc_);
        dpt = DSToken(dpt_);
        priceFeed = MedianizerLike(priceFeed_);
        dptSeller = dptSeller_;
    }

    /**
    * @dev Fallback function is used to buy tokens.
    */
    function () external payable {
        buyTokens();
    }

    /**
    * @dev Тoken purchase function.
    */
    function buyTokens() public payable stoppable returns (uint tokens) {
        require(msg.value != 0, "Invalid amount");

        tokens = wmul(msg.value, ethCdcRate);

        address(owner).transfer(msg.value);
        cdc.transferFrom(owner, msg.sender, tokens);
        emit LogBuyToken(owner, msg.sender, msg.value, tokens, ethCdcRate);
        return tokens;
    }

    /**
    * @dev Тoken purchase with DPT fee function.
    */
    // TODO: auth to call this function
    function buyTokensWithFee() public payable stoppable returns (uint tokens) {
        require(msg.value != 0, "Invalid amount");

        uint feeEth = takeDptFee();
        uint ethAmountToBuyCdc = sub(msg.value, feeEth);

        // Transfer ETH for fee
        address(dptSeller).transfer(feeEth);

        tokens = wmul(ethAmountToBuyCdc, ethCdcRate);
        cdc.transferFrom(owner, msg.sender, tokens);
        // Transfer ETH for CDC
        address(owner).transfer(ethAmountToBuyCdc);

        // burn DPT fee
        dpt.burn(fee);
        emit LogBuyTokenWithFee(owner, msg.sender, msg.value, tokens, ethCdcRate, fee);
        return tokens;
    }

    /**
    * @dev DPT fee transfer.
    */
    // TODO: only authorized addresses can call this function
    function takeDptFee() internal returns (uint ethAmount) {
        bytes32 dptEthRateBytes;
        bool feedValid;

        require(msg.value != 0, "Invalid ETH amount");

        // receive ETH/DPT price from external feed
        (dptEthRateBytes, feedValid) = priceFeed.peek();

        // if feed is valid, load ETH/DPT rate from it
        if (feedValid) {
            dptEthRate = uint(dptEthRateBytes);
        } else {
            // if feed invalid revert if manualUSDRate_ is NOT allowed
            require(manualDptRate, "Manual rate not allowed");
        }

        // calculate fee price in ETH and transfer to owner ETH
        ethAmount = wmul(dptEthRate, fee);

        // transfer fee to contract, this fee will be burn
        dpt.transferFrom(dptSeller, address(this), fee);
        emit LogBuyDptFee(owner, msg.sender, ethAmount, dptEthRate, fee);
        return ethAmount;
    }

    /**
    * @dev Get DPT price in ETH for amount.
    */
    function getCdcPriceWithFee(uint amount_) public view returns (uint ethPrice) {
        require(amount_ > 0, "Invalid amount");

        uint dptEthRate_ = dptEthRate;
        bool feedValid;
        bytes32 dptEthRateBytes;

        // receive ETH/DPT price from external feed
        (dptEthRateBytes, feedValid) = priceFeed.peek();

        // if feed is valid, load ETH/DPT rate from it
        if (feedValid) {
            dptEthRate_ = uint(dptEthRateBytes);
        } else {
            // if feed invalid revert if manualUSDRate_ is NOT allowed
            require(manualDptRate, "Manual rate not allowed");
        }

        // Total price = DPT fee price + CDC amount price
        ethPrice = add(wmul(dptEthRate_, fee), wdiv(ethCdcRate, amount_));
        return ethPrice;
    }

    /**
    * @dev Set exchange rate ETH/CDC value.
    */
    function setEthCdcRate(uint ethCdcRate_) public auth note {
        require(ethCdcRate_ > 0, "Invalid amount");
        ethCdcRate = ethCdcRate_;
    }

    /**
    * @dev Set the fee to buying CDC
    */
    function setFee(uint fee_) public auth note {
        fee = fee_;
    }

    /**
    * @dev Set the price feed
    */
    function setPriceFeed(address priceFeed_) public auth note {
        require(priceFeed_ != 0x0, "Wrong PriceFeed address");
        priceFeed = MedianizerLike(priceFeed_);
    }

    /**
    * @dev Set the DPT seller
    */
    function setDptSeller(address dptSeller_) public auth {
        emit LogDptSellerChange(dptSeller, dptSeller_);
        dptSeller = dptSeller_;
    }

    /**
    * @dev Set manual feed update
    *
    * If `manualDptRate` is true, then `buyDptFee()` will calculate the DPT amount based on latest valid `dptEthRate`,
    * so `dptEthRate` must be updated by admins if priceFeed fails to provide valid price data.
    *
    * If manualUsdRate is false, then buyDptFee() will simply revert if priceFeed does not provide valid price data.
    */
    function setManualDptRate(bool manualDptRate_) public auth note {
        manualDptRate = manualDptRate_;
    }
}
