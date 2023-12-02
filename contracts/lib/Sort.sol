// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

library Sort {
    /// @notice Sort a small array (insertion sort -> O(n^2))
    /// @param unsorted Potentially unsorted array to be sorted inplace
    function sort(
        uint8[] memory unsorted
    ) internal pure returns (uint8[] memory) {
        uint256 len = unsorted.length;
        for (uint256 i = 1; i < len; ++i) {
            uint8 curr = unsorted[i];
            uint256 j = i - 1;
            for (; curr < unsorted[j] && j >= 0; --j) {
                unsorted[j + 1] = unsorted[j];
            }
            unsorted[j + 1] = curr;
        }
        return unsorted;
    }
}
