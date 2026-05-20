// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { UD60x18, convert, powu, ud } from "@prb/math/src/UD60x18.sol";

import { tokToUD, UDToTok } from "../contracts/Conversions.sol";
import { ERC20Ownable } from "../contracts/ERC20Ownable.sol";
import { EnergyAMM, BidOutsideRange, AskOutsideRange } from "../contracts/EnergyAMM.sol";

using { tokToUD } for uint256;
using { UDToTok } for UD60x18;

contract EnergyAMMTest is Test {
    address owner;
    address liquidityProvider;
    address trader;

    ERC20Ownable MToken;
    ERC20Ownable EToken;
    EnergyAMM AMM;

    function setUp() public {
        owner = vm.randomAddress();
        liquidityProvider = vm.randomAddress();
        trader = vm.randomAddress();

        vm.startPrank(owner);
        MToken = new ERC20Ownable("MToken", "MTK", 18);
        EToken = new ERC20Ownable("EToken", "ETK", 18);
        AMM = new EnergyAMM(MToken, EToken);

        MToken.mint(liquidityProvider, 10000 * 10 ** MToken.decimals());
        EToken.mint(liquidityProvider, 10000 * 10 ** EToken.decimals());
        MToken.mint(trader, 10000 * 10 ** MToken.decimals());
        EToken.mint(trader, 10000 * 10 ** EToken.decimals());
        vm.stopPrank();
    }

    function testFuzz_MReserve(uint256 EAmount) public {
        vm.startPrank(owner);
        AMM.setPoolPriceBounds(ud(0.5e18), convert(2));
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(EAmount);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        assertEq(AMM.MReserve(), AMM.MToken().balanceOf(address(AMM)));
    }

    function testFuzz_EReserve(uint256 EAmount) public {
        vm.startPrank(owner);
        AMM.setPoolPriceBounds(ud(0.5e18), convert(2));
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(EAmount);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        assertEq(AMM.EReserve(), AMM.EToken().balanceOf(address(AMM)));
    }

    function testFuzz_poolPrice(
        uint256 EAmount,
        UD60x18 poolPriceLowerBound,
        UD60x18 poolPriceUpperBound,
        bool buyOrSell
    ) public {
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        vm.prank(owner);
        AMM.openTrading();

        vm.startPrank(trader);
        if (buyOrSell) {
            vm.assumeNoRevert();
            (uint256 MSwap,) = AMM.bidSwap(EAmount);

            vm.assumeNoRevert();
            uint256 MFee = AMM.bidFee(EAmount);

            vm.assumeNoRevert();
            MToken.approve(address(AMM), MSwap + MFee);

            vm.assumeNoRevert();
            AMM.buy(EAmount);
        } else {
            vm.assumeNoRevert();
            (, uint256 ESwap) = AMM.askSwap(EAmount);

            vm.assumeNoRevert();
            EToken.approve(address(AMM), ESwap);

            vm.assumeNoRevert();
            AMM.sell(EAmount);
        }
        vm.stopPrank();

        assertEq(
            AMM.poolPrice().unwrap(),
            ((AMM.MReserve() + AMM.MVirtual()).tokToUD(AMM.MToken())
                    / (AMM.EReserve() + AMM.EVirtual()).tokToUD(AMM.EToken()))
            .unwrap()
        );
        assert(AMM.poolPriceBoundLower() <= AMM.poolPrice());
        assert(AMM.poolPrice() <= AMM.poolPriceBoundUpper());
    }

    function testFuzz_bidSwap(uint256 EAmount, UD60x18 poolPriceLowerBound, UD60x18 poolPriceUpperBound) public {       
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        vm.startPrank(trader);
        vm.assumeNoRevert();
        (uint256 MSwap, uint256 ESwap) = AMM.bidSwap(EAmount);
        vm.stopPrank();

        assert((MSwap == 0 && ESwap == 0) || (MSwap > 0 && ESwap > 0));
        if (MSwap > 0 && ESwap > 0) {
            assert(
                MSwap
                    == (powu(AMM.liquidity(), 2) / (AMM.EReserve() + AMM.EVirtual() - ESwap).tokToUD(EToken)
                            - (AMM.MReserve() + AMM.MVirtual()).tokToUD(MToken))
                    .UDToTok(MToken)
            );
        }
    }

    function testFuzz_bidSwapOutSideRange(uint256 EAmount, UD60x18 poolPriceLowerBound, UD60x18 poolPriceUpperBound)
        public
    {
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        (uint256 EMin, uint256 EMax) = AMM.bidRange();
        vm.assume(EAmount < EMin || EAmount > EMax);

        vm.startPrank(trader);
        vm.expectRevert(abi.encodeWithSelector(BidOutsideRange.selector, EMin, EMax, EAmount), address(AMM), 1);
        AMM.bidSwap(EAmount);
        vm.stopPrank();
    }

    function testFuzz_askSwap(uint256 EAmount, UD60x18 poolPriceLowerBound, UD60x18 poolPriceUpperBound) public {
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        vm.startPrank(trader);
        vm.assumeNoRevert();
        (uint256 MSwap, uint256 ESwap) = AMM.askSwap(EAmount);
        vm.stopPrank();

        assert((MSwap == 0 && ESwap == 0) || (MSwap > 0 && ESwap > 0));
        if (MSwap > 0 && ESwap > 0) {
            assert(
                MSwap
                    == ((AMM.MReserve() + AMM.MVirtual()).tokToUD(MToken) - powu(AMM.liquidity(), 2)
                            / (AMM.EReserve() + AMM.EVirtual() + ESwap).tokToUD(EToken))
                    .UDToTok(MToken)
            );
        }
    }

    function testFuzz_askSwapOutSideRange(uint256 EAmount, UD60x18 poolPriceLowerBound, UD60x18 poolPriceUpperBound)
        public
    {
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        (uint256 EMin, uint256 EMax) = AMM.askRange();
        vm.assume(EAmount < EMin || EAmount > EMax);

        vm.startPrank(trader);
        vm.expectRevert(abi.encodeWithSelector(AskOutsideRange.selector, EMin, EMax, EAmount), address(AMM), 1);
        AMM.askSwap(EAmount);
        vm.stopPrank();
    }

    function testFuzz_bidFee(uint256 EAmount, UD60x18 feeRate, UD60x18 poolPriceLowerBound, UD60x18 poolPriceUpperBound)
        public
    {
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.setFeeRate(feeRate);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        vm.startPrank(trader);
        vm.assumeNoRevert();
        (uint256 MSwap,) = AMM.bidSwap(EAmount);
        vm.assumeNoRevert();
        uint256 MFee = AMM.bidFee(EAmount);
        vm.stopPrank();

        assertEq(MFee, (MSwap.tokToUD(MToken) * feeRate).UDToTok(MToken));
    }

    function testFuzz_askFee(uint256 EAmount, UD60x18 feeRate, UD60x18 poolPriceLowerBound, UD60x18 poolPriceUpperBound)
        public
    {
        vm.startPrank(owner);
        vm.assumeNoRevert();
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.setFeeRate(feeRate);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        vm.assumeNoRevert();
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(10 ** 21);

        vm.assumeNoRevert();
        MToken.approve(address(AMM), MLiq);

        vm.assumeNoRevert();
        EToken.approve(address(AMM), ELiq);

        vm.assumeNoRevert();
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        vm.startPrank(trader);
        vm.assumeNoRevert();
        (uint256 MSwap,) = AMM.askSwap(EAmount);
        vm.assumeNoRevert();
        uint256 MFee = AMM.askFee(EAmount);
        vm.stopPrank();

        (uint256 MSwapWithoutFee,) = AMM.askSwap((EAmount.tokToUD(EToken) * (convert(1) - feeRate)).UDToTok(EToken));

        assertEq(MSwap - MFee, MSwapWithoutFee);
    }
}
