pragma solidity ^0.5.11;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "ds-token/token.sol";
import "cdc-token/Cdc.sol";
import "dpass/Dpass.sol";
import "./CdcExchange.sol";
import "./Burner.sol";


contract TestFeeCalculator is DSMath {
    uint public fee;

    function calculateFee(
        address sender,
        uint256 value,
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) external view returns (uint256) {
        if (sender == address(0x0)) {return 0;}
        if (sellToken == address(0x0)) {return 0;}
        if (buyToken == address(0x0)) {return 0;}
        return add(add(add(value, sellAmtOrId), buyAmtOrId), fee);
    }

    function setFee(uint fee_) public {
        fee = fee_;
    }
}


contract TestFeedLike {
    bytes32 public rate;
    bool public feedValid;

    constructor(uint rate_, bool feedValid_) public {
        require(rate_ > 0, "TestFeedLike: Rate must be > 0");
        rate = bytes32(rate_);
        feedValid = feedValid_;
    }

    function peek() external view returns (bytes32, bool) {
        return (rate, feedValid);
    }

    function setRate(uint rate_) public {
        rate = bytes32(rate_);
    }

    function setValid(bool feedValid_) public {
        feedValid = feedValid_;
    }
}


contract DptTester {
    DSToken public _dpt;

    constructor(DSToken dpt) public {
        require(address(dpt) != address(0), "CET: dpt 0x0 invalid");
        _dpt = dpt;
    }

    function doApprove(address to, uint amount) public {
        DSToken(_dpt).approve(to, amount);
    }

    function doTransfer(address to, uint amount) public {
        DSToken(_dpt).transfer(to, amount);
    }

    function () external payable {
    }
}


contract CdcExchangeTester {
    CdcExchange public exchange;
    DSToken public _dpt;
    DSToken public _cdc;
    DSToken public _dai;

    constructor(address payable exchange_, address dpt, address cdc, address dai) public {
        require(exchange_ != address(0), "CET: exchange 0x0 invalid");
        require(dpt != address(0), "CET: dpt 0x0 invalid");
        require(cdc != address(0), "CET: cdc 0x0 invalid");
        require(dai != address(0), "CET: dai 0x0 invalid");
        exchange = CdcExchange(exchange_);
        _dpt = DSToken(dpt);
        _cdc = DSToken(cdc);
        _dai = DSToken(dai);
    }

    function () external payable {
    }

    function doApprove(address token, address to, uint amount) public {
        require(token != address(0), "Can't approve token of 0x0");
        require(to != address(0), "Can't approve address of 0x0");
        DSToken(token).approve(to, amount);
    }

    function doBuyTokensWithFee(
        address sellToken, 
        uint256 sellAmtOrId, 
        address buyToken,
        uint256 buyAmtOrId
    ) public payable {
        if (sellToken == address(0xee)) {
            CdcExchange(exchange).buyTokensWithFee.value(sellAmtOrId)(sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        } else {
            CdcExchange(exchange).buyTokensWithFee(sellToken, sellAmtOrId, buyToken, buyAmtOrId);
        }
    }

    function doSetConfig(bytes32 what, address value_, address value1_) public { doSetConfig(what, b32(value_), b32(value1_), ""); }
    function doSetConfig(bytes32 what, address value_, bytes32 value1_) public { doSetConfig(what, b32(value_), value1_, ""); }
    function doSetConfig(bytes32 what, address value_, uint256 value1_) public { doSetConfig(what, b32(value_), b32(value1_), ""); }
    function doSetConfig(bytes32 what, address value_, bool value1_) public { doSetConfig(what, b32(value_), b32(value1_), ""); }
    function doSetConfig(bytes32 what, address value_, uint256 value1_, address value2_) public { doSetConfig(what, b32(value_), b32(value1_), b32(value2_)); }
    function doSetConfig(bytes32 what, uint256 value_, address value1_) public { doSetConfig(what, b32(value_), b32(value1_), ""); }
    function doSetConfig(bytes32 what, uint256 value_, bytes32 value1_) public { doSetConfig(what, b32(value_), value1_, ""); }
    function doSetConfig(bytes32 what, uint256 value_, uint256 value1_) public { doSetConfig(what, b32(value_), b32(value1_), ""); }
    function doSetConfig(bytes32 what, uint256 value_, bool value1_) public { doSetConfig(what, b32(value_), b32(value1_), ""); }

    function doSetConfig(bytes32 what_, bytes32 value_, bytes32 value1_, bytes32 value2_) public {
        CdcExchange(exchange).setConfig(what_, value_, value1_, value2_);
    }
    
    function doGetDecimals(address token_) public view returns(uint8) {
        return CdcExchange(exchange).getDecimals(token_);
    }

    /**
    * @dev Convert address to bytes32
    * @param a address that is converted to bytes32
    * @return bytes32 conversion of address
    */
    function b32(address a) public pure returns (bytes32) {
        return bytes32(uint256(a));
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
    * @dev Convert uint256 to bytes32
    * @param a_ bool value to be converted
    * @return bytes32 converted value
    */
    function b32(bool a_) public pure returns (bytes32) {
        return bytes32(uint256(a_ ? 1 : 0));
    }

    /**
    * @dev Convert address to bytes32
    */
    function addr(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function doToDecimals(uint256 amt_, uint8 srcDec_, uint8 dstDec_) public view returns (uint256) {
        return CdcExchange(exchange).toDecimals(amt_, srcDec_, dstDec_);
    }

    function doCalculateFee(
        address sender_,
        uint256 value_,
        address sellToken_, 
        uint256 sellAmtOrId_, 
        address buyToken_,
        uint256 buyAmtOrId_
    ) public view returns (uint256) {
        return CdcExchange(exchange).calculateFee(sender_, value_, sellToken_, sellAmtOrId_, buyToken_, buyAmtOrId_);
    }

    function doGetRate(address token_) public view returns (uint rate_) {
        return CdcExchange(exchange).getRate(token_);
    }

    function doGetLocalRate(address token_) public view returns (uint rate_) {
        return CdcExchange(exchange).getRate(token_);
    }
}


contract TrustedAssetManagementTester {
    bool public txEnabled = true;
    mapping(address => mapping( uint256 => uint256)) public price;
    mapping(address => uint256) public forSale;
    mapping(address => bool) public own;

    function setPrice(TrustedErc721 erc721, uint256 id721, uint256 price_) public {
        price[address(erc721)][id721] = price_;
    }
    
    function setTxEnabled(bool enabled_) public {
        txEnabled = enabled_;
    }

    function setAmtForSale(address token, uint256 amtForSale) public {
        forSale[token] = amtForSale;
    }
    
    function setOwnerOf(address token, bool isOwner) public {
        own[token] = isOwner;
    }

    function sendToken(address token, address dst, uint256 value) public {
       DSToken tok = DSToken(token);
       tok.transfer(dst, value);
    }

    function notifyTransferFrom(TrustedErc721 erc721, address src, address dst, uint256 id721) public view {
        // begin----------------- just to avoid compiler warnings --------
        TrustedErc721 a;
        address b;
        uint c;
        
        a = erc721;
        b = src;
        b = dst;
        c = id721;
        // end----------------- just to avoid compiler warnings --------

        require(txEnabled, "Transaction is not allowed");
    }

    function getPrice(TrustedErc721 erc721, uint256 id721) public view returns(uint256) {
        return price[address(erc721)][id721];
    }

    function getAmtForSale(address token) public view returns (uint256){
        return forSale[token];
    }

    function isOwnerOf(address token) public view returns(bool) {
        return own[token];
    }

    function () external payable {
    }
}


contract CdcExchangeTest is DSTest, DSMath, CdcExchangeEvents {
    event LogNamedUintUint(bytes32 key, uint val, uint val1);
    event LogTest(uint256 what);
    event LogTest(bool what);
    event LogTest(address what);
    event LogTest(bytes32 what);

    uint public constant SUPPLY = (10 ** 7) * (10 ** 18);
    uint public constant INITIAL_BALANCE = 1000 ether;

    address public cdc;     // Cdc()
    address public dpass;   // Dpass()
    address public dpt;     // DSToken()
    address public dai;     // DSToken()
    address public eth;
    address payable public exchange; // CdcExchange()

    address payable public liquidityContract;   // CdcExchangeTester()
    address payable public wal;                 // DptTester()
    address payable public asm;                 // TrustedAssetManagementTester()
    address payable public user;                // CdcExchangeTester()

    address payable public burner;              // Burner()
    address payable public fca;                 // TestFeeCalculator()

    // test variables
    mapping(address => mapping(address => uint)) public balance;

    mapping(address => uint) public usdRate;
    mapping(address => address) feed;                           // address => TestFeedLike()
    mapping(address => address payable) custodian20;
    mapping(address => address payable) custodian721;


    uint public fixFee = 0 ether;           
    uint public varFee = .2 ether;          // variable fee is 20% of value
    uint public profitRate = .3 ether;      // profit rate 30%
    bool public takeProfitOnlyInDpt = false; // take only profit or total fee (cost + profit) in DPT 

    // variables for calculating expected behaviour --------------------------
    uint userDpt;
    uint feeDpt;
    uint restOfFeeT;
    uint restOfFeeV;
    uint feeV;
    uint sentV;
    uint profitV;
    uint profitDpt;
    uint expectedBalance;

    function setUp() public {
        cdc = address(new Cdc());
        dpass = address(new Dpass());
        dpt = address(new DSToken("DPT"));
        dai = address(new DSToken("DAI"));
        eth = address(0xee);
        
        DSToken(dpt).mint(SUPPLY);
        DSToken(dai).mint(SUPPLY);

        usdRate[dpt] = 5 ether;
        usdRate[cdc] = 7 ether;
        usdRate[eth] = 11 ether;
        usdRate[dai] = 13 ether;

        feed[eth] = address(new TestFeedLike(usdRate[eth], true));
        feed[dpt] = address(new TestFeedLike(usdRate[dpt], true));
        feed[cdc] = address(new TestFeedLike(usdRate[cdc], true));
        feed[dai] = address(new TestFeedLike(usdRate[dai], true));

        burner = address(uint160(address(new Burner(DSToken(dpt))))); // Burner()


        wal = address(uint160(address(new DptTester(DSToken(dai))))); // DptTester()
        asm = address(uint160(address(new TrustedAssetManagementTester())));
        
        custodian20[dpt] = asm;
        custodian20[cdc] = asm;
        custodian20[eth] = asm;
        custodian20[dai] = asm;

        TrustedAssetManagementTester(asm).setOwnerOf(cdc, true);                             // asset management will handle this token
        TrustedAssetManagementTester(asm).setAmtForSale(cdc, INITIAL_BALANCE);
        Cdc(cdc).transfer(asm, INITIAL_BALANCE);

        TrustedAssetManagementTester(asm).setOwnerOf(dpass, true);

        liquidityContract = address(uint160(address(new CdcExchangeTester(address(0xfa), dpt, cdc, dai)))); // FAKE DECLARATION, will overdeclare later
        DSToken(dpt).transfer(liquidityContract, INITIAL_BALANCE);
        
        exchange = address(uint160(address(new CdcExchange(
            cdc,
            dpt,
            dpass,
            feed[eth],
            feed[dpt],
            feed[cdc],
            liquidityContract,
            burner,
            asm,
            fixFee,
            varFee,
            profitRate,
            wal
        ))));
        CdcExchange(exchange).setConfig("canSellErc20", dai, true);
        CdcExchange(exchange).setConfig("priceFeed", dai, feed[dai]);
        CdcExchange(exchange).setConfig("rate", dai, usdRate[dai]);
        CdcExchange(exchange).setConfig("manualRate", dai, true);
        CdcExchange(exchange).setConfig("decimals", dai, 18);
        CdcExchange(exchange).setConfig("custodian20", dai, custodian20[dai]);
        // CdcExchange(exchange).setConfig("handledByAsm", dai, true);      // set true if token can be bougt by user and asm should handle it

        CdcExchange(exchange).setConfig("canSellErc20", eth, true);
        CdcExchange(exchange).setConfig("priceFeed", eth, feed[eth]);
        CdcExchange(exchange).setConfig("rate", eth, usdRate[eth]);
        CdcExchange(exchange).setConfig("manualRate", eth, true);
        CdcExchange(exchange).setConfig("decimals", eth, 18);
        CdcExchange(exchange).setConfig("custodian20", eth, custodian20[eth]);
        // CdcExchange(exchange).setConfig("handledByAsm", eth, true);      // set true if token can be bougt by user and asm should handle it

        CdcExchange(exchange).setConfig("canSellErc20", cdc, true);
        CdcExchange(exchange).setConfig("canBuyErc20", cdc, true);
        CdcExchange(exchange).setConfig("custodian20", cdc, custodian20[cdc]);
        CdcExchange(exchange).setConfig("priceFeed", cdc, feed[cdc]);
        CdcExchange(exchange).setConfig("rate", cdc, usdRate[cdc]);
        CdcExchange(exchange).setConfig("manualRate", cdc, true);
        CdcExchange(exchange).setConfig("decimals", cdc, 18);

        CdcExchange(exchange).setConfig("canSellErc20", dpt, true);
        CdcExchange(exchange).setConfig("custodian20", dpt, asm);
        CdcExchange(exchange).setConfig("priceFeed", dpt, feed[dpt]);
        CdcExchange(exchange).setConfig("rate", dpt, usdRate[dpt]);
        CdcExchange(exchange).setConfig("manualRate", dpt, true);
        CdcExchange(exchange).setConfig("decimals", dpt, 18);
        CdcExchange(exchange).setConfig("custodian20", dpt, custodian20[dpt]);
        CdcExchange(exchange).setConfig("takeProfitOnlyInDpt", b32(takeProfitOnlyInDpt), "", "");

        liquidityContract = address(uint160(address(new CdcExchangeTester(exchange, dpt, cdc, dai))));
        DSToken(dpt).transfer(liquidityContract, INITIAL_BALANCE);
        CdcExchangeTester(liquidityContract).doApprove(dpt, exchange, uint(-1));
        CdcExchange(exchange).setConfig("liq", liquidityContract, "");

        user = address(uint160(address(new CdcExchangeTester(exchange, dpt, cdc, dai))));
        fca = address(uint160(address(new TestFeeCalculator())));

        Cdc(cdc).approve(exchange, uint(-1));
        DSToken(dpt).approve(exchange, uint(-1));
        DSToken(dai).approve(exchange, uint(-1));

        // Prepare seller of DPT fees

        user.transfer(INITIAL_BALANCE);
        Cdc(cdc).transfer(user, INITIAL_BALANCE);
        DSToken(dai).transfer(user, INITIAL_BALANCE);

        CdcExchangeTester(user).doApprove(dpt, exchange, uint(-1));
        CdcExchangeTester(user).doApprove(cdc, exchange, uint(-1));
        CdcExchangeTester(user).doApprove(dai, exchange, uint(-1));

        balance[address(this)][eth] = address(this).balance;
        balance[user][eth] = user.balance;
        balance[user][cdc] = Cdc(cdc).balanceOf(user);
        balance[user][dpt] = Cdc(dpt).balanceOf(user);
        balance[user][dai] = Cdc(dai).balanceOf(user);

        balance[asm][eth] = asm.balance;
        balance[asm][cdc] = Cdc(cdc).balanceOf(asm);
        balance[asm][dpt] = Cdc(dpt).balanceOf(asm);
        balance[asm][dai] = Cdc(dai).balanceOf(asm);

        balance[liquidityContract][eth] = liquidityContract.balance;
        balance[wal][eth] = wal.balance;
        balance[custodian20[eth]][eth] = custodian20[eth].balance;
        balance[custodian20[cdc]][cdc] = Cdc(cdc).balanceOf(custodian20[cdc]);
        balance[custodian20[dpt]][cdc] = DSToken(dpt).balanceOf(custodian20[dpt]);
        balance[custodian20[dai]][cdc] = DSToken(dai).balanceOf(custodian20[dai]);

        emit log_named_address("exchange", exchange);
        emit log_named_address("dpt", dpt);
        emit log_named_address("cdc", cdc);
        emit log_named_address("asm", asm);
        emit log_named_address("user", user);
        emit log_named_address("wal", wal);
        emit log_named_address("liq", liquidityContract);
        emit log_named_address("burner", burner);
    }

    function doExchange(address sellToken, uint256 sellAmtOrId, address buyToken, uint256 buyAmtOrId) public {
        userDpt = DSToken(dpt).balanceOf(user); 
        sentV = wmul(sellAmtOrId, usdRate[sellToken]);
        feeV = add(wmul(varFee, sentV), fixFee);
        feeDpt = wdiv(feeV, usdRate[dpt]);
        profitV = wmul(feeV, profitRate);
        profitDpt = wdiv(profitV, usdRate[dpt]);

        if (userDpt < feeDpt) {
            restOfFeeV = wmul(sub(feeDpt, userDpt), usdRate[dpt]);
            restOfFeeT = wdiv(restOfFeeV, usdRate[eth]);
        }

        if (takeProfitOnlyInDpt) {

            expectedBalance = sub(
                INITIAL_BALANCE, 
                userDpt < profitDpt ?
                    sub(profitDpt, userDpt) :
                    0);
        } else {

            expectedBalance = sub(
                INITIAL_BALANCE, 
                userDpt < feeDpt ?
                    sub(profitDpt, wmul(userDpt, profitRate)) :
                    0);
        }

        CdcExchangeTester(user).doBuyTokensWithFee(
            sellToken,
            sellAmtOrId,
            buyToken,
            buyAmtOrId
        );

        logUint("userDptValue", wmul(userDpt, usdRate[dpt]), 18);
        logUint("userDpt", userDpt, 18);
        logUint("sentV", sentV, 18);
        logUint("sellAmtOrId", sellAmtOrId, 18);
        logUint("feeV(total)", feeV, 18);
        logUint("feeDpt(total)", feeDpt, 18);
        logUint("profitRate", profitRate, 18);
        logUint("profitV", profitV, 18);
        logUint("profitDpt", profitDpt, 18);
        logUint("restOfFeeV", restOfFeeV, 18);
        logUint("restOfFeeT", restOfFeeT, 18);


    }         

    function logUint(bytes32 what, uint256 num, uint256 decimals) public {
        emit LogNamedUintUint( what, num / 10 ** decimals, num % 10 ** decimals);
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
    * @dev Convert uint256 to bytes32
    * @param a_ bool value to be converted
    * @return bytes32 converted value
    */
    function b32(bool a_) public pure returns (bytes32) {
        return bytes32(uint256(a_ ? 1 : 0));
    }

    function () external payable {
    }
/*
    function testCalculateFee() public {
        // By default fee should be equal to init value
        assertEq(CdcExchange(exchange).calculateFee(
            address(this),
            1 ether,
            address(0x0),
            0,
            address(0x0),
            0
        ), .1 ether);
    }
    
    function testSetFixFee() public {
        uint fee = 0.1 ether;
        CdcExchange(exchange).setConfig("fixFee", fee, "");
        assertEq(CdcExchange(exchange).calculateFee(
            address(this),
            0 ether,
            address(0x0),
            0,
            address(0x0),
            0
        ), fee);
    }

    function testSetVarFee() public {
        uint fee = 0.5 ether;
        CdcExchange(exchange).setConfig("varFee", fee, "");
        assertEq(CdcExchange(exchange).calculateFee(
            address(this),
            1 ether,
            address(0x0),
            0,
            address(0x0),
            0
        ), fee);
    }

    function testSetVarAndFixFee() public {
        uint value = 1 ether;
        uint varFee1 = 0.5 ether;
        uint fixFee1 = uint(10) / uint(3) * 1 ether;
        CdcExchange(exchange).setConfig("varFee", varFee1, "");
        CdcExchange(exchange).setConfig("fixFee", fixFee1, "");
        assertEq(CdcExchange(exchange).calculateFee(
            address(this),
            value,
            address(0x0),
            0,
            address(0x0),
            0
        ), add(fixFee1, wmul(varFee1, value)));
    }

    function testFailNonOwnerSetVarFee() public {
        uint newFee = 0.1 ether;
        CdcExchangeTester(user).doSetConfig("varFee", newFee, "");
    }

    function testFailNonOwnerSetFixFee() public {
        uint newFee = 0.1 ether;
        CdcExchangeTester(user).doSetConfig("fixFee", newFee, "");
    }

    function testSetEthPriceFeed() public {
        address token = eth;
        uint rate = 1 ether;
        CdcExchange(exchange).setConfig("priceFeed", token, feed[dai]);
        TestFeedLike(feed[dai]).setRate(rate); 
        assertEq(CdcExchange(exchange).getRate(token), rate);
    }

    function testSetDptPriceFeed() public {
        address token = dpt;
        uint rate = 2 ether;
        CdcExchange(exchange).setConfig("priceFeed", token, feed[dai]);
        TestFeedLike(feed[dai]).setRate(rate); 
        assertEq(CdcExchange(exchange).getRate(token), rate);
    }

    function testSetCdcPriceFeed() public {
        address token = cdc;
        uint rate = 4 ether;
        CdcExchange(exchange).setConfig("priceFeed", token, feed[dai]);
        TestFeedLike(feed[dai]).setRate(rate); 
        assertEq(CdcExchange(exchange).getRate(token), rate);
    }

    function testSetDaiPriceFeed() public {
        address token = dai;
        uint rate = 5 ether;
        CdcExchange(exchange).setConfig("priceFeed", token, feed[dai]);
        TestFeedLike(feed[dai]).setRate(rate); 
        assertEq(CdcExchange(exchange).getRate(token), rate);
    }

    function testFailWrongAddressSetPriceFeed() public {
        address token = eth;
        CdcExchange(exchange).setConfig("priceFeed", token, address(0));
    }

    function testFailNonOwnerSetEthPriceFeed() public {
        address token = eth;
        CdcExchangeTester(user).doSetConfig("priceFeed", token, address(0));
    }

    function testFailWrongAddressSetDptPriceFeed() public {
        address token = dpt;
        CdcExchange(exchange).setConfig("priceFeed", token, address(0));
    }

    function testFailWrongAddressSetCdcPriceFeed() public {
        address token = cdc;
        CdcExchange(exchange).setConfig("priceFeed", token, address(0));
    }

    function testFailNonOwnerSetCdcPriceFeed() public {
        address token = cdc;
        CdcExchangeTester(user).doSetConfig("priceFeed", token, address(0));
    }

    function testSetLiquidityContract() public {
        DSToken(dpt).transfer(user, 100 ether);
        CdcExchange(exchange).setConfig("liq", user, "");
        assertEq(CdcExchange(exchange).liq(), user);
    }

    function testFailWrongAddressSetLiquidityContract() public {
        CdcExchange(exchange).setConfig("liq", address(0x0), "");
    }

    function testFailNonOwnerSetLiquidityContract() public {
        DSToken(dpt).transfer(user, 100 ether);
        CdcExchangeTester(user).doSetConfig("liq", user, "");
    }

    function testFailWrongAddressSetWalletContract() public {
        CdcExchange(exchange).setConfig("wal", address(0x0), "");
    }

    function testFailNonOwnerSetWalletContract() public {
        CdcExchangeTester(user).doSetConfig("wal", user, "");
    }

    function testSetManualDptRate() public {
        CdcExchange(exchange).setConfig("manualRate", dpt, true);
        assertTrue(CdcExchange(exchange).getManualRate(dpt));
        CdcExchange(exchange).setConfig("manualRate", dpt, false);
        assertTrue(!CdcExchange(exchange).getManualRate(dpt));
    }

    function testSetManualCdcRate() public {
        CdcExchange(exchange).setConfig("manualRate", cdc, true);
        assertTrue(CdcExchange(exchange).getManualRate(cdc));
        CdcExchange(exchange).setConfig("manualRate", cdc, false);
        assertTrue(!CdcExchange(exchange).getManualRate(cdc));
    }

    function testSetManualEthRate() public {
        CdcExchange(exchange).setConfig("manualRate", address(0xee), true);
        assertTrue(CdcExchange(exchange).getManualRate(address(0xee)));
        CdcExchange(exchange).setConfig("manualRate", address(0xee), false);
        assertTrue(!CdcExchange(exchange).getManualRate(address(0xee)));
    }

    function testSetManualDaiRate() public {
        CdcExchange(exchange).setConfig("manualRate", dai, true);
        assertTrue(CdcExchange(exchange).getManualRate(dai));
        CdcExchange(exchange).setConfig("manualRate", dai, false);
        assertTrue(!CdcExchange(exchange).getManualRate(dai));
    }
    
    function testFailNonOwnerSetManualDptRate() public {
        CdcExchangeTester(user).doSetConfig("manualRate", dpt, false);
    }

    function testFailNonOwnerSetManualCdcRate() public {
        CdcExchangeTester(user).doSetConfig("manualRate", cdc, false);
    }

    function testFailNonOwnerSetManualEthRate() public {
        CdcExchangeTester(user).doSetConfig("manualRate", address(0xee), false);
    }

    function testFailNonOwnerSetManualDaiRate() public {
        CdcExchangeTester(user).doSetConfig("manualRate", dai, false);
    }

    function testSetFeeCalculatorContract() public {
        CdcExchange(exchange).setConfig("fca", address(fca), "");
        assertEq(address(CdcExchange(exchange).fca()), address(fca));
    }

    function testFailWrongAddressSetCfo() public {
        CdcExchange(exchange).setConfig("fca", address(0), "");
    }

    function testFailNonOwnerSetCfo() public {
        CdcExchangeTester(user).doSetConfig("fca", user, "");
    }

    function testSetDptUsdRate() public {
        uint newRate = 5 ether;
        CdcExchange(exchange).setConfig("rate", dpt, newRate);
        assertEq(CdcExchange(exchange).getLocalRate(dpt), newRate);
    }

    function testFailIncorectRateSetDptUsdRate() public {
        CdcExchange(exchange).setConfig("rate", dpt, uint(0));
    }

    function testFailNonOwnerSetDptUsdRate() public {
        uint newRate = 5 ether;
        CdcExchangeTester(user).doSetConfig("rate", dpt, newRate);
    }

    function testSetCdcUsdRate() public {
        uint newRate = 5 ether;
        CdcExchange(exchange).setConfig("rate", cdc, newRate);
        assertEq(CdcExchange(exchange).getLocalRate(cdc), newRate);
    }

    function testFailIncorectRateSetCdcUsdRate() public {
        CdcExchange(exchange).setConfig("rate", cdc, uint(0));
    }

    function testFailNonOwnerSetCdcUsdRate() public {
        uint newRate = 5 ether;
        CdcExchangeTester(user).doSetConfig("rate", cdc, newRate);
    }

    function testSetEthUsdRate() public {
        uint newRate = 5 ether;
        CdcExchange(exchange).setConfig("rate", eth, newRate);
        assertEq(CdcExchange(exchange).getLocalRate(eth), newRate);
    }

    function testFailIncorectRateSetEthUsdRate() public {
        CdcExchange(exchange).setConfig("rate", eth, uint(0));
    }

    function testFailNonOwnerSetEthUsdRate() public {
        uint newRate = 5 ether;
        CdcExchangeTester(user).doSetConfig("rate", eth, newRate);
    }
*/
    function testFailInvalidDptFeedAndManualDisabledBuyTokensWithFee() public logs_gas {
        uint sentEth = 1 ether;
       
        CdcExchange(exchange).setConfig("manualRate", dpt, false);
       
        TestFeedLike(feed[dpt]).setValid(false);
        
        CdcExchange(exchange).buyTokensWithFee(dpt, sentEth, cdc, uint(-1));
    }

    function testFailInvalidEthFeedAndManualDisabledBuyTokensWithFee() public logs_gas {
        uint sentEth = 1 ether;

        CdcExchange(exchange).setConfig("manualRate", eth, false);

        TestFeedLike(feed[eth]).setValid(false);
        
        CdcExchange(exchange).buyTokensWithFee.value(sentEth)(eth, sentEth, cdc, uint(-1));
    }

    function testFailInvalidCdcFeedAndManualDisabledBuyTokensWithFee() public {
        uint sentEth = 1 ether;

        CdcExchange(exchange).setConfig("manualRate", cdc, false);

        TestFeedLike(feed[cdc]).setValid(false);
        
        CdcExchange(exchange).buyTokensWithFee(cdc, sentEth, cdc, uint(-1));
    }

    /**
    * @dev User does not has any DPT and send only ETH and get CDC
    */
    function testBuyCdcWithEthUserDptNotZeroNotEnough() public {
        userDpt = 1 ether;
        DSToken(dpt).transfer(user, userDpt);

        address sellToken = eth;
        uint sellAmtOrId = 17 ether;
        address buyToken = cdc;
        uint buyAmtOrId = uint(-1);

        doExchange(sellToken, sellAmtOrId, buyToken, buyAmtOrId); 
        
    }

    /**
    * @dev User does not has any DPT and send only ETH and get CDC
    */
    function testBuyCdcWithEthUserDptNotZeroEnough() public {
        userDpt = 123 ether;
        DSToken(dpt).transfer(user, userDpt);

        address sellToken = eth;
        uint sellAmtOrId = 27 ether;
        address buyToken = cdc;
        uint buyAmtOrId = uint(-1);

        doExchange(sellToken, sellAmtOrId, buyToken, buyAmtOrId); 
    }

}
