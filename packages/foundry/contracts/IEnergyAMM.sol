// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { SD59x18 } from "@prb/math/src/SD59x18.sol";

interface IEnergyAMM {

    struct TradeInfo {
        address trader;
        string transType;
        uint256 MAmount;
        uint256 EAmount;
        uint256 fee;
        UD60x18 poolPrice;
        UD60x18 transPrice;
        SD59x18 slippage;
    }

    struct LiquidityInfo {
        address provider;
        string transType;
        uint256 MAmount;
        uint256 EAmount;
        uint256 LAmount;
    }

    function MToken() external view returns (IERC20);

    function EToken() external view returns (IERC20);

    function LToken() external view returns (IERC20);

    function MReserve() external view returns (uint256);

    function EReserve() external view returns (uint256);

    function poolPriceRange() external view returns (UD60x18 min, UD60x18 max);

    function poolPrice() external view returns (UD60x18);

    function feeRate() external view returns (UD60x18);

    function bidRange() external view returns (uint256 min, uint256 max);

    function askRange() external view returns (uint256 min, uint256 max);

    function bidSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap);

    function askSwap(uint256 EAmount) external view returns (uint256 MSwap, uint256 ESwap);

    function bidFee(uint256 EAmount) external view returns (uint256);

    function askFee(uint256 EAmount) external view returns (uint256);

    function bidPrice(uint256 EAmount) external view returns (UD60x18);

    function askPrice(uint256 EAmount) external view returns (UD60x18);

    function bidSlippage(uint256 EAmount) external view returns (SD59x18);

    function askSlippage(uint256 EAmount) external view returns (SD59x18);

    function liquidityAdditionRange() external view returns (uint256 min, uint256 max);

    function liquidityProvision(uint256 LAmount) external view returns (uint256 MLiq, uint256 ELiq);

    function liquidityProportion(uint256 LAmount) external view returns (UD60x18);

    function buy(uint256 EAmount) external returns (TradeInfo memory);

    function sell(uint256 EAmount) external returns (TradeInfo memory);

    function addLiquidity(uint256 LAmount) external returns (LiquidityInfo memory);

    function removeLiquidity(uint256 LAmount) external returns (LiquidityInfo memory);

    function setPoolPriceRange(UD60x18 min, UD60x18 max) external;

    function setFeeRate(UD60x18 feeRate) external;

    function setBidRange(UD60x18 min, UD60x18 max) external;

    function setAskRange(UD60x18 min, UD60x18 max) external;

    function setLiquidityAdditionRange(UD60x18 min, UD60x18 max) external;
}
