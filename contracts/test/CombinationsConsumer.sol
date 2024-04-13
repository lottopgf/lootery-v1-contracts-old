// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Combinations} from "../lib/Combinations.sol";

contract CombinationsConsumer {
    function choose(uint256 n, uint256 k) external pure returns (uint256) {
        return Combinations.choose(n, k);
    }

    function genCombinations(
        uint8[] memory pick,
        uint256 k
    ) external view returns (uint8[][] memory result, uint256 gas) {
        gas = gasleft();
        result = Combinations.genCombinations(pick, k);
        gas -= gasleft();
    }
}
