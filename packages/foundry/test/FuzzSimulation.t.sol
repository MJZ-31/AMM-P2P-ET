// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { UD60x18, convert, ud } from "@prb/math/src/UD60x18.sol";

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { EnergyAMM } from "../contracts/EnergyAMM.sol";
import { ERC20Ownable } from "../contracts/ERC20Ownable.sol";
import { Range, RangeOps } from "../contracts/Range.sol";

using RangeOps for Range;

contract FuzzSimulation is Test {
    address owner;
    address[] liquidityProviders;
    address[] traders;

    ERC20Ownable MToken;
    ERC20Ownable EToken;
    EnergyAMM AMM;

    function testFuzz_simulation(uint256 seed) public {
        vm.setSeed(seed);

        // Initialize wallets.
        owner = vm.randomAddress();
        uint256 liquidityProviderNumber = vm.randomUint(1, 10);
        for (uint256 iLiquidityProviders = 0; iLiquidityProviders < liquidityProviderNumber; ++iLiquidityProviders) {
            liquidityProviders.push(vm.randomAddress());
        }
        uint256 traderNumber = vm.randomUint(1, 10);
        for (uint256 iTraders = 0; iTraders < traderNumber; ++iTraders) {
            traders.push(vm.randomAddress());
        }

        vm.startPrank(owner);
        // Create contracts.
        EToken = new ERC20Ownable("EToken", "ETK", uint8(vm.randomUint(0, 25)));
        MToken = new ERC20Ownable("MToken", "MTK", uint8(vm.randomUint(0, 25)));
        AMM = new EnergyAMM(IERC20Metadata(EToken), IERC20Metadata(MToken));

        // Fund wallets.
        for (uint256 iLiquidityProviders = 0; iLiquidityProviders < liquidityProviders.length; ++iLiquidityProviders) {
            EToken.mint(liquidityProviders[iLiquidityProviders], 1e35);
            MToken.mint(liquidityProviders[iLiquidityProviders], 1e35);
        }
        for (uint256 iTraders = 0; iTraders < traders.length; ++iTraders) {
            EToken.mint(traders[iTraders], 1e35);
            MToken.mint(traders[iTraders], 1e35);
        }

        // Configure AMM.
        AMM.setFeeRate(ud(vm.randomUint(0, 1e18)));
        console.log("Fee Rate: %e", AMM.feeRate().unwrap());

        Range memory swapPriceRange;
        swapPriceRange.min = vm.randomUint(0, 1e18);
        swapPriceRange.max = vm.randomUint(swapPriceRange.min, 1e25);
        uint8 curveType = uint8(vm.randomUint(1, 5));
        if (curveType == 1) {
            swapPriceRange.min = (swapPriceRange.min + swapPriceRange.max) / 2;
            swapPriceRange.max = swapPriceRange.min;
            swapPriceRange.isMinBounded = true;
            swapPriceRange.isMaxBounded = true;

            console.log("Curve Type: CSMM");
        } else if (curveType == 2) {
            swapPriceRange.isMinBounded = false;
            swapPriceRange.isMaxBounded = false;

            console.log("Curve Type: CPMM");
        } else if (curveType == 3) {
            if (swapPriceRange.min == swapPriceRange.max) {
                swapPriceRange.min = swapPriceRange.max - 1;
            }
            swapPriceRange.isMinBounded = true;
            swapPriceRange.isMaxBounded = true;

            console.log("Curve Type: CLMM");
        } else if (curveType == 4) {
            swapPriceRange.isMinBounded = true;
            swapPriceRange.isMaxBounded = false;

            console.log("Curve Type: CLMM_PARTIAL_MIN");
        } else if (curveType == 5) {
            swapPriceRange.isMinBounded = false;
            swapPriceRange.isMaxBounded = true;

            console.log("Curve Type: CLMM_PARTIAL_MAX");
        } else {
            vm.assertTrue(false, "Unknown curve type.");
        }
        AMM.setSwapPriceRange(swapPriceRange);
        vm.stopPrank();
        console.log("Swap Price Range: [%e, %e]", AMM.swapPriceRange().isMinBounded ? AMM.swapPriceRange().min : 0,
                    AMM.swapPriceRange().isMaxBounded ? AMM.swapPriceRange().max : type(uint256).max);

        // Run iterations. On each iteration, select a random liquidity provider or trader and have them execute a
        // random operation on the AMM. If the selected operation isn't possible, skip the iteration.
        uint256 opCount = 0;
        uint256 swapCount = 0;
        uint256 buyCount = 0;
        uint256 sellCount = 0;
        uint256 liquidityCount = 0;
        uint256 addCount = 0;
        uint256 removeCount = 0;

        for (uint256 iteration = 0; iteration < 100; ++iteration) {
            bool liquidityOrSwap = vm.randomBool();
            if (iteration == 0) {
                liquidityOrSwap = true;
            }
            if (liquidityOrSwap) {
                address liquidityProvider = liquidityProviders[vm.randomUint(0, liquidityProviders.length - 1)];

                bool addOrRemove = vm.randomBool();
                if (iteration == 0) {
                    addOrRemove = true;
                }
                if (addOrRemove) {
                    uint256 LAmount = vm.randomUint(
                        0, Math.sqrt(EToken.balanceOf(liquidityProvider) * MToken.balanceOf(liquidityProvider)) / 2
                    );

                    (uint256 LShare, uint256 ELiq, uint256 MLiq) = AMM.liquidityProvision(LAmount);
                    if (LShare == 0 || ELiq == 0 || MLiq == 0) {
                        continue;
                    }
                    if (ELiq > EToken.balanceOf(liquidityProvider) || MLiq > MToken.balanceOf(liquidityProvider)) {
                        continue;
                    }

                    vm.startPrank(liquidityProvider);
                    EToken.approve(address(AMM), ELiq);
                    MToken.approve(address(AMM), MLiq);
                    AMM.addLiquidity(LAmount);
                    vm.stopPrank();

                    ++liquidityCount;
                    ++addCount;

                    console.log("%s Added %e E-Tokens and %e M-Tokens", liquidityProvider, ELiq, MLiq);
                } else {
                    uint256 LAmount = vm.randomUint(0, AMM.LToken().balanceOf(liquidityProvider));

                    (uint256 LShare, uint256 ELiq, uint256 MLiq) = AMM.liquidityReduction(LAmount);
                    if (LShare == 0 || ELiq == 0 || MLiq == 0) {
                        continue;
                    }

                    vm.startPrank(liquidityProvider);
                    AMM.removeLiquidity(LAmount);
                    vm.stopPrank();

                    ++liquidityCount;
                    ++removeCount;

                    console.log("%s Removed %e E-Tokens and %e M-Tokens", liquidityProvider, ELiq, MLiq);
                }

            } else {
                address trader = traders[vm.randomUint(0, traders.length - 1)];

                bool buyOrSell = vm.randomBool();
                if (buyOrSell) {
                    Range memory bidRange = AMM.bidRange();
                    if (!bidRange.isValid()) {
                        continue;
                    }
                    uint256 EAmount = vm.randomUint(
                        bidRange.isMinBounded ? bidRange.min : 0,
                        bidRange.isMaxBounded ? bidRange.max : type(uint256).max
                    );

                    (uint256 ESwap, uint256 MSwap) = AMM.bidSwap(EAmount);
                    if (ESwap == 0 || MSwap == 0) {
                        continue;
                    }

                    uint256 MFee = AMM.bidFee(EAmount);
                    if (MSwap + MFee > MToken.balanceOf(trader)) {
                        continue;
                    }

                    vm.startPrank(trader);
                    MToken.approve(address(AMM), MSwap + MFee);
                    AMM.buy(EAmount);
                    vm.stopPrank();

                    ++swapCount;
                    ++buyCount;

                    console.log("%s Bought %e E-Tokens for %e M-Tokens", trader, ESwap, MSwap);
                } else {
                    Range memory askRange = AMM.askRange();
                    if (!askRange.isValid()) {
                        continue;
                    }
                    uint256 EAmount = vm.randomUint(
                        askRange.isMinBounded ? askRange.min : 0,
                        askRange.isMaxBounded ? askRange.max : type(uint256).max
                    );

                    (uint256 ESwap, uint256 MSwap) = AMM.askSwap(EAmount);
                    if (ESwap == 0 || MSwap == 0) {
                        continue;
                    }

                    if (ESwap > EToken.balanceOf(trader)) {
                        continue;
                    }

                    vm.startPrank(trader);
                    EToken.approve(address(AMM), ESwap);
                    AMM.sell(EAmount);
                    vm.stopPrank();

                    ++swapCount;
                    ++sellCount;

                    console.log("%s Sold %e E-Tokens %e M-Tokens", trader, ESwap, MSwap);
                }
            }

            ++opCount;
        }

        console.log("%d Operations", opCount);
        console.log("  %d Swaps", swapCount);
        console.log("    %d Buys", buyCount);
        console.log("    %d Sells", sellCount);
        console.log("  %d Liquidity Operations", liquidityCount);
        console.log("    %d Additions", addCount);
        console.log("    %d Removals", removeCount);
    }
}
