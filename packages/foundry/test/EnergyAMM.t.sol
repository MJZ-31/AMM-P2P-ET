// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { UD60x18, convert, powu, sqrt, ud } from "@prb/math/src/UD60x18.sol";
import { SD59x18 } from "@prb/math/src/SD59x18.sol";

import { tokToUD, UDToTok } from "../contracts/Conversions.sol";
import { ERC20Ownable } from "../contracts/ERC20Ownable.sol";
import { EnergyAMM, BidOutsideRange, AskOutsideRange } from "../contracts/EnergyAMM.sol";

using { tokToUD } for uint256;
using { UDToTok } for UD60x18;

contract EnergyAMMTest is Test {
    UD60x18 immutable EPSILON = convert(1) / convert(10 ** 10);

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

        uint8 MDecimals = uint8(vm.randomUint() % 5 + 16);
        uint8 EDecimals = uint8(vm.randomUint() % 5 + 16);

        vm.startPrank(owner);
        MToken = new ERC20Ownable("MToken", "MTK", MDecimals);
        EToken = new ERC20Ownable("EToken", "ETK", EDecimals);
        AMM = new EnergyAMM(MToken, EToken);

        MToken.mint(liquidityProvider, 10000 * 10 ** MToken.decimals());
        EToken.mint(liquidityProvider, 10000 * 10 ** EToken.decimals());
        MToken.mint(trader, 10000 * 10 ** MToken.decimals());
        EToken.mint(trader, 10000 * 10 ** EToken.decimals());
        vm.stopPrank();

        uint256 EAmountLiq = vm.randomUint() % (EToken.balanceOf(liquidityProvider) / 2);
        uint256 EAmountTrade = vm.randomUint() % (EToken.balanceOf(trader) / 2);
        bool buyOrSell = vm.randomBool();
        UD60x18 poolPriceUpperBound = ud(vm.randomUint() % convert(1).unwrap());
        UD60x18 poolPriceLowerBound = ud(vm.randomUint() % poolPriceUpperBound.unwrap());
        UD60x18 feeRate = ud(vm.randomUint() % convert(1).unwrap());

        vm.startPrank(owner);
        AMM.setPoolPriceBounds(poolPriceLowerBound, poolPriceUpperBound);
        AMM.setFeeRate(feeRate);
        AMM.openLiquidityAddition();
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        (uint256 MLiq, uint256 ELiq) = AMM.liquidityProvision(EAmountLiq);

        MToken.approve(address(AMM), MLiq);
        EToken.approve(address(AMM), ELiq);
        AMM.addLiquidity(ELiq);
        vm.stopPrank();

        vm.startPrank(owner);
        AMM.closeLiquidityAddition();
        AMM.openTrading();
        vm.stopPrank();

        vm.startPrank(trader);
        if (buyOrSell) {
            (uint256 EMin, uint256 EMax) = AMM.bidRange();
            EAmountTrade = EAmountTrade % (EMax - EMin) + EMin;

            (uint256 MSwap,) = AMM.bidSwap(EAmountTrade);
            uint256 MFee = AMM.bidFee(EAmountTrade);
            MToken.approve(address(AMM), MSwap + MFee);

            AMM.buy(EAmountTrade);
        } else {
            (uint256 EMin, uint256 EMax) = AMM.askRange();
            EAmountTrade = EAmountTrade % (EMax - EMin) + EMin;

            (, uint256 ESwap) = AMM.askSwap(EAmountTrade);
            vm.assume(ESwap < EToken.balanceOf(trader) / 2);
            EToken.approve(address(AMM), ESwap);

            AMM.sell(EAmountTrade);
        }
        vm.stopPrank();

        vm.startPrank(owner);
        AMM.closeTrading();
        vm.stopPrank();
    }

    function test_MReserve() public {
        assertEq(AMM.MReserve(), AMM.MToken().balanceOf(address(AMM)));
    }

    function test_EReserve() public {
        assertEq(AMM.EReserve(), AMM.EToken().balanceOf(address(AMM)));
    }

    function test_poolPrice() public {
        assert(
            AMM.poolPrice()
                == (AMM.MReserve() + AMM.MVirtual()).tokToUD(AMM.MToken())
                    / (AMM.EReserve() + AMM.EVirtual()).tokToUD(AMM.EToken())
        );
        assert(AMM.poolPriceBoundLower() <= AMM.poolPrice());
        assert(AMM.poolPrice() <= AMM.poolPriceBoundUpper());
    }

    function testFuzz_bidSwap(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.bidRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        (uint256 MSwap, uint256 ESwap) = AMM.bidSwap(EAmount);

        assert((MSwap == 0 && ESwap == 0) || (MSwap > 0 && ESwap > 0));
        assertApproxEqAbsDecimal(
            AMM.liquidity().unwrap(),
            sqrt(
                    (AMM.MReserve() + AMM.MVirtual() + MSwap).tokToUD(MToken)
                        * (AMM.EReserve() + AMM.EVirtual() - ESwap).tokToUD(EToken)
                ).unwrap(),
            EPSILON.unwrap(),
            18
        );
    }

    function testFuzz_bidSwapOutsideRange(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.bidRange();
        vm.assume(EAmount < EMin || EAmount > EMax);

        vm.expectRevert(abi.encodeWithSelector(BidOutsideRange.selector, EMin, EMax, EAmount), address(AMM), 1);
        AMM.bidSwap(EAmount);
    }

    function testFuzz_askSwap(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.askRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        (uint256 MSwap, uint256 ESwap) = AMM.askSwap(EAmount);

        assert((MSwap == 0 && ESwap == 0) || (MSwap > 0 && ESwap > 0));
        assertApproxEqAbsDecimal(
            AMM.liquidity().unwrap(),
            sqrt(
                    (AMM.MReserve() + AMM.MVirtual() - MSwap).tokToUD(MToken)
                        * (AMM.EReserve() + AMM.EVirtual() + ESwap).tokToUD(EToken)
                ).unwrap(),
            EPSILON.unwrap(),
            18
        );
    }

    function testFuzz_askSwapOutsideRange(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.askRange();
        vm.assume(EAmount < EMin || EAmount > EMax);

        vm.expectRevert(abi.encodeWithSelector(AskOutsideRange.selector, EMin, EMax, EAmount), address(AMM), 1);
        AMM.askSwap(EAmount);
    }

    function testFuzz_bidFee(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.bidRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        (uint256 MSwap,) = AMM.bidSwap(EAmount);
        uint256 MFee = AMM.bidFee(EAmount);

        assertEq(MFee, (MSwap.tokToUD(MToken) * AMM.feeRate()).UDToTok(MToken));
    }

    function testFuzz_askFee(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.askRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        (uint256 MSwap,) = AMM.askSwap(EAmount);
        uint256 MFee = AMM.askFee(EAmount);

        (uint256 MSwapWithoutFee,) = AMM.askSwap((EAmount.tokToUD(EToken) * (convert(1) - AMM.feeRate())).UDToTok(EToken));

        assertEq(MSwap - MFee, MSwapWithoutFee);
    }

    function testFuzz_bidPrice(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.bidRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        (uint256 MSwap, uint256 ESwap) = AMM.bidSwap(EAmount);
        UD60x18 price = AMM.bidPrice(EAmount);

        if (MSwap.tokToUD(MToken) == ud(0) || ESwap.tokToUD(EToken) == ud(0)) {
            assertEqDecimal(price.unwrap(), 0, 18);
        } else {
            assertEqDecimal(price.unwrap(), (MSwap.tokToUD(MToken) / ESwap.tokToUD(EToken)).unwrap(), 18);
        }
    }

    function testFuzz_askPrice(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.askRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        (uint256 MSwap, uint256 ESwap) = AMM.askSwap(EAmount);
        UD60x18 price = AMM.askPrice(EAmount);

        if (MSwap.tokToUD(MToken) == ud(0) || ESwap.tokToUD(EToken) == ud(0)) {
            assertEqDecimal(price.unwrap(), 0, 18);
        } else {
            assertEqDecimal(price.unwrap(), (MSwap.tokToUD(MToken) / ESwap.tokToUD(EToken)).unwrap(), 18);
        }
    }

    function testFuzz_bidAskSpread(uint256 EAmount) public {
        (uint256 EMin, uint256 EMax) = AMM.askRange();
        EAmount = EAmount % (EMax - EMin) + EMin;

        UD60x18 bidPrice = AMM.bidPrice(EAmount);
        UD60x18 askPrice = AMM.askPrice(EAmount);
        SD59x18 bidAskSpread = AMM.bidAskSpread(EAmount);

        assertEqDecimal(bidAskSpread.unwrap(), (askPrice.intoSD59x18() - bidPrice.intoSD59x18()).unwrap(), 18);
    }
}
