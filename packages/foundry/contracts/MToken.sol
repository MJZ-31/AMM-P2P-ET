// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./ERC20Ownable.sol";

contract MToken is ERC20Ownable {
    constructor() ERC20Ownable("Money Token", "MTK", 18) {}
}
