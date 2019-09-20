pragma solidity ^0.5.10;

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


contract TrustedDSAuthority is DSAuthority {
    function stub() external;
}


/**
* @dev Contract to calculate user fee based on amount
*/
contract TrustedFeeCalculator {
    function calculateFee(
        address sender,
        uint256 value,
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) external view returns (uint);
}


contract TrustedDsToken {
    function transferFrom(address src, address dst, uint wad) external returns (bool);
    function totalSupply() external view returns (uint);
    function balanceOf(address src) external view returns (uint);
    function allowance(address src, address guy) external view returns (uint); 
}


contract TrustedAssetManagement {
    function notifyTransferFrom(TrustedErc721 erc721, address src, address dst, uint256 id721) external;
    function getPrice(TrustedErc721 erc721, uint256 id721) external view returns(uint256);
}


contract TrustedErc721 {
    function transferFrom(address src, address to, uint256 amt) external;    
}


contract TrustedErc20 {
    function transferFrom(address src, address dst, uint wad) external returns (bool);
    function totalSupply() external view returns (uint);
    function balanceOf(address src) external view returns (uint);
    function allowance(address src, address guy) external view returns (uint); 
}


/**
 * @title Cdc
 * @dev Cdc Exchange contract.
 */
contract CdcExchangeEvents {
    event LogBuyTokenWithFee(
        uint256 indexed txId,
        address indexed sender,
        address custodian,
        address sellToken,
        address buyToken,
        uint256 value,
        uint256 fee,
        uint256 priceOrRate
    );

    event LogAllowedToken(address indexed token, bytes4 buy, bool allowed); 
    event LogValueChange(bytes32 indexed what, bytes32 value, bytes32 value1); 
}


contract CdcExchange is DSAuth, DSStop, DSMath, CdcExchangeEvents {
    TrustedDsToken public cdc;                              // CDC token contract
    address public dpt;                                     // DPT token contract
    TrustedErc721 public dpass;                             // DPASS default token address

    mapping(address => uint256) private rate;               // exchange rate for a token
    mapping(address => bool) public manualRate;             // manualRate is allowed for a token (if feed invalid)
    mapping(address => TrustedFeedLike) public priceFeed;   // price feed address for token  
    mapping(bytes4 => mapping(address => bool)) public allow20; // stores allowed ERC20 tokens to sell and buy 
    mapping(bytes4 => mapping(address => bool)) public allow721;// stores allowed ERC721 tokens to sell and buy 
    mapping(address => uint8) public decimals;                  // stores decimals for each ERC20 token
    mapping(address => bool) public decimalsSet;                // stores if decimals were set for ERC20 token 
    mapping(address => address) public custodian;               // custodian that holds a token

    TrustedFeeCalculator public fcc;        // fee calculator contract

    address public liq;                     // contract providing DPT liquidity to pay for fee
    address public wal;                     // wallet address, where we keep all the tokens we received as fee
    address public burner;                  // contract where accured fee of DPT is stored before being burned
    TrustedAssetManagement public asm;      // Asset Management contract
    uint256 public fixFee;                  // Fixed part of fee charged for buying 18 decimals precision in base currency
    uint256 public varFee;                  // Variable part of fee charged for buying 18 decimals precision in base currency
    uint256 public profitRate;              // the percentage of profit that is burned on all fees received. 18 decimals precision
    uint256 public callGas = 2500;           // using this much gas when Ether is transferred
    uint256 public txId;                    // Unique id of each transaction.
    bool public takeProfitOnlyInDpt;        // If true, it takes cost + profit in DPT, if false only profit in DPT
    uint256 public dust = 2;                // dust amount. Numbers below this amount are considered 0.

    constructor(
        address cdc_,
        address dpt_,
        address dpass_,
        address ethPriceFeed_,
        address dptPriceFeed_,
        address cdcPriceFeed_,
        address liq_,
        address burner_,
        address asm_,
        uint fixFee_,
        uint varFee_,
        uint profitRate_,
        address wal_
    ) public {

    // default exchage rates must be set manually as constructor can not set more variables
        
        allowToken(cdc_, "sell", "erc20", true);
        allowToken(cdc_, "buy", "erc20", true);
        allowToken(dpt_, "sell", "erc20", true);
        allowToken(dpt_, "buy", "erc20", true);
        allowToken(dpass_, "buy", "erc721", true);

        setConfig("decimals", cdc_, 18);
        setConfig("decimals", dpt_, 18);
        setConfig("decimals", 0xee, 18);
        setConfig("cdc", cdc_, "");
        setConfig("dpt", dpt_, "");
        setConfig("dpass", dpass_, "");
        setConfig("priceFeed", 0xee, ethPriceFeed_);
        setConfig("priceFeed", dpt_, dptPriceFeed_);
        setConfig("priceFeed", cdc_, cdcPriceFeed_);
        setConfig("liq", liq_, "");
        setConfig("burner", burner_, "");
        setConfig("asm", asm_, "");
        setConfig("fixFee", fixFee_, "");
        setConfig("varFee", varFee_, "");
        setConfig("profitRate", profitRate_, "");
        setConfig("wal", wal_, "");
    }

    /**
    * @dev Fallback function to buy tokens.
    */
    function () external payable {
        buyTokensWithFee(address(0xee), msg.value, address(cdc), uint(-1));
    }

    /**
    * @dev Тoken purchase with fee. (If user has DPT he must approve this contract,
    * otherwise transaction will fail.)
    */
    function buyTokensWithFee (
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) public payable stoppable {
        address feeTakenFrom;
        uint valueBuy;
        uint valueSell;
        uint fee;
        
        updateRates(sellToken, buyToken);

        (valueBuy, valueSell) = getValues(sellToken, sellAmtOrId, buyToken, buyAmtOrId); 

        require(valueBuy - dust <= valueSell, "Not enough funds");

        fee = calculateFee(msg.sender, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        
        if (fee > 0) {
            (valueSell, valueBuy, feeTakenFrom) = 
                takeFee(fee, valueSell, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        }

        sellTokens(valueSell, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);

        txId++;
        
        emit LogBuyTokenWithFee(txId, msg.sender, custodian[buyToken], sellToken, buyToken, valueSell, fee, valueBuy);
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
        if (erc_ == "erc20") {
            allow20[buySell_][token_] = allowed_;
        } else {
            allow721[buySell_][token_] = allowed_;
        }
        emit LogAllowedToken(token_, buySell_, allowed_);
    }

    function setConfig(bytes32 what, address value_, address value1_) public auth { setConfig(what, b32(value_), b32(value1_)); }
    function setConfig(bytes32 what, address value_, bytes32 value1_) public auth { setConfig(what, b32(value_), value1_); }
    function setConfig(bytes32 what, address value_, uint256 value1_) public auth { setConfig(what, b32(value_), b32(value1_)); }
    function setConfig(bytes32 what, uint256 value_, address value1_) public auth { setConfig(what, b32(value_), b32(value1_)); }
    function setConfig(bytes32 what, uint256 value_, bytes32 value1_) public auth { setConfig(what, b32(value_), value1_); }
    function setConfig(bytes32 what, uint256 value_, uint256 value1_) public auth { setConfig(what, b32(value_), b32(value1_)); }

    /**
    * @dev Set configuration values for contract
    */
    function setConfig(bytes32 what, bytes32 value_, bytes32 value1_) public auth {
        if (what == "custodian") {
            custodian[addr(value_)] = addr(value1_);

        } else if (what == "profitRate") {
            profitRate = uint256(value_);
            require(profitRate <= 10 ** 18, "Profit rate out of range");

        } else if (what == "rate") {
            address token = addr(value_);
            uint256 value = uint256(value1_);
            require(
                allow20["sell"][token] ||
                allow20["buy"][token],
                "Token not allowed");
            require(value > 0, "Rate must be greater than 0");
            rate[token] = value;

        } else if (what == "manualRate") {
            address token = addr(value_);
            require(
                allow20["sell"][token] ||
                allow20["buy"][token],
                "Token not allowed");
            manualRate[token] = uint256(value1_) > 0;

        } else if (what == "priceFeed") {
            require(allow20["sell"][addr(value_)] || allow20["buy"][addr(value_)], "Token not allowed");
            require(addr(value1_) != address(address(0x0)), "Wrong PriceFeed address");
            priceFeed[addr(value_)] = TrustedFeedLike(addr(value1_));

        } else if (what == "takeProfitOnlyInDpt") {
            takeProfitOnlyInDpt = uint256(value_) > 0;

        } else if (what == "liq") {
            liq = addr(value_);
            require(TrustedErc20(dpt).balanceOf(liq) > 0, "Insufficient funds of DPT");

        } else if (what == "asm") {
            require(addr(value_) != address(0x0), "Wrong address");
            asm = TrustedAssetManagement(addr(value_));

        } else if (what == "burner") {
            require(addr(value_) != address(0x0), "Wrong address");
            burner = addr(value_);

        } else if (what == "cdc") {
            require(addr(value_) != address(0x0), "Wrong address");
            cdc = TrustedDsToken(addr(value_));

        } else if (what == "custodian") {
            require(addr(value_) != address(0x0), "Wrong address");
            custodian[addr(value_)] = addr(value1_);

        } else if (what == "fcc") {
            require(addr(value_) != address(0x0), "Wrong address");
            fcc = TrustedFeeCalculator(addr(value_));

        } else if (what == "fixFee") {
            fixFee = uint256(value_);

        } else if (what == "varFee") {
            varFee = uint256(value_);

        } else if (what == "decimals") {
            require(addr(value_) != address(0x0), "Wrong address");
            decimals[addr(value_)] = uint8(uint256(value1_)); 
            decimalsSet[addr(value_)] = true;

        } else if (what == "wal") {
            require(addr(value_) != address(0x0), "Wrong address");
            wal = addr(value_);

        } else if (what == "callGas") {
            callGas = uint256(value_);

        } else if (what == "dust") {
            dust = uint256(value_);

        } else if (what == "dpass") {
            require(addr(value_) != address(0x0), "Wrong address");
            dpass = TrustedErc721(addr(value_));

        } else if (what == "dpt") {
            require(addr(value_) != address(0x0), "Wrong address");
            dpt = addr(value_);

        } else if (what == "owner") {
            require(addr(value_) != address(0x0), "Wrong address");
            setOwner(addr(value_));

        } else if (what == "authority") {
            require(addr(value_) != address(0x0), "Wrong address");
            setAuthority(TrustedDSAuthority(addr(value_)));

        } else {
            require(false, "No such option");
        }
        emit LogValueChange(what, value_, value1_);
    }

    /**
    * @dev Convert address to bytes32
    * @param a address that is converted to bytes32
    * @return bytes32 conversion of address
    */
    function b32(address a) public pure returns (bytes32) {
        return bytes32(uint256(a) << 96);
    }

    /**
    * @dev Convert uint256 to bytes32
    * @param a uint value to be converted
    * @return bytes32 converted value
    */
    function b32(uint a) public pure returns (bytes32) {
        return bytes32(a);
    }

    /**
    * @dev Convert address to bytes32
    */
    function addr(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }

    /**
    * @dev Retrieve the decimals of a token
    */
    function getDecimals(address token_) public view returns (uint8) {
        require(decimalsSet[token_], "Token with unset decimals");
        return decimals[token_];
    }

    /**
    * @dev Adjusts a number to decimals
    */
    function toDecimals(uint256 amt, uint8 srcDec, uint8 dstDec) public pure returns (uint256) {
        if (srcDec == dstDec) return amt;
        if (srcDec < dstDec) return mul(amt, 10 ** uint256(dstDec - srcDec));
        return amt / 10 ** uint256(srcDec - dstDec);
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
        uint256 buyAmtOrId
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
        require(TrustedFeedLike(address(0x0)) != priceFeed[token_], "No price feed for token");

        (usdRateBytes, feedValid) = priceFeed[token_].peek();          // receive DPT/USD price
        if (feedValid) {                                               // if feed is valid, load DPT/USD rate from it
            rate_ = uint(usdRateBytes);
        } else {
            require(manualRate[token_], "Manual rate not allowed");    // if feed invalid revert if manualEthRate is NOT allowed
            rate_ = rate[token_];
        }
    }

    //
    // internal functions
    //

    function updateRates(address sellToken, address buyToken) internal {
        if (allow20["sell"][sellToken]) updateRate(sellToken);
        if (allow20["buy"][buyToken]) updateRate(buyToken);
        updateRate(dpt);
    }

    /**
    * @dev Get sell and buy token values in base currency
    */
    function getValues(
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) internal returns (uint256 valueBuy, uint256 valueSell) {
        TrustedErc20 buyToken20;
        TrustedErc20 sellToken20;
        TrustedErc721 buyToken721;
        TrustedErc721 sellToken721;
        uint buyAmt = buyAmtOrId;
        uint sellAmt = sellAmtOrId;

        if (allow20["sell"][sellToken]) {
            sellToken20 = TrustedErc20(sellToken);

            require(
                sellToken == address(0xee) ||
                sellAmtOrId == uint(-1) ||
                sellAmtOrId <= min(
                    sellToken20.balanceOf(address(msg.sender)),
                    sellToken20.allowance(msg.sender, address(this))),
                "Sell amount exceeds allowance");

            require(
                sellToken != address(0xee) ||
                sellAmtOrId == uint(-1) ||
                sellAmtOrId <= msg.value,
                "Sell amount exceeds Ether value");
            
            if (sellAmt == uint(-1)) {
                sellAmt = min(
                    sellToken20.balanceOf(msg.sender), 
                    sellToken20.allowance(msg.sender, address(this)));
            }
            valueSell = wmul(
                toDecimals(sellAmt, getDecimals(sellToken), 18), 
                rate[sellToken]);
                
        } else if (allow721["sell"][sellToken]) {

            sellToken721 = TrustedErc721(sellToken);
            valueSell = asm.getPrice(TrustedErc721(buyToken), buyAmtOrId);

        } else {

            require(false, "Token not allowed to be sold");

        }

        if (allow20["buy"][buyToken]) {
            buyToken20 = TrustedErc20(buyToken);
            require(
                buyToken == address(0xee) ||
                buyAmtOrId == uint(-1) ||
                buyAmtOrId <= min(
                    buyToken20.balanceOf(msg.sender), 
                    buyToken20.allowance(msg.sender, address(this))),
                "Buy amount exceeds allowance");
            require(buyToken != address(0xee) || buyAmtOrId == uint(-1) || buyAmtOrId <= msg.value, "Buy amount exceeds Ether value");
            if (buyAmtOrId == uint(-1)) {
                buyAmt = min(buyToken20.balanceOf(custodian[buyToken]), buyToken20.allowance(custodian[buyToken], address(this)));
                if (allow20["sell"][sellToken] && sellAmtOrId == uint(-1)) {
                    buyAmt = min(
                        wdiv(toDecimals(valueSell, 18, getDecimals(buyToken)), rate[buyToken]),
                        buyAmt
                    );
                }
            }
            valueBuy = wmul(toDecimals(buyAmt, getDecimals(buyToken), 18), rate[buyToken]);
        } else if (allow721["buy"][buyToken]) {
            require(allow20["sell"][sellToken], "One of tokens must be erc20");
            buyToken721 = TrustedErc721(buyToken);
            valueBuy = asm.getPrice(TrustedErc721(buyToken), buyAmtOrId);
        } else {
            require(false, "Token not allowed to be bought");
        }
    }

    /**
    * @dev Sell tokens of user
    */
    function sellTokens(
        uint256 valueSell,          //sell value after fee was subtracted
        uint256 valueBuy,           //buy value after fee was subtracted
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) internal {
        uint sellValueToken;
        uint buyValueToken;

        sellValueToken = wdiv(
            toDecimals(valueSell, 18, getDecimals(sellToken)),
            rate[sellToken]
        );

        buyValueToken = wdiv(
            toDecimals(valueBuy, 18, getDecimals(buyToken)),
            rate[buyToken]
        );

        if (allow20["sell"][sellToken]) {

            sendToken(sellToken, msg.sender, custodian[sellToken], sellValueToken);

        }  else {
            
            TrustedErc721(sellToken).transferFrom(msg.sender, custodian[sellToken], sellAmtOrId);
            asm.notifyTransferFrom(TrustedErc721(sellToken), msg.sender, custodian[sellToken], sellAmtOrId);
        }

        if (allow20["buy"][buyToken]) {
            
            sendToken(buyToken, custodian[buyToken], msg.sender, buyValueToken);
        
        }  else {
        
            TrustedErc721(buyToken).transferFrom(custodian[buyToken], msg.sender, buyAmtOrId);
            asm.notifyTransferFrom(TrustedErc721(buyToken), custodian[buyToken], msg.sender, buyAmtOrId);
        }
    }
    /**
    * @dev Get exchange rate for a token
    */
    function updateRate(address token) internal returns (uint256 rate_) {
        rate_ = getRate(token);
        rate[token] = rate_;
    }

    /**
    * @dev Taking fee from user. If user has DPT takes it, if there is none buys it for user.
    * @return the amount of remaining ETH after buying fee if it was required
    */
    function takeFee(
        uint256 fee,
        uint256 valueSell,
        uint256 valueBuy,
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) 
    internal 
    returns(uint256, uint256, address ) {
        uint feeTaken;
        uint amt;
        address token;

        feeTaken = takeProfitOnlyInDpt ? wmul(fee, profitRate) : fee; 
        feeTaken = takeFeeInDptFromUser(feeTaken);
        
        if (fee - feeTaken > dust && fee - feeTaken < fee) { //if we could not take all fees from user DPT (with round-off errors considered)
            fee = sub(fee, feeTaken);

            if (allow20["sell"][sellToken]) {

                require(
                    allow20["buy"][buyToken] ||
                    valueSell + dust >= valueBuy + fee,
                    "Not enough sell tokens");

                token = sellToken;
                amt = sellAmtOrId;

                if (valueSell + dust >= valueBuy + fee) {
                
                    valueSell = valueBuy;
                
                } else {
                    
                    valueBuy = sub(valueSell, fee);
                    valueSell = sub(valueSell, fee); 
                }

            } else if (allow20["buy"][buyToken]) {
                
                require(
                    allow20["sell"][sellToken] ||
                    valueSell <= valueBuy + fee + dust,
                    "Not enough tokens to buy");

                require(!allow721["sell"][sellToken], "Both tokens can not be erc721");

                token = buyToken;
                amt = buyAmtOrId;

                if (valueSell <= valueBuy + fee + dust) 
                    valueBuy = sub(valueSell, fee); 

            } else {
                
                require(false, "No token to get fee from");

            }

            sendProfitAndCost(fee, feeTaken, token, amt);
        }

        return (valueSell, valueBuy, token);
    }

    /**
    * @dev Calculate and send profit and cost
    */
    function sendProfitAndCost(
        uint256 fee,
        uint256 feeTaken,
        address token,
        uint256 amountToken
    ) internal {
        uint profitValue;
        uint profitToken;
        uint costToken;

        profitValue = sub(                                      // profit value still to be paid 

            wmul(fee + feeTaken, profitRate),                   // total profit due

            takeProfitOnlyInDpt ?                               // profit payed already
                feeTaken :
                wmul(feeTaken, profitRate)
        );

        profitToken = wdiv(
            toDecimals(profitValue, 18, getDecimals(dpt)),
            rate[dpt]
        );

        sendToken(dpt, liq, burner, profitToken);

        costToken = wdiv(                                                // convert fee from base currency to token 
            toDecimals(fee, 18, getDecimals(token)),
            rate[token]
        );

        require(costToken < amountToken, "Not enough token to pay fee"); 

        sendToken(address(token), msg.sender, wal, costToken);
}
    /**
    * @dev Take fee in DPT from user if it has any
    * @param fee the fee amount in base currency
    * @return the remaining fee amount in DPT
    */
    function takeFeeInDptFromUser(uint256 fee) internal returns(uint256 feeTaken) {
        TrustedErc20 dpt20 = TrustedErc20(dpt); 

        uint dptUser = min(
            dpt20.balanceOf(msg.sender),
            dpt20.allowance(msg.sender, address(this))
        );
        
        uint feeDpt = wdiv(
            toDecimals(fee, 18, getDecimals(dpt)),
            rate[dpt]
        );
        
        uint minDpt = min(feeDpt, dptUser);
        
        feeTaken = wmul( 
                        toDecimals(minDpt, getDecimals(dpt), 18),
                        rate[dpt]
        );

        if (minDpt > dust) {
            if (takeProfitOnlyInDpt) {
                sendToken(dpt, msg.sender, burner, minDpt); // only profit is put to the burner
            } else {
                sendToken(dpt, msg.sender, burner, wmul(minDpt, profitRate));
                sendToken(dpt, msg.sender, wal, wmul(minDpt, sub(1000000000000000000, profitRate)));
            }
        }

    } 

    /**
    * &dev send token or ether to destination
    */
    function sendToken(address token, address src, address dst, uint256 amount) internal returns(uint256 etherSpent) {
        TrustedErc20 erc20 = TrustedErc20(token);

        if (token == address(0xee) && amount > dust) {

            dst.call.value(amount).gas(callGas);

            etherSpent = amount;
        } else {

            if (amount > dust) erc20.transferFrom(src, dst, amount); // transfer all of token to wallet
        }
    }
}
