// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { SD59x18 } from "@prb/math/src/SD59x18.sol";
import { UD60x18, convert, inv, powu, sqrt, ud } from "@prb/math/src/UD60x18.sol";

import { tokToUD, UDToTok } from "./Conversions.sol";
import { ERC20Ownable } from "./ERC20Ownable.sol";
import {
    MarketStateChanged,
    InsufficientAllowance,
    ZeroTransfer,
    TradeInfo,
    LiquidityInfo,
    IEnergyAMM
} from "./IEnergyAMM.sol";
import { Range, RangeOps, InvalidRange, OutsideRange } from "./Range.sol";

using RangeOps for Range;
using { tokToUD } for uint256;
using { UDToTok } for UD60x18;

/**
 * @title An Automated Market Maker (AMM) for the trading of energy.
 * @author Mitchel Justinen
 * @notice This contract is responsible for maintaining a liquidity pool containing reserves of tokens representing
 * energy and money, and provides methods for trading, liquidity provision, and market regulation.
 */
contract EnergyAMM is Ownable, IEnergyAMM {
    /**
     * @dev An ERC20 token representing energy. The liquidity pool includes a balance of this token which is swapped
     * with traders.
     */
    IERC20Metadata private _EToken;

    /**
     * @dev An ERC20 token representing real currency. The liquidity pool includes a balance of this token which is
     * swapped with traders.
     */
    IERC20Metadata private _MToken;

    /**
     * @dev An ERC20 token representing liquidity shares.
     */
    ERC20Ownable private _LToken;

    /**
     * @dev The liquidity constant of the pricing curve.
     */
    uint256 private _liquidity;

    /**
     * @dev The amount of virtual ETokens in the liquidity pool. Virtual assets cannot leave the liquidity pool and
     * exist purely to force the pool price into a specified range.
     */
    uint256 private _EVirtual;

    /**
     * @dev The amount of virtual MTokens in the liquidity pool. Virtual assets cannot leave the liquidity pool and
     * exist purely to force the pool price into a specified range.
     */
    uint256 private _MVirtual;

    /**
     * @dev The range of possible pool prices.
     */
    Range private _poolPriceRangeX18;

    /**
     * @dev The range of possible pool prices, expressed as the square root of the pool price.
     */
    Range private _poolPriceSqrtRangeX18;

    /**
     * @dev The range possible bid amounts.
     */
    Range private _bidRange;

    /**
     * @dev The range possible ask amounts.
     */
    Range private _askRange;

    /**
     * @inheritdoc IEnergyAMM
     */
    UD60x18 public feeRate;

    /**
     * @dev Functions with this modifier will recalculate the liquidity of the market after it executes.
     */
    modifier liquidityShift() {
        _;

        _liquidity = _calculateLiquidity(this.EReserve(), this.MReserve(), _poolPriceSqrtRangeX18);
        _EVirtual = _calculateEVirtual(_liquidity, _poolPriceSqrtRangeX18);
        _MVirtual = _calculateMVirtual(_liquidity, _poolPriceSqrtRangeX18);
    }

    constructor(IERC20Metadata EToken_, IERC20Metadata MToken_) Ownable(msg.sender) {
        require(address(EToken_) != address(0), "Invalid EToken contract address");
        require(address(MToken_) != address(0), "Invalid MToken contract address");
        require(address(EToken_) != address(MToken_), "EToken and MToken contract addresses must be different");

        _EToken = EToken_;
        _MToken = MToken_;
        _LToken = new ERC20Ownable("EnergyAMM Liquidity Token", "ELIQ", EToken_.decimals());

        _liquidity = 0;
        _EVirtual = 0;
        _MVirtual = 0;

        feeRate = ud(0);
    }

    /**
     * @dev Returns the liquidity of the market given the market reserve amounts and the pool price range.
     * @param EReserve_ The amount of ETokens in reserve.
     * @param MReserve_ The amount of MTokens in reserve.
     * @param poolPriceSqrtRangeX18_ The range of possible pool prices, expressed as the square root of the pool price.
     * @return The liquidity of the market.
     */
    function _calculateLiquidity(uint256 EReserve_, uint256 MReserve_, Range storage poolPriceSqrtRangeX18_)
        internal
        view
        returns (uint256)
    {
        uint256 E = EReserve_;
        uint256 M = MReserve_;
        UD60x18 pLoS = ud(poolPriceSqrtRangeX18_.min);
        UD60x18 pHiS = ud(poolPriceSqrtRangeX18_.max);

        if (poolPriceSqrtRangeX18_.isMinBounded && poolPriceSqrtRangeX18_.isMaxBounded) {
            if (poolPriceSqrtRangeX18_.min == poolPriceSqrtRangeX18_.max) {
                // Pool price is bounded to a single value. Use the Constant Sum pricing curve.
                return E * powu(pLoS, 2).unwrap() / 1e18 + M;
            } else {
                // Pool price is bounded on both sides, but not to a single value. Use the Concentrated Liquidity pricing curve.
                UD60x18 a = convert(1) - pLoS / pHiS;
                uint256 v1 = E * pLoS.unwrap() / 1e18;
                uint256 v2 = M * 1e18 / pHiS.unwrap();
                uint256 b1 = v1 + v2;
                uint256 b2 = v1 > v2 ? v1 - v2 : v2 - v1;
                uint256 c = E * M;

                return (b1 + Math.sqrt(b2 ** 2 + 4 * c)) * 1e18 / (2 * a.unwrap());
            }
        } else if (poolPriceSqrtRangeX18_.isMinBounded) {
            // Pool price is bounded on only the low side. Use a partial Concentrated Liquidity pricing curve.
            uint256 b = E * pLoS.unwrap() / 1e18;
            uint256 c = E * M;

            return (b + Math.sqrt(b ** 2 + 4 * c)) / 2;
        } else if (poolPriceSqrtRangeX18_.isMaxBounded) {
            // Pool price is bounded on only the high side. Use a partial Concentrated Liquidity pricing curve.
            uint256 b = M * 1e18 / pHiS.unwrap();
            uint256 c = E * M;

            return (b + Math.sqrt(b ** 2 + 4 * c)) / 2;
        } else {
            // Pool price is unbounded. Use the Constant Product pricing curve.
            return Math.sqrt(E * M);
        }
    }

    /**
     * @dev Returns the amount of virtual ETokens in the market given the market liquidity and the pool price range.
     * @param liquidity_ The liquidity of the market.
     * @param poolPriceSqrtRangeX18_ The range of possible pool prices, expressed as the square root of the pool price.
     * @return The amount of virtual ETokens in the market.
     */
    function _calculateEVirtual(uint256 liquidity_, Range storage poolPriceSqrtRangeX18_)
        internal
        view
        returns (uint256)
    {
        if (liquidity_ == 0 || !poolPriceSqrtRangeX18_.isMaxBounded) {
            return 0;
        } else {
            return liquidity_ * 1e18 / poolPriceSqrtRangeX18_.max;
        }
    }

    /**
     * @dev Returns the amount of virtual MTokens in the market given the market liquidity and the pool price range.
     * @param liquidity_ The liquidity of the market.
     * @param poolPriceSqrtRangeX18_ The range of possible pool prices, expressed as the square root of the pool price.
     * @return The amount of virtual MTokens in the market.
     */
    function _calculateMVirtual(uint256 liquidity_, Range storage poolPriceSqrtRangeX18_)
        internal
        view
        returns (uint256)
    {
        if (liquidity_ == 0 || !poolPriceSqrtRangeX18_.isMinBounded) {
            return 0;
        } else {
            return liquidity_ * poolPriceSqrtRangeX18_.min / 1e18;
        }
    }

    /**
     * @dev Returns the MToken per EToken price of energy given an amount of MTokens and ETokens.
     * @param EAmount The amount of ETokens.
     * @param MAmount The amount of MTokens.
     * @return The price of energy.
     */
    function _calculatePrice(uint256 EAmount, uint256 MAmount) internal pure returns (UD60x18) {
        uint256 E = EAmount;
        uint256 M = MAmount;

        if (E == 0 || M == 0) {
            return convert(0);
        } else {
            return ud(M * 1e18 / E);
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function EToken() external view returns (IERC20) {
        return _EToken;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function MToken() external view returns (IERC20) {
        return _MToken;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function LToken() external view returns (IERC20) {
        return _LToken;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function EReserve() external view returns (uint256) {
        return _EToken.balanceOf(address(this));
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function MReserve() external view returns (uint256) {
        return _MToken.balanceOf(address(this));
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function poolPriceRange() external view returns (Range memory) {
        return _poolPriceRangeX18;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function poolPrice() external view returns (UD60x18) {
        return _calculatePrice(this.EReserve() + _EVirtual, this.MReserve() + _MVirtual);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidRange() external view returns (Range memory) {
        if (this.EReserve() == 0) {
            return Range(1, 0, true, true);
        } else {
            return Range(0, this.EReserve(), false, true);
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askRange() external view returns (Range memory) {
        if (_MVirtual == 0) {
            return Range(1, 0, false, false);
        } else {
            if (this.EReserve() + _EVirtual > _liquidity ** 2 / _MVirtual) {
                return Range(0, 0, true, true);
            } else {
                return Range(0, _liquidity ** 2 / _MVirtual - (this.EReserve() + _EVirtual), false, true);
            }
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidSwap(uint256 EAmount) external view returns (uint256 ESwap, uint256 MSwap) {
        Range memory bidRange_ = this.bidRange();
        if (!bidRange_.contains(EAmount)) {
            revert OutsideRange(bidRange_, EAmount);
        }

        uint256 EReserveNew = this.EReserve() + _EVirtual - EAmount;
        uint256 MReserveNew = _liquidity ** 2 / EReserveNew;

        ESwap = EAmount;

        if ((this.MReserve() + _MVirtual) > MReserveNew) {
            MSwap = 0;
        } else {
            MSwap = MReserveNew - (this.MReserve() + _MVirtual);
        }

        if (ESwap != 0 && MSwap != 0) {
            UD60x18 price = _calculatePrice(ESwap, MSwap);

            if (_poolPriceRangeX18.isMinBounded && price <= ud(_poolPriceRangeX18.min)) {
                ESwap = MSwap * 1e18 / _poolPriceRangeX18.min;
            } else if (_poolPriceRangeX18.isMaxBounded && price >= ud(_poolPriceRangeX18.max)) {
                MSwap = ESwap * _poolPriceRangeX18.max / 1e18;
            }
        }

        if (ESwap == 0) {
            MSwap = 0;
        }
        if (MSwap == 0) {
            ESwap = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askSwap(uint256 EAmount) external view returns (uint256 ESwap, uint256 MSwap) {
        Range memory askRange_ = this.askRange();
        if (!askRange_.contains(EAmount)) {
            revert OutsideRange(askRange_, EAmount);
        }

        uint256 EReserveNew = this.EReserve() + _EVirtual + EAmount;
        uint256 MReserveNew = _liquidity ** 2 / EReserveNew;

        ESwap = EAmount;

        if (MReserveNew > (this.MReserve() + _MVirtual)) {
            MSwap = 0;
        } else {
            MSwap = (this.MReserve() + _MVirtual) - MReserveNew;
        }

        if (ESwap != 0 && MSwap != 0) {
            UD60x18 price = _calculatePrice(ESwap, MSwap);

            if (_poolPriceRangeX18.isMinBounded && price <= ud(_poolPriceRangeX18.min)) {
                ESwap = MSwap * 1e18 / _poolPriceRangeX18.min;
            } else if (_poolPriceRangeX18.isMaxBounded && price >= ud(_poolPriceRangeX18.max)) {
                MSwap = ESwap * _poolPriceRangeX18.max / 1e18;
            }
        }

        if (ESwap == 0) {
            MSwap = 0;
        }
        if (MSwap == 0) {
            ESwap = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidFee(uint256 EAmount) external view returns (uint256) {
        (, uint256 MSwap) = this.bidSwap(EAmount);

        return MSwap * feeRate.unwrap() / 1e18;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askFee(uint256 EAmount) external view returns (uint256) {
        (, uint256 MSwap) = this.askSwap(EAmount);

        (, uint256 MSwapWithoutFee) = this.askSwap(EAmount * 1e18 / (convert(1) + feeRate).unwrap());

        return MSwap - MSwapWithoutFee;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidPrice(uint256 EAmount) external view returns (UD60x18) {
        (uint256 ESwap, uint256 MSwap) = this.bidSwap(EAmount);

        return _calculatePrice(ESwap, MSwap);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askPrice(uint256 EAmount) external view returns (UD60x18) {
        (uint256 ESwap, uint256 MSwap) = this.askSwap(EAmount);

        return _calculatePrice(ESwap, MSwap);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidSlippage(uint256 EAmount) external view returns (SD59x18) {
        return (this.bidPrice(EAmount) / this.poolPrice()).intoSD59x18() - convert(1).intoSD59x18();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askSlippage(uint256 EAmount) external view returns (SD59x18) {
        return (this.askPrice(EAmount) / this.poolPrice()).intoSD59x18() - convert(1).intoSD59x18();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityProvision(uint256 EAmount, uint256 MAmount)
        external
        view
        returns (uint256 LShare, uint256 ELiq, uint256 MLiq)
    {
        uint256 EReserveNew = this.EReserve() + EAmount;
        uint256 MReserveNew = this.MReserve() + MAmount;
        uint256 liquidityNew = Math.sqrt(EReserveNew * MReserveNew);

        MLiq = MAmount;
        ELiq = EAmount;
        LShare = liquidityNew - _LToken.totalSupply();

        if (ELiq == 0) {
            MLiq = 0;
            LShare = 0;
        }
        if (MLiq == 0) {
            ELiq = 0;
            LShare = 0;
        }
        if (LShare == 0) {
            MLiq = 0;
            ELiq = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityReduction(uint256 LAmount) external view returns (uint256 LShare, uint256 ELiq, uint256 MLiq) {
        if (LAmount > _LToken.balanceOf(msg.sender)) {
            LAmount = _LToken.balanceOf(msg.sender);
        }
        UD60x18 balanceProportion = ud(LAmount * 1e18 / _LToken.balanceOf(msg.sender));

        UD60x18 proportion = this.liquidityProportion(msg.sender) * balanceProportion;

        if (LAmount != 0) {
            ELiq = this.EReserve() * proportion.unwrap() / 1e18.
            MLiq = this.MReserve() * proportion.unwrap() / 1e18.
        }
        LShare = LAmount;

        if (ELiq == 0) {
            MLiq = 0;
            LShare = 0;
        }
        if (MLiq == 0) {
            ELiq = 0;
            LShare = 0;
        }
        if (LShare == 0) {
            MLiq = 0;
            ELiq = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityProportion(address provider) external view returns (UD60x18) {
        if (_LToken.totalSupply() == 0) {
            return ud(0);
        }
        return ud(_LToken.balanceOf(provider) * 1e18 / _LToken.totalSupply());
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function buy(uint256 EAmount) external liquidityShift returns (TradeInfo memory info) {
        (uint256 ESwap, uint256 MSwap) = this.bidSwap(EAmount);
        uint256 MFee = this.bidFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroTransfer();
        }

        info.trader = msg.sender;
        info.op = "buy";
        info.EAmount = ESwap;
        info.MAmount = MSwap;
        info.fee = MFee;
        info.poolPrice = this.poolPrice();
        info.tradePrice = this.bidPrice(EAmount);
        info.slippage = this.bidSlippage(EAmount);

        uint256 MAllowance = _MToken.allowance(msg.sender, address(this));
        if (MAllowance < MSwap + MFee) {
            revert InsufficientAllowance(IERC20(_MToken), MSwap + MFee, MAllowance);
        }
        require(_MToken.transferFrom(msg.sender, address(this), MSwap + MFee));
        require(_EToken.transfer(msg.sender, ESwap));

        emit MarketStateChanged();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function sell(uint256 EAmount) external liquidityShift returns (TradeInfo memory info) {
        (uint256 ESwap, uint256 MSwap) = this.askSwap(EAmount);
        uint256 MFee = this.askFee(EAmount);

        if (ESwap == 0 || MSwap == 0) {
            revert ZeroTransfer();
        }

        info.trader = msg.sender;
        info.op = "sell";
        info.EAmount = ESwap;
        info.MAmount = MSwap;
        info.fee = MFee;
        info.poolPrice = this.poolPrice();
        info.tradePrice = this.askPrice(EAmount);
        info.slippage = this.askSlippage(EAmount);

        uint256 EAllowance = _EToken.allowance(msg.sender, address(this));
        if (EAllowance < ESwap) {
            revert InsufficientAllowance(IERC20(_EToken), ESwap, EAllowance);
        }
        require(_MToken.transfer(msg.sender, MSwap - MFee));
        require(_EToken.transferFrom(msg.sender, address(this), ESwap));

        emit MarketStateChanged();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function addLiquidity(uint256 EAmount, uint256 MAmount)
        external
        liquidityShift
        returns (LiquidityInfo memory info)
    {
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = this.liquidityProvision(EAmount, MAmount);
        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            revert ZeroTransfer();
        }

        info.provider = msg.sender;
        info.op = "addition";
        info.ELiq = ELiq;
        info.MLiq = MLiq;
        info.LShare = LShare;
        info.poolPrice = this.poolPrice();
        info.liqPrice = convert(MLiq) / convert(ELiq);

        uint256 EAllowance = _EToken.allowance(msg.sender, address(this));
        uint256 MAllowance = _MToken.allowance(msg.sender, address(this));
        if (EAllowance < ELiq) {
            revert InsufficientAllowance(IERC20(_EToken), ELiq, EAllowance);
        }
        if (MAllowance < MLiq) {
            revert InsufficientAllowance(IERC20(_MToken), MLiq, MAllowance);
        }
        require(_EToken.transferFrom(msg.sender, address(this), ELiq));
        require(_MToken.transferFrom(msg.sender, address(this), MLiq));

        _LToken.mint(msg.sender, LShare);

        emit MarketStateChanged();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function removeLiquidity(uint256 LAmount) external liquidityShift returns (LiquidityInfo memory info) {
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = this.liquidityReduction(LAmount);
        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            revert ZeroTransfer();
        }

        info.provider = msg.sender;
        info.op = "removal";
        info.ELiq = ELiq;
        info.MLiq = MLiq;
        info.LShare = LShare;
        info.poolPrice = this.poolPrice();
        info.liqPrice = convert(MLiq) / convert(ELiq);

        require(_EToken.transfer(msg.sender, ELiq));
        require(_MToken.transfer(msg.sender, MLiq));
        _LToken.burn(msg.sender, LShare);

        emit MarketStateChanged();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setPoolPriceRange(Range calldata range) external liquidityShift onlyOwner {
        if (!range.isValid()) {
            revert InvalidRange(range);
        }

        _poolPriceRangeX18 = range;

        _poolPriceSqrtRangeX18.isMinBounded = range.isMinBounded;
        _poolPriceSqrtRangeX18.isMaxBounded = range.isMaxBounded;
        if (_poolPriceSqrtRangeX18.isMinBounded) {
            _poolPriceSqrtRangeX18.min = sqrt(ud(range.min)).unwrap();
        }
        if (_poolPriceSqrtRangeX18.isMaxBounded) {
            _poolPriceSqrtRangeX18.max = sqrt(ud(range.max)).unwrap();
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setFeeRate(UD60x18 feeRate_) external onlyOwner {
        feeRate = feeRate_;
    }
}
