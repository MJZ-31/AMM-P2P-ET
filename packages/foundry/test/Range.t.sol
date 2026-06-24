// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Test } from "forge-std/Test.sol";
import { InvalidRange, OutsideRange, Range, RangeOps } from "../contracts/Range.sol";

using RangeOps for Range;

contract RangeTest is Test {

    function setUp() public {
    }

    function testFuzz_isValid(Range calldata range) public pure {
        if (!range.isMinBounded || !range.isMaxBounded) {
            assert(range.isValid());
        } else {
            if (range.min <= range.max) {
                assert(range.isValid());
            } else {
                assert(!range.isValid());
            }
        }
    }

    function testFuzz_contains(Range calldata range, uint256 value) public pure {
        if (range.isValid()) {
            if (range.isMinBounded && range.isMaxBounded) {
                if (range.min <= value && value <= range.max) {
                    assert(range.contains(value));
                } else {
                    assert(!range.contains(value));
                }
            } else if (range.isMinBounded && !range.isMaxBounded) {
                if (range.min <= value) {
                    assert(range.contains(value));
                } else {
                    assert(!range.contains(value));
                }
            } else if (!range.isMinBounded && range.isMaxBounded) {
                if (value <= range.max) {
                    assert(range.contains(value));
                } else {
                    assert(!range.contains(value));
                }
            } else if (!range.isMinBounded && !range.isMaxBounded) {
                assert(range.contains(value));
            }
        } else {
            assert(!range.contains(value));
        }
    }

    function testFuzz_intersect(Range calldata range1, Range calldata range2) public {
        Range memory intersect = RangeOps.intersect(range1, range2);
        if (!range1.isValid() || !range2.isValid()) {
            assert(!intersect.isValid());
        }
        if (range1.isMinBounded || range2.isMinBounded) {
            assert(intersect.isMinBounded);
        }
        if (range1.isMaxBounded || range2.isMaxBounded) {
            assert(intersect.isMaxBounded);
        }
        if (intersect.isMinBounded) {
            assertEq(intersect.min, Math.max(range1.min, range2.min));
        }
        if (intersect.isMaxBounded) {
            assertEq(intersect.max, Math.min(range1.max, range2.max));
        }
    }
}
