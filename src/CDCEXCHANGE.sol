pragma solidity ^0.4.25;

import "ds-math/math.sol";
import "ds-auth/auth.sol";
import "ds-token/token.sol";
import "ds-stop/stop.sol";
import "ds-note/note.sol";


/**
 * @title CDC
 * @dev CDC EXCHANGE contract.
 */
contract CDCEXCHANGEEvents {
    event LogBuyToken(
        address owner,
        address sender,
        uint ethValue,
        uint cdcValue,
        uint rate
    );
}

contract CDCEXCHANGE is DSAuth, DSStop, DSMath, CDCEXCHANGEEvents {
    ERC20 public cdc;                    //CDC token contract
    uint public rate;                    //price of 1 CDC token. 18 digit precision

    /**
    * @dev Constructor
    */
    constructor(address cdc_, uint rate_) public {
        cdc = ERC20(cdc_);
        rate = rate_;
    }

    /**
    * @dev Fallback function is used to buy tokens.
    */
    function () external payable {
        buyTokens();
    }

    /**
    * @dev Low level token purchase function.
    */
    function buyTokens() public payable stoppable {
        require(msg.value != 0, "Invalid amount");

        uint tokens;
        tokens = wdiv(msg.value, rate);

        address(owner).transfer(msg.value);
        cdc.transferFrom(owner, msg.sender, tokens);
        emit LogBuyToken(owner, msg.sender, msg.value, tokens, rate);
    }

    /**
    * @dev Set exchange rate CDC/ETH value.
    */
    function setRate(uint rate_) public auth note {
        require(rate_ > 0, "Invalid amount");
        rate = rate_;
    }
}
