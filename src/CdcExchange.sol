pragma solidity ^0.4.25;

import "ds-math/math.sol";
import "ds-auth/auth.sol";
import "ds-token/token.sol";
import "ds-stop/stop.sol";
import "ds-note/note.sol";


/**
* @dev Contract to get ETH/USD price
*/
contract TrustedFeedLike {
    function peek() external view returns (bytes32, bool);
}


/**
* @dev Contract to calculate user fee based on amount
*/
contract TrustedFeeCalculator {
    function calculateFee(address sender, uint value) external view returns (uint);
}


contract TrustedDsToken {
    function transferFrom(address from, address to, uint256 amount) external returns(bool);
    function allowance(address src, address guy) public view returns (uint);
}


contract TrustedAssetManagement {
    function notifyTransferFrom(TrustedErc721 erc721, address src, address dst, uint256 id721) external;
    function getPrice(TrustedErc721 erc721, uint256 id721) external view returns(uint256);
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
        indexed uint256 txId,
        indexed address sender,
        address custodian,
        address sellToken,
        address buyToken,
        uint256 value,
        uint256 fee,
        uint256 priceOrRate
    );

    event LogAllowedToken(indexed address token, bytes4 buy, bool allowed); // TODO: DONE
    event LogValueChange(indexed bytes32 kind, bytes32 value, bytes32 value1); // TODO: DONE
}


contract CdcExchange is DSAuth, DSStop, DSMath, CdcExchangeEvents {
    TrustedDsToken public cdc;                     //CDC token contract
    TrustedDsToken public dpt;                     //DPT token contract
    TrustedErc721Token public dpass;               //DPASS default token address

    mapping(address => uint256) private rate;         //exchange rate for a token
    mapping(address => bool) public manualRate;       //manualRate is allowed for a token (if feed invalid)
    mapping(address => MedianizerLike) public priceFeed; //price feed address for token  
    mapping(bytes4 => mapping(address => bool)) public allowed20;
    mapping(bytes4 => mapping(address => bool)) public allowed721;
    mapping(address => uint8) public decimals;
    mapping(address => bool) public decimalsSet;
    mapping(address => address) public custodian;

    TrustedFeeCalculator public fcc;           //fee calculator contract

    address public liq;                     //contract providing DPT liquidity to pay for fee
    address public wal;                     //wallet address, where we keep all the tokens we received as fee
    address public burner;                  //contract where accured fee of DPT is stored before being burned
    TrustedAssetManagement public asm;      //Asset Management contract
    uint256 public fixFee;                  //Fixed part of fee charged for buying 18 decimals precision in base currency
    uint256 public varFee;                  //Variable part of fee charged for buying 18 decimals precision in base currency
    uint256 public profitRate;           //the percentage of profit that is burned on all fees received. 18 decimals precision
    uint256 public callGas;                 //using this much gas when Ether is transferred
    uint256 public dust = 9;                //dust amount. Numbers below this amount are considered 0.
    uint256 public txId;                    //Unique id of each transaction.
    bool public takeAllFeeInDpt;            //If true, it takes cost + profit in DPT, if false only profit in DPT

    constructor(
        address cdc_,
        address dpt_,
        address dpass_,
        address ethPriceFeed_,
        address dptPriceFeed_,
        address cdcPriceFeed_,
        address liq_,
        address burner_,
        TrustedAssetManagement asm_,
        uint dptExchangeRate_,
        uint cdcExchangeRate_,
        uint ethExchangeRate_,
        uint fixFee_,
        uint varFee_,
        uint profitRate_,
        address wal_,
        uint256 callGas_
    ) public {

        allowToken(cdc_, "sell", "erc20", true);
        allowToken(cdc_, "buy", "erc20", true);
        allowToken(dpt_, "sell", "erc20", true);
        allowToken(dpt_, "buy", "erc20", true);
        allowToken(dpass_, "buy", "erc721", true);
;
        setValue("decimals", cdc_, 18);
        setValue("decimals", dpt_, 18);
        setValue("decimals", 0xee, 18);
        setValue("cdc", cdc_);
        setValue("dpt", dpt_);
        setValue("dpass", dpass_);
        setValue("priceFeed", 0xee, ethPriceFeed_)
        setValue("priceFeed", dpt_, dptPriceFeed_)
        setValue("priceFeed", cdc_, cdcPriceFeed_)
        setValue("liq", liq_);
        setValue("burner", burner_);
        setValue("asm", asm_);
        setValue("rate", dpt_, dptExchange_);
        setValue("rate", cdc_, cdcExchange_);
        setValue("rate", 0xee, ethExchange_);
        setValue("fixFee", fixFee_);
        setValue("varFee", varFee_);
        setValue("profitRate", profitRate_);
        setValue("wal", wal_);
        setValue("callGas", callGas_);
    }

    /**
    * @dev Fallback function to buy tokens.
    */
    function () external payable {
        buyTokensWithFee(0xee, msg.value, cdc, uint(-1));
    }

    /**
    * @dev Тoken purchase with fee. (If user has DPT he must approve this contract,
    * otherwise transaction will fail.)
    */
    function buyTokensWithFee (
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId, 
    ) public payable stoppable returns (uint tokens) {
        TrustedErc20 sellToken20;
        TrustedErc721 sellToken721;
        TrustedErc20 buyToken20;
        TrustedErc721 buyToken721;
        uint valueSell;
        uint valueBuy;
        bool isSellTokenErc20;
        bool isBuyTokenErc20;
        uint sellAmt = sellAmtOrId;
        uint buyAmt = buyAmtOrId;
        address feeTakenFrom;

        if (allowed20["sell"][sellToken]) {
            isSellTokenErc20 = true;
            sellToken20 = TrustedErc20(sellToken);
            require(sellToken == 0xee || sellAmtOrId == uint(-1) || sellAmtOrId <= min(sellToken20.blanceOf(msg.sender), token.allowance(msg.sender, this)), "Sell amount exceeds allowance");
            require(sellToken != 0xee || sellAmtOrId == uint(-1) || sellAmtOrId <= msg.value, "Sell amount exceeds Ether value");
            if (sellAmt == uint(-1)) {
                sellAmt = min(sellToken20.blanceOf(msg.sender), token.allowance(msg.sender, this));
            }
            valueSell = wmul(toDecimals(sellAmt, getDecimals(sellToken20), 18), updateRate(token));
                
        } else if (allowed721["sell"][sellToken]) {
            isSellTokenErc20 = false;
            sellToken721 = TrustedErc721(sellToken);
            valueSell = asm.getPrice(buyToken, buyAmtOrId);
        } else {
            require(false, "Token can not be sold");
        }

        if (allowed20["buy"][buyToken]) {
            isBuyTokenErc20 = true;
            buyToken20 = TrustedErc20(buyToken);
            require(buyToken == 0xee || buyAmtOrId == uint(-1) || buyAmtOrId <= min(buyToken20.blanceOf(msg.sender), token.allowance(msg.sender, this)), "Buy amount exceeds allowance");
            require(buyToken != 0xee || buyAmtOrId == uint(-1) || buyAmtOrId <= msg.value, "Buy amount exceeds Ether value");
            if (buyAmtOrId == uint(-1)) {
                buyAmt = min(buyToken20.balanceOf(custodian[buyToken20]), buyToken20.allowance(custodian[buyToken20], this));
                if (isSellTokenErc20 && sellAmtOrId == uint(-1)) {
                    buyAmt = min(
                        wdiv(toDecimals(valueSell, 18, getDecimals(buyToken20)), updateRate(buyToken20)),
                        buyAmt
                    );
                }
            }
            valueBuy = wmul(toDecimals(buyAmt, getDecimals(buyToken20), 18), updateRate(token));
        } else if (allowed721["buy"][buyToken]) {
            isBuyTokenErc20 = false;
            require(isSellTokenErc20, "One of tokens must be erc20");
            buyToken721 = TrustedErc721(buyToken);
            valueBuy = asm.getPrice(buyToken, buyAmtOrId);
        } else {
            require(false, "Token can not be bought");
        }
        
        fee = calculateFee(msg.sender, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        
        if (fee > 0) {
            (value, feeTakenFrom) = takeFee(fee, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        }

        sellTokens(value, feeTakenFrom, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);

        txId++;
        
        emit LogBuyTokenWithFee(txId, msg.sender, custodian[buyToken], sellToken, buyToken, value, fee, 
                                isBuyTokenErc20 ? rate[buyToken] : valueBuy);
    }

    /**
    * @dev Sell tokens of user
    */
    function sellTokens(
        uint256 valueAfterFee,      //adjusted value  that must be withdrawn
        address feeTakenFrom,       //token we subtracted the fee from
        uint256 origValue,          //trade value before fee was subtracted
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId, 
    ) internal {
        if (feeTakenFrom == sellToken) {
            if (allowed20["sell"][sellToken]) {
                sendToken(sellToken, msg.sender, custodian[sellToken], valueAfterFee);
            }  else {
                TrustedErc721(sellToken).transferFrom(msg.sender, custodian[sellToken], sellAmtOrId);
                asm.notifyTransferFrom(msg.sender, custodian[sellToken], sellAmtOrId);
            }
        }
    }
    
    /**
    * @dev Allow token to buy or to sell on exchange
    */
    function allowToken(address token_, bytes4 buySell_, bytes6 erc_, bool allowed_) public auth {
        require(
            buySell_ == "buy" ||
            buySell_ == "sell",
            "Invalid buy or sell");
        require(
            erc_ == "erc721" ||
            erc_ == "erc20",
            "Invalid token type");
        allowed = erc_ == "erc20" ? allowed20 : allowed721 
        allowed[buySell_][token_] = allowed_
        emit LogAllowedToken(token_, buySell_, allowed_);
    }

    /**
    * @dev Set configuration values for contract
    */
    function setValue(bytes32 kind, bytes32 value_, bytes32 value1_) public auth {
        if (kind == "custodian") {
            custodian[address(value_)] = address(value1_);

        } else if (kind == "profitRate") {
            profitRate = uint256(value_);
            require(profitRate <= 10 ** 18, "Profit rate out of range");

        } else if (kind == "rate") {
            address token = address(value_);
            uint256 value = uint256(value1_);
            require(
                allowed20["sell"][token] ||
                allowed20["buy"][token],
                "Token not allowed");
            require(value > 0, "Rate must be greater than 0");
            rate[token] = value;

        } else if (kind == "manualRate") {
            address token = address(value_);
            require(
                allowed20["sell"][token] ||
                allowed20["buy"][token],
                "Token not allowed");
            manualRate[token] = bool(value1_);

        } else if (kind == "priceFeed") {
            require(allowed20["sell"][address(value_)] || allowed20["buy"][address(value_)], "Token not allowed")
            require(address(value1_) != 0x0, "Wrong PriceFeed address");
            priceFeed[address(value_)] = TrustedFeedLike(address(value1_));

        } else if (kind == "takeAllFeeInDpt") {
            takeAllFeeInDpt = bool(value_);

        } else if (kind == "liq") {
            require(dpt.balanceOf(address(value_)) > 0, "Insufficient funds of DPT");
            liq = address(value_);

        } else if (kind == "asm") {
            require(address(value_) != 0x0, "Wrong address");
            asm = TrustedAssetManagement(address(value_));

        } else if (kind == "burner") {
            require(address(value_) != 0x0, "Wrong address");
            burner = address(value_);

        } else if (kind == "cdc") {
            require(address(value_) != 0x0, "Wrong address");
            cdc = TrustedDsToken(address(value_));

        } else if (kind == "custodian") {
            require(address(value_) != 0x0, "Wrong address");
            custodian[address(value_)] = address(value1_);

        } else if (kind == "fcc") {
            require(address(value_) != 0x0, "Wrong address");
            fcc = TrustedFeeCalculator(address(value_));

        } else if (kind == "fixFee") {
            fixFee = uint256(value_);

        } else if (kind == "varFee") {
            varFee = uint256(value_);

        } else if (kind == "decimals") {
            require(address(value_) != 0x0, "Wrong address");
            decimals[address(value_)] = uint8(value1_); 
            decimalsSet[address(value_)] = true;

        } else if (kind == "wal") {
            require(address(value_) != 0x0, "Wrong address");
            wal = address(value_);

        } else if (kind == "callGas") {
            callGas = uint256(value_);

        } else if (kind == "dust") {
            dust = uint256(value_);

        } else if (kind == "dpass") {
            require(address(value_) != 0x0, "Wrong address");
            dpass = TrustedErc721(address(value_));

        } else if (kind == "dpt") {
            require(address(value_) != 0x0, "Wrong address");
            dpt = TrustedDsToken(address(value_));

        } else {
            require(false, "No such option");
        }
        emit LogValueChange(kind, value_, value1_);
    }

    /**
    * @dev Retrieve the decimals of a token
    */
    function getDecimals(address token_) public returns uint8 {
        require(decimalsSet[token_], "Token with unset decimals");
        return decimals[token_];
    }

    /**
    * @dev Get total value of all tokens in base currency 
    */
    function getValue(
        TrustedErc20[] erc20Addr,
        uint256[] amt,
        TrustedErc721[] erc721Addr,
        uint256[] id,
        bytes4 buySell
    ) 
    public 
    view 
    returns (uint256) {
        return sellTokens(uint(-1), erc20Addr, amt, erc721Addr, id, buySell, false);
    }

    /**
    * @dev Adjusts a number to decimals
    */
    function toDecimals(uint256 amt, uint8 srcDec, uint8 dstDec) public view returns (uint256) {
        if (srcDec == dstDec) return amt;
        if (srcDec < dstDec) return mul(amt, 10 ** (dstDec - srcDec));
        return amt / 10 ** (srcDec - dstDec);
    }

    /**
    * @dev Ability to delegate fee calculating to external contract.
    * @return the fee amount in USD
    */
    function calculateFee(
        address sender,
        uint256 value,
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId, 
    ) public view returns (uint) {
        if (fcc == TrustedFeeCalculator(0)) {
            return fixFee + wmul(varFee, value);
        } else {
            return fcc.calculateFee(sender, value, sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        }
    }

    /**
    * @dev Get token_ / quote_currency rate from priceFeed 
    * Revert transaction if not valid feed and manual value not allowed
    */
    function getRate(address token_) public view returns (uint rate_) {
        bool feedValid;
        bytes32 usdRateBytes;
        require(priceFeed[token_] != TrustedMedianizerLike(0x), "No price feed for token");

        (usdRateBytes, feedValid) = priceFeed[token_].peek();          // receive DPT/USD price
        if (feedValid) {                                               // if feed is valid, load DPT/USD rate from it
            rate_ = uint(usdRateBytes);
        } else {
            require(manualRate[token_], "Manual rate not allowed");    // if feed invalid revert if manualEthRate is NOT allowed
            rate_ = rate[token];
        }
    }

    //
    // internal functions
    //
    /**
    * @dev Get exchange rate for a token
    */
    function updateRate(address token) internal auth returns (uint256 rate_) {
        rate_ = getRate(token)
        rate[token] = rate_
    }

    /**
    * @dev Taking fee from user. If user has DPT takes it, if there is none buys it for user.
    * @return the amount of remaining ETH after buying fee if it was required
    */
    function takeFee(
        uint fee,
        uint value,
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId, 
    ) 
    internal 
    returns(uint newValue, address token) {
        uint feeTaken;
        uint feeToken;
        uint amt;

        feeTaken = takeAllFeeInDpt ? fee : wmul(fee, profitRate);
        feeTaken = takeFeeInDptFromUser(feeTaken);
        
        if (fee - feeTaken > dust && fee - feeTaken < fee) { //if we could not take all fees from user DPT (with round-off errors considered)
            fee = sub(fee, feeTaken);

            if (allowed20["sell"][sellToken]) {
                token = sellToken;
                amt = sellAmtOrId;
            
            } else if (allowed20["buy"][buyToken]) {
                token = buyToken;
                amt = buyAmtOrId;
            
            } else {
                require(false, "No token to get fee from");

            }

            feeToken = wdiv(                                                // convert fee in base currency to token 
                            toDecimals(fee, 18, getDecimals(token)),
                            updateRate(token)
            );

            require(feeToken < amt, "Not enough token for fee"); 
            //TODO: handle profit 
            sendToken(token, msg.sender, wal, feeToken);
        }
        newValue = value - fee;
    }

    /**
    * @dev Take fee in DPT from user if it has any
    * @param feeDpt the fee amount in DPT
    * @return the remaining fee amount in DPT
    */
    function takeFeeInDptFromUser(uint256 fee) internal returns(uint256 feeTaken) {
        
        uint dptUser = min(
            dpt.balanceOf(msg.sender),
            dpt.allowance(msg.sender, this)
        );
        
        uint feeDpt = wdiv(
            toDecimals(fee, 18, getDecimals(dpt)),
            updateRate(dpt)
        );
        
        uint minDpt = min(feeDpt, dptUser);
        
        feeTaken = wmul( 
                        toDecimals(minDpt, getDecimals(dpt), 18),
                        rate[dpt]
        );

        if (minDpt > dust) {
            if (takeAllFeeInDpt) {
                dpt.transferFrom(user, burner, wmul(minDpt, profitRate));
                dpt.transferFrom(user, wal, wmul(minDpt, sub(1000000000000000000, profitRate)));
            } else {
                dpt.transferFrom(user, burner, minDpt); // only profit is put to the burner
            }
        }

    } 

    /**
    * @dev Take fee in DPT from user if it has any
    * @param feeDpt the fee amount in DPT
    * @return the remaining fee amount in DPT
    */
    function takeFeeFromUser(
        address user,
        TrustedErc20 token,
        uint maxAmount,
        uint feeToken,
        uint etherRemaining
    ) internal returns (uint remainingFee, uint etherSpent) {
        uint profitToken;
        uint profitDpt;

        uint tokenBalance = token == 0xee ? etherRemaining : token.balanceOf(user); 
        
        uint minToken = min(feeToken, tokenBalance); // calculate how much token user has to pay as fee
        minToken = min(minToken, maxAmount);
        
        remainingFee = sub(feeToken, minToken);
        profitToken = wmul(minToken, profitRate)

        if (minToken > 0) {
            etherSpent = sendToken(token, msg.sender, wal, minToken);
        }
        
        profitDpt = wdiv(
            wmul(
                toDecimals(profitToken, getDecimals(token), decimals[dpt]),
                updateRate(token)
                ),
            updateRate(dpt)
        );
        
        if (profitDpt > 0) 
            dpt.transferFrom(liq, burner, profitDpt); // DPT transfer to burner 
    }

    /**
    * &dev send token or ether to destination
    */
    function sendToken(TrustedErc20 token, address src, address dst, uint256 amount) internal returns(uint256 etherSpent) {
        if (token == 0xee) {

            require(dst.call.value(amount).gas(callGas),
                    "Ether could not be sent");

            etherSpent = amount;
        } else {
            token.transferFrom(src, dst, amount); // transfer all of token to wallet
        }
    }
}
