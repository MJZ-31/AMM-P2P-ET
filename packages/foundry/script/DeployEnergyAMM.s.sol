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
        MToken mToken = new MToken();
        EToken eToken = new EToken();
        EnergyAMM AMM = new EnergyAMM(IERC20Metadata(mToken), IERC20Metadata(eToken));

        AMM.setPoolPriceRange(Range(0.5e18, 2e18, false, false));
        AMM.setFeeRate(ud(0.01e18));

        address user = 0x582dbea045e68002e57bab00f02d9ea38d54F52d;

        mToken.mint(user, 1e25);
        eToken.mint(user, 1e25);
        AMM.transferOwnership(user);
    }
}
