// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidityToken is ERC20, Ownable {

    uint8 private _decimals;

    constructor(uint8 decimals_) ERC20("EnergyAMM Liquidity Token", "ELIQ") Ownable(msg.sender) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 value) external onlyOwner() {
        _mint(account, value);
    }

    function burn(address account, uint256 value) external onlyOwner() {
        _burn(account, value);
    }
}
