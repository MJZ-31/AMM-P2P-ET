import { ErrorDecoder } from 'ethers-decode-error';
import { ethers } from "ethers";

const FUND_AMOUNT_ETHEREUM = ethers.parseEther("2.0");
const FUND_AMOUNT_ETOKEN = 10000000000000000000000n;
const FUND_AMOUNT_MTOKEN = 10000000000000000000000n;

const errorsABI = [
    {
        inputs: [
            {
                internalType: "address",
                name: "spender",
                type: "address",
            },
            {
                internalType: "uint256",
                name: "allowance",
                type: "uint256",
            },
            {
                internalType: "uint256",
                name: "needed",
                type: "uint256",
            }
        ],
        name: "ERC20InsufficientAllowance",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "sender",
                type: "address"
            },
            {
                internalType: "uint256",
                name: "allowance",
                type: "uint256"
            },
            {
                internalType: "uint256",
                name: "needed",
                type: "uint256"
            }
        ],
        name: "ERC20InsufficientBalance",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "approver",
                type: "address"
            }
        ],
        name: "ERC20InvalidApprover",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "receiver",
                type: "address"
            }
        ],
        name: "ERC20InvalidReceiver",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "sender",
                type: "address"
            }
        ],
        name: "ERC20InvalidSender",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "spender",
                type: "address"
            }
        ],
        name: "ERC20InvalidSpender",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "owner",
                type: "address"
            }
        ],
        name: "OwnableInvalidOwner",
        type: "error"
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "account",
                type: "address"
            }
        ],
        name: "OwnableUnauthorizedAccount",
        type: "error"
    },
];

const errorDecoder = ErrorDecoder.create([errorsABI]);

const ERC20OwnableABI = [
    "event Transfer(address,address,uint256)",
    "event Approval(address,address,uint256)",
    "event OwnershipTransferred(address,address)",

    "error ERC20InsufficientAllowance(address,uint256,uint256)",
    "error ERC20InsufficientBalance(address,uint256,uint256)",
    "error ERC20InvalidApprover(address)",
    "error ERC20InvalidReceiver(address)",
    "error ERC20InvalidSender(address)",
    "error ERC20InvalidSpender(address)",

    "error OwnableInvalidOwner(address)",
    "error OwnableUnauthorizedAccount(address)",

    "function totalSupply() external view returns (uint256)",
    "function balanceOf(address) external view returns (uint256)",
    "function transfer(address,uint256) external returns (bool)",
    "function allowance(address,address) external view returns (uint256)",
    "function approve(address,uint256) external returns (bool)",
    "function transferFrom(address,address,uint256) external returns (bool)",
    "function mint(address,uint256) public",

    "function name() external view returns (string)",
    "function symbol() external view returns (string)",
    "function decimals() external view returns (uint8)"
];

// Setup
// const seed = "0x3f841bf589fdf83a521e55d51afddc34fa65351161eead24f064855fc29c9580";
const accounts = [
    "0xd826E703658FA2CE8D1018D42E637C08d9846A17",
    "0xD1cf9D73a91DE6630c2bb068Ba5fDdF9F0DEac09",
    "0x500a8704F86C0d9126Dfb949fDC4dc248c228fB4",
    "0x247DdfA00415710E0416f8c103b5E6428782C916",
    "0x32d9ad8F398995fFF658E74430749d65E0ee6702",
    "0x9fCDe74bf5465D5C32a09f158047803a061B3C1B",
    "0xd32d3f6dA1664C4ee7acae64fEC3661cEa6ee448",
    "0x179740E29B1E7b2C61F6004b8d5caD575D6eaa88",
    "0x5F6C5F2431CE84f2Fa84deB6B27A1764DB6feB1a",
    "0xb582703c0a0e2b598f9362A5e5c17Ab6865b0342",
    "0x36034A93A438EF5A945fe06f02fA9ADBc4eB8B2e",
    "0x64504fbc37fa75a88C013F2bE90AC5A5cAB483Ff",
    "0x88abf2ceE4b58Ab9702Df91a1A516ccADab4d24D",
    "0x42Fe48f5436cCa4202376Edf5e15DbB4a80731C0",
    "0x7aF066991DdD95ac5069C9098b2D468f846c8A45",
    "0x03596930470E52354B61500057E73E1d4559b7DE",
    "0x1225f8622c84b250b89Ecd4493377c1A69eF7106",
    "0x61CC661D90f575c1fA356F92eDc2BB8FFAD9ADb3",
    "0xa880178B9cF92d037715C4DeA911Ec530528B83d",
    "0xfbcb84314B5675a2E6262Ca18F3d3F969eB8612A",
    "0xC298f0f265Eb0Ca3E5C656E33D2E9cFd0706eF29",
    "0xe224B68cE29CEe7CBD61A1CB789031e5Ef5760f7",
    "0x76019cB6C7a3F9b2e0B8D7E0177557b7ED30355e",
    "0x0eECa74F8bC24EcC5CB87d6b558EEb4eA83756f9",
    "0xF9167846E02DeF6289C153F5Ad55678c26881070",
    "0x2DED1e40703b87E53AfaF1F39ab5630Da5551650",
    "0x3e57899E7f6FfD88c79D861872eC2B8301BcbB1C",
    "0x02b3E148E652c3F1857C208f2f9dc7c48c2c9d64",
    "0xCd18bA36A66BDbC6AD6F58bFf175CD39bB9411C2",
    "0xfB03ED9c4b1fC235d8EB4E03c88f81B30DffB44A",
    "0x506170E9Bf6C60FDAb27443849236a6F5A4966B6",
    "0x156419028f43105AeaFF4450325bFD4aC202b28e",
    "0xeF0e6E1bD6F30eb010A2AF8b2A4693BC52E98ed9",
    "0xa65C9A68662B9b5C42Df3840a7fbB0a2046822EF",
    "0x96DB73Bb6C85528AB6b413B03Ed9c3f476fba53b",
    "0xabBbC0c6945990e947fc9691ACC4a557E4b2bAD4",
    "0xE5E7aeb35f796C9C9eDCd4C393b7C11145CC7522",
    "0x4242E2F7c73456BA67C90Bfbd725AA46c35A02ea",
    "0x874E64Cd64Bd05BCE56F4E1336365Dda6f5c4e02",
    "0x63b2df787cdEA8A31426D5ae9DD92b93ce4249AB",
    "0xd8D946530f9569c3dbfA8883fE5F70F03d4efc04",
    "0x7F4387b89cc7f0B10513E542005496Dc073E4Af8",
    "0x23eB4388dB8B7D6A3c10F039F10f691d76aB8007",
    "0x789f2528751eeb1D34a6d1Ce3E8e6C487AF08cBb",
    "0xba76503380f9fE6A7E38dA9178F534b6CFd51033",
    "0x99EAA2DE386545e562C46Be86ebf4d4c4F566458",
    "0x11B7D3eeC50141916B73FBe844cAf624B69c1dC1",
    "0xb7260D7A44cBe0CB9393B3e83892E63B00E61595",
    "0xA54154164ebF9c05afD421801948885e44182cE5",
    "0x030b19e1Ec13F20aD1fB959B008c14C34703Dbf4"
];
const RPC_URL = "ws://localhost:8545";
const provider = new ethers.WebSocketProvider(RPC_URL);

// Deployer wallet (must have ETH)
const deployer = new ethers.NonceManager(
    new ethers.Wallet(
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // sample private key from Anvil
        provider
    ));

const owner = new ethers.NonceManager(
    new ethers.Wallet(
        "0xd0704a85072e2c67b54ac75d7d73b482e03cc1cba7c0280877b838cbee112a37",
        provider
    ));

const EToken = new ethers.Contract(
    "0xa15bb66138824a1c7167f5e85b957d04dd34e468",
    ERC20OwnableABI,
    provider
);

const MToken = new ethers.Contract(
    "0xb19b36b1456e65e3a6d514d3f715f204bd59f431",
    ERC20OwnableABI,
    provider
);

// const hdNode = ethers.utils.HDNode.fromSeed(seed);

async function main() {
    console.log("Starting prefund script...");

    const ownerEthTx = await deployer.sendTransaction({
        to: owner.getAddress(),
        value: FUND_AMOUNT_ETHEREUM
    });
    await ownerEthTx.wait();

    for (let i = 0; i < accounts.length; i++) {
        // const path = `m/44'/60'/${i}'/0/0`; // Caliper's derivation path
        // const wallet = hdNode.derivePath(path);
        const address = accounts[i];

        try {
            const ethTx = await deployer.sendTransaction({
                to: address,
                value: FUND_AMOUNT_ETHEREUM
            });
            const ETokenTxUnsigned = await EToken.mint.populateTransaction(address, FUND_AMOUNT_ETOKEN);
            const ETokenTx = await owner.sendTransaction(ETokenTxUnsigned);
            const MTokenTxUnsigned = await MToken.mint.populateTransaction(address, FUND_AMOUNT_MTOKEN);
            const MTokenTx = await owner.sendTransaction(MTokenTxUnsigned);

            await ethTx.wait();
            console.log(`Sent 2 ETH to ${address} | TxHash: ${ethTx.hash}`);
            await ETokenTx.wait();
            console.log(`Minted 10,000 ETokens to ${address} | TxHash: ${ETokenTx.hash}`);
            await MTokenTx.wait();
            console.log(`Minted 10,000 MTokens to ${address} | TxHash: ${MTokenTx.hash}`);

            // const ethBalance = await provider.getBalance(address);
            // const ETokenBalance = await EToken.balanceOf(address);
            // const MTokenBalance = await MToken.balanceOf(address);

            // console.log(`Balance of ${address} is ${ethers.formatEther(ethBalance)} ETH, ${(parseInt(ETokenBalance) / (10 ** parseInt(await EToken.decimals()))).toFixed(2)} ETK, and ${(parseInt(MTokenBalance) / (10 ** parseInt(await MToken.decimals()))).toFixed(2)} USDC.\n`);
        } catch (err) {
            const decodedErr = await errorDecoder.decode(err);
            console.error(`Failed to send funds to ${address}: ${decodedErr.reason} ${decodedErr.args}`);
            return -1;
        }
    }

    console.log(`Prefunded the first ${accounts.length} accounts.`);
}

main().catch(console.error);
