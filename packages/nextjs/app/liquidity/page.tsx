'use client';

import { useEffect, useState } from 'react';

import { BaseInput } from '@scaffold-ui/components';
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from '~~/hooks/scaffold-eth';

import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';

const LiquidityPage = () => {
    const [addOrRemove, setAddOrRemove] = useState("Add");
    const [liquidityAmount, setLiquidityAmount] = useState("");
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
            setEAmount(liqAdd?.data ? liqAdd.data[1] : undefined);
            setMAmount(liqAdd?.data ? liqAdd.data[2] : undefined);
        } else if (addOrRemove == "Remove") {
            setEAmount(liqRemove?.data ? liqRemove.data[1] : undefined);
            setMAmount(liqRemove?.data ? liqRemove.data[2] : undefined);
        }
    }, [liqAdd, liqRemove, addOrRemove]);

    // useEffect(() => {
    //     document.getElementById("EAmount-input").value = EAmount ? Number(EAmount) / 1e18 : "";
    // }, [EAmount]);

    // useEffect(() => {
    //     document.getElementById("MAmount-input").value = MAmount ? Number(MAmount) / 1e18 : "";
    // }, [MAmount]);

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
      <center>
        <Box sx={{ width: '50%', p: 2}}>
          <Tabs
            value={addOrRemove}
            onChange={(event: React.SyntheticEvent, newValue: string) => {
                setAddOrRemove(newValue);
            }}
          >
            <Tab value="Add" label="Add"/>
            <Tab value="Remove" label="Remove"/>
          </Tabs>
          <label>Liquidity to {addOrRemove}:</label>
          <BaseInput
            placeholder="0"
            value={liquidityAmount}
            onChange={(value) => {
                setLiquidityAmount(value);
                setLAmount(value ? Math.floor(parseFloat(value) * 1e18) : 0);
            }}
          />
          <label>Energy to {addOrRemove} (kWh):</label>
          <BaseInput
            placeholder="0"
            value={EAmount ? Number(EAmount) / 1.0e18 : 0}
            onChange={(value) => {}}
          />
          <label>Funds to {addOrRemove} ($):</label>
          <BaseInput
            placeholder="0"
            value={MAmount ? Number(MAmount) / 1.0e18 : 0}
            onChange={(value) => {}}
          />
          <Button variant="contained" onClick={confirm}>Confirm</Button>
        </Box>
      </center>
    );
}

export default LiquidityPage;
