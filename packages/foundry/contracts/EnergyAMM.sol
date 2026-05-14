// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { UD60x18, powu, sqrt, ud } from "@prb/math/src/UD60x18.sol";
import { SD59x18, sd } from "@prb/math/src/SD59x18.sol";

import { ERC20Ownable } from "./ERC20Ownable.sol";

/// @title EnergyAMM: An Automated Market Maker (AMM) for the trading of energy.
/// @author Mitchel Justinen
/// @notice This contract is responsible for maintaining a liquidity pool containing reserves of
/// tokens representing energy and money, and provides methods for trading, liquidity provision,
/// and market regulation.
contract EnergyAMM is Ownable {

    /// @title Information about a liquidity addition.
    struct LiquidityAdditionInfo {
        address provider;   // The address of the liquidity provider.
        uint256 MAmount;    // The amount of MTokens added.
        uint256 EAmount;    // The amount of ETokens added.
    }

    /// @title Information about a transaction.
    struct TransactionInfo {
        address trader;     // The address of the trader.
        string transType;   // The type of transaction, either "buy" or "sell".
        uint256 MAmount;    // The amount of MTokens swapped.
        uint256 EAmount;    // The amount of ETokens swapped.
        uint256 fee;        // The amount of MTokens taken as a transaction fee.
        UD60x18 poolPrice;  // The pool price at the time of the swap.
        UD60x18 transPrice; // The per-EToken price of the transaction.
        SD59x18 slippage;   // The proportional difference between the transaction and pool price.
    }

    /// @notice The address of an ERC20 token representing currencty.
    /// @dev Ideally, this should be a stablecoin or some other representation of real currency.
    IERC20Metadata public MToken;

    /// @notice The address of an ERC20 token representing energy in kWh.
    IERC20Metadata public EToken;

    /// @notice The address of an ERC20 token representing liquidity shares.
    /// @dev Each instantiation of this contract has its own LToken contract and has exclusive
    /// rights to mint and burn the LTokens.
    ERC20Ownable public LToken;

    /// @dev The addresses of liquidity providers.
    address[] private liquidityProviders;

    /// @dev The liquidity constant of the pricing function.
    UD60x18 public liquidity;

    /// @dev The amount of virtual MTokens in the liquidity pool. These cannot leave the liquidity
    /// pool, and exist purely to force the pool price into a specific range.
    uint256 public MVirtual;

    /// @dev The amount of virtual ETokens in the liquidity pool. These cannot leave the liquidity
    /// pool, and exist purely to force the pool price into a specific range.
    uint256 public EVirtual;

    /// @notice The lowest possible pool price.
    UD60x18 public poolPriceBoundLower;

    /// @notice The highest possible pool price.
    UD60x18 public poolPriceBoundUpper;

    /// @notice The pool price whether the amount of ETokens in the liquidity pool is halfway
    /// between the minimum and maximum amounts.
    UD60x18 public poolPriceEquilibrium;

    /// @notice The proportion of transactions taken as fees.
    UD60x18 public feeRate;

    /// @notice Whether or not the market is open for liquidity addition.
    bool public isLiquidityAdditionOpen;

    /// @notice Whether or not the market is open for trading.
    bool public isTradingOpen;

    /// @notice Emitted when the market state changes, either after a liquidity addition or
    /// transaction.
    event MarketStateChanged();

    /// @notice Emitted when the market is opened for liquidity addition.
    event LiquidityAdditionOpened();

    /// @notice Emitted when the market is closed for liquidity addition.
    event LiquidityAdditionClosed();

    /// @notice Emitted when the market is opened for trading.
    event TradingOpened();

    /// @notice Emitted when the market is closed for trading.
    event TradingClosed();

    /// @notice Emitted when the market is resolved.
    event MarketResolved();

    /// @notice Thrown if a swap is attempted with a token quantity of zero.
    /// @param MSwap The amount of MTokens in the attempted swap.
    /// @param ESwap The amount of ETokens in the attempted swap.
    error ZeroSwap(uint256 MSwap, uint256 ESwap);

    /// @notice Thrown if a swap attempts to remove more reserve tokens than are available.
    /// @param _MReserve The amount of MTokens in reserve.
    /// @param _EReserve The amount of ETokens in reserve.
    /// @param MSwap The amount of MTokens to be removed in the attempted swap.
    /// @param ESwap The amount of ETokens to be removed in the attempted swap.
    error ReserveExceeded(uint256 _MReserve, uint256 _EReserve, uint256 MSwap, uint256 ESwap);

    /// @notice Thrown if a transaction is attempted when the transaction is closed, such as trading
    /// when the market is closed to trading.
    error OperationClosed();

    /// @notice Creates a new EnergyAMM contract for trading the given MToken and EToken. The
    /// liquidity pool will be empty and will have no registered liquidity proviers. The creator of
    /// the contract becomes its owner.
    /// @param _MToken The address to the MToken to trade.
    /// @param _EToken The address to the EToken to trade.
    constructor(IERC20Metadata _MToken, IERC20Metadata _EToken) Ownable(msg.sender) {
        MToken = _MToken;
        EToken = _EToken;
        LToken = new ERC20Ownable("EnergyAMM Liquidity Token", "ELIQ", _EToken.decimals());
    }

    /// @dev Converts an amount of an ERC20 token from its native representation to a UD60x18.
    /// @param value The token amount in the token's native representation.
    /// @param token The token.
    /// @return A UD60x18 equivalent to `value`.
    function tokToUD(uint256 value, IERC20Metadata token) internal view returns (UD60x18) {
        uint8 decimals = token.decimals();
        if (decimals < 18) {
            return UD60x18.wrap(value / (10**(decimals - 18)));
        } else {
            return UD60x18.wrap(value * (10**(18 - decimals)));
        }
    }

    /// @dev Converts an amount of an ERC20 token from a UD60x18 to its native representation.
    /// @param value The token amount in a UD60x18.
    /// @param token The token.
    /// @return A value equivalent to `value` in `token`'s native representation.
    function UDToTok(UD60x18 value, IERC20Metadata token) internal view returns (uint256) {
        uint8 decimals = token.decimals();
        if (decimals < 18) {
            return value.unwrap() * (10**(decimals - 18));
        } else {
            return value.unwrap() / (10**(18 - decimals));
        }
    }

    /// @dev Calculates the liquidity of the market and the amount of virtual assets in the
    /// liquidity pool. Should be executed after any operation which changes the market state.
    function calculateLiquidity() internal {
        UD60x18 a = ud(1) - sqrt(poolPriceBoundLower / poolPriceBoundUpper);
        UD60x18 b = tokToUD(this.MReserve(), MToken) / sqrt(poolPriceBoundUpper) +
            tokToUD(this.EReserve(), EToken) * sqrt(poolPriceBoundLower);
        UD60x18 c = tokToUD(this.MReserve(), MToken) * tokToUD(this.EReserve(), EToken);

        liquidity = (b + sqrt(powu(b, 2) + ud(4) * a * c)) / (ud(2) * a);

        MVirtual = UDToTok(liquidity * sqrt(poolPriceBoundLower), MToken);
        EVirtual = UDToTok(liquidity / sqrt(poolPriceBoundUpper), EToken);
    }


    /// @notice Returns the amount of MTokens in the liquidity pool.
    /// @return The amount of MTokens in the liquidity pool.
    function MReserve() external view returns (uint256) {
        return MToken.balanceOf(address(this));
    }

    /// @notice Returns the amount of ETokens in the liquidity pool.
    /// @return The amount of ETokens in the liquidity pool.
    function EReserve() external view returns (uint256) {
        return EToken.balanceOf(address(this));
    }

    /// @notice Returns the pool price, which is the ratio of MTokens to ETokens in the liquidity
    /// pool.
    /// @return The pool price.
    function poolPrice() external view returns (UD60x18) {
        return tokToUD(this.MReserve() + MVirtual, MToken) /
            tokToUD(this.EReserve() + EVirtual, EToken);
    }

    /// @notice Returns the swap amounts for buying ETokens, before fees are applied.
    /// @param EAmount The amount of ETokens to buy.
    /// @return MSwap The amount of MTokens that will be transfered from the user to the liquidity 
    /// pool.
    /// @return ESwap The amount of ETokens that will be transfered from the liquidity pool to the
    /// user.
    function bidSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap) {
        if (EAmount == 0) {
            return (0, 0);
        }

        MSwap = UDToTok(
            powu(liquidity, 2) / tokToUD(this.EReserve() + EVirtual - EAmount, EToken) -
                tokToUD(this.MReserve() + MVirtual, MToken),
            MToken);
        ESwap = EAmount;
    }

    /// @notice Returns the swap amounts for selling ETokens, before fees are applied.
    /// @param EAmount The amount of ETokens to sell.
    /// @return MSwap The amount of MTokens that will be transfered from the liquidity pool to the
    /// user.
    /// @return ESwap The amount of ETokens that will be transfered from the user to the liquidity
    /// pool.
    function askSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap) {
        if (EAmount == 0) {
            return (0, 0);
        }

        MSwap = UDToTok(
            tokToUD(this.MReserve() + MVirtual, MToken) - 
                powu(liquidity, 2) / tokToUD(this.EReserve() + EVirtual + EAmount, EToken),
            MToken);
        ESwap = EAmount;
    }

    /// @notice Returns the amount of MTokens required to fulfill the fee for buying ETokens.
    /// @param EAmount The amount of ETokens to buy.
    /// @return The fee amount.
    function bidFee(uint256 EAmount) external view returns (uint256) {
        if (EAmount == 0) {
            return 0;
        }

        (uint256 MSwap,) = this.bidSwap(EAmount);

        return UDToTok(tokToUD(MSwap, MToken) * feeRate, MToken);
    }

    /// @notice Returns the amount of MTokens required to fulfill the fee for selling ETokens.
    /// @param EAmount the amount of ETokens to sell.
    /// @return The fee amount.
    function askFee(uint256 EAmount) external view returns (uint256) {
        if (EAmount == 0) {
            return 0;
        }

        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);

        uint256 EAmountWithFee = UDToTok(tokToUD(ESwap, EToken) / (ud(1) - feeRate), EToken);

        (uint256 MSwapWithFee,) = this.askSwap(EAmountWithFee);

        return MSwapWithFee - MSwap;
    }

    /// @notice Returns the price of energy when buying.
    /// @param EAmount The amount of ETokens to buy.
    /// @return The price of energy.
    function bidPrice(uint256 EAmount) external view returns (UD60x18) {
        if (EAmount == 0) {
            return ud(0);
        }

        (uint256 MSwap, uint256 ESwap) = this.bidSwap(EAmount);
        return tokToUD(MSwap, MToken) / tokToUD(ESwap, EToken);
    }

    /// @notice Returns the price of energy when selling.
    /// @param EAmount The amount of ETokens to sell.
    /// @return The price of energy.
    function askPrice(uint256 EAmount) external view returns (UD60x18) {
        if (EAmount == 0) {
            return ud(0);
        }

        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);
        return tokToUD(MSwap, MToken) / tokToUD(ESwap, EToken);
    }

    /// @notice Returns the bid-ask spread, which is the difference between the ask price and the
    /// bid price for a certain amount of energy.
    /// @param EAmount The amount of ETokens to buy or sell.
    /// @return The bid-ask spread.
    function bidAskSpread(uint256 EAmount) external view returns (SD59x18) {
        return this.askPrice(EAmount).intoSD59x18() - this.bidPrice(EAmount).intoSD59x18();
    }

    /// @notice Returns the slippage of a bid, which is the proportional difference between the bid
    /// price and the pool price.
    /// @param EAmount The amount of ETokens to buy.
    /// @return The slippage of the bid.
    function bidSlippage(uint256 EAmount) external view returns (SD59x18) {
        return this.bidPrice(EAmount).intoSD59x18() / this.poolPrice().intoSD59x18() - sd(1);
    }

    /// @notice Returns the slippage of a ask, which is the proportional difference between the ask
    /// price and the pool price.
    /// @param EAmount The amount of ETokens to sell.
    /// @return The slippage of the ask.
    function askSlippage(uint256 EAmount) external view returns (SD59x18) {
        return this.askPrice(EAmount).intoSD59x18() / this.poolPrice().intoSD59x18() - sd(1);
    }

    /// @notice Returns the amount of MTokens and ETokens required to add an specific amount of
    /// ETokens to the liquidity pool.
    /// @param EAmount The amount of ETokens to add to the liquidity pool.
    /// @return MLiq The amount of MTokens required.
    /// @return ELiq The amount of ETokens required.
    function liquidityProvision(uint256 EAmount)
        external view returns (uint256 MLiq, uint256 ELiq) {

        if (EAmount == 0) {
            return (0, 0);
        }

        MLiq = UDToTok(
            tokToUD(this.EReserve() + EAmount, EToken) *
                sqrt(poolPriceEquilibrium * poolPriceBoundUpper) *
                (sqrt(poolPriceEquilibrium) - sqrt(poolPriceBoundLower)) /
                (sqrt(poolPriceBoundUpper) - sqrt(poolPriceEquilibrium)) -
                tokToUD(this.MReserve(), MToken),
            MToken);
        ELiq = EAmount;
    }

    /// @notice Adds liquidity to the liquidity pool.
    /// @param EAmount the amount of ETokens to add to the liquidity pool.
    /// @return info Information about the liquidity addition.
    function addLiquidity(uint256 EAmount) external returns (LiquidityAdditionInfo memory info) {
        if (!this.isLiquidityAdditionOpen()) {
            revert OperationClosed();
        }

        (uint256 MLiq, uint256 ELiq) = this.liquidityProvision(EAmount);

        require(MToken.transferFrom(msg.sender, address(this), MLiq),
                "Failed to transfer from caller.");
        require(EToken.transferFrom(msg.sender, address(this), ELiq),
                "Failed to transfer fram caller.");

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

    /// @notice Buys energy from the market.
    /// @param EAmount the amount of ETokens to buy.
    /// @return info Information about the transaction.
    function buy(uint256 EAmount) external returns (TransactionInfo memory info) {
        if (!this.isTradingOpen()) {
            revert OperationClosed();
        }

        (uint256 MSwap, uint256 ESwap) = this.bidSwap(EAmount);
        uint256 MFee = this.bidFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroSwap(MSwap, ESwap);
        }
        if (ESwap > this.EReserve()) {
            revert ReserveExceeded(0, 0, 0, 0);
        }

        info.trader = msg.sender;
        info.transType = "buy";
        info.MAmount = MSwap;
        info.EAmount = ESwap;
        info.fee = MFee;
        info.poolPrice = this.poolPrice();
        info.transPrice = this.bidPrice(EAmount);
        info.slippage = this.bidSlippage(EAmount);

        require(MToken.transferFrom(msg.sender, address(this), MSwap + MFee),
                "Failed to transfer MTokens from sender.");
        require(EToken.transfer(msg.sender, ESwap), "Failed to transfer ETokens to sender.");

        calculateLiquidity();

        emit MarketStateChanged();
    }

    /// @notice Sells energy to the market.
    /// @param EAmount the amount of ETokens to sell.
    /// @return info Information about the transaction.
    function sell(uint256 EAmount) external returns (TransactionInfo memory info) {
        if (!this.isTradingOpen()) {
            revert OperationClosed();
        }

        (uint256 MSwap, uint256 ESwap) = this.askSwap(EAmount);
        uint256 MFee = this.askFee(EAmount);

        if (MSwap == 0 || ESwap == 0) {
            revert ZeroSwap(MSwap, ESwap);
        }
        if (MSwap > this.MReserve()) {
            revert ReserveExceeded(0, 0, 0, 0);
        }

        info.trader = msg.sender;
        info.transType = "sell";
        info.MAmount = MSwap;
        info.EAmount = ESwap;
        info.fee = MFee;
        info.poolPrice = this.poolPrice();
        info.transPrice = this.askPrice(EAmount);
        info.slippage = this.askSlippage(EAmount);

        require(MToken.transfer(msg.sender, MSwap - MFee), "Failed to transfer MTokens to sender.");
        require(EToken.transferFrom(msg.sender, address(this), ESwap),
                "Failed to transfer ETokens from sender.");

        calculateLiquidity();

        emit MarketStateChanged();
    }

    /// @notice Sets the bounds on the pool price.
    /// @param lower The lowest possible pool price.
    /// @param upper The greatest possible pool price.
    function setPoolPriceBounds(UD60x18 lower, UD60x18 upper) external onlyOwner() {
        require(!this.isLiquidityAdditionOpen(),
                "Cannot change the price bounds while the market is open for liquidity addition.");
        require(!this.isTradingOpen(),
                "Cannot change the price bounds while the market is open for trading.");

        poolPriceBoundLower = lower;
        poolPriceBoundUpper = upper;
        poolPriceEquilibrium = ud(4) * poolPriceBoundLower * poolPriceBoundUpper /
            powu((sqrt(poolPriceBoundLower) + sqrt(poolPriceBoundUpper)), 2);
    }

    /// @notice Sets the fee rate for transactions.
    /// @param feeRate_ The fee rate.
    function setFeeRate(UD60x18 feeRate_) external onlyOwner() {
        require(!this.isTradingOpen(),
                "Cannot change the fee rate while the market is open for trading.");

        feeRate = feeRate_;
    }

    /// @notice Opens the market for liquidity addition.
    function openLiquidityAddition() external onlyOwner() {
        isLiquidityAdditionOpen = true;
        this.closeTrading();
        emit LiquidityAdditionOpened();
    }

    /// @notice Closes the market for liquidity addition.
    function closeLiquidityAddition() external onlyOwner() {
        isLiquidityAdditionOpen = false;
        emit LiquidityAdditionClosed();
    }

    /// @notice Opens the market for trading.
    function openTrading() external onlyOwner() {
        isTradingOpen = true;
        this.closeLiquidityAddition();
        emit TradingOpened();
    }

    /// @notice Closes the market for trading.
    function closeTrading() external onlyOwner() {
        isTradingOpen = false;
        emit TradingClosed();
    }

    /// @notice Resolves the market after trading. This involves resetting the liquidity pool and
    /// reimbursing liquidity providers.
    function resolveMarket() external onlyOwner() {
        this.closeLiquidityAddition();
        this.closeTrading();

        uint256 LTotal = LToken.totalSupply();
        for (uint256 iProviders = 0; iProviders < liquidityProviders.length; ++iProviders) {
            address provider = liquidityProviders[iProviders];
            uint256 LAmount = LToken.balanceOf(provider);
            UD60x18 proportion = tokToUD(LAmount, LToken) / tokToUD(LTotal, LToken);

            uint256 MAmount = UDToTok(proportion * tokToUD(this.MReserve(), MToken), MToken);
            uint256 EAmount = UDToTok(proportion * tokToUD(this.EReserve(), EToken), EToken);

            require(MToken.transfer(provider, MAmount),
                    "Failed to transfer MTokens to liquidity provider.");
            require(EToken.transfer(provider, EAmount),
                    "Failed to transfer MTokens to liquidity provider.");

            LToken.burn(provider, LAmount);
        }

        calculateLiquidity();
        
        emit MarketResolved();
        emit MarketStateChanged();
    }
}
