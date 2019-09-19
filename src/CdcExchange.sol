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
        address owner,
        address sender,
        uint ethValue,
        uint cdcValue,
        uint rate,
        uint fee
    );

    event LogAllowedToken(indexed address token, bytes4 buy, bool allowed); // TODO: DONE
    event LogBuyDptFee(address sender, uint ethValue, uint ethUsdRate, uint dptUsdRate, uint fee);
    event LogValueChange(indexed bytes32 kind, bytes32 value, bytes32 value1);
    event LogSetDecimals(address token_, uint8 decimals_);
    event LogSetPriceFeed(indexed address token, address priceFeed); // TODO: DONE
    event LogSetFee(uint fee);
    event LogSetManualRate(indexed address token, bool manualRate); // TODO: DONE
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
    uint256 public profitPercent;           //the percentage of profit that is burned on all fees received. 18 decimals precision
    uint256 public callGas;                 //using this much gas when Ether is transferred
    uint256 public dust = 9;                //dust amount. Numbers below this amount are considered 0.

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
        uint profitPercent_,
        address wal_,
        uint256 callGas_
    ) public {

        allowToken(cdc_, "sell", "erc20", true)
        allowToken(cdc_, "buy", "erc20", true)
        allowToken(dpt_, "sell", "erc20", true)
        allowToken(dpt_, "buy", "erc20", true)
        allowToken(dpass_, "buy", "erc721", true)

        setDecimals(cdc_, 18)
        setDecimals(dpt_, 18)
        setDecimals(0xee, 18)

        cdc = TrustedDsToken(cdc_);
        dpt = TrustedDsToken(dpt_);
        dpass = TrustedErc721Token(dpass_);
        priceFeed[0xee] = TrustedFeedLike(ethPriceFeed_);
        priceFeed[dpt_] = TrustedFeedLike(dptPriceFeed_);
        priceFeed[cdc_] = TrustedFeedLike(cdcPriceFeed_);
        liq = liq_;
        burner = burner_;
        asm = asm_;
        rate[dpt_] = dptExchange_;
        rate[cdc_] = cdcExchangeRate_;
        rate[0xee] = ethExchangeRate_;
        fixFee = fixFee_;
        varFee = varFee_;
        profitPercent = profitPercent_;
        wal = wal_;
        callGas = callGas_;
    }

    /**
    * @dev Fallback function to buy tokens.
    */
    function () external payable {
        buyTokensWithFee([0xee], [msg.value], [], [], [cdc], [0], [], []);
    }

    /**
    * @dev Тoken purchase with fee. (If user has DPT he must approve this contract,
    * otherwise transaction will fail.)
    */
    function buyTokensWithFee (
        TrustedErc20[] sellErc20Addr, 
        uint256[] sellAmt, 
        TrustedErc721[] sellErc721Addr, 
        uint256[] sellId, 
        TrustedDsToken[] buyErc20Addr,
        uint256[] buyAmt, 
        TrustedErc721[] buyErc721Addr,
        TrustedId[] buyId
    ) public payable stoppable returns (uint tokens) {
        uint remainingFee;

        uint sellValue = getValue(sellErc20Addr, sellAmt, sellErc721Addr, sellId, "sell");
        uint buyValue  = getValue(buyErc20Addr, buyAmt, buyErc721Addr, buyId, "buy");
        
        uint fee = calculateFee(msg.sender, sellValue, buyValue,    // Calculate fee in base currency
            sellErc20Addr, sellAmt, sellErc721Addr, sellId,
            buyErc20Addr, buyAmt, buyErc721Addr, buyId);               

        require(sub(sellValue, fee) >= buyValue, "Not enough funds to buy tokens"); 
        sellValue = sub(sellValue, fee);

        remainingFee = takeFee(fee, sellErc20Addr, sellAmt); // take fee and return remaining amount to buy tokens 

        sellValue = buyTokens(sellValue, remainingFee, buyErc20Addr, buyAmt, buyErc721Addr, buyId); // send CDC to user
        
        sellTokens(sellValue, sellErc20Addr, sellAmt, sellErc721Addr, sellId);

        //TODO: update following Log
        emit LogBuyTokenWithFee(owner, msg.sender, msg.value, tokens, cdcUsdRate, fee);
        return tokens;
    }

    /**
    * @dev Sell tokens of user
    */
    function sellTokens(
        uint256 sellValue,
        TrustedErc20[] erc20Addr, 
        uint256[] amt, 
        TrustedErc721[] erc721Addr, 
        uint256[] id,
        bytes4 buySell,
        bool sellTokens
    ) internal returns (uint256 totalValue) {
        uint amountToken;
        uint8 srcDec;
        uint remaining = sellValue;
        mapping(address => bool) tokenUsed;
        uint id721;
        TrustedErc721 erc721;
        TrustedErc20 erc20;
        uint price;
        uint value;

        require(erc20Addr.length == amt.length, "ERC20 token count invalid");
        require(erc721Addr.length == id.length, "ERC721 token count invalid");


        for (uint idx = 0; idx < erc721Addr.length; idx++) {
            erc721 = erc721Addr[idx];
            id721 = id[idx];
            price = asm.getPrice(erc721, id721);
            require(!tokenUsed[erc721], "Token listed more than once");
            tokenUsed[erc721] = true;
            
            require(allowed721[buySell][erc721], "ERC721 token not allowed");
            require(
                buySell == "buy" ||
                erc721.getApproved(id721) == this ||
                erc721.ownerOf(id721) == this ||
                erc721.isApprovedForAll(erc721.ownerOf(id721), this)
                , "ERC721 not approved");


            totalValue = add(totalValue, price);

            if (buySell == "sell" && sellTokens) {
                if (price > remaining) continue;
                remaining = sub(remaining, price);
                erc721.transferFrom(msg.sender, custodian[token], id721);
            }
            
        }

        for (uint idx = 0; idx < erc20Addr.length && remaining > dust; idx++) {
            erc20 = erc20Addr[idx];
            amountToken = amt[idx];
            srcDec = getDecimals(erc20);

            if (amountToken == 0 && buySell == "sell") {       //if sell amountToken 0, sell the total available 
                amountToken = min(
                    erc20.allowance(msg.sender, this),
                    erc20.balanceOf(msg.sender)
                );
            }

            amountToken = min( 
                        amountToken,
                        wdiv(toDecimals(remaining, 18, srcDec), updateRate(erc20))
                        );

            require(allowed20[buySell][erc20], "ERC20 token not allowed");
            require(buySell == "buy" || erc20.allowance(msg.sender, this) >= amountToken, "Amount not approved");
            require(!tokenUsed[erc20], "Token listed more than once");

            tokenUsed[erc20] = true;

            value = wmul(          
                        updateRate(erc20),                      // get exchange rate 
                        toDecimals(amountToken, srcDec, 18)
                        );

            if (buySell == "sell" && sellTokens) {
                sendToken(erc20, msg.sender, wal, amountToken);
                remaining = sub(remaining, value);
            }
            
            totalValue = add(totalValue, value); 
        }
    }
    
    /**
    * @dev Allow token to buy or to sell
    */
    function allowToken(address token_, bytes4 buySell_, bytes6 erc, bool allowed_) public auth {
        require(
            buySell_ == "buy" ||
            buySell == "sell",
            "Invalid buy or sell");
        require(
            erc == "erc721" ||
            erc == "erc20",
            "Invalid token type");
        allowed = erc == "erc20" ? allowed20 : allowed721 
        allowed[buySell_][token_] = allowed_
        emit LogAllowedToken(token_, buySell_, allowed_);
    }

    /**
    * @dev Set the decimal places for token
    */
    function setDecimals(address token_, uint8 decimals_) public auth {
        decimals[token_] = decimals_; 
        decimalsSet[token_] = true;
        emit LogSetDecimals(token_, decimals_);
    }

    /**
    * @dev Set configuration values for contract
    */
    function setValue(bytes32 kind, bytes32 value_, bytes32 value1_) public auth {
        require(address(value_) != 0x0, "Wrong address");
        if (kind == "profitPercent") {
            profitPercent = uint256(value_);

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

        } else if (kind == "liquidity") {
            require(dpt.balanceOf(address(value_)) > 0, "Insufficient funds of DPT");
            liq = address(value_);

        } else if (kind == "asm") {
            asm = TrustedAssetManagement(address(value_));

        } else if (kind == "burner") {
            burner = address(value_);

        } else if (kind == "cdc") {
            cdc = TrustedDsToken(address(value_));

        } else if (kind == "custodian") {
            custodian[address(value_)] = address(value1_);

        } else if (kind == "fcc") {
            require(address(value_) != 0x0, "Wrong address");
            fcc = TrustedFeeCalculator(address(value_));

        } else if (kind == "fixFee") {
            fixFee = uint256(value_);

        } else if (kind == "varFee") {
            varFee = uint256(value_);

        } else if (kind == "decimals") {
            decimals[address(value_)] = uint8(value1_); 
            decimalsSet[address(value_)] = true;

        } else if (kind == "wal") {
            wal = address(value_);

        } else if (kind == "callGas") {
            callGas = uint256(value_);

        } else if (kind == "dust") {
            dust = uint256(value_);

        } else if (kind == "dpass") {
            dpass = TrustedErc721(address(value_));

        } else if (kind == "dpt") {
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
        uint256 sellValue,
        uint256 buyValue,
        TrustedErc20[] sellErc20Addr, 
        uint256[] sellAmt, 
        TrustedErc721[] sellErc721Addr, 
        uint256[] sellId, 
        TrustedDsToken[] buyErc20Addr,
        uint256[] buyAmt, 
        TrustedErc721[] buyErc721Addr,
        TrustedId[] buyId
    ) public view returns (uint) {
        if (fcc == TrustedFeeCalculator(0)) {
            return fixFee + wmul(varFee, sellValue);
        } else {
            return fcc.calculateFee(sender, sellValue, buyValue,
                                    sellErc20Addr, sellAmt, sellErc721Addr, sellId, 
                                    buyErc20Addr, buyAmt, buyErc721Addr, buyId);
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
        TrustedErc20[] sellErc20Addr, 
        uint256[] sellAmt,
    ) 
    internal 
    returns(uint remaining) {
        uint feeToken;
        uint sellAmount;
        remaining = fee;
        uint remainingToken;
        uint etherSpent;
        uint etherRemaining = msg.value;
        TrustedErc20 token;

        for (uint idx = 0; idx < sellErc20Addr.length && remaining > dust; idx++) {
            token = sellErc20Addr[idx];
            sellAmount = sellAmt[idx];

            feeToken = wdiv(
                toDecimals(fee, 18, getDecimals(token)),
                updateRate(token)
            );
            
            (remainingToken, etherSpent) = 
                takeFeeFromUser(msg.sender, token, sellAmount, feeToken, etherRemaining);

            etherRemaining = sub(etherRemaining, etherSpent);           //make sure we spend max msg.value amount of ether

            remaining = wmul(
                toDecimals(remainingToken, decimals[token], 18),
                rate[token]
            );
        }
        return remaining; 
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
        profitToken = wmul(minToken, profitPercent)

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

    /**
    * @dev Calculate and transfer CDC tokens to user. Transfer ETH to owner for CDC
    * @return sold token amount
    */
    function buyTokens(
        uint256  sellValue,
        uint256 remainingFee,
        TrustedDsToken[] buyErc20Addr,
        uint256[] buyAmt, 
        TrustedErc721[] buyErc721Addr,
        TrustedId[] buyId
    ) internal returns (uint sellValueNew) {
        uint256 remainingFeeToken;
        uint256 remainingSellValue = sellValue;
        uint256 remainingSellValueToken;
        uint256 amt;
        address cus;
        uint8 decToken;
        uint id721;
        TrustedErc721 erc721; 
        TrustedDsToken token;

        for (uint idx = 0; idx < buyErc721Addr.length && remainingSellValue > dust; idx++) {
            erc721 = buyErc721Addr[idx];
            id721 = buyId[idx];
            cus = custodian[id721];
            asm.notifyTransferFrom(erc721, cus, msg.sender, id721);
            erc721.transferFrom(cus, msg.sender, id721);
            remainingSellValue = sub(remainingSellValue, asm.getPrice(erc721, id721));
        }

        for (uint idx = 0; idx < buyErc20Addr.length && remainingSellValue > dust; idx++) {
            token = buyErc20Addr[idx];
            amt = buyAmt[idx];
            cus = custodian[token];
            decToken = getDecimals(token);

            remainingSellValueToken = wdiv(
                toDecimals(remainingSellValue, 18, decToken),
                updateRate(token)
            );
            
            if (amt == 0) {
                amt = remainingSellValueToken;
            }                
            
            amt = min(amt, remainingSellValueToken);
            remainingSellValue = sub(
                remainingSellValue,
                wmul(
                    toDecimals(amt, decToken, 18),
                    rate[token]
                    )
            );
            
            sendToken(token, cus, msg.sender, amt);

            if (remainingFee > dust && token != 0xee) {
                
                remainingFeeToken = wdiv(
                    toDecimals(remainingFee, 18, decToken),
                    rate[token]
                );
                
                remainingFeeToken = min(
                                        min(
                                            remainingFeeToken,
                                            token.balanceOf(cus)
                                        ),
                                        token.allowance(cus, this)
                );

                sendToken(token, cus, wal, remainingFeeToken); 

                remainingFee = sub(remainingFee, toDec(wmul(remainingFeeToken, rate[token]), decToken, 18));
            }
        }
        require(remainingFee < dust, "Could not withdraw fee");
        sellValueNew = sub(sellValue, remainingSellValue);
    }
}
