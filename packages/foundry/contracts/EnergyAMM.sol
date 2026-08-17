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
     * @dev The amount of MTokens in the liquidity pool.
     */
    uint256 private _MReserve;

    /**
     * @dev The amount of ETokens in the liquidity pool.
     */
    uint256 private _EReserve;

    /**
     * @dev The amount of market liquidity, ignoring the pool price range.
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
     * @dev The amount of virtual liquidity in the market. Unlike _liquidity, this value takes virtual assets into
     * account.
     */
    uint256 private _liquidityVirtual;

    /**
     * @dev The range of possible swap prices.
     */
    Range private _swapPriceRangeX18;

    /**
     * @dev The range of possible swap prices, expressed as the square root of the swap price.
     */
    Range private _swapPriceSqrtRangeX18;

    /**
     * @dev The fee rate of swaps.
     */
    UD60x18 public _feeRate;

    /**
     * @dev The list of liquidity providers.
     */
    address[] private _liquidityProviders;

    /**
     * @dev Enumeration constant for _curveType. Represents a Constant Sum pricing curve, which is used when the pool
     * price is bounded to a single possible value.
     */
    uint256 private constant _CSMM = 1;

    /**
     * @dev Enumeration constant for _curveType. Represents a Constant Product pricing curve, which is used when the
     * pool price range in completely unbounded.
     */
    uint256 private constant _CPMM = 2;

    /**
     * @dev Enumeration constant for _curveType. Represents a Concentrated Liquidity pricing curve, which is used when
     * the pool price range is bounded on both sides.
     */
    uint256 private constant _CLMM = 3;

    /**
     * @dev Enumeration constant for _curveType. Represents a partial Concentrated Liquidity pricing curve, which is
     * used when the pool price range is bounded on the lower side but not the upper side.
     */
    uint256 private constant _CLMM_PARTIAL_MIN = 4;

    /**
     * @dev Enumeration constant for _curveType. Represents a partial Concentrated Liquidity pricing curve, which is
     * used when the pool price range is bounded on the upper side but not the lower side.
     */
    uint256 private constant _CLMM_PARTIAL_MAX = 5;

    /**
     * @dev The current type for the pricing curve.
     */
    uint256 private _curveType;

    constructor(IERC20Metadata EToken_, IERC20Metadata MToken_) Ownable(msg.sender) {
        if (address(EToken_) == address(0)) {
            revert("Invalid EToken contract address");
        }
        if (address(MToken_) == address(0)) {
            revert("Invalid MToken contract address");
        }
        if (address(EToken_) == address(MToken_)) {
            revert("EToken and MToken contract addresses must be different");
        }

        _EToken = EToken_;
        _MToken = MToken_;
        _LToken = new ERC20Ownable("EnergyAMM Liquidity Token", "ELIQ", 18);

        _EReserve = 0;
        _MReserve = 0;
        _liquidity = 0;

        _EVirtual = 0;
        _MVirtual = 0;
        _liquidityVirtual = 0;

        _swapPriceRangeX18 = Range(0, 0, false, false);
        _swapPriceSqrtRangeX18 = Range(0, 0, false, false);

        _feeRate = ud(0);

        _curveType = _CPMM;
    }

    /**
     * @dev Recalculates the pricing curve of the market. Meant to be called after a transaction.
     */
    function _recalculatePricingCurve() internal {
        if (_curveType == _CSMM) {
            _liquidityVirtual = _EReserve * _swapPriceRangeX18.min / 1e18 + _MReserve;
        } else if (_curveType == _CPMM) {
            _liquidityVirtual = Math.sqrt(_EReserve * _MReserve);
        } else if (_curveType == _CLMM) {
            UD60x18 a = convert(1) - ud(_swapPriceSqrtRangeX18.min * 1e18 / _swapPriceSqrtRangeX18.max);
            uint256 v1 = _EReserve * _swapPriceSqrtRangeX18.min / 1e18;
            uint256 v2 = _MReserve * 1e18 / _swapPriceSqrtRangeX18.max;
            uint256 b1 = v1 + v2;
            uint256 b2 = v1 > v2 ? v1 - v2 : v2 - v1;
            uint256 c = _EReserve * _MReserve;

            _liquidityVirtual = (b1 + Math.sqrt(b2 ** 2 + 4 * c)) * 1e18 / (2 * a.unwrap());
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            uint256 b = _EReserve * _swapPriceSqrtRangeX18.min / 1e18;
            uint256 c = _EReserve * _MReserve;

            _liquidityVirtual = (b + Math.sqrt(b ** 2 + 4 * c)) / 2;
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            uint256 b = _MReserve * 1e18 / _swapPriceSqrtRangeX18.max;
            uint256 c = _EReserve * _MReserve;

            _liquidityVirtual = (b + Math.sqrt(b ** 2 + 4 * c)) / 2;
        } else {
            revert("Unknown curve type");
        }

        if (_curveType == _CLMM || _curveType == _CLMM_PARTIAL_MAX) {
            _EVirtual = _liquidityVirtual * 1e18 / _swapPriceSqrtRangeX18.max;
        }

        if (_curveType == _CLMM || _curveType == _CLMM_PARTIAL_MIN) {
            _MVirtual = _liquidityVirtual * _swapPriceSqrtRangeX18.min / 1e18;
        }
    }

    /**
     * @dev Mints new LTokens to distribute newly added liquidity among the liquidity providers. Meant to be called
     * after a swap fee is collected.
     * @param liquidityOld_ The amount of market liquidity before the liquidity change.
     * @param liquidityNew_ The amount of market liquidity after the liquidity change.
     */
    function _distributeLiquidity(uint256 liquidityOld_, uint256 liquidityNew_) internal {
        if (liquidityOld_ == liquidityNew_) {
            return;
        }

        uint256 liqLeft = liquidityOld_ > liquidityNew_ ? liquidityOld_ - liquidityNew_ : liquidityNew_ - liquidityOld_;

        for (uint256 i = 0; i < _liquidityProviders.length; ++i) {
            address provider = _liquidityProviders[i];
            uint256 balanceOld = _LToken.balanceOf(provider);

            UD60x18 proportion = ud(1e18);
            if (liquidityOld_ != 0) {
                proportion = ud(balanceOld * 1e18 / liquidityOld_);
            }

            uint256 balanceNew = liquidityNew_ * proportion.unwrap() / 1e18;

            if (balanceOld > balanceNew) {
                if (i == _liquidityProviders.length - 1) {
                    _LToken.burn(provider, liqLeft);
                    liqLeft = 0;
                } else {
                    _LToken.burn(provider, balanceOld - balanceNew);
                    liqLeft -= balanceOld - balanceNew;
                }
            } else {
                if (i == _liquidityProviders.length - 1) {
                    _LToken.mint(provider, liqLeft);
                    liqLeft = 0;
                } else {
                    _LToken.mint(provider, balanceNew - balanceOld);
                    liqLeft -= balanceNew - balanceOld;
                }
            }
        }

        if (_LToken.totalSupply() != liquidityNew_) {
            revert("Liquidity distribution failed");
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
        return _EReserve;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function MReserve() external view returns (uint256) {
        return _MReserve;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidity() external view returns (uint256) {
        return _liquidity;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function swapPriceRange() external view returns (Range memory) {
        return _swapPriceRangeX18;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function poolPrice() external view returns (UD60x18) {
        if (_curveType == _CSMM) {
            return _calculatePrice(_EReserve, _MReserve);
        } else if (_curveType == _CPMM) {
            return _calculatePrice(_EReserve, _MReserve);
        } else if (_curveType == _CLMM) {
            return _calculatePrice(_EReserve + _EVirtual, _MReserve + _MVirtual);
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            return _calculatePrice(_EReserve, _MReserve + _MVirtual);
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            return _calculatePrice(_EReserve + _EVirtual, _MReserve);
        } else {
            revert("Unknown curve type");
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function feeRate() external view returns (UD60x18) {
        return _feeRate;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidRange() external view returns (Range memory) {
        if (_EReserve == 0) {
            return Range(1, 0, true, true);
        }

        if (_curveType == _CSMM) {
            return Range(0, _EReserve, false, true);
        } else if (_curveType == _CPMM) {
            if (_EReserve == 0) {
                return Range(1, 0, true, true);
            } else {
                return Range(0, _EReserve - 1, false, true);
            }
        } else if (_curveType == _CLMM) {
            return Range(0, _EReserve, false, true);
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            if (_EReserve == 0) {
                return Range(1, 0, true, true);
            } else {
                return Range(0, _EReserve - 1, false, true);
            }
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            return Range(0, _EReserve, false, true);
        } else {
            revert("Unknown curve type");
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askRange() external view returns (Range memory) {
        if (_MReserve == 0) {
            return Range(1, 0, true, true);
        }

        if (_curveType == _CSMM) {
            return Range(0, _liquidityVirtual * 1e18 / _swapPriceRangeX18.min - _EReserve, false, true);
        } else if (_curveType == _CPMM) {
            return Range(0, type(uint256).max / 1e18, false, true);
        } else if (_curveType == _CLMM) {
            if (_EReserve + _EVirtual > _liquidityVirtual ** 2 / _MVirtual) {
                return Range(0, 0, false, true);
            } else {
                return Range(0, _liquidityVirtual ** 2 / _MVirtual - (_EReserve + _EVirtual), false, true);
            }
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            if (_EReserve > _liquidityVirtual ** 2 / _MVirtual) {
                return Range(0, 0, false, true);
            } else {
                return Range(0, _liquidityVirtual ** 2 / _MVirtual - _EReserve, false, true);
            }
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            return Range(0, type(uint256).max / 1e18, false, true);
        } else {
            revert("Unknown curve type");
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

        uint256 EReserveNew = _EReserve - EAmount;
        uint256 MReserveNew;
        if (_curveType == _CSMM) {
            MReserveNew = _liquidityVirtual - EReserveNew * _swapPriceRangeX18.min / 1e18;
        } else if (_curveType == _CPMM) {
            MReserveNew = _liquidityVirtual ** 2 / EReserveNew;
        } else if (_curveType == _CLMM) {
            MReserveNew = _liquidityVirtual ** 2 / (EReserveNew + _EVirtual) - _MVirtual;
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            MReserveNew = _liquidityVirtual ** 2 / EReserveNew - _MVirtual;
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            MReserveNew = _liquidityVirtual ** 2 / (EReserveNew + _EVirtual);
        } else {
            revert("Unknown curve type");
        }

        ESwap = EAmount;

        if (_MReserve > MReserveNew) {
            MSwap = 0;
        } else {
            MSwap = MReserveNew - _MReserve;
        }

        if (ESwap != 0 && MSwap != 0) {
            UD60x18 price = _calculatePrice(ESwap, MSwap);

            if (_swapPriceRangeX18.isMinBounded && price <= ud(_swapPriceRangeX18.min)) {
                ESwap = MSwap * 1e18 / _swapPriceRangeX18.min;
            } else if (_swapPriceRangeX18.isMaxBounded && price >= ud(_swapPriceRangeX18.max)) {
                MSwap = ESwap * _swapPriceRangeX18.max / 1e18;
            }
        }

        if (ESwap == 0 || MSwap == 0) {
            ESwap = 0;
            MSwap = 0;
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

        uint256 EReserveNew = _EReserve + EAmount;
        uint256 MReserveNew;
        if (_curveType == _CSMM) {
            MReserveNew = _liquidityVirtual - EReserveNew * _swapPriceRangeX18.min / 1e18;
        } else if (_curveType == _CPMM) {
            MReserveNew = _liquidityVirtual ** 2 / EReserveNew;
        } else if (_curveType == _CLMM) {
            MReserveNew = _liquidityVirtual ** 2 / (EReserveNew + _EVirtual) - _MVirtual;
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            MReserveNew = _liquidityVirtual ** 2 / (EReserveNew + _EVirtual);
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            MReserveNew = _liquidityVirtual ** 2 / EReserveNew - _MVirtual;
        } else {
            revert("Unknown curve type");
        }

        ESwap = EAmount;

        if (MReserveNew > _MReserve) {
            MSwap = 0;
        } else {
            MSwap = _MReserve - MReserveNew;
        }

        if (ESwap != 0 && MSwap != 0) {
            UD60x18 price = _calculatePrice(ESwap, MSwap);

            if (_swapPriceRangeX18.isMinBounded && price <= ud(_swapPriceRangeX18.min)) {
                ESwap = MSwap * 1e18 / _swapPriceRangeX18.min;
            } else if (_swapPriceRangeX18.isMaxBounded && price >= ud(_swapPriceRangeX18.max)) {
                MSwap = ESwap * _swapPriceRangeX18.max / 1e18;
            }
        }

        if (ESwap == 0 || MSwap == 0) {
            ESwap = 0;
            MSwap = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function bidFee(uint256 EAmount) external view returns (uint256) {
        (, uint256 MSwap) = this.bidSwap(EAmount);

        return MSwap * _feeRate.unwrap() / 1e18;
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askFee(uint256 EAmount) external view returns (uint256) {
        (, uint256 MSwap) = this.askSwap(EAmount);

        (, uint256 MSwapWithoutFee) = this.askSwap(EAmount * 1e18 / (ud(1e18) + _feeRate).unwrap());

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
        if (_curveType == _CSMM) {
            return ud(0).intoSD59x18();
        } else if (_curveType == _CPMM) {
            return (this.bidPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else if (_curveType == _CLMM) {
            return (this.bidPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            return (this.bidPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            return (this.bidPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else {
            revert("Unknown curve type");
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function askSlippage(uint256 EAmount) external view returns (SD59x18) {
        if (_curveType == _CSMM) {
            return ud(0).intoSD59x18();
        } else if (_curveType == _CPMM) {
            return (this.askPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else if (_curveType == _CLMM) {
            return (this.askPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else if (_curveType == _CLMM_PARTIAL_MIN) {
            return (this.askPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else if (_curveType == _CLMM_PARTIAL_MAX) {
            return (this.askPrice(EAmount) / this.poolPrice()).intoSD59x18() - ud(1e18).intoSD59x18();
        } else {
            revert("Unknown curve type");
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityProvision(uint256 LAmount) external view returns (uint256 LShare, uint256 ELiq, uint256 MLiq) {
        uint256 liquidityNew = _liquidity + LAmount;

        uint256 EReserveNew = 0;
        if (_EReserve == 0 || _MReserve == 0) {
            EReserveNew = liquidityNew;
        } else {
            EReserveNew = liquidityNew * Math.sqrt(_EReserve) * 1e18 / Math.sqrt(_MReserve) / 1e18;
        }

        uint256 MReserveNew = 0;
        if (_EReserve == 0 || _MReserve == 0) {
            MReserveNew = liquidityNew;
        } else {
            MReserveNew = liquidityNew * Math.sqrt(_MReserve) * 1e18 / Math.sqrt(_EReserve) / 1e18;
        }

        LShare = _liquidity > liquidityNew ? 0 : liquidityNew - _liquidity;
        ELiq = _EReserve > EReserveNew ? 0 : EReserveNew - _EReserve;
        MLiq = _MReserve > MReserveNew ? 0 : MReserveNew - _MReserve;

        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            LShare = 0;
            ELiq = 0;
            MLiq = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityReduction(uint256 LAmount) external view returns (uint256 LShare, uint256 ELiq, uint256 MLiq) {
        if (LAmount > _liquidity) {
            LAmount = _liquidity;
        }
        uint256 liquidityNew = _liquidity - LAmount;

        uint256 EReserveNew = 0;
        if (_EReserve == 0 || _MReserve == 0) {
            EReserveNew = liquidityNew;
        } else {
            EReserveNew = liquidityNew * Math.sqrt(_EReserve) * 1e18 / Math.sqrt(_MReserve) / 1e18;
        }

        uint256 MReserveNew = 0;
        if (_EReserve == 0 || _MReserve == 0) {
            MReserveNew = liquidityNew;
        } else {
            MReserveNew = liquidityNew * Math.sqrt(_MReserve) * 1e18 / Math.sqrt(_EReserve) / 1e18;
        }

        LShare = liquidityNew > _liquidity ? 0 : _liquidity - liquidityNew;
        ELiq = EReserveNew > _EReserve ? 0 : _EReserve - EReserveNew;
        MLiq = MReserveNew > _MReserve ? 0 : _MReserve - MReserveNew;

        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            LShare = 0;
            ELiq = 0;
            MLiq = 0;
        }
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function liquidityProportion(address provider) external view returns (UD60x18) {
        if (_liquidity == 0) {
            return ud(0);
        }
        return ud(_LToken.balanceOf(provider) * 1e18 / _liquidity);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function buy(uint256 EAmount) external {
        (uint256 ESwap, uint256 MSwap) = this.bidSwap(EAmount);
        uint256 MFee = this.bidFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroTransfer();
        }

        uint256 MAllowance = _MToken.allowance(msg.sender, address(this));
        if (MAllowance < MSwap + MFee) {
            revert InsufficientAllowance(IERC20(_MToken), MSwap + MFee, MAllowance);
        }

        if (!_MToken.transferFrom(msg.sender, address(this), MSwap + MFee)) {
            revert("Failed to transfer from sender");
        }
        if (!_EToken.transfer(msg.sender, ESwap)) {
            revert("Failed to transfer to sender");
        }

        uint256 liquidityOld = _liquidity;

        _EReserve -= ESwap;
        _MReserve += MSwap + MFee;
        _liquidity = Math.sqrt(_EReserve * _MReserve);

        uint256 liquidityNew = _liquidity;
        _distributeLiquidity(liquidityOld, liquidityNew);

        _recalculatePricingCurve();

        if (_EReserve != _EToken.balanceOf(address(this))) {
            revert("Failed to adjust EReserve");
        }
        if (_MReserve != _MToken.balanceOf(address(this))) {
            revert("Failed to adjust MReserve");
        }
        if (_liquidity != _LToken.totalSupply()) {
            revert("Failed to adjust liquidity");
        }

        emit MarketStateChanged(this.poolPrice(), _EReserve, _MReserve, _liquidity);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function sell(uint256 EAmount) external {
        (uint256 ESwap, uint256 MSwap) = this.askSwap(EAmount);
        uint256 MFee = this.askFee(EAmount);

        if (ESwap == 0 || MSwap == 0) {
            revert ZeroTransfer();
        }

        uint256 EAllowance = _EToken.allowance(msg.sender, address(this));
        if (EAllowance < ESwap) {
            revert InsufficientAllowance(IERC20(_EToken), ESwap, EAllowance);
        }
        if (!_MToken.transfer(msg.sender, MSwap - MFee)) {
            revert("Failed to transfer MTokens");
        }
        if (!_EToken.transferFrom(msg.sender, address(this), ESwap)) {
            revert("Failed to transfer ETokens");
        }

        uint256 liquidityOld = _liquidity;

        _EReserve += ESwap;
        _MReserve -= MSwap - MFee;
        _liquidity = Math.sqrt(_EReserve * _MReserve);

        uint256 liquidityNew = _liquidity;
        _distributeLiquidity(liquidityOld, liquidityNew);

        _recalculatePricingCurve();

        if (_EReserve != _EToken.balanceOf(address(this))) {
            revert("Failed to adjust EReserve");
        }
        if (_MReserve != _MToken.balanceOf(address(this))) {
            revert("Failed to adjust MReserve");
        }
        if (_liquidity != _LToken.totalSupply()) {
            revert("Failed to adjust liquidity");
        }

        emit MarketStateChanged(this.poolPrice(), _EReserve, _MReserve, _liquidity);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function addLiquidity(uint256 LAmount) external {
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = this.liquidityProvision(LAmount);
        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            revert ZeroTransfer();
        }

        uint256 EAllowance = _EToken.allowance(msg.sender, address(this));
        uint256 MAllowance = _MToken.allowance(msg.sender, address(this));
        if (EAllowance < ELiq) {
            revert InsufficientAllowance(IERC20(_EToken), ELiq, EAllowance);
        }
        if (MAllowance < MLiq) {
            revert InsufficientAllowance(IERC20(_MToken), MLiq, MAllowance);
        }
        if (!_EToken.transferFrom(msg.sender, address(this), ELiq)) {
            revert("Failed to transfer ETokens");
        }
        if (!_MToken.transferFrom(msg.sender, address(this), MLiq)) {
            revert("Failed to transfer MTokens");
        }

        if (_LToken.balanceOf(msg.sender) == 0) {
            _liquidityProviders.push(msg.sender);
        }

        uint256 liquidityOld = _liquidity;

        _EReserve += ELiq;
        _MReserve += MLiq;
        _liquidity = Math.sqrt(_EReserve * _MReserve);

        uint256 liquidityNew = _liquidity;

        _LToken.mint(msg.sender, liquidityNew - liquidityOld);

        _recalculatePricingCurve();

        if (_EReserve != _EToken.balanceOf(address(this))) {
            revert("Failed to adjust EReserve");
        }
        if (_MReserve != _MToken.balanceOf(address(this))) {
            revert("Failed to adjust MReserve");
        }
        if (_liquidity != _LToken.totalSupply()) {
            revert("Failed to adjust liquidity");
        }

        emit MarketStateChanged(this.poolPrice(), _EReserve, _MReserve, _liquidity);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function removeLiquidity(uint256 LAmount) external {
        (uint256 LShare, uint256 ELiq, uint256 MLiq) = this.liquidityReduction(LAmount);
        if (LShare == 0 || ELiq == 0 || MLiq == 0) {
            revert ZeroTransfer();
        }

        if (!_EToken.transfer(msg.sender, ELiq)) {
            revert("Failed to transfer ETokens");
        }
        if (!_MToken.transfer(msg.sender, MLiq)) {
            revert("Failed to transfer MTokens");
        }

        if (_LToken.balanceOf(msg.sender) == 0) {
            for (uint256 i = 0; i < _liquidityProviders.length; i++) {
                if (_liquidityProviders[i] == msg.sender) {
                    for (uint256 j = i; j < _liquidityProviders.length - 1; ++j) {
                        _liquidityProviders[j] = _liquidityProviders[j + 1];
                    }
                    _liquidityProviders.pop();
                    break;
                }
            }
        }

        uint256 liquidityOld = _liquidity;

        _EReserve -= ELiq;
        _MReserve -= MLiq;
        _liquidity = Math.sqrt(_EReserve * _MReserve);

        uint256 liquidityNew = _liquidity;

        _LToken.burn(msg.sender, liquidityOld - liquidityNew);

        _recalculatePricingCurve();

        if (_EReserve != _EToken.balanceOf(address(this))) {
            revert("Failed to adjust EReserve");
        }
        if (_MReserve != _MToken.balanceOf(address(this))) {
            revert("Failed to adjust MReserve");
        }
        if (_liquidity != _LToken.totalSupply()) {
            revert("Failed to adjust liquidity");
        }

        emit MarketStateChanged(this.poolPrice(), _EReserve, _MReserve, _liquidity);
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setSwapPriceRange(Range calldata range) external onlyOwner {
        if (!range.isValid()) {
            revert InvalidRange(range);
        }

        _swapPriceRangeX18 = range;

        _swapPriceSqrtRangeX18.isMinBounded = range.isMinBounded;
        _swapPriceSqrtRangeX18.isMaxBounded = range.isMaxBounded;
        if (_swapPriceSqrtRangeX18.isMinBounded) {
            _swapPriceSqrtRangeX18.min = sqrt(ud(range.min)).unwrap();
        }
        if (_swapPriceSqrtRangeX18.isMaxBounded) {
            _swapPriceSqrtRangeX18.max = sqrt(ud(range.max)).unwrap();
        }

        if (_swapPriceSqrtRangeX18.isMinBounded && _swapPriceSqrtRangeX18.isMaxBounded) {
            if (_swapPriceSqrtRangeX18.min == _swapPriceSqrtRangeX18.max) {
                // Swap price is bounded to a single value. Use the Constant Sum pricing curve.
                _curveType = _CSMM;
            } else {
                // Swap price is bounded on both sides, but not to a single value. Use the Concentrated Liquidity
                // pricing curve.
                _curveType = _CLMM;
            }
        } else if (_swapPriceSqrtRangeX18.isMinBounded) {
            // Swap price is bounded on only the low side. Use a partial Concentrated Liquidity pricing curve.
            _curveType = _CLMM_PARTIAL_MIN;
        } else if (_swapPriceSqrtRangeX18.isMaxBounded) {
            // Swap price is bounded on only the high side. Use a partial Concentrated Liquidity pricing curve.
            _curveType = _CLMM_PARTIAL_MAX;
        } else {
            // Swap price is unbounded. Use the Constant Product pricing curve.
            _curveType = _CPMM;
        }

        _recalculatePricingCurve();
    }

    /**
     * @inheritdoc IEnergyAMM
     */
    function setFeeRate(UD60x18 feeRate_) external onlyOwner {
        _feeRate = feeRate_;
    }
}
