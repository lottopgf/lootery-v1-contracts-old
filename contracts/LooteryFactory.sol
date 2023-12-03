// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Lootery} from "./Lootery.sol";

/// @title LooteryFactory
/// @notice Launch your own lottos!
contract LooteryFactory {
    address public looteryMasterCopy;
    address public randomiser;
    uint256 public nonce;

    /// @notice Launch your own lotto
    function create(
        string memory name_,
        string memory symbol_,
        uint256 numPicks_,
        uint8 maxBallValue_,
        uint256 gamePeriod_,
        uint256 ticketPrice_,
        uint256 communityFeeBps_
    ) external returns (address) {
        uint256 nonce_ = nonce++;
        bytes32 salt = keccak256(abi.encode(nonce_, "lootery"));
        address looteryProxy = Clones.cloneDeterministic(
            looteryMasterCopy,
            salt
        );
        Lootery(looteryProxy).init(
            msg.sender,
            name_,
            symbol_,
            numPicks_,
            maxBallValue_,
            gamePeriod_,
            ticketPrice_,
            communityFeeBps_,
            randomiser
        );
        return looteryProxy;
    }
}
