// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {BitSet} from "./BitSet.sol";

library Combinations {
    error InvalidChoose(uint256 n, uint256 k);

    /// @notice Compute number of combinations of size k from a set of n
    /// @param n Size of set to choose from
    /// @param k Size of subsets to choose
    function choose(
        uint256 n,
        uint256 k
    ) internal pure returns (uint256 result) {
        if (n < k) revert InvalidChoose(n, k);
        assembly {
            /// @notice factorial fn: compute x!
            function fac(x) -> y {
                switch iszero(x)
                case 1 {
                    // Base case: x == 0
                    y := 1
                }
                default {
                    y := mul(x, fac(sub(x, 1)))
                }
            }

            // "n choose k"
            // result <- n! / [ k!(n-k)! ]
            result := div(fac(n), mul(fac(k), fac(sub(n, k))))
        }
    }

    /// @notice Generate all possible combinations of 8-bit number sets with
    ///     length k from a set of size n. Returns indices.
    /// @dev Runs in O(2^n) but best for small n (n<8)
    /// @param n Size of set to choose from
    /// @param k Size of subsets to choose
    function genCombinationIndices(
        uint256 n,
        uint256 k
    ) internal pure returns (uint8[][] memory combinations) {
        combinations = new uint8[][](choose(n, k));
        uint256 c;
        for (uint256 i; i < (uint256(1) << n); ++i) {
            if (BitSet.popcnt(i) == k) {
                combinations[c] = new uint8[](k);
                uint256 d;
                for (uint256 j; j < 256; ++j) {
                    if (i & (uint256(1) << j) != 0) {
                        combinations[c][d++] = uint8(j);
                    }
                    if (d == k) break;
                }
                c += 1;
            }
        }
        return combinations;
    }

    struct CombinationIterator {
        uint256 size;
        uint256 n;
        uint256 k;
        uint256 i;
        uint256 j;
    }

    function iter(
        uint256 n,
        uint256 k
    ) internal pure returns (CombinationIterator memory) {
        return
            CombinationIterator({size: choose(n, k), n: n, k: k, i: 0, j: 0});
    }

    // function next(
    //     CombinationIterator memory iter
    // )
    //     internal
    //     pure
    //     returns (CombinationIterator memory, uint8[] memory combination)
    // {
    //         if (iter.i >= iter.size) {
    //             revert("no more elements");
    //         }
    //     for (uint256 i; i < (uint256(1) << n); ++i) {
    //         if (BitSet.popcnt(i) == iter.k) {
    //             combination = new uint8[](k);
    //             uint256 d;
    //             for (uint256 j; j < 256; ++j) {
    //                 if (i & (uint256(1) << j) != 0) {
    //                     combinations[c][d++] = uint8(j);
    //                 }
    //                 if (d == k) break;
    //             }
    //             c += 1;
    //         }
    //     }
    //     return (iter, combination);
    // }

    /// @notice Generate all possible combinations from `set`
    /// @param set Set to choose elements from
    /// @param k Size of subsets to choose
    function genCombinations(
        uint8[] memory set,
        uint256 k
    ) internal pure returns (uint8[][] memory combinations) {
        uint256 n = set.length;
        if (n < k) revert InvalidChoose(n, k);

        combinations = genCombinationIndices(n, k);
        uint256 c = combinations.length;
        for (uint256 i; i < c; ++i) {
            for (uint256 j; j < k; ++j) {
                combinations[i][j] = set[combinations[i][j]];
            }
        }
    }
}
