// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Lootery} from "./Lootery.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract LooteryNativeHelper {
    IWETH9 public wrappedToken;

    constructor(address payable _wrappedTokenAddress) {
        wrappedToken = IWETH9(_wrappedTokenAddress);
    }

    function purchaseNative(
        address payable looteryAddress,
        Lootery.Ticket[] calldata tickets
    ) public payable {
        Lootery lootery = Lootery(looteryAddress);
        uint256 ticketsCount = tickets.length;
        uint256 totalPrice = lootery.ticketPrice() * ticketsCount;

        require(msg.value >= totalPrice, "Insufficient funds");

        wrappedToken.deposit{value: totalPrice}();
        wrappedToken.approve(looteryAddress, totalPrice);

        lootery.purchase(tickets);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
    }

    function seedJackpotNative(address payable looteryAddress) public payable {
        Lootery lootery = Lootery(looteryAddress);

        wrappedToken.deposit{value: msg.value}();
        wrappedToken.approve(looteryAddress, msg.value);

        lootery.seedJackpot(msg.value);
    }
}
