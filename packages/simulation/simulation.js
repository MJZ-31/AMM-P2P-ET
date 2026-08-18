const ethers = require("ethers")
const xlsx = require("xlsx")
const fs = require("fs")

async function main() {
    let sheet = xlsx.readFile("household_data_cleaned_60.ods").Sheets["60min"]
    data = xlsx.utils.sheet_to_json(sheet).map((e) => {
        delete e.household
        return Object.values(e)
    }).splice(2)

    const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545")
    const households = [
        new ethers.NonceManager(
            new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97", provider)),
        new ethers.NonceManager(
            new ethers.Wallet("0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6", provider))
    ]

    const prb_math_errors_abi = [
        "error PRBMath_UD60x18_Ceil_Overflow(uint256)",
        "error PRBMath_UD60x18_Convert_Overflow(uint256)",
        "error PRBMath_UD60x18_Exp_InputTooBig(uint256)",
        "error PRBMath_UD60x18_Exp2_InputTooBig(uint256 x)",
        "error PRBMath_UD60x18_Gm_Overflow(uint256,uint256)",
        "error PRBMath_UD60x18_IntoSD1x18_Overflow(uint256)",
        "error PRBMath_UD60x18_IntoSD21x18_Overflow(uint256)",
        "error PRBMath_UD60x18_IntoSD59x18_Overflow(uint256)",
        "error PRBMath_UD60x18_IntoUD2x18_Overflow(uint256)",
        "error PRBMath_UD60x18_IntoUD21x18_Overflow(uint256)",
        "error PRBMath_UD60x18_IntoUint128_Overflow(uint256)",
        "error PRBMath_UD60x18_IntoUint40_Overflow(uint256)",
        "error PRBMath_UD60x18_Log_InputTooSmall(uint256)",
        "error PRBMath_UD60x18_Sqrt_Overflow(uint256)"
    ]

    const EnergyAMM_abi = [
        "event MarketStateChanged(uint256, uint256, uint256, uint256)",

        "error InsufficientAllowance(address, uint256, uint256)",
        "error ZeroTransfer()",

        "function EToken() external view returns (address)",
        "function MToken() external view returns (address)",
        "function LToken() external view returns (address)",
        "function EReserve() external view returns (uint256)",
        "function MReserve() external view returns (uint256)",
        "function liquidity() external view returns (uint256)",
        "function swapPriceRange() external view returns (bool, bool, uint256, uint256)",
        "function poolPrice() external view returns (uint256)",
        "function feeRate() external view returns (uint256)",
        "function bidRange() external view returns (bool, bool, uint256, uint256)",
        "function askRange() external view returns (bool, bool, uint256, uint256)",
        "function bidSwap(uint256) external view returns (uint256, uint256)",
        "function askSwap(uint256) external view returns (uint256, uint256)",
        "function bidFee(uint256) external view returns (uint256)",
        "function askFee(uint256) external view returns (uint256)",
        "function bidPrice(uint256) external view returns (uint256)",
        "function askPrice(uint256) external view returns (uint256)",
        "function bidSlippage(uint256) external view returns (int256)",
        "function askSlippage(uint256) external view returns (int256)",
        "function liquidityProvision(uint256) external view returns (uint256, uint256, uint256)",
        "function liquidityReduction(uint256) external view returns (uint256, uint256, uint256)",
        "function liquidityProportion(uint256) external view returns (uint256)",
        "function buy(uint256) external",
        "function sell(uint256) external",
        "function addLiquidity(uint256) external",
        "function removeLiquidity(uint256) external",
        "function setSwapPriceRange(bool, bool, uint256, uint256) external",
        "function setFeeRate(uint256) external",
    ].concat(prb_math_errors_abi)

    const ERC20Metadata_abi = [
        "event Transfer(address,address,uint256)",
        "event Approval(address,address,uint256)",

        "error ERC20InsufficientBalance(address,uint256,uint256)",
        "error ERC20InvalidSender(address)",
        "error ERC20InvalidReceiver(address)",
        "error ERC20InsufficientAllowance(address,uint256,uint256)",
        "error ERC20InvalidApprover(address)",
        "error ERC20InvalidSpender(address)",

        "function totalSupply() external view returns (uint256)",
        "function balanceOf(address) external view returns (uint256)",
        "function transfer(address,uint256) external returns (bool)",
        "function allowance(address,address) external view returns (uint256)",
        "function approve(address,uint256) external returns (bool)",
        "function transferFrom(address,address,uint256) external returns (bool)",

        "function name() external view returns (string)",
        "function symbol() external view returns (string)",
        "function decimals() external view returns (uint8)"
    ]

    let EToken = new ethers.Contract(
        process.env.ETOKEN_ADDRESS,
        ERC20Metadata_abi,
        provider
    )
    let MToken = new ethers.Contract(
        process.env.MTOKEN_ADDRESS,
        ERC20Metadata_abi,
        provider
    )
    let EnergyAMM = new ethers.Contract(
        process.env.ENERGYAMM_ADDRESS,
        EnergyAMM_abi,
        provider
    )

    const TARGET_MARKET = EnergyAMM 
    const OUTPUT_FILE = "hybrid_curve_simulation_data.csv"

    function UD60x18ToFloat(value) {
        return parseInt(value) / (10**18)
    }

    async function ETokensToFloat(value) {
        return parseInt(value) / (10**parseInt(await EToken.decimals()))
    }

    async function MTokensToFloat(value) {
        return parseInt(value) / (10**parseInt(await MToken.decimals()))
    }

    async function FloatToETokens(value) {
        return BigInt(Math.trunc(value * (10**parseInt(await EToken.decimals()))))
    }

    async function FloatToMTokens(value) {
        return BigInt(Math.trunc(value * (10**parseInt(await MToken.decimals()))))
    }

    const etk_initial_balances = await households.map(async (e) => { return await ETokensToFloat(await EToken.balanceOf(await e.getAddress())) })
    const usdc_initial_balances = await households.map(async (e) => { return await MTokensToFloat(await MToken.balanceOf(await e.getAddress())) })
    for (e of etk_initial_balances) { await e }
    for (e of usdc_initial_balances) { await e }

    await fs.writeFile(OUTPUT_FILE, "household0,,household1,,household2,,household3,,household4,,household5,,household6,,household7,,household8,,household9,,poolPrice\n", (e) => {})
    await fs.appendFile(OUTPUT_FILE, "ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,ETK balance,USDC balance,\n", (e) => {})
    for (iHour in data) {
        for (iHousehold in households) {
            const buy_amount = await FloatToETokens(parseFloat(data[iHour][iHousehold*2]))
            const sell_amount = await FloatToETokens(parseFloat(data[iHour][iHousehold*2 + 1]))

            if (parseInt(buy_amount) != 0 && parseInt((await TARGET_MARKET.bidSwap(buy_amount))[1]) != 0) {
                console.log("Household", iHousehold, "buys", parseFloat(data[iHour][iHousehold*2]), "ETokens for", await MTokensToFloat((await TARGET_MARKET.bidSwap(buy_amount))[1]), "MTokens")

                const buy_approval_unsigned_tx = await MToken.approve.populateTransaction(TARGET_MARKET.getAddress(), (await TARGET_MARKET.bidSwap(buy_amount))[1] + await TARGET_MARKET.bidFee(buy_amount))
                const buy_approval_tx = await households[iHousehold].sendTransaction(buy_approval_unsigned_tx)
                const buy_approval_receipt = await buy_approval_tx.wait()

                const buy_unsigned_tx = await TARGET_MARKET.buy.populateTransaction(buy_amount)
                const buy_tx = await households[iHousehold].sendTransaction(buy_unsigned_tx)
                const buy_receipt = await buy_tx.wait()
            }

            if (parseInt(sell_amount) != 0 && parseInt(await TARGET_MARKET.askSwap(sell_amount)) != 0) {
                console.log("Household", iHousehold, "sells", parseFloat(data[iHour][iHousehold*2 + 1]), "ETokens for", await MTokensToFloat(await TARGET_MARKET.askSwap(sell_amount)), "MTokens")

                const sell_approval_unsigned_tx = await EToken.approve.populateTransaction(TARGET_MARKET.getAddress(), sell_amount)
                const sell_approval_tx = await households[iHousehold].sendTransaction(sell_approval_unsigned_tx)
                const sell_approval_receipt = await sell_approval_tx.wait()

                const sell_unsigned_tx = await TARGET_MARKET.sell.populateTransaction(sell_amount)
                const sell_tx = await households[iHousehold].sendTransaction(sell_unsigned_tx)
                const sell_receipt = await sell_tx.wait()
            }
        }

        const etk_current_balances = await households.map(async (e) => { return await ETokensToFloat(await EToken.balanceOf(await e.getAddress())) })
        const usdc_current_balances = await households.map(async (e) => { return await MTokensToFloat(await MToken.balanceOf(await e.getAddress())) })
        for (e of etk_current_balances) { await e }
        for (e of usdc_current_balances) { await e }
        for (i in etk_initial_balances) {
            // await fs.appendFile(OUTPUT_FILE,
            //     `${await etk_current_balances[i] - await etk_initial_balances[i]},${await usdc_current_balances[i] - await usdc_initial_balances[i]},`,
            //     (e) => {})
            await fs.appendFile(OUTPUT_FILE,
                `${await etk_current_balances[i]},${await usdc_current_balances[i]},`,
                (e) => {})
        }
        await fs.appendFile(OUTPUT_FILE, `${UD60x18ToFloat(await TARGET_MARKET.poolPrice())}\n`, (e) => {})
    }
}

main()
