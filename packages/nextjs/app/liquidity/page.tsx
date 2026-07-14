'use client';

import { useEffect, useState } from 'react';

import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from '~~/hooks/scaffold-eth';

const LiquidityPage = () => {
    const [addOrRemove, setAddOrRemove] = useState("Add");
    const [LAmount, setLAmount] = useState();
    const [EAmount, setEAmount] = useState();
    const [MAmount, setMAmount] = useState();

    const liqAdd = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "liquidityProvision",
        args: [LAmount],
        watch: true
    });

    const liqRemove = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "liquidityReduction",
        args: [LAmount],
        watch: true
    });

    useEffect(() => {
        if (addOrRemove == "Add") {
            console.log(liqAdd?.data)
            console.log(LAmount)
            setEAmount(liqAdd?.data ? liqAdd.data[1] : undefined);
            setMAmount(liqAdd?.data ? liqAdd.data[2] : undefined);
        } else if (addOrRemove == "Remove") {
            console.log(liqRemove?.data)
            console.log(LAmount)
            setEAmount(liqRemove?.data ? liqRemove.data[1] : undefined);
            setMAmount(liqRemove?.data ? liqRemove.data[2] : undefined);
        }
    }, [liqAdd, liqRemove, addOrRemove]);

    useEffect(() => {
        document.getElementById("EAmount-input").value = EAmount ? Number(EAmount) / 1e18 : "";
    }, [EAmount]);

    useEffect(() => {
        document.getElementById("MAmount-input").value = MAmount ? Number(MAmount) / 1e18 : "";
    }, [MAmount]);

    const { writeContractAsync: writeEnergyAMM } = useScaffoldWriteContract({ contractName: "EnergyAMM" });
    const { writeContractAsync: writeEToken } = useScaffoldWriteContract({ contractName: "EToken" });
    const { writeContractAsync: writeMToken } = useScaffoldWriteContract({ contractName: "MToken" });

    const { data: EnergyAMMInfo } = useDeployedContractInfo({ contractName: "EnergyAMM" });

    const confirm = async () => {
        try {
            if (addOrRemove == "Add") {
                await writeEToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, liqAdd.data[1]]
                });
                await writeMToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, liqAdd.data[2]]
                });
                await writeEnergyAMM({
                    functionName: "addLiquidity",
                    args: [LAmount]
                });
            } else if (addOrRemove == "Remove") {
                await writeEnergyAMM({
                    functionName: "removeLiquidity",
                    args: [LAmount]
                });
            }
            setLAmount(0);
            setEAmount(0);
            setMAmount(0);
        } catch (e) {
            console.error("Liquidity Confirm: ", e);
        }
    }

    return (
      <>
        <form action={confirm}>
          <input id="LAmount-input" type="text" placeholder="0" autoComplete="off"
            onChange={() => {
                setLAmount(Math.floor(document.getElementById("LAmount-input").value * 1e18));
            }}
          /><label> Shares</label><br/>
          <input id="EAmount-input" type="text" readOnly placeholder="0"/><label> kWh</label><br/>
          <label>$ </label><input id="MAmount-input" type="text" readOnly placeholder="0"/><br/>
          <input id="addOrRemove-button" type="button" value={addOrRemove}
            onClick={() => {
                if (addOrRemove == "Add") {
                    setAddOrRemove("Remove");
                } else {
                    setAddOrRemove("Add");
                }
            }}
          /><br/>
          <input id="liquidity-confirm" type="submit" value="Confirm"/>
        </form>
      </>
    );
}

export default LiquidityPage;
