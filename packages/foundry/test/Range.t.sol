// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { InvalidRange, OutsideRange, Range, RangeOps } from "../contracts/Range.sol";

using RangeOps for Range;

contract RangeTest is Test {

    function setUp() public {
    }

    function testFuzz_isValid(Range calldata range) public pure {
        if (range.isMinBounded && range.isMaxBounded) {
            if (range.min <= range.max) {
                assert(range.isValid());
            } else {
                assert(!range.isValid());
            }
        } else {
            assert(range.isValid());
        }
    }

    function testFuzz_contains(Range calldata range, uint256 value) public {
    }
}
