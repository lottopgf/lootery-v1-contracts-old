// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

library BitSet {
    function from(uint8[] memory arr) internal pure returns (uint256 out) {
        uint256 n = arr.length;
        for (uint256 i; i < n; ++i) {
            out |= uint256(1) << uint256(arr[i]);
        }
    }

    function set(uint256 x, uint8 i) internal pure returns (uint256 out) {
        assembly {
            out := or(x, shl(i, 1))
        }
    }

    function unset(uint256 x, uint8 i) internal pure returns (uint256 out) {
        assembly {
            out := and(x, shl(i, 1))
        }
    }

    function has(uint256 x, uint8 i) internal pure returns (bool out) {
        assembly {
            out := and(1, shr(i, x))
        }
    }

    function intersection(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256 out) {
        assembly {
            out := and(a, b)
        }
    }

    function union(uint256 a, uint256 b) internal pure returns (uint256 out) {
        assembly {
            out := or(a, b)
        }
    }

    /// @notice Brian Kernighan's popcount algorithm
    /// @dev Returns the number of set bits in `x`.
    function popcnt(uint256 x) internal pure returns (uint256 c) {
        assembly {
            for {

            } iszero(iszero(x)) {

            } {
                x := and(x, sub(x, 1))
                c := add(c, 1)
            }
        }
    }
}
