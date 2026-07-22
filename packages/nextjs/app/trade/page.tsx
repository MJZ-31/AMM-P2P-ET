'use client';

import { useEffect, useState } from 'react';

import { BaseInput } from '@scaffold-ui/components';
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from '~~/hooks/scaffold-eth';

import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';

const TradePage = () => {
    const [buyOrSell, setBuyOrSell] = useState("Buy");
    const [energyAmount, setEnergyAmount] = useState("");
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
            setEnergyAmount(0);
            setEAmount(0);
            setMAmount(0);
        } catch (e) {
            console.error("Trade Confirm: ", e);
        }
    }

    return (
      <center>
        <Box sx={{ width: '50%', p: 2}}>
          <Tabs
            value={buyOrSell}
            onChange={(event: React.SyntheticEvent, newValue: string) => {
                setBuyOrSell(newValue);
            }}
          >
            <Tab value="Buy" label="Buy"/>
            <Tab value="Sell" label="Sell"/>
          </Tabs>
          <label>Energy to {buyOrSell} (kWh):</label>
          <BaseInput
            placeholder="0"
            value={energyAmount}
            onChange={(value) => {
                setEnergyAmount(value);
                setEAmount(value ? Math.floor(parseFloat(value) * 1e18) : 0);
            }}
          />
          <label>Base {buyOrSell == "Buy" ? "Price" : "Earnings"} ($):</label>
          <BaseInput
            placeholder="0"
            value={MAmount ? Number(MAmount) / 1.0e18 : 0}
            onChange={(value) => {}}/>
          <Button variant="contained" onClick={confirm}>Confirm</Button>
        </Box>
      </center>
    );
}

export default TradePage;
