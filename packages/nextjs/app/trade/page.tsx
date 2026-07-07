'use client';

import { useState } from 'react';

import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from '~~/hooks/scaffold-eth'

const TradePage = () => {
    const [buyOrSell, setBuyOrSell] = useState("Buy");
    const [EAmount, setEAmount] = useState(0);

    const bidSwap = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "bidSwap",
        args: [EAmount],
        watch: true
    }).data;
    
    const bidFee = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "bidFee",
        args: [EAmount],
        watch: true
    }).data;

    const ESwapBid = bidSwap ? bidSwap[0] : undefined;
    const MSwapBid = bidSwap ? bidSwap[1] : undefined;

    const askSwap = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "askSwap",
        args: [EAmount],
        watch: true
    }).data;

    const askFee = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "askFee",
        args: [EAmount],
        watch: true
    }).data;

    const ESwapAsk = askSwap ? askSwap[0] : undefined;
    const MSwapAsk = askSwap ? askSwap[1] : undefined;

    const ESwap = buyOrSell == "Buy" ? ESwapBid : ESwapAsk;
    const MSwap = buyOrSell == "Buy" ? MSwapBid : MSwapAsk;

    const fee = buyOrSell == "Buy" ? bidFee : askFee;

    const { writeContractAsync: writeEnergyAMM } = useScaffoldWriteContract({ contractName: "EnergyAMM" });
    const { writeContractAsync: writeEToken } = useScaffoldWriteContract({ contractName: "EToken" });
    const { writeContractAsync: writeMToken } = useScaffoldWriteContract({ contractName: "MToken" });

    const { data: EnergyAMMInfo } = useDeployedContractInfo({ contractName: "EnergyAMM" });

    const confirm = async () => {
        try {
            if (buyOrSell == "Buy") {
                await writeMToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, MSwap + fee]
                });
                await writeEnergyAMM({
                    functionName: "buy",
                    args: [EAmount]
                });
            } else if (buyOrSell == "Sell") {
                await writeEToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, ESwap]
                });
                await writeEnergyAMM({
                    functionName: "sell",
                    args: [EAmount]
                });
            }
        } catch (e) {
            console.error("Trade Confirm: ", e);
        }
        setEAmount(0);
    }

    return (
      <>
        <form action={confirm}>
          <input type="text" id="EAmount-input" placeholder="0 kWh"
            onChange={() => {
                setEAmount(Math.floor(document.getElementById("EAmount-input").value * 1e18));
            }}
          />
          <input type="text" readOnly id="MAmount-input" placeholder="$ 0" value={"$ " + Number(MSwap) / 1e18}/>
          <input type="button" value={buyOrSell}
            onClick={() => {
                if (buyOrSell == "Buy") {
                    setBuyOrSell("Sell");
                } else {
                    setBuyOrSell("Buy");
                }
            }}
          /><br/>
          <input type="submit" value="Confirm"/>
        </form>
      </>
    );
}

export default TradePage;
