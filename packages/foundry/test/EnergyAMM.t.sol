// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { UD60x18, convert, ud } from "@prb/math/src/UD60x18.sol";

import { Test } from "forge-std/Test.sol";
import { EnergyAMM } from "../contracts/EnergyAMM.sol";
import { ERC20Ownable } from "../contracts/ERC20Ownable.sol";
import { Range, RangeOps } from "../contracts/Range.sol";

using RangeOps for Range;

contract EnergyAMMTest is Test {
    address owner;
    address liquidityProvider;
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
        liquidityProvider = vm.randomAddress();    
        trader = vm.randomAddress();    

        uint8 EDecimals = uint8(vm.randomUint() % 15 + 6);
        uint8 MDecimals = uint8(vm.randomUint() % 15 + 6);

        vm.startPrank(owner);
        EToken = new ERC20Ownable("EToken", "ETK", EDecimals);
        MToken = new ERC20Ownable("MToken", "MTK", MDecimals);
        AMM = new EnergyAMM(EToken, MToken);

        EToken.mint(liquidityProvider, 1e25);
        MToken.mint(liquidityProvider, 1e25);
        EToken.mint(trader, 1e25);
        MToken.mint(trader, 1e25);
        vm.stopPrank();

        Range memory swapPriceRange;
        swapPriceRange.max = vm.randomUint() % (1e25 - 1e17) + 1e17;
        swapPriceRange.min = vm.randomUint() % swapPriceRange.max;
        swapPriceRange.isMinBounded = vm.randomBool();
        swapPriceRange.isMaxBounded = vm.randomBool();

        vm.prank(owner);
        AMM.setSwapPriceRange(swapPriceRange);

        UD60x18 feeRate = ud(vm.randomUint() % 1e18);

        vm.prank(owner);
        AMM.setFeeRate(feeRate);

        uint256 LAmount = vm.randomUint() % 1e25;
        (, uint256 ELiq, uint256 MLiq) = AMM.liquidityProvision(LAmount);

        vm.startPrank(liquidityProvider);
        EToken.approve(address(AMM), ELiq);
        MToken.approve(address(AMM), MLiq);
        AMM.addLiquidity(LAmount);
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

    function testFuzz_liquidity() public {
        assertEq(AMM.liquidity(), AMM.LToken().totalSupply());
    }

    function testFuzz_swapPriceRange() public {
        assert(AMM.swapPriceRange().isValid());
    }

    function testFuzz_poolPrice() public {
        Range memory swapPriceRange = AMM.swapPriceRange();
        if (swapPriceRange.min != swapPriceRange.max) {
            assertEq(AMM.poolPrice().unwrap(), AMM.MReserve() * 1e18 / AMM.EReserve());
        }
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
                assert(AMM.swapPriceRange().contains(bidPrice.unwrap()));
            }
        }
    }

    function testFuzz_askPrice(uint256 EAmount) public {
        Range memory askRange = AMM.askRange();
        if (askRange.isValid()) {
            EAmount = clampRange(EAmount, askRange);
            UD60x18 askPrice = AMM.askPrice(EAmount);
            if (askPrice != convert(0)) {
                assert(AMM.swapPriceRange().contains(askPrice.unwrap()));
            }
        }
    }

    function testFuzz_buy(uint256 EAmount) public {
        Range memory bidRange = AMM.bidRange();
        if (bidRange.isValid()) {
            EAmount = EAmount % 1e20;
            EAmount = clampRange(EAmount, bidRange);
            (uint256 ESwap, uint256 MSwap) = AMM.bidSwap(EAmount);
            uint256 MFee = AMM.bidFee(EAmount);
            vm.assume(MSwap + MFee < MToken.balanceOf(trader));
            if (ESwap != 0 && MSwap != 0) {
                vm.startPrank(trader);
                MToken.approve(address(AMM), MSwap + MFee);
                AMM.buy(EAmount);
                vm.stopPrank();
            }
        }
    }

    function testFuzz_sell(uint256 EAmount) public {
        Range memory askRange = AMM.askRange();
        if (askRange.isValid()) {
            EAmount = EAmount % EToken.balanceOf(trader);
            EAmount = clampRange(EAmount, askRange);
            (uint256 ESwap, uint256 MSwap) = AMM.askSwap(EAmount);
            if (ESwap != 0 && MSwap != 0) {
                vm.startPrank(trader);
                EToken.approve(address(AMM), ESwap);
                AMM.sell(EAmount);
                vm.stopPrank();
            }
        }
    }

    function testFuzz_liquidityProvision(uint256 LAmount) public {
        LAmount = LAmount % 1e25;
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = AMM.liquidityProvision(LAmount);

        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            assertEq(LShare, 0);
            assertEq(ELiq, 0);
            assertEq(MLiq, 0);
        } else {
            assertEq(LShare, LAmount);
            assertEq(AMM.liquidity() + LShare, Math.sqrt((AMM.EReserve() + ELiq) * (AMM.MReserve() + MLiq)));
        }
    }

    function testFuzz_liquidityReduction(uint256 LAmount) public {
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = AMM.liquidityReduction(LAmount);
        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            assertEq(LShare, 0);
            assertEq(ELiq, 0);
            assertEq(MLiq, 0);
        } else {
            if (LAmount > AMM.LToken().balanceOf(liquidityProvider)) {
                assertEq(LShare, AMM.LToken().balanceOf(liquidityProvider));
            } else {
                assertEq(LShare, LAmount);
            }
            assertEq(AMM.liquidity() - LShare, Math.sqrt((AMM.EReserve() - ELiq) * (AMM.MReserve() - MLiq)));
        }
    }

    function test_addRemoveLiquidity(uint256 LAmount) public {
        LAmount = LAmount % (Math.sqrt(EToken.balanceOf(liquidityProvider)) *
                             Math.sqrt(MToken.balanceOf(liquidityProvider)));

        uint256 LBalance = AMM.LToken().balanceOf(liquidityProvider);
        uint256 EBalance = AMM.EToken().balanceOf(liquidityProvider);
        uint256 MBalance = AMM.MToken().balanceOf(liquidityProvider);

        uint256 EReserve = AMM.EReserve();
        uint256 MReserve = AMM.MReserve();
        uint256 liquidity = AMM.liquidity();

        (uint256 LShareAdd, uint256 ELiqAdd, uint256 MLiqAdd) = AMM.liquidityProvision(LAmount);
        if (LShareAdd != 0 && ELiqAdd != 0 && MLiqAdd != 0) {
            vm.startPrank(liquidityProvider);
            EToken.approve(address(AMM), ELiqAdd);
            MToken.approve(address(AMM), MLiqAdd);
            AMM.addLiquidity(LAmount);
            vm.stopPrank();
        }

        (uint256 LShareRemove, uint256 ELiqRemove, uint256 MLiqRemove) = AMM.liquidityReduction(LAmount);
        if (LShareRemove != 0 && ELiqRemove != 0 && MLiqRemove != 0) {
            vm.startPrank(liquidityProvider);
            AMM.removeLiquidity(LAmount);
            vm.stopPrank();
        }

        assertEq(LShareAdd, LShareRemove);

        uint256 LBalanceNew = AMM.LToken().balanceOf(liquidityProvider);
        uint256 EBalanceNew = AMM.EToken().balanceOf(liquidityProvider);
        uint256 MBalanceNew = AMM.MToken().balanceOf(liquidityProvider);

        assertEq(LBalance, LBalanceNew);
        assertEq(EBalance, EBalanceNew);
        assertEq(MBalance, MBalanceNew);

        assertEq(EReserve, AMM.EReserve());
        assertEq(MReserve, AMM.MReserve());
        assertEq(liquidity, AMM.liquidity());
    }

    function testFuzz_addLiquidity(uint256 LAmount) public {
        LAmount = LAmount % (Math.sqrt(EToken.balanceOf(liquidityProvider)) *
                             Math.sqrt(MToken.balanceOf(liquidityProvider)));
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = AMM.liquidityProvision(LAmount);
        if (LShare != 0 && ELiq != 0 && MLiq != 0) {
            uint256 LBalance = AMM.LToken().balanceOf(liquidityProvider);
            uint256 EBalance = AMM.EToken().balanceOf(liquidityProvider);
            uint256 MBalance = AMM.MToken().balanceOf(liquidityProvider);

            vm.startPrank(liquidityProvider);
            EToken.approve(address(AMM), ELiq);
            MToken.approve(address(AMM), MLiq);
            AMM.addLiquidity(LAmount);
            vm.stopPrank();

            uint256 LBalanceNew = AMM.LToken().balanceOf(liquidityProvider);
            uint256 EBalanceNew = AMM.EToken().balanceOf(liquidityProvider);
            uint256 MBalanceNew = AMM.MToken().balanceOf(liquidityProvider);

            assertEq(LShare, LBalanceNew - LBalance);
            assertEq(ELiq, EBalance - EBalanceNew);
            assertEq(MLiq, MBalance - MBalanceNew);
        }
        assertEq(AMM.liquidity(), Math.sqrt(AMM.EReserve() * AMM.MReserve()));
    }

    function testFuzz_removeLiquidity(uint256 LAmount) public {
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = AMM.liquidityReduction(LAmount);
        if (LShare != 0 && ELiq != 0 && MLiq != 0) {
            uint256 LBalance = AMM.LToken().balanceOf(liquidityProvider);
            uint256 EBalance = AMM.EToken().balanceOf(liquidityProvider);
            uint256 MBalance = AMM.MToken().balanceOf(liquidityProvider);

            vm.startPrank(liquidityProvider);
            AMM.removeLiquidity(LAmount);
            vm.stopPrank();

            uint256 LBalanceNew = AMM.LToken().balanceOf(liquidityProvider);
            uint256 EBalanceNew = AMM.EToken().balanceOf(liquidityProvider);
            uint256 MBalanceNew = AMM.MToken().balanceOf(liquidityProvider);

            assertEq(LShare, LBalance - LBalanceNew);
            assertEq(ELiq, EBalanceNew - EBalance);
            assertEq(MLiq, MBalanceNew - MBalance);
        }
        assertEq(AMM.liquidity(), Math.sqrt(AMM.EReserve() * AMM.MReserve()));
    }
}
