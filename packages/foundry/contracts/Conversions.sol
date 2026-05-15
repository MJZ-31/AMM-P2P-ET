// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { UD60x18, powu, sqrt, ud } from "@prb/math/src/UD60x18.sol";

/**
 * @notice Converts an amount of an ERC20 token from the token's native fixed-point representation to a UD60x18.
 * @param self The amount to convert, in the token's native representation.
 * @param token The ERC20 token of the amount.
 * @return The same value, but represented by a UD60x18.
 */
function tokToUD(uint256 self, IERC20Metadata token) view returns (UD60x18) {
    uint8 decimals = token.decimals();
    if (decimals < 18) {
        return ud(self / (10 ** (decimals - 18)));
    } else {
        return ud(self * (10 ** (18 - decimals)));
    }
}

/**
 * @notice Converts an amount of an ERC20 token from a UD60x18 to the token's native fixed-point representation to a
 * UD60x18.
 * @param self The amount to convert, represented by a UD60x18.
 * @param token The ERC20 token of the amount.
 * @return The same value, but in the token's native representation.
 */
function UDToTok(UD60x18 self, IERC20Metadata token) view returns (uint256) {
    uint8 decimals = token.decimals();
    if (decimals < 18) {
        return self.unwrap() * (10 ** (decimals - 18));
    } else {
        return self.unwrap() / (10 ** (18 - decimals));
    }
}
