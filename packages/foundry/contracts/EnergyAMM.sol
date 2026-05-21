// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { UD60x18, convert, powu, sqrt, ud } from "@prb/math/src/UD60x18.sol";
import { SD59x18 } from "@prb/math/src/SD59x18.sol";

import { tokToUD, UDToTok } from "./Conversions.sol";
import { ERC20Ownable } from "./ERC20Ownable.sol";

using { tokToUD } for uint256;
using { UDToTok } for UD60x18;

/**
 * @notice Emitted when the market state changes, either after a liquidity addition or transaction.
 */
event MarketStateChanged();

/**
 * @notice Emitted when the market is opened for liquidity addition.
 */
event LiquidityAdditionOpened();

/**
 * @notice Emitted when the market is closed for liquidity addition.
 */
event LiquidityAdditionClosed();

/**
 * @notice Emitted when the market is opened for trading.
 */
event TradingOpened();

/**
 * @notice Emitted when the market is closed for trading.
 */
event TradingClosed();

/**
 * @notice Emitted when the market is resolved.
 */
event MarketResolved();

/**
 * @notice Thrown if a liquidity addition is attempted with a token quantity of zero.
 * @param MLiq The amount of MTokens in the attempted liquidity addition.
 * @param ELiq The amount of ETokens in the attempted liquidity addition.
 */
error ZeroProvision(uint256 MLiq, uint256 ELiq);

/**
 * @notice Thrown if a swap is attempted with a token quantity of zero.
 * @param MSwap The amount of MTokens in the attempted swap.
 * @param ESwap The amount of ETokens in the attempted swap.
 */
error ZeroSwap(uint256 MSwap, uint256 ESwap);

/**
 * @notice Thrown if bid is attempted for an amount of ETokens outside of the allowable range.
 * @param EMin The minimum amount of ETokens for a bid.
 * @param EMin The maximum amount of ETokens for a bid.
 * @param EAmount The amount of ETokens made in the bid.
 */
error BidOutsideRange(uint256 EMin, uint256 EMax, uint256 EAmount);

/**
 * @notice Thrown if ask is attempted for an amount of ETokens outside of the allowable range.
 * @param EMin The minimum amount of ETokens for a ask.
 * @param EMin The maximum amount of ETokens for a ask.
 * @param EAmount The amount of ETokens made in the ask.
 */
error AskOutsideRange(uint256 EMin, uint256 EMax, uint256 EAmount);


/**
 * @notice Thrown if the pool price bounds are set to an invalid range. For example, if the lower bound is greater than
 * the upper bound.
 * @param lower The lower bound of the pool price.
 * @param upper The lower bound of the pool price.
 */
error InvalidPoolPriceBounds(UD60x18 lower, UD60x18 upper);

/**
 * @notice Thrown if a transaction is attempted without the required allowance of MTokens and/or ETokens.
 * @param MRequired The required amount of MTokens.
 * @param ERequired The required amount of ETokens.
 * @param MAllowance The amount of MTokens given by the caller.
 * @param EAllowance The amount of ETokens given by the caller.
 */
error InsufficientAllowance(uint256 MRequired, uint256 ERequired, uint256 MAllowance, uint256 EAllowance);

/**
 * @notice Thrown if a operation is attempted while the operation is closed, such as trading when the market is
 * closed to trading.
 */
error OperationClosed();

/**
 * @title EnergyAMM: An Automated Market Maker (AMM) for the trading of energy.
 * @author Mitchel Justinen
 * @notice This contract is responsible for maintaining a liquidity pool containing reserves of tokens representing
 * energy and money, and provides methods for trading, liquidity provision, and market regulation.
 */
contract EnergyAMM is Ownable {
    /**
     * @title Information about a liquidity addition.
     */
    struct LiquidityAdditionInfo {
        address provider; // The address of the liquidity provider.
        uint256 MAmount; // The amount of MTokens added.
        uint256 EAmount; // The amount of ETokens added.
    }

    /**
     * @title Information about a transaction.
     */
    struct TransactionInfo {
        address trader; // The address of the trader.
        string transType; // The type of transaction, either "buy" or "sell".
        uint256 MAmount; // The amount of MTokens swapped.
        uint256 EAmount; // The amount of ETokens swapped.
        uint256 fee; // The amount of MTokens taken as a transaction fee.
        UD60x18 poolPrice; // The pool price at the time of the swap.
        UD60x18 transPrice; // The per-EToken price of the transaction.
        SD59x18 slippage; // The proportional difference between the transaction and pool price.
    }

    /**
     * @notice The address of an ERC20 token representing currencty.
     * @dev Ideally, this should be a stablecoin or some other representation of real currency.
     */
    IERC20Metadata public MToken;

    /**
     * @notice The address of an ERC20 token representing energy in kWh.
     */
    IERC20Metadata public EToken;

    /**
     * @notice The address of an ERC20 token representing liquidity shares.
     * @dev Each instantiation of this contract has its own LToken contract and has exclusive rights to mint and burn
     * the LTokens.
     */
    ERC20Ownable public LToken;

    /**
     * @dev The addresses of liquidity providers.
     */
    address[] private liquidityProviders;

    /**
     * @notice The liquidity constant of the pricing function.
     */
    UD60x18 public liquidity;

    /**
     * @notice The amount of virtual MTokens in the liquidity pool. These cannot leave the liquidity pool, and exist
     * purely to force the pool price into a specific range.
     */
    uint256 public MVirtual;

    /**
     * @notice The amount of virtual ETokens in the liquidity pool. These cannot leave the liquidity pool, and exist
     * purely to force the pool price into a specific range.
     */
    uint256 public EVirtual;

    /**
     * @notice The lowest possible pool price.
     */
    UD60x18 public poolPriceBoundLower;

    /**
     * @notice The highest possible pool price.
     */
    UD60x18 public poolPriceBoundUpper;

    /**
     * @notice The pool price where the amount of ETokens in the liquidity pool is halfway between the minimum and
     * maximum amounts.
     */
    UD60x18 public poolPriceEquilibrium;

    /**
     * @notice The proportion of transactions taken as fees.
     */
    UD60x18 public feeRate;

    /**
     * @notice Whether or not the market is open for liquidity addition.
     */
    bool public isLiquidityAdditionOpen;

    /**
     * @notice Whether or not the market is open for trading.
     */
    bool public isTradingOpen;

    /**
     * @notice Creates a new EnergyAMM contract for trading the given MToken and EToken. The liquidity pool will be
     * empty and will have no registered liquidity providers. The creator of the contract becomes its owner.
     * @param _MToken The address to the MToken to trade.
     * @param _EToken The address to the EToken to trade.
     */
    constructor(IERC20Metadata _MToken, IERC20Metadata _EToken) Ownable(msg.sender) {
        MToken = _MToken;
        EToken = _EToken;
        LToken = new ERC20Ownable("EnergyAMM Liquidity Token", "ELIQ", _EToken.decimals());
    }

    /**
     * @dev Calculates the liquidity of the market and the amount of virtual assets in the liquidity pool. Should be
     * executed after any operation which changes the market state.
     */
    function calculateLiquidity() internal {
        UD60x18 M = this.MReserve().tokToUD(MToken);
        UD60x18 E = this.EReserve().tokToUD(EToken);

        UD60x18 a = convert(1) - sqrt(poolPriceBoundLower / poolPriceBoundUpper);
        UD60x18 b = M / sqrt(poolPriceBoundUpper) + E * sqrt(poolPriceBoundLower);
        UD60x18 c = M * E;

        liquidity = (b + sqrt(powu(b, 2) + convert(4) * a * c)) / (convert(2) * a);

        MVirtual = (liquidity * sqrt(poolPriceBoundLower)).UDToTok(MToken);
        EVirtual = (liquidity / sqrt(poolPriceBoundUpper)).UDToTok(EToken);
    }

    /**
     * @notice Returns the amount of MTokens in the liquidity pool.
     * @return The amount of MTokens in the liquidity pool.
     */
    function MReserve() external view returns (uint256) {
        return MToken.balanceOf(address(this));
    }

    /**
     * @notice Returns the amount of ETokens in the liquidity pool.
     * @return The amount of ETokens in the liquidity pool.
     */
    function EReserve() external view returns (uint256) {
        return EToken.balanceOf(address(this));
    }

    /**
     * @notice Returns the pool price, which is the ratio of MTokens to ETokens in the liquidity pool.
     * @return The pool price.
     */
    function poolPrice() external view returns (UD60x18) {
        return (this.MReserve() + MVirtual).tokToUD(MToken) / (this.EReserve() + EVirtual).tokToUD(EToken);
    }

    /**
     * @notice Returns the range of valid amount of ETokens for a bid.
     * @return EMin The minimum amount of ETokens.
     * @return EMax The maximum amount of ETokens.
     */
    function bidRange() external view returns (uint256 EMin, uint256 EMax) {
        EMin = 0;
        EMax = this.EReserve();
    }

    /**
     * @notice Returns the range of valid amount of ETokens for an ask.
     * @return EMin The minimum amount of ETokens.
     * @return EMax The maximum amount of ETokens.
     */
    function askRange() external view returns (uint256 EMin, uint256 EMax) {
        EMin = 0;
        EMax = (powu(liquidity, 2) / MVirtual.tokToUD(MToken) - (this.EReserve() + EVirtual).tokToUD(EToken)).UDToTok(EToken);
    }

    /**
     * @notice Returns the swap amounts for buying ETokens, before fees are applied.
     * @param EAmount The amount of ETokens to buy.
     * @return MSwap The amount of MTokens that will be transfered from the user to the liquidity pool.
     * @return ESwap The amount of ETokens that will be transfered from the liquidity pool to the user.
     */
    function bidSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap) {
        (uint256 EMin, uint256 EMax) = this.bidRange();
        if (EAmount < EMin || EAmount > EMax) {
            revert BidOutsideRange(EMin, EMax, EAmount);
        }

        uint256 EReserveNew = this.EReserve() + EVirtual - EAmount;
        uint256 MReserveNew = (powu(liquidity, 2) / (EReserveNew).tokToUD(EToken)).UDToTok(MToken);

        if ((this.MReserve() + MVirtual) > MReserveNew) {
            MSwap = 0;
        } else {
            MSwap = MReserveNew - (this.MReserve() + MVirtual);
        }

        if (EReserveNew > (this.EReserve() + EVirtual)) {
            ESwap = 0;
        } else {
            ESwap = (this.EReserve() + EVirtual) - EReserveNew;
        }

        if (MSwap == 0) {
            ESwap = 0;
        }
        if (ESwap == 0) {
            MSwap = 0;
        }
    }

    /**
     * @notice Returns the swap amounts for selling ETokens, before fees are applied.
     * @param EAmount The amount of ETokens to sell.
     * @return MSwap The amount of MTokens that will be transfered from the liquidity pool to the user.
     * @return ESwap The amount of ETokens that will be transfered from the user to the liquidity pool.
     */
    function askSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap) {
        (uint256 EMin, uint256 EMax) = this.askRange();
        if (EAmount < EMin || EAmount > EMax) {
            revert AskOutsideRange(EMin, EMax, EAmount);
        }

        uint256 EReserveNew = this.EReserve() + EVirtual + EAmount;
        uint256 MReserveNew = (powu(liquidity, 2) / EReserveNew.tokToUD(EToken)).UDToTok(MToken);

        if (MReserveNew > (this.MReserve() + MVirtual)) {
            MSwap = 0;
        } else {
            MSwap = (this.MReserve() + MVirtual) - MReserveNew;
        }

        if ((this.EReserve() + EVirtual) > EReserveNew) {
            ESwap = 0;
        } else {
            ESwap = EReserveNew - (this.EReserve() + EVirtual);
        }

        if (MSwap == 0) {
            ESwap = 0;
        }
        if (ESwap == 0) {
            MSwap = 0;
        }
    }

    /**
     * @notice Returns the amount of MTokens required to fulfill the fee for buying ETokens.
     * @param EAmount The amount of ETokens to buy.
     * @return The fee amount.
     */
    function bidFee(uint256 EAmount) external view returns (uint256) {
        (uint256 MSwap,) = this.bidSwap(EAmount);

        return (MSwap.tokToUD(MToken) * feeRate).UDToTok(MToken);
    }

    /**
     * @notice Returns the amount of MTokens required to fulfill the fee for selling ETokens.
     * @param EAmount the amount of ETokens to sell.
     * @return The fee amount.
     */
    function askFee(uint256 EAmount) external view returns (uint256) {
        (uint256 MSwap,) = this.askSwap(EAmount);

        (uint256 MSwapWithoutFee,) = this.askSwap((EAmount.tokToUD(EToken) * (convert(1) - feeRate)).UDToTok(EToken));

        return MSwap - MSwapWithoutFee;
    }

    /**
     * @notice Returns the price of energy when buying.
     * @param EAmount The amount of ETokens to buy.
     * @return The price of energy.
     */
    function bidPrice(uint256 EAmount) external view returns (UD60x18) {
        (uint256 MSwap, uint256 ESwap) = this.bidSwap(EAmount);

        if (MSwap.tokToUD(MToken) == ud(0) || ESwap.tokToUD(EToken) == ud(0)) {
            return ud(0);
        }
        return MSwap.tokToUD(MToken) / ESwap.tokToUD(EToken);
    }

    /**
     * @notice Returns the price of energy when selling.
     * @param EAmount The amount of ETokens to sell.
     * @return The price of energy.
     */
    function askPrice(uint256 EAmount) external view returns (UD60x18) {
        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);

        if (MSwap.tokToUD(MToken) == ud(0) || ESwap.tokToUD(EToken) == ud(0)) {
            return ud(0);
        }
        return MSwap.tokToUD(MToken) / ESwap.tokToUD(EToken);
    }

    /**
     * @notice Returns the bid-ask spread, which is the difference between the ask price and the bid price for a certain
     * amount of energy.
     * @param EAmount The amount of ETokens to buy or sell.
     * @return The bid-ask spread.
     */
    function bidAskSpread(uint256 EAmount) external view returns (SD59x18) {
        return this.askPrice(EAmount).intoSD59x18() - this.bidPrice(EAmount).intoSD59x18();
    }

    /**
     * @notice Returns the slippage of a bid, which is the proportional difference between the bid price and the pool
     * price.
     * @param EAmount The amount of ETokens to buy.
     * @return The slippage of the bid.
     */
    function bidSlippage(uint256 EAmount) external view returns (SD59x18) {
        return (this.bidPrice(EAmount) / this.poolPrice()).intoSD59x18() - convert(1).intoSD59x18();
    }

    /**
     * @notice Returns the slippage of a ask, which is the proportional difference between the ask price and the pool
     * price.
     * @param EAmount The amount of ETokens to sell.
     * @return The slippage of the ask.
     */
    function askSlippage(uint256 EAmount) external view returns (SD59x18) {
        return (this.askPrice(EAmount) / this.poolPrice()).intoSD59x18() - convert(1).intoSD59x18();
    }

    /**
     * @notice Returns the amount of MTokens and ETokens required to add an specific amount of ETokens to the liquidity
     * pool.
     * @param EAmount The amount of ETokens to add to the liquidity pool.
     * @return MLiq The amount of MTokens required.
     * @return ELiq The amount of ETokens required.
     */
    function liquidityProvision(uint256 EAmount) external view returns (uint256 MLiq, uint256 ELiq) {
        if (EAmount == 0) {
            return (0, 0);
        }

        MLiq = ((this.EReserve() + EAmount).tokToUD(EToken) * sqrt(poolPriceEquilibrium * poolPriceBoundUpper)
                * (sqrt(poolPriceEquilibrium) - sqrt(poolPriceBoundLower))
                / (sqrt(poolPriceBoundUpper) - sqrt(poolPriceEquilibrium)) - (this.MReserve()).tokToUD(MToken))
        .UDToTok(MToken);
        ELiq = EAmount;
    }

    /**
     * @notice Adds liquidity to the liquidity pool.
     * @param EAmount the amount of ETokens to add to the liquidity pool.
     * @return info Information about the liquidity addition.
     */
    function addLiquidity(uint256 EAmount) external returns (LiquidityAdditionInfo memory info) {
        if (!this.isLiquidityAdditionOpen()) {
            revert OperationClosed();
        }

        (uint256 MLiq, uint256 ELiq) = this.liquidityProvision(EAmount);
        if (MLiq == 0 || ELiq == 0) {
            revert ZeroProvision(MLiq, ELiq);
        }

        uint256 MAllowance = MToken.allowance(msg.sender, address(this));
        uint256 EAllowance = EToken.allowance(msg.sender, address(this));
        if (MAllowance < MLiq || EAllowance < ELiq) {
            revert InsufficientAllowance(MLiq, ELiq, MAllowance, EAllowance);
        } else {
            require(MToken.transferFrom(msg.sender, address(this), MLiq));
            require(EToken.transferFrom(msg.sender, address(this), ELiq));
        }

        bool isRegistered = false;
        for (uint256 iProviders = 0; iProviders < liquidityProviders.length; ++iProviders) {
            if (liquidityProviders[iProviders] == msg.sender) {
                isRegistered = true;
            }
        }
        if (!isRegistered) {
            liquidityProviders.push(msg.sender);
        }
        LToken.mint(msg.sender, ELiq);

        info.provider = msg.sender;
        info.MAmount = MLiq;
        info.EAmount = ELiq;

        calculateLiquidity();

        emit MarketStateChanged();
    }

    /**
     * @notice Buys energy from the market.
     * @param EAmount the amount of ETokens to buy.
     * @return info Information about the transaction.
     */
    function buy(uint256 EAmount) external returns (TransactionInfo memory info) {
        if (!this.isTradingOpen()) {
            revert OperationClosed();
        }

        (uint256 MSwap, uint256 ESwap) = this.bidSwap(EAmount);
        uint256 MFee = this.bidFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroSwap(MSwap, ESwap);
        }

        info.trader = msg.sender;
        info.transType = "buy";
        info.MAmount = MSwap;
        info.EAmount = ESwap;
        info.fee = MFee;
        info.poolPrice = this.poolPrice();
        info.transPrice = this.bidPrice(EAmount);
        info.slippage = this.bidSlippage(EAmount);

        uint256 MAllowance = MToken.allowance(msg.sender, address(this));
        uint256 EAllowance = EToken.allowance(msg.sender, address(this));
        if (MAllowance < MSwap + MFee) {
            revert InsufficientAllowance(MSwap + MFee, 0, MAllowance, EAllowance);
        } else {
            require(MToken.transferFrom(msg.sender, address(this), MSwap + MFee));
            require(EToken.transfer(msg.sender, ESwap));
        }

        calculateLiquidity();

        emit MarketStateChanged();
    }

    /**
     * @notice Sells energy to the market.
     * @param EAmount the amount of ETokens to sell.
     * @return info Information about the transaction.
     */
    function sell(uint256 EAmount) external returns (TransactionInfo memory info) {
        if (!this.isTradingOpen()) {
            revert OperationClosed();
        }

        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);
        uint256 MFee = this.askFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroSwap(MSwap, ESwap);
        }

        info.trader = msg.sender;
        info.transType = "sell";
        info.MAmount = MSwap;
        info.EAmount = ESwap;
        info.fee = MFee;
        info.poolPrice = this.poolPrice();
        info.transPrice = this.askPrice(EAmount);
        info.slippage = this.askSlippage(EAmount);

        uint256 MAllowance = MToken.allowance(msg.sender, address(this));
        uint256 EAllowance = EToken.allowance(msg.sender, address(this));
        if (EAllowance < ESwap) {
            revert InsufficientAllowance(0, ESwap, MAllowance, EAllowance);
        } else {
            require(MToken.transfer(msg.sender, MSwap - MFee));
            require(EToken.transferFrom(msg.sender, address(this), ESwap));
        }

        calculateLiquidity();

        emit MarketStateChanged();
    }

    /**
     * @notice Sets the bounds on the pool price.
     * @param lower The lowest possible pool price.
     * @param upper The greatest possible pool price.
     */
    function setPoolPriceBounds(UD60x18 lower, UD60x18 upper) external onlyOwner {
        if (this.isLiquidityAdditionOpen() || this.isTradingOpen()) {
            revert OperationClosed();
        }
        if (lower >= upper) {
            revert InvalidPoolPriceBounds(lower, upper);
        }

        poolPriceBoundLower = lower;
        poolPriceBoundUpper = upper;
        poolPriceEquilibrium = convert(4) * poolPriceBoundLower * poolPriceBoundUpper
            / powu((sqrt(poolPriceBoundLower) + sqrt(poolPriceBoundUpper)), 2);
    }

    /**
     * @notice Sets the fee rate for transactions.
     * @param feeRate_ The fee rate.
     */
    function setFeeRate(UD60x18 feeRate_) external onlyOwner {
        if (this.isLiquidityAdditionOpen() || this.isTradingOpen()) {
            revert OperationClosed();
        }
        feeRate = feeRate_;
    }

    /**
     * @notice Opens the market for liquidity addition.
     */
    function openLiquidityAddition() external onlyOwner {
        isTradingOpen = false;
        emit TradingClosed();

        isLiquidityAdditionOpen = true;
        emit LiquidityAdditionOpened();
    }

    /**
     * @notice Closes the market for liquidity addition.
     */
    function closeLiquidityAddition() external onlyOwner {
        isLiquidityAdditionOpen = false;
        emit LiquidityAdditionClosed();
    }

    /**
     * @notice Opens the market for trading.
     */
    function openTrading() external onlyOwner {
        isLiquidityAdditionOpen = false;
        emit LiquidityAdditionClosed();

        isTradingOpen = true;
        emit TradingOpened();
    }

    /**
     * @notice Closes the market for trading.
     */
    function closeTrading() external onlyOwner {
        isTradingOpen = false;
        emit TradingClosed();
    }

    /**
     * @notice Resolves the market after trading. This involves resetting the liquidity pool and reimbursing liquidity
     * providers.
     */
    function resolveMarket() external onlyOwner {
        this.closeLiquidityAddition();
        this.closeTrading();

        uint256 LTotal = LToken.totalSupply();
        for (uint256 iProviders = 0; iProviders < liquidityProviders.length; ++iProviders) {
            address provider = liquidityProviders[iProviders];
            uint256 LAmount = LToken.balanceOf(provider);
            UD60x18 proportion = tokToUD(LAmount, LToken) / tokToUD(LTotal, LToken);

            uint256 MAmount = (proportion * this.MReserve().tokToUD(MToken)).UDToTok(MToken);
            uint256 EAmount = (proportion * this.EReserve().tokToUD(EToken)).UDToTok(EToken);

            require(MToken.transfer(provider, MAmount));
            require(EToken.transfer(provider, EAmount));

            LToken.burn(provider, LAmount);
        }

        calculateLiquidity();

        emit MarketResolved();
        emit MarketStateChanged();
    }
}
