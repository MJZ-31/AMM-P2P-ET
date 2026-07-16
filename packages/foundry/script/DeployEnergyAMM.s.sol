// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./DeployHelpers.s.sol";
import "../contracts/EnergyAMM.sol";
import "../contracts/EToken.sol";
import "../contracts/MToken.sol";
import "../contracts/Range.sol";

/**
 * @notice Deploy script for YourContract contract
 * @dev Inherits ScaffoldETHDeploy which:
 *      - Includes forge-std/Script.sol for deployment
 *      - Includes ScaffoldEthDeployerRunner modifier
 *      - Provides `deployer` variable
 * Example:
 * yarn deploy --file DeployYourContract.s.sol  # local anvil chain
 * yarn deploy --file DeployYourContract.s.sol --network optimism # live network (requires keystore)
 */
contract DeployEnergyAMM is ScaffoldETHDeploy {
    /**
     * @dev Deployer setup based on `ETH_KEYSTORE_ACCOUNT` in `.env`:
     *      - "scaffold-eth-default": Uses Anvil's account #9 (0xa0Ee7A142d267C1f36714E4a8F75612F20a79720), no password prompt
     *      - "scaffold-eth-custom": requires password used while creating keystore
     *
     * Note: Must use ScaffoldEthDeployerRunner modifier to:
     *      - Setup correct `deployer` account and fund it
     *      - Export contract addresses & ABIs to `nextjs` packages
     */
    function run() external ScaffoldEthDeployerRunner {
        address deployer = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
        address owner = 0x582dbea045e68002e57bab00f02d9ea38d54F52d;
        EToken eToken = new EToken();
        MToken mToken = new MToken();
        EnergyAMM AMM = new EnergyAMM(IERC20Metadata(eToken), IERC20Metadata(mToken));

        AMM.setPoolPriceRange(Range(0.5e18, 2e18, false, false));
        AMM.setFeeRate(ud(0.01e18));

        eToken.mint(deployer, 1e25);
        mToken.mint(deployer, 1e25);

        eToken.transferOwnership(owner);
        mToken.transferOwnership(owner);
        AMM.transferOwnership(owner);

        (, uint256 ELiq, uint256 MLiq) = AMM.liquidityProvision(1e21);
        eToken.approve(address(AMM), ELiq);
        mToken.approve(address(AMM), MLiq);
        AMM.addLiquidity(1e21);
    }
}
