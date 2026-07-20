// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { SD59x18 } from "@prb/math/src/SD59x18.sol";

import { Range } from "./Range.sol";

/**
 * @notice Emitted when the state of the market changes. This occurs on every buy, sell, or liquidity addition or
 * removal.
 * @param poolPrice The current pool price.
 * @param EReserve The current reserve of ETokens.
 * @param MReserve The current reserve of MTokens.
 * @param liquidity The current market liquidity.
 */
event MarketStateChanged(UD60x18 poolPrice, uint256 EReserve, uint256 MReserve, uint256 liquidity);

/**
 * @notice Thrown if an operation is attempted without the required allowance of an ERC20 token.
 * @param token The ERC20 token the allowance is for.
 * @param required The required allowance amount.
 * @param allowance The actual allowance amount, which is less than the required amount.
 */
error InsufficientAllowance(IERC20 token, uint256 required, uint256 allowance);

/**
 * @notice Thrown if an asset amount as part of a transaction is zero. A transaction for nothing is not worth
 * processing.
 */
error ZeroTransfer();

/**
 * @notice Information about a trade.
 */
struct TradeInfo {
    address trader;
    string op;
    uint256 EAmount;
    uint256 MAmount;
    uint256 fee;
    UD60x18 poolPrice;
    UD60x18 tradePrice;
    SD59x18 slippage;
}

/**
 * @notice Information about a liquidity addition or removal.
 */
struct LiquidityInfo {
    address provider;
    string op;
    uint256 ELiq;
    uint256 MLiq;
    uint256 LShare;
    UD60x18 poolPrice;
    UD60x18 liqPrice;
}

/**
 * @title Interface for an energy trading AMM.
 * @author Mitchel Justinen
 */
interface IEnergyAMM {
    /**
     * @notice Returns the address of an ERC20 token representing energy.
     * @return The address of the EToken.
     */
    function EToken() external view returns (IERC20);

    /**
     * @notice Returns the address of an ERC20 token representing currency.
     * @return The address of the MToken.
     */
    function MToken() external view returns (IERC20);

    /**
     * @notice Returns the address of an ERC20 token representing liquidity shares in this market.
     * @return The address of the LToken.
     */
    function LToken() external view returns (IERC20);

    /**
     * @notice Returns the amount of ETokens in the liquidity pool.
     * @dev The liquidity pool is composed of the tokens owned by the contract itself, so this value will be equivalent
     * to the amount of ETokens owned by this contract.
     * @return The amount of ETokens in the liquidity pool.
     */
    function EReserve() external view returns (uint256);

    /**
     * @notice Returns the amount of MTokens in the liquidity pool.
     * @dev The liquidity pool is composed of the tokens owned by the contract itself, so this value will be equivalent
     * to the amount of MTokens owned by this contract.
     * @return The amount of MTokens in the liquidity pool.
     */
    function MReserve() external view returns (uint256);

    /**
     * @notice Returns the amount of liquidity in the liquidity pool.
     * @dev This is equivalent to the total supply of LTokens.
     * @return The amount of market liquidity.
     */
    function liquidity() external view returns (uint256);

    /**
     * @notice Returns the range of possible values for the pool price.
     * @return The pool price range.
     */
    function poolPriceRange() external view returns (Range memory);

    /**
     * @notice Returns the MToken per EToken price of energy in the market.
     * @return The pool price.
     */
    function poolPrice() external view returns (UD60x18);

    /**
     * @notice Returns the trading fee rate. This is the proportion of each swap that will be taken as fees.
     * @return The fee rate.
     */
    function feeRate() external view returns (UD60x18);

    /**
     * @notice Returns the range of possible amounts of ETokens for a bid.
     * @return The bid range.
     */
    function bidRange() external view returns (Range memory);

    /**
     * @notice Returns the range of possible amounts of ETokens for an ask.
     * @return The ask range.
     */
    function askRange() external view returns (Range memory);

    /**
     * @notice Returns the amount of MTokens and ETokens that will be swapped for a bid.
     * @param EAmount The amount of ETokens being bought.
     * @return ESwap The amount of ETokens that will be transferred from the liquidity pool to the sender for the swap.
     * @return MSwap The amount of MTokens that will be transferred from the sender to the liquidity pool for the swap.
     */
    function bidSwap(uint256 EAmount) external view returns (uint256 ESwap, uint256 MSwap);

    /**
     * @notice Returns the amount of MTokens and ETokens that will be swapped for an ask.
     * @param EAmount The amount of ETokens being sold.
     * @return ESwap The amount of ETokens that will be transferred from the sender to the liquidity pool for the swap.
     * @return MSwap The amount of MTokens that will be transferred from the liquidity pool to the sender for the swap.
     */
    function askSwap(uint256 EAmount) external view returns (uint256 ESwap, uint256 MSwap);

    /**
     * @notice Returns the amount of MTokens which will be taken as the fee for a bid.
     * @param EAmount The amount of ETokens being bought.
     * @return The fee for a bid.
     */
    function bidFee(uint256 EAmount) external view returns (uint256);

    /**
     * @notice Returns the amount of MTokens which will be taken as the fee for an ask.
     * @param EAmount The amount of ETokens being sold.
     * @return The fee for an ask.
     */
    function askFee(uint256 EAmount) external view returns (uint256);

    /**
     * @notice Returns the MToken per EToken price of energy for a bid, excluding fees.
     * @param EAmount The amount of ETokens being bought.
     * @return The price of a bid.
     */
    function bidPrice(uint256 EAmount) external view returns (UD60x18);

    /**
     * @notice Returns the MToken per EToken price of energy for an ask, excluding fees.
     * @param EAmount The amount of ETokens being sold.
     * @return The price of an ask.
     */
    function askPrice(uint256 EAmount) external view returns (UD60x18);

    /**
     * @notice Returns the proportional difference between the price of a bid and the current pool price. This measures
     * the deviation of the actual price of energy from the market price.
     * @param EAmount The amount of ETokens being bought.
     * @return The slippage of a bid.
     */
    function bidSlippage(uint256 EAmount) external view returns (SD59x18);

    /**
     * @notice Returns the proportional difference between the price of an ask and the current pool price. This measures
     * the deviation of the actual price of energy from the market price.
     * @param EAmount The amount of ETokens being sold.
     * @return The slippage of an ask.
     */
    function askSlippage(uint256 EAmount) external view returns (SD59x18);

    /**
     * @notice Returns the amount of MTokens and ETokens required to add a certain amount of liquidity to the market.
     * @param LAmount The amount of liquidity being added to the market.
     * @return LShare The amount of LTokens that will be minted and transferred to the sender.
     * @return ELiq The amount of ETokens that will be transferred from the sender to the liquidity pool. This may be
     * lower than MAmount to keep the addition price point in the pool price range.
     * @return MLiq The amount of MTokens that will be transferred from the sender to the liquidity pool. This may be
     * lower than MAmount to keep the addition price point in the pool price range.
     */
    function liquidityProvision(uint256 LAmount)
        external
        view
        returns (uint256 LShare, uint256 ELiq, uint256 MLiq);

    /**
     * @notice Returns the amount of MTokens and ETokens to be returned to a liquidity provider for a liquidity removal.
     * @param LAmount The amount of LTokens being given up by the liquidity provider.
     * @return LShare The amount of LTokens that will be transferred from the sender and burned.
     * @return ELiq The amount of ETokens that will be transferred from the liquidity pool to the sender.
     * @return MLiq The amount of MTokens that will be transferred from the liquidity pool to the sender.
     */
    function liquidityReduction(uint256 LAmount) external view returns (uint256 LShare, uint256 ELiq, uint256 MLiq);

    /**
     * @notice Returns the proportion of liquidity shares that a liquidity provider holds.
     * @param provider The address of the liquidity provider.
     * @return The provider's proportion of liquidity.
     */
    function liquidityProportion(address provider) external view returns (UD60x18);

    /**
     * @notice Executes a market swap to buy ETokens. The requested amount of ETokens will be transferred from the
     * liquidity pool to the sender. The corresponding amount of MTokens, plus fees, will be transferred from the sender
     * to the liquidity pool. The fee will be split among the liquidity providers in proportion to their liquidity
     * shares.
     * @param EAmount The amount of ETokens being bought.
     * @return Information about the trade.
     */
    function buy(uint256 EAmount) external returns (TradeInfo memory);

    /**
     * @notice Executes a market swap to sell ETokens. The requested amount of ETokens will be transferred from the
     * sender to the liquidity pool. The corresponding amount of MTokens, minus fees, will be transferred from the
     * liquidity pool to the sender. The fee will be split among the liquidity providers in proportion to their
     * liquidity shares.
     * @param EAmount The amount of ETokens being sold.
     * @return Information about the trade.
     */
    function sell(uint256 EAmount) external returns (TradeInfo memory);

    /**
     * @notice Executes a liquidity addition. The required amount of MTokens and ETokens will be transferred from the
     * sender to the liquidity pool. A corresponding amount of LTokens will be minted and transferred to the sender.
     * @param LAmount The amount of liquidity to add.
     * @return Information about the liquidity addition.
     */
    function addLiquidity(uint256 LAmount) external returns (LiquidityInfo memory);

    /**
     * @notice Executes a liquidity removal. The desired amount of LTokens will be transferred from the sender and
     * burned. An amount of MTokens and ETokens in proportion to the amount of LTokens sold will be transferreed from
     * the liquidity pool to the sender.
     * @param LAmount The amount of LTokens being sold.
     * @return Information about the liquidity removal.
     */
    function removeLiquidity(uint256 LAmount) external returns (LiquidityInfo memory);

    /**
     * @notice Sets the pool price range.
     * @param range The pool price range.
     */
    function setPoolPriceRange(Range memory range) external;

    /**
     * @notice Sets the fee rate.
     * @param feeRate The fee rate.
     */
    function setFeeRate(UD60x18 feeRate) external;
}
