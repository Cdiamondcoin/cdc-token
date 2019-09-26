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
    function balanceOf(TrustedErc20 token, 
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

    event LogConfigChange(bytes32 indexed what, bytes32 value, bytes32 value1); 
}


contract CdcExchange is DSAuth, DSStop, DSMath, CdcExchangeEvents {
    TrustedDsToken public cdc;                              // CDC token contract
    address public dpt;                                     // DPT token contract
    TrustedErc721 public dpass;                             // DPASS default token address

    mapping(address => uint256) private rate;               // exchange rate for a token
    mapping(address => bool) public manualRate;             // manualRate is allowed for a token (if feed invalid)
    mapping(address => TrustedFeedLike) public priceFeed;   // price feed address for token  
    mapping(address => bool) public canBuyErc20;            // stores allowed ERC20 tokens to buy 
    mapping(address => bool) public canSellErc20;           // stores allowed ERC20 tokens to sell
    mapping(address => bool) public canBuyErc721;           // stores allowed ERC20 tokens to buy 
    mapping(address => bool) public canSellErc721;          // stores allowed ERC20 tokens to sell
    mapping(address => uint8) public decimals;              // stores decimals for each ERC20 token
    mapping(address => bool) public decimalsSet;            // stores if decimals were set for ERC20 token 
    mapping(address => address) public custodian;           // custodian that holds a token

    TrustedFeeCalculator public fcc;        // fee calculator contract

    address public liq;                     // contract providing DPT liquidity to pay for fee
    address public wal;                     // wallet address, where we keep all the tokens we received as fee
    address public burner;                  // contract where accured fee of DPT is stored before being burned
    TrustedAssetManagement public asm;      // Asset Management contract
    uint256 public fixFee;                  // Fixed part of fee charged for buying 18 decimals precision in base currency
    uint256 public varFee;                  // Variable part of fee charged for buying 18 decimals precision in base currency
    uint256 public profitRate;              // the percentage of profit that is burned on all fees received. 18 decimals precision
    uint256 public callGas = 2500;          // using this much gas when Ether is transferred
    uint256 public txId;                    // Unique id of each transaction.
    bool public takeProfitOnlyInDpt = true; // If true, it takes cost + profit in DPT, if false only profit in DPT
    uint256 public dust = 10000;            // Numbers below this amount are considered 0. Can only be used 
                                            // next to 18 decimal precisions numbers.

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
        
        allowToken(cdc_, "sell", "ERC20", true);
        allowToken(cdc_, "buy", "ERC20", true);
        allowToken(dpt_, "sell", "ERC20", true);
        allowToken(dpt_, "buy", "ERC20", true);
        allowToken(dpass_, "buy", "ERC721", true);

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
        uint valueBuy;
        uint valueSell;
        uint fee;
        

        updateRates(sellToken, buyToken);

        (valueBuy, valueSell) = getValues(sellToken, sellAmtOrId, buyToken, buyAmtOrId); 


        fee = calculateFee(msg.sender, valueBuy, sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        
        if (fee > 0) {

            (valueSell, valueBuy) = 
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
            erc_ == "ERC721" ||
            erc_ == "ERC20",
            "Invalid token type");
        if (erc_ == "ERC20") {
            if (buySell_ == "buy") { 
                canBuyErc20[token_] = allowed_;
                emit LogConfigChange(allowed_ ? "canBuy" : "canNotBuy", token, erc_);
            } else { 
                canSellErc20[token_] = allowed_; 
                emit LogConfigChange(allowed_ ? "canSell" : "canNotSell", token, erc_);
            }
        } else {
            if (buySell_ == "buy") { 
                canBuyErc721[token_] = allowed_;
                emit LogConfigChange(allowed_ ? "canBuy" : "canNotBuy", token, erc_);
            } else { 
                canSellErc721[token_] = allowed_; 
                emit LogConfigChange(allowed_ ? "canSell" : "canNotSell", token, erc_);
            }
        }
        emit LogValueChange(allowed_ ? "allowToken" : "denyToken", b32(token_), buySell_); 
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
                canSellErc20[token] ||
                canBuyErc20[token],
                "Token not allowed");
            require(value > 0, "Rate must be greater than 0");
            rate[token] = value;

        } else if (what == "fixFee") {
            fixFee = uint256(value_);

        } else if (what == "varFee") {
            varFee = uint256(value_);

        } else if (what == "manualRate") {
            address token = addr(value_);
            require(
                canSellErc20[token] ||
                canBuyErc20[token],
                "Token not allowed");
            manualRate[token] = uint256(value1_) > 0;

        } else if (what == "priceFeed") {
            require(canSellErc20[addr(value_)] || canBuyErc20[addr(value_)], "Token not allowed");
            require(addr(value1_) != address(address(0x0)), "Wrong PriceFeed address");
            priceFeed[addr(value_)] = TrustedFeedLike(addr(value1_));

        } else if (what == "fixFee") {
            fixFee = uint256(value_);

        } else if (what == "varFee") {
            varFee = uint256(value_);

        } else if (what == "takeOnlyProfitInDpt") {
            takeOnlyProfitInDpt = uint256(value_) > 0;

        } else if (what == "liq") {
            liq = addr(value_);
            require(TrustedErc20(dpt).balanceOf(liq) > 0,
                    "Insufficient funds of DPT");

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
        emit LogConfigChange(what, value_, value1_);
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
    * @dev Adjusts a number from one precision to another
    */
    function toDecimals(uint256 amt, uint8 srcDec, uint8 dstDec) public pure returns (uint256) {
        if (srcDec == dstDec) return amt;                                       // no change
        if (srcDec < dstDec) return mul(amt, 10 ** uint256(dstDec - srcDec));   // add zeros to the right
        return amt / 10 ** uint256(srcDec - dstDec);                            // remove digits 
    }

    /**
    * @dev Calculate fee locally or using an external smart contract
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
            return fixFee + wmul(varFee, value);                        // calculate proportional fee locally
        } else {
            return fcc.calculateFee(                                    // calculate fee using external smart contract
                sender, 
                value, 
                sellToken,
                sellAmtOrId,
                buyToken,
                buyAmtOrId);
        }
    }

    /**
    * @dev Get token_ / quote_currency rate from priceFeed 
    * Revert transaction if not valid feed and manual value not allowed
    */
    function getRate(address token_) public view returns (uint rate_) {
        bool feedValid;
        bytes32 usdRateBytes;

        require(
            TrustedFeedLike(address(0x0)) != priceFeed[token_],         // require token to have a price feed
            "No price feed for token");

        (usdRateBytes, feedValid) = priceFeed[token_].peek();           // receive DPT/USD price

        if (feedValid) {                                                // if feed is valid, load DPT/USD rate from it
            rate_ = uint(usdRateBytes);
        } else {
            require(manualRate[token_], "Manual rate not allowed");     // if feed invalid revert if manualEthRate is NOT allowed
            rate_ = rate[token_];
        }
    }
    //
    // internal functions
    //

    function updateRates(address sellToken, address buyToken) internal {
        if (canSellErc20[sellToken]) updateRate(sellToken);
        if (canBuyErc20[buyToken]) updateRate(buyToken);
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

        require(buyToken != 0xee, "Ether can not be sold here");        // we can not sell Ether with this smart contract currently

        if (canSellErc20[sellToken]) {                                  // if sellToken is a valid ERC20 token

            sellToken20 = TrustedErc20(sellToken);

            require(
                sellToken == address(0xee) ||                           // disregard Ether 
                sellAmtOrId == uint(-1) ||                              // disregard uint(-1) as it has a special meaning
                sellAmtOrId <= min(                                     // sellAmtOrId should be less then sellToken available to this contract
                    sellToken20.balanceOf(address(msg.sender)),
                    sellToken20.allowance(msg.sender, address(this))),
                "Sell amount exceeds allowance");

            require(
                sellToken != address(0xee) ||                           // regard Ether only
                sellAmtOrId == uint(-1) ||                              // disregard uint(-1) as it has a special meaning
                sellAmtOrId <= msg.value,                               // sellAmtOrId sold should be less than the Ether we received from user
                "Sell amount exceeds Ether value");
            
            if (sellAmt == uint(-1)) {                                  // if user wants to sell maximum possible

                sellAmt = min(                                          // set sell amount to max possible
                    sellToken20.balanceOf(msg.sender), 
                    sellToken20.allowance(msg.sender, address(this)));
            }

            valueSell = wmul(                                           // sell value in base currency
                toDecimals(sellAmt, getDecimals(sellToken), 18), 
                rate[sellToken]);
                
        } else if (canSellErc721[sellToken]) {                          // if sellToken is a valid ERC721 token  

            sellToken721 = TrustedErc721(sellToken);
            valueSell = asm.getPrice(TrustedErc721(buyToken), buyAmtOrId);  // get price from Asset Management

        } else {

            require(false, "Token not allowed to be sold");

        }

        if (canBuyErc20[buyToken]) {                                    // if buyToken is a valid ERC20 token
            buyToken20 = TrustedErc20(buyToken);

            require(
                buyToken == address(0xee) ||                            // disregard Ether
                buyAmtOrId == uint(-1) ||                               // disregard uint(-1) as it has a special meaning
                buyAmtOrId <= min(                                      // require token's buy amount to be less or equal than avaulable to us 
                    buyToken20.balanceOf(msg.sender), 
                    buyToken20.allowance(msg.sender, address(this))),
                "Buy amount exceeds allowance");
            
            require(
                buyToken != address(0xee) ||                            // disregard non Ether tokens
                buyAmtOrId == uint(-1) ||                               // disregard uint(-1) as it has special meaning
                buyAmtOrId <= msg.value,                                // value of Ether bought must be less or equal than we received 
                "Buy amount exceeds Ether value");
            
            if (buyAmtOrId == uint(-1)) {                               // user wants to buy the maximum possible

                buyAmt = min(                                           // buyAmt is the maximum possible
                    buyToken20.balanceOf(custodian[buyToken]),                  
                    buyToken20.allowance(
                        custodian[buyToken], address(this)));           

                if (canSellErc20[sellToken] &&                          // sell and buy tokens are ERC20 and user wants to sell max
                    sellAmtOrId == uint(-1)) {   

                    buyAmt = min(                                       // minimum of buyTokens and the number of tokens we ...
                        wdiv(                                           // ... can buy from sell value
                            toDecimals(
                                valueSell,
                                18,
                                getDecimals(buyToken)),
                            rate[buyToken]), 
                        buyAmt);
                
                }
            }

            valueBuy = wmul(                                            // final buy value in base currency
                toDecimals(buyAmt, getDecimals(buyToken), 18),
                rate[buyToken]);

        } else if (canBuyErc721[buyToken]) {                            // if buyToken is a valid ERC721 token

            require(canSellErc20[sellToken],                            // require that at least one of sell and buy token is ERC20
                    "One of tokens must be erc20");

            buyToken721 = TrustedErc721(buyToken);
            valueBuy = asm.getPrice(                                    // calculate price with Asset Management contract
                TrustedErc721(buyToken), 
                buyAmtOrId);

        } else {
            require(false, "Token not allowed to be bought");           // token can not be bought here
        }

        require(valueBuy - dust <= valueSell, "Not enough funds");
    }

    /**
    * @dev Sell tokens of user
    */
    function sellTokens(
        uint256 valueSell,                                              // sell value after fee was subtracted
        uint256 valueBuy,                                               // buy value after fee was subtracted
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) internal {
        uint sellValueToken;
        uint buyValueToken;

        sellValueToken = wdiv(                                          // calculate token amount to be sold
            toDecimals(valueSell, 18, getDecimals(sellToken)),
            rate[sellToken]
        );

        buyValueToken = wdiv(                                           // calculate token amount to be bought
            toDecimals(valueBuy, 18, getDecimals(buyToken)),
            rate[buyToken]
        );

        if (canSellErc20[sellToken]) {                                  // if sellToken is a valid ERC20 token

            sendToken(sellToken, msg.sender,                            // send token or Ether
                    custodian[sellToken], sellValueToken);

        }  else {                                                       // if sellToken is a valid ERC721 token
            
            TrustedErc721(sellToken)                                    // 
            .transferFrom(
                msg.sender, 
                custodian[sellToken], 
                sellAmtOrId);

            asm.notifyTransferFrom(
                TrustedErc721(sellToken), 
                msg.sender,
                custodian[sellToken],
                sellAmtOrId);
        }

        if (canBuyErc20[buyToken]) {
            
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
    returns(uint256, uint256) {
        uint feeTaken;
        uint amt;
        address token;
        address src;

        feeTaken = takeOnlyProfitInDpt ? wmul(fee, profitRate) : fee; 
        feeTaken = takeFeeInDptFromUser(feeTaken);
        
        if (fee - feeTaken > dust && fee - feeTaken < fee) { // if we could not take all fees from user DPT (with round-off errors considered)
            fee = sub(fee, feeTaken);

            if (canSellErc20[sellToken]) {

                require(
                    canBuyErc20[buyToken] ||                // apply rule below to ERC721 buyTokens only
                    valueSell + dust >= valueBuy + fee,     // for erc721 buy tokens the sellValue must be buyValue plus fee
                    "Not enough sell tokens");

                token = sellToken;                          // fees are sent in this token
                src = msg.sender;                           // owner of fee token is sender
                amt = sellAmtOrId;                          // max amount user wants to sell

                if (valueSell + dust >= valueBuy + fee) {   // if sellValue is higher or equal then buyValue plus fee
                
                    valueSell = valueBuy;                   // reduce sellValue to buyValue plus fee
                
                } else {                                    // if sellValue is lower than buyValue plus fee and both buy and sell tokens are ERC20
                    
                    valueBuy = sub(valueSell, fee);         // buyValue is sellValue minus fee 
                    valueSell = sub(valueBuy, fee);         // sellValue is buyValue minus fee 
                }

            } else if (canBuyErc20[buyToken]) {             // if sellToken is an ERC721 token and buyToken is an ERC20 token
                
                require(
                    valueSell <= valueBuy + fee + dust,     // sellValue must be smaller than buyValue plus fee
                    "Not enough tokens to buy");


                token = buyToken;                           // fees are sent in this token
                src = custodian[token];                     // source of funds is custodian
                amt = buyAmtOrId;                           // max amount the user intended to buy 

                if (valueSell <= valueBuy + fee + dust) 
                    valueBuy = sub(valueSell, fee); 

            } else {
                
                require(false, "No token to get fee from"); // not allowed to have both buy and sell tokens to be ERC721

            }

            sendProfitAndCost(fee, feeTaken, token, src, amt);
        }

        return (valueSell, valueBuy);
    }

    /**
    * @dev Calculate and send profit and cost
    */
    function sendProfitAndCost(
        uint256 fee,
        uint256 feeTaken,
        address token,
        address src,
        uint256 amountToken
    ) internal {
        uint profitValue;
        uint profitDpt;
        uint costToken;

        profitValue = sub(                                      // profit value still to be paid 

            wmul(fee + feeTaken, profitRate),                   // total profit due

            takeOnlyProfitInDpt ?                               // profit payed already
                feeTaken :
                wmul(feeTaken, profitRate)
        );

        profitDpt = wdiv(                                       // profit in DPT
            toDecimals(profitValue, 18, getDecimals(dpt)),      
            rate[dpt]
        );

        sendToken(dpt, liq, burner, profitDpt);                 // send profit to burner

        costToken = wdiv(                                       // convert fee from base currency to token amount 
            toDecimals(fee, 18, getDecimals(token)),
            rate[token]
        );

        require(
            costToken < amountToken,                            // require that the cost we pay is less than user intended to pay
            "Not enough token to pay fee"); 

        sendToken(address(token), src, wal, costToken);         // send user token to wallet
    }

    /**
    * @dev Take fee in DPT from user if it has any
    * @param fee the fee amount in base currency
    * @return the remaining fee amount in DPT
    */
    function takeFeeInDptFromUser(uint256 fee) internal returns(uint256 feeTaken) {
        TrustedErc20 dpt20 = TrustedErc20(dpt); 
        uint profitDpt;
        uint costDpt;

        uint dptUser = min(
            dpt20.balanceOf(msg.sender),
            dpt20.allowance(msg.sender, address(this))
        );
        
        uint feeDpt = wdiv(                                         // fee in DPT
                            toDecimals(fee, 18, getDecimals(dpt)),
                            rate[dpt]
        );
        
        uint minDpt = min(feeDpt, dptUser);
        
        feeTaken = wmul(                                            // fee in terms of base currency 
                        toDecimals(minDpt, getDecimals(dpt), 18),
                        rate[dpt]
        );

        if (minDpt > 0) {
            if (takeProfitOnlyInDpt) {

                sendToken(dpt, msg.sender, burner, minDpt);         // only profit is put to the burner

            } else {
                
                profitDpt = wmul(minDpt, profitRate);
                sendToken(dpt, msg.sender, burner, profitDpt);      // send profit

                costDpt = sub(minDpt, profitDpt);  
                sendToken(dpt, msg.sender, wal, costDpt);           // send cost
            }
        }

    } 

    /**
    * &dev send token or ether to destination
    */
    function sendToken(address token, address src, address dst, uint256 amount) internal returns(uint256 etherSpent) {
        TrustedErc20 erc20 = TrustedErc20(token);

        if (token == address(0xee) && amount > dust) {              // if token is Ether and amount is higher than dust limit

            dst.call.value(amount).gas(callGas);                    // transfer ether

            etherSpent = amount;                                    // let caller know how much ether was spent
        } else {

            if (amount > 0) erc20.transferFrom(src, dst, amount);   // transfer all of token to wallet
        }
    }
}
