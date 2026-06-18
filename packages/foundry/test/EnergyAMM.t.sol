// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UD60x18, convert, ud } from "@prb/math/src/UD60x18.sol";

import { Test } from "forge-std/Test.sol";
import { EnergyAMM } from "../contracts/EnergyAMM.sol";
import { ERC20Ownable } from "../contracts/ERC20Ownable.sol";
import { Range, RangeOps } from "../contracts/Range.sol";

using RangeOps for Range;

contract EnergyAMMTest is Test {
    address owner;
    address liquidityProvider1;
    address liquidityProvider2;
    address trader;

    ERC20Ownable MToken;
    ERC20Ownable EToken;
    EnergyAMM AMM;

    function clampRange(uint256 value, Range memory range) private returns (uint256) {
        if (!range.isValid()) {
            return value;
        }

        if (range.isMinBounded && range.isMaxBounded) {
            return value % (range.max - (range.min - 1)) + range.min;
        }
        if (range.isMinBounded) {
            return value % (0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - (range.min - 1)) +
                range.min;
        }
        if (range.isMaxBounded) {
            return value % range.max;
        }
    }

    function setUp() public {
        owner = vm.randomAddress();    
        liquidityProvider1 = vm.randomAddress();    
        liquidityProvider2 = vm.randomAddress();    
        trader = vm.randomAddress();    

        uint8 EDecimals = uint8(vm.randomUint() % 15 + 6);
        uint8 MDecimals = uint8(vm.randomUint() % 15 + 6);

        vm.startPrank(owner);
        EToken = new ERC20Ownable("EToken", "ETK", EDecimals);
        MToken = new ERC20Ownable("MToken", "MTK", MDecimals);
        AMM = new EnergyAMM(EToken, MToken);

        EToken.mint(liquidityProvider1, 1e25);
        MToken.mint(liquidityProvider1, 1e25);
        EToken.mint(liquidityProvider2, 1e25);
        MToken.mint(liquidityProvider2, 1e25);
        EToken.mint(trader, 1e25);
        MToken.mint(trader, 1e25);
        vm.stopPrank();

        Range memory poolPriceRange;
        poolPriceRange.max = vm.randomUint() % (1e25 - 1e17) + 1e17;
        poolPriceRange.min = vm.randomUint() % (poolPriceRange.max - 1e10) + 1e10;
        poolPriceRange.isMinBounded = vm.randomBool();
        poolPriceRange.isMaxBounded = vm.randomBool();

        vm.prank(owner);
        AMM.setPoolPriceRange(poolPriceRange);

        UD60x18 feeRate = ud(vm.randomUint() % 1e18);

        vm.prank(owner);
        AMM.setFeeRate(feeRate);

        uint256 ELiq = vm.randomUint() % EToken.balanceOf(liquidityProvider1);
        uint256 MLiq = vm.randomUint() % MToken.balanceOf(liquidityProvider1);
        UD60x18 proportion = ud(vm.randomUint() % 1e18);
        uint256 ELiq1 = ELiq * proportion.unwrap() / 1e18;
        uint256 MLiq1 = MLiq * proportion.unwrap() / 1e18;
        uint256 ELiq2 = ELiq - ELiq1;
        uint256 MLiq2 = MLiq - MLiq1;
        (, ELiq1, MLiq1) = AMM.liquidityProvision(ELiq1, MLiq1);
        (, ELiq2, MLiq2) = AMM.liquidityProvision(ELiq2, MLiq2);

        vm.startPrank(liquidityProvider1);
        EToken.approve(address(AMM), ELiq1);
        MToken.approve(address(AMM), MLiq1);
        AMM.addLiquidity(ELiq1, MLiq1);
        vm.stopPrank();

        vm.startPrank(liquidityProvider2);
        EToken.approve(address(AMM), ELiq2);
        MToken.approve(address(AMM), MLiq2);
        AMM.addLiquidity(ELiq2, MLiq2);
        vm.stopPrank();
    }

    function testFuzz_EToken() public {
        assertEq(address(AMM.EToken()), address(EToken));
    }

    function testFuzz_MToken() public {
        assertEq(address(AMM.MToken()), address(MToken));
    }

    function testFuzz_LToken() public {
        assertNotEq(address(AMM.LToken()), address(0));
    }

    function testFuzz_EReserve() public {
        assertEq(AMM.EReserve(), AMM.EToken().balanceOf(address(AMM)));
    }

    function testFuzz_MReserve() public {
        assertEq(AMM.MReserve(), AMM.MToken().balanceOf(address(AMM)));
    }

    function testFuzz_poolPriceRange() public {
        assert(AMM.poolPriceRange().isValid());
    }

    function testFuzz_poolPrice() public {
        assert(AMM.poolPriceRange().contains(AMM.poolPrice().unwrap()));
    }

    function testFuzz_bidSwap(uint256 EAmount) public {
        Range memory bidRange = AMM.bidRange();
        EAmount = clampRange(EAmount, bidRange);
        (uint256 ESwap, uint256 MSwap) = AMM.bidSwap(EAmount);
        assert((ESwap == 0 && MSwap == 0) || (ESwap != 0 && MSwap != 0));
    }

    function testFuzz_askSwap(uint256 EAmount) public {
        Range memory askRange = AMM.askRange();
        EAmount = clampRange(EAmount, askRange);
        (uint256 ESwap, uint256 MSwap) = AMM.askSwap(EAmount);
        assert((ESwap == 0 && MSwap == 0) || (ESwap != 0 && MSwap != 0));
    }

    function testFuzz_bidPrice(uint256 EAmount) public {
        Range memory bidRange = AMM.bidRange();
        if (bidRange.isValid()) {
            EAmount = clampRange(EAmount, bidRange);
            UD60x18 bidPrice = AMM.bidPrice(EAmount);
            if (bidPrice != convert(0)) {
                assert(AMM.poolPriceRange().contains(bidPrice.unwrap()));
            }
        }
    }

    function testFuzz_askPrice(uint256 EAmount) public {
        Range memory askRange = AMM.askRange();
        if (askRange.isValid()) {
            EAmount = clampRange(EAmount, askRange);
            UD60x18 askPrice = AMM.askPrice(EAmount);
            if (askPrice != convert(0)) {
                assert(AMM.poolPriceRange().contains(askPrice.unwrap()));
            }
        }
    }
}
