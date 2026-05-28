// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @notice Thrown if an invalid range is used for an operation.
 * @param range The invalid range.
 */
error InvalidRange(Range range);

/**
 * @notice Thrown if an operation is attempted with a value outside of the allowable range.
 * @param range The allowable range.
 * @param value The value outside of the range.
 */
error OutsideRange(Range range, uint256 value);

/**
 * @notice A structure representing a range of possible uint256 values between a minimum and maximum. The minumum and
 * maximum can both be unbounded.
 */
struct Range {
    uint256 min;
    uint256 max;
    bool isMinUnbounded;
    bool isMaxUnbounded;
}

/**
 * @author Mitchel Justinen
 * @title A set of operations on a range.
 */
library RangeOps {
    /**
     * @notice Returns whether or not a range is valid. A range is invalid if its minimum is greater than its maximum. A
     * range is always valid if either the minimum or the maximum are unbounded.
     * @param range The range to check.
     * @return True if the range is valid, false if not.
     */
    function isValid(Range memory range) public pure returns (bool) {
        if (!range.isMinUnbounded && !range.isMaxUnbounded && range.min > range.max) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * @notice Returns whether or not a value is in a range.
     * @param range The range to check against.
     * @param value The value to check.
     * @return True if the value is in the range, false if not.
     */
    function contains(Range memory range, uint256 value) public pure returns (bool) {
        if (!isValid(range)) {
            return false;
        } else if (range.isMinUnbounded && range.isMaxUnbounded) {
            return true;
        } else if (range.isMinUnbounded && value <= range.max) {
            return true;
        } else if (range.isMaxUnbounded && range.min <= value) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice Returns the intersection of two ranges, which is the range where they overlap.
     * @param range1 One of the overlapping ranges.
     * @param range2 One of the overlapping ranges.
     * @return The intersection of the two ranges. If one of the given ranges is invalid, this will be an invalid range.
     * If the two ranges don't overlap, this will be an invalid range.
     */
    function intersect(Range memory range1, Range memory range2) public pure returns (Range memory) {
        Range memory out;

        out.isMinUnbounded = range1.isMinUnbounded && range2.isMinUnbounded;
        out.isMaxUnbounded = range1.isMaxUnbounded && range2.isMaxUnbounded;
        if (!out.isMinUnbounded) {
            out.min = Math.max(range1.min, range2.min);
        }
        if (!out.isMaxUnbounded) {
            out.max = Math.min(range1.max, range2.max);
        }

        return out;
    }

    /**
     * @notice Sets the minimum value of the range.
     * @param range The range to manipulate.
     * @param min The minimum.
     */
    function setMin(Range memory range, uint256 min) public {
        range.min = min;
        range.isMinUnbounded = false;
    }

    /**
     * @notice Sets the maximum value of the range.
     * @param range The range to manipulate.
     * @param max The maximum.
     */
    function setMax(Range memory range, uint256 max) public {
        range.max = max;
        range.isMinUnbounded = false;
    }

    /**
     * @notice Unbounds the range's minimum.
     * @param range The range to manipulate.
     */
    function unboundMin(Range memory range) public {
        range.isMinUnbounded = true;
    }

    /**
     * @notice Unbounds the range's maximum.
     * @param range The range to manipulate.
     */
    function unboundMax(Range memory range) public {
        range.isMaxUnbounded = true;
    }
}
