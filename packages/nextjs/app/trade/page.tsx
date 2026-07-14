'use client';

import { useEffect, useState } from 'react';

import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from '~~/hooks/scaffold-eth';

const TradePage = () => {
    const [buyOrSell, setBuyOrSell] = useState("Buy");
    const [EAmount, setEAmount] = useState();
    const [MAmount, setMAmount] = useState();

    const bidSwap = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "bidSwap",
        args: [EAmount],
        watch: true
    });
    
    const bidFee = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "bidFee",
        args: [EAmount],
        watch: true
    });

    const askSwap = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "askSwap",
        args: [EAmount],
        watch: true
    });

    const askFee = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "askFee",
        args: [EAmount],
        watch: true
    });

    useEffect(() => {
        if (buyOrSell == "Buy") {
            setMAmount(bidSwap?.data ? bidSwap.data[1] : undefined);
        } else if (buyOrSell == "Sell") {
            setMAmount(askSwap?.data ? askSwap.data[1] : undefined);
        }
    }, [bidSwap, askSwap, buyOrSell]);

    useEffect(() => {
        document.getElementById("MAmount-input").value = MAmount ? Number(MAmount) / 1e18 : "";
    }, [MAmount]);

    const { writeContractAsync: writeEnergyAMM } = useScaffoldWriteContract({ contractName: "EnergyAMM" });
    const { writeContractAsync: writeEToken } = useScaffoldWriteContract({ contractName: "EToken" });
    const { writeContractAsync: writeMToken } = useScaffoldWriteContract({ contractName: "MToken" });

    const { data: EnergyAMMInfo } = useDeployedContractInfo({ contractName: "EnergyAMM" });

    const confirm = async () => {
        try {
            if (buyOrSell == "Buy") {
                bidSwap.refetch()
                bidFee.refetch()
                await writeMToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, bidSwap?.data[1] + bidFee?.data]
                });
                await writeEnergyAMM({
                    functionName: "buy",
                    args: [EAmount]
                });
            } else if (buyOrSell == "Sell") {
                askSwap.refetch()
                await writeEToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, askSwap?.data[0]]
                });
                await writeEnergyAMM({
                    functionName: "sell",
                    args: [EAmount]
                });
            }
            setEAmount(0);
            setMAmount(0);
        } catch (e) {
            console.error("Trade Confirm: ", e);
        }
    }

    return (
      <>
        <form action={confirm}>
          <input id="EAmount-input" type="text" placeholder="0" autoComplete="off"
            onChange={() => {
                setEAmount(Math.floor(document.getElementById("EAmount-input").value * 1e18));
            }}
          /><label>kWh</label><br/>
          <label>$</label><input id="MAmount-input" type="text" readOnly placeholder="0"/><br/>
          <input id="buyOrSell-button" type="button" value={buyOrSell}
            onClick={() => {
                if (buyOrSell == "Buy") {
                    setBuyOrSell("Sell");
                } else {
                    setBuyOrSell("Buy");
                }
            }}
          />
          <input id="trade-confirm" type="submit" value="Confirm"/>
        </form>
      </>
    );
}

export default TradePage;
