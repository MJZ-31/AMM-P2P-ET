// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { SD59x18 } from "@prb/math/src/SD59x18.sol";
import { UD60x18, convert, powu, sqrt, ud } from "@prb/math/src/UD60x18.sol";

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
     * @dev An ERC20 token representing real currency. The liquidity pool includes a balance of this token which is
     * swapped with traders.
     */
    IERC20Metadata private _MToken;

    /**
     * @dev An ERC20 token representing energy. The liquidity pool includes a balance of this token which is swapped
     * with traders.
     */
    IERC20Metadata private _EToken;

    /**
     * @dev An ERC20 token representing liquidity shares.
     */
    ERC20Ownable private _LToken;

    /**
     * @dev The liquidity constant of the pricing curve.
     */
    UD60x18 private _liquidity;

    /**
     * @dev The amount of virtual MTokens in the liquidity pool. Virtual assets cannot leave the liquidity pool and
     * exist purely to force the pool price into a specified range.
     */
    uint256 private _MVirtual;

    /**
     * @dev The amount of virtual ETokens in the liquidity pool. Virtual assets cannot leave the liquidity pool and
     * exist purely to force the pool price into a specified range.
     */
    uint256 private _EVirtual;

    /**
     * @dev The range of possible pool prices, expressed as the square root of the pool price.
     */
    Range private _poolPriceSqrtRange;

    /**
     * @dev The square root of the pool price when the liquidity pool contains the same amount of MTokens and ETokens.
     */
    UD60x18 _poolPriceSqrtEq;

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

        _liquidity = _calculateLiquidity(this.MReserve(), this.EReserve(), _poolPriceSqrtRange);
        _MVirtual = _calculateMVirtual(_liquidity, _poolPriceSqrtRange);
        _EVirtual = _calculateEVirtual(_liquidity, _poolPriceSqrtRange);
    }

    constructor(IERC20Metadata MToken_, IERC20Metadata EToken_) Ownable(msg.sender) {
        require(address(MToken_) != address(0), "Invalid MToken contract address");
        require(address(EToken_) != address(0), "Invalid EToken contract address");
        require(address(MToken_) != address(EToken_), "MToken and EToken contract addresses must be different");

        _MToken = MToken_;
        _EToken = EToken_;
        _LToken = new ERC20Ownable("EnergyAMM Liquidity Token", "ELIQ", EToken_.decimals());

        _liquidity = convert(0);
        _MVirtual = 0;
        _EVirtual = 0;

        _poolPriceSqrtRange.unboundMin();
        _poolPriceSqrtRange.unboundMax();

        _bidRange.unboundMin();
        _bidRange.unboundMax();

        _askRange.unboundMin();
        _askRange.unboundMax();

        feeRate = convert(0);
    }

    /**
     * @dev Returns the liquidity of the market given the market reserve amounts and the pool price range.
     * @param MReserve_ The amount of MTokens in reserve.
     * @param EReserve_ The amount of ETokens in reserve.
     * @param poolPriceSqrtRange_ The range of possible pool prices, expressed as the square root of the pool price.
     * @return The liquidity of the market.
     */
    function _calculateLiquidity(uint256 MReserve_, uint256 EReserve_, Range storage poolPriceSqrtRange_)
        internal
        view
        returns (UD60x18)
    {
        UD60x18 M = MReserve_.tokToUD(_MToken);
        UD60x18 E = EReserve_.tokToUD(_EToken);

        UD60x18 p_lo_sqrt = ud(poolPriceSqrtRange_.min);
        UD60x18 p_hi_sqrt = ud(poolPriceSqrtRange_.max);

        if (poolPriceSqrtRange_.isMinUnbounded && poolPriceSqrtRange_.isMaxUnbounded) {
            // Pool price is unbounded. Use the Constant Product pricing curve.
            return sqrt(M * E);
        } else if (poolPriceSqrtRange_.isMinUnbounded) {
            // Pool price is bounded on only the low side. Use a partial Concentrated Liquidity pricing curve.
            UD60x18 b = M / p_hi_sqrt;
            UD60x18 c = M * E;

            return (b + sqrt(powu(b, 2) + convert(4) * c)) / convert(2);
        } else if (poolPriceSqrtRange_.isMaxUnbounded) {
            // Pool price is bounded on only the high side. Use a partial Concentrated Liquidity pricing curve.
            UD60x18 b = M * p_lo_sqrt;
            UD60x18 c = M * E;

            return (b + sqrt(powu(b, 2) + convert(4) * c)) / convert(2);
        } else if (poolPriceSqrtRange_.min == poolPriceSqrtRange_.max) {
            // Pool price is bounded to a single value. Use the Constant Sum pricing curve.
            return M + E * powu(ud(poolPriceSqrtRange_.min), 2);
        } else {
            // Pool price is bounded on both sides, but not to a single value. Use the Concentrated Liquidity pricing curve.
            UD60x18 a = convert(1) - p_lo_sqrt / p_hi_sqrt;
            UD60x18 b = M / p_hi_sqrt + E * p_lo_sqrt;
            UD60x18 c = M * E;

            return (b + sqrt(powu(b, 2) + convert(4) * a * c)) / (convert(2) * a);
        }
    }

    /**
     * @dev Returns the amount of virtual MTokens in the market given the market liquidity and the pool price range.
     * @param liquidity_ The liquidity of the market.
     * @param poolPriceSqrtRange_ The range of possible pool prices, expressed as the square root of the pool price.
     * @return The amount of virtual MTokens in the market.
     */
    function _calculateMVirtual(UD60x18 liquidity_, Range storage poolPriceSqrtRange_) internal view returns (uint256) {
        if (liquidity_ == convert(0) || poolPriceSqrtRange_.isMinUnbounded) {
            return 0;
        } else {
            return (liquidity_ * ud(poolPriceSqrtRange_.min)).UDToTok(_MToken);
        }
    }

    /**
     * @dev Returns the amount of virtual ETokens in the market given the market liquidity and the pool price range.
     * @param liquidity_ The liquidity of the market.
     * @param poolPriceSqrtRange_ The range of possible pool prices, expressed as the square root of the pool price.
     * @return The amount of virtual ETokens in the market.
     */
    function _calculateEVirtual(UD60x18 liquidity_, Range storage poolPriceSqrtRange_) internal view returns (uint256) {
        if (liquidity_ == convert(0) || poolPriceSqrtRange_.isMaxUnbounded) {
            return 0;
        } else {
            return (liquidity_ / ud(poolPriceSqrtRange_.max)).UDToTok(_MToken);
        }
    }

    /**
     * @dev Returns the MToken per EToken price of energy given an amount of MTokens and ETokens.
     * @param MAmount The amount of MTokens.
     * @param EAmount The amount of ETokens.
     * @return The price of energy.
     */
    function _calculatePrice(uint256 MAmount, uint256 EAmount) internal view returns (UD60x18) {
        UD60x18 M = MAmount.tokToUD(_MToken);
        UD60x18 E = EAmount.tokToUD(_EToken);

        if (M == convert(0) && E == convert(0)) {
            return powu(_poolPriceSqrtEq, 2);
        } else if (M == convert(0) || E == convert(0)) {
            return convert(0);
        } else {
            return M / E;
        }
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
    function EToken() external view returns (IERC20) {
        return _EToken;
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
    function MReserve() external view returns (uint256) {
        return _MToken.balanceOf(address(this));
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
    function poolPriceRange() external view returns (Range memory) {
        Range memory range;
        range.min = powu(ud(_poolPriceSqrtRange.min), 2).unwrap();
        range.max = powu(ud(_poolPriceSqrtRange.max), 2).unwrap();
        range.isMinUnbounded = _poolPriceSqrtRange.isMinUnbounded;
        range.isMaxUnbounded = _poolPriceSqrtRange.isMaxUnbounded;

        return range;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function poolPrice() external view returns (UD60x18) {
        return _calculatePrice(this.MReserve() + _MVirtual, this.EReserve() + _EVirtual);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidRange() external view returns (Range memory range) {
        Range memory absoluteRange;
        absoluteRange.min = 0;
        absoluteRange.max = this.EReserve();
        absoluteRange.isMinUnbounded = false;
        absoluteRange.isMaxUnbounded = false;

        return absoluteRange.intersect(_bidRange);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askRange() external view returns (Range memory) {
        Range memory absoluteRange;
        absoluteRange.min = 0;
        if (_MVirtual.tokToUD(_MToken) == convert(0)) {
            absoluteRange.max = 0;
        } else {
            absoluteRange.max = (powu(_liquidity, 2) / _MVirtual.tokToUD(_MToken)
                    - (this.EReserve() + _EVirtual).tokToUD(_EToken))
            .UDToTok(_EToken);
        }
        absoluteRange.isMinUnbounded = false;
        absoluteRange.isMaxUnbounded = false;

        return absoluteRange.intersect(_askRange);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap) {
        Range memory bidRange_ = this.bidRange();
        if (!bidRange_.contains(EAmount)) {
            revert OutsideRange(bidRange_, EAmount);
        }

        uint256 EReserveNew = this.EReserve() + _EVirtual - EAmount;
        uint256 MReserveNew = (powu(_liquidity, 2) / EReserveNew.tokToUD(_EToken)).UDToTok(_MToken);

        if ((this.MReserve() + _MVirtual) > MReserveNew) {
            MSwap = 0;
        } else {
            MSwap = MReserveNew - (this.MReserve() + _MVirtual);
        }

        if (EReserveNew > (this.EReserve() + _EVirtual)) {
            ESwap = 0;
        } else {
            ESwap = (this.EReserve() + _EVirtual) - EReserveNew;
        }

        if (MSwap == 0) {
            ESwap = 0;
        }
        if (ESwap == 0) {
            MSwap = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap) {
        Range memory askRange_ = this.askRange();
        if (!askRange_.contains(EAmount)) {
            revert OutsideRange(askRange_, EAmount);
        }

        uint256 EReserveNew = this.EReserve() + _EVirtual + EAmount;
        uint256 MReserveNew = (powu(_liquidity, 2) / EReserveNew.tokToUD(_EToken)).UDToTok(_MToken);

        if (MReserveNew > (this.MReserve() + _MVirtual)) {
            MSwap = 0;
        } else {
            MSwap = (this.MReserve() + _MVirtual) - MReserveNew;
        }

        if ((this.EReserve() + _EVirtual) > EReserveNew) {
            ESwap = 0;
        } else {
            ESwap = EReserveNew - (this.EReserve() + _EVirtual);
        }

        if (MSwap == 0) {
            ESwap = 0;
        }
        if (ESwap == 0) {
            MSwap = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidFee(uint256 EAmount) external view returns (uint256) {
        (uint256 MSwap,) = this.bidSwap(EAmount);

        return (MSwap.tokToUD(_MToken) * feeRate).UDToTok(_MToken);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askFee(uint256 EAmount) external view returns (uint256) {
        (uint256 MSwap,) = this.askSwap(EAmount);

        (uint256 MSwapWithoutFee,) = this.askSwap((EAmount.tokToUD(_EToken) * (convert(1) - feeRate)).UDToTok(_EToken));

        return MSwap - MSwapWithoutFee;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidPrice(uint256 EAmount) external view returns (UD60x18) {
        (uint256 MSwap, uint256 ESwap) = this.bidSwap(EAmount);

        return _calculatePrice(MSwap, ESwap);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askPrice(uint256 EAmount) external view returns (UD60x18) {
        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);

        return _calculatePrice(MSwap, ESwap);
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
    function liquidityProvision(uint256 MAmount, uint256 EAmount)
        external
        view
        returns (uint256 LShare, uint256 MLiq, uint256 ELiq)
    {
        MLiq = MAmount;
        ELiq = EAmount;

        UD60x18 price = MLiq.tokToUD(_MToken) / ELiq.tokToUD(_EToken);

        if (price < powu(ud(_poolPriceSqrtRange.min), 2)) {
            ELiq = (MLiq.tokToUD(_MToken) / powu(ud(_poolPriceSqrtRange.min), 2)).UDToTok(_EToken);
        } else if (price > powu(ud(_poolPriceSqrtRange.max), 2)) {
            MLiq = (ELiq.tokToUD(_EToken) * powu(ud(_poolPriceSqrtRange.max), 2)).UDToTok(_MToken);
        }

        LShare = sqrt(MLiq.tokToUD(_MToken) * ELiq.tokToUD(_EToken)).UDToTok(_LToken);

        if (MLiq == 0) {
            ELiq = 0;
            LShare = 0;
        }
        if (ELiq == 0) {
            MLiq = 0;
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
    function liquidityReduction(uint256 LAmount) external view returns (uint256 LShare, uint256 MLiq, uint256 ELiq) {
        uint256 MShare = (_liquidityProportion(msg.sender) * this.MReserve().tokToUD(_MToken)).UDToTok(_MToken);
        uint256 EShare = (_liquidityProportion(msg.sender) * this.EReserve().tokToUD(_EToken)).UDToTok(_EToken);

        MLiq = (MShare.tokToUD(_MToken) * LAmount.tokToUD(_LToken) / _LToken.balanceOf(msg.sender).tokToUD(_LToken))
        .UDToTok(_MToken);
        ELiq = (EShare.tokToUD(_EToken) * LAmount.tokToUD(_LToken) / _LToken.balanceOf(msg.sender).tokToUD(_LToken))
        .UDToTok(_EToken);
        LShare = LAmount;

        if (MLiq == 0) {
            ELiq = 0;
            LShare = 0;
        }
        if (ELiq == 0) {
            MLiq = 0;
            LShare = 0;
        }
        if (LShare == 0) {
            MLiq = 0;
            ELiq = 0;
        }
    }

    /**
     * @dev Returns the proportion of liquidity owned by a liquidity provider.
     * @param provider The address of a liquidity provider.
     * @return The proportion of liquidity.
     */
    function _liquidityProportion(address provider) internal view returns (UD60x18) {
        return _LToken.balanceOf(provider).tokToUD(_LToken) / _LToken.totalSupply().tokToUD(_LToken);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityProportion() external view returns (UD60x18) {
        return _liquidityProportion(msg.sender);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function buy(uint256 EAmount) external liquidityShift returns (TradeInfo memory info) {
        (uint256 MSwap, uint256 ESwap) = this.bidSwap(EAmount);
        uint256 MFee = this.bidFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroTransfer();
        }

        info.trader = msg.sender;
        info.op = "buy";
        info.MAmount = MSwap;
        info.EAmount = ESwap;
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
        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);
        uint256 MFee = this.askFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroTransfer();
        }

        info.trader = msg.sender;
        info.op = "sell";
        info.MAmount = MSwap;
        info.EAmount = ESwap;
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
    function addLiquidity(uint256 MAmount, uint256 EAmount)
        external
        liquidityShift
        returns (LiquidityInfo memory info)
    {
        (uint256 LShare, uint256 MLiq, uint256 ELiq) = this.liquidityProvision(MAmount, EAmount);
        if (LShare == 0 || MLiq == 0 || ELiq == 0) {
            revert ZeroTransfer();
        }

        info.provider = msg.sender;
        info.op = "addition";
        info.MLiq = MLiq;
        info.ELiq = ELiq;
        info.LShare = LShare;
        info.poolPrice = this.poolPrice();
        info.liqPrice = MLiq.tokToUD(_MToken) / ELiq.tokToUD(_EToken);

        uint256 MAllowance = _MToken.allowance(msg.sender, address(this));
        uint256 EAllowance = _EToken.allowance(msg.sender, address(this));
        if (MAllowance < MLiq) {
            revert InsufficientAllowance(IERC20(_MToken), MLiq, MAllowance);
        }
        if (EAllowance < ELiq) {
            revert InsufficientAllowance(IERC20(_EToken), ELiq, EAllowance);
        }
        require(_MToken.transferFrom(msg.sender, address(this), MLiq));
        require(_EToken.transferFrom(msg.sender, address(this), ELiq));

        _LToken.mint(msg.sender, LShare);

        emit MarketStateChanged();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function removeLiquidity(uint256 LAmount) external liquidityShift returns (LiquidityInfo memory info) {
        (uint256 LShare, uint256 MLiq, uint256 ELiq) = this.liquidityReduction(LAmount);
        if (LShare == 0 || MLiq == 0 || ELiq == 0) {
            revert ZeroTransfer();
        }

        info.provider = msg.sender;
        info.op = "removal";
        info.MLiq = MLiq;
        info.ELiq = ELiq;
        info.LShare = LShare;
        info.poolPrice = this.poolPrice();
        info.liqPrice = MLiq.tokToUD(_MToken) / ELiq.tokToUD(_EToken);

        require(_MToken.transfer(msg.sender, MLiq));
        require(_EToken.transfer(msg.sender, ELiq));
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
        _poolPriceSqrtRange = range;

        uint256 MBase = 10 ** _MToken.decimals();
        uint256 EBase = 10 ** _EToken.decimals();
        UD60x18 liquidityBase = _calculateLiquidity(MBase, EBase, _poolPriceSqrtRange);
        uint256 MVirtualBase = _calculateMVirtual(liquidityBase, _poolPriceSqrtRange);
        uint256 EVirtualBase = _calculateEVirtual(liquidityBase, _poolPriceSqrtRange);

        _poolPriceSqrtEq = sqrt(_calculatePrice(MBase + MVirtualBase, EBase + EVirtualBase));
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setFeeRate(UD60x18 feeRate_) external onlyOwner {
        feeRate = feeRate_;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setBidRange(Range calldata range) external onlyOwner {
        if (!range.isValid()) {
            revert InvalidRange(range);
        }
        _bidRange = range;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setAskRange(Range calldata range) external onlyOwner {
        if (!range.isValid()) {
            revert InvalidRange(range);
        }
        _askRange = range;
    }
}
