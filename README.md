# AMM-P2P-ET
This project contains files, code, and/or documentation from
[scaffold-eth-2](https://github.com/scaffold-eth/scaffold-eth-2), which is available for use under
an MIT license. A copy of this license can be found in
[licenses/LICENSE-SCAFFOLD-ETH-2.txt](https://github.com/MJZ-31/AMM-P2P-ET/blob/main/licenses/LICENSE-SCAFFOLD-ETH-2.txt).
As per the license, anyone can modify and reuse scaffold-eth-2 subject to the terms of the license.

# Requirements
- Node.js: Versions v18.17 or higher are required.
    ```
    node -v
    ```
- Yarn: Either Yarn Classic (v1.x) or Yarn Berry (v2+) is required, as `scaffold-ETH 2` relies heavily on Yarn Workspaces.
    ```
    npm install --global yarn
    yarn -v
    ```
- Foundry: The smart contract development toolchain. 
    ```
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
    ```

# Get Started
1. Clone this repository.
2. Install Project Dependencies. Navigate to the root directory of your cloned repository and run the setup command:
    ```
    yarn install
    ```
3. Once `yarn install` completes, create three separate terminal windows to run the localized stack:

    Terminal 1 (Local Chain): Starts a local Ethereum node using Foundry's Anvil
    ```
    yarn chain
    ```
    Terminal 2: (Smart Contracts): Compiles and deploys your Solidity contracts to the local network.
    ```
    yarn deploy
    ```
    In the case of OpenZeppelin Solidity dependency contracts not found,install the contracts via Forge:
    ```
    cd packages/foundry
    forge install OpenZeppelin/openzeppelin-contracts
    forge clean && forge build
    ```

    Terminal 3 (Frontend): Boots up your Next.js frontend at http://localhost:3000
    ```
    yarn start
    ```
4. You will see the NextJS frontend (DApp) launched by visiting http://localhost:3000 in your browser.