// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./ERC20Ownable.sol";

contract EToken is ERC20Ownable {
    constructor() ERC20Ownable("Energy Token", "ETK", 18) {}
}
