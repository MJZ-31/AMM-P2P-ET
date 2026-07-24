'use client';

import { useEffect, useRef, useState } from 'react';

import { BaseInput } from '@scaffold-ui/components';
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from '~~/hooks/scaffold-eth';

import { useAccount } from 'wagmi';

import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Grid from '@mui/material/Grid';
import Stack from '@mui/material/Stack';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';

const TradePage = () => {
    const { address: connectedAddress } = useAccount();

    const [buyOrSell, setBuyOrSell] = useState("Buy");
    const [energyAmount, setEnergyAmount] = useState("");
    const [EAmount, setEAmount] = useState();
    const [MAmount, setMAmount] = useState();

    const [error, setError] = useState(undefined);
    const [EInputError, setEInputError] = useState(false);
    const [MInputError, setMInputError] = useState(false);

    const transactionInProgress = useRef(false);

    const EBalance = useScaffoldReadContract({
        contractName: "EToken",
        functionName: "balanceOf",
        args: [connectedAddress]
    })?.data;

    const MBalance = useScaffoldReadContract({
        contractName: "MToken",
        functionName: "balanceOf",
        args: [connectedAddress]
    })?.data;

    const bidSwap = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "bidSwap",
        args: [EAmount],
        watch: true
    })?.data;
    
    const bidFee = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "bidFee",
        args: [EAmount],
        watch: true
    })?.data;

    const askSwap = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "askSwap",
        args: [EAmount],
        watch: true
    })?.data;

    const askFee = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "askFee",
        args: [EAmount],
        watch: true
    })?.data;

    useEffect(() => {
        if (buyOrSell == "Buy") {
            setMAmount(bidSwap?.[1]);
            setError(undefined);
            setEInputError(false);
            if (MAmount > MBalance) {
                setError("Required funds exceed your account balance.");
                setMInputError(true);
            } else {
                setError(undefined);
                setMInputError(false);
            }
        } else if (buyOrSell == "Sell") {
            setMAmount(askSwap?.[1]);
            setError(undefined);
            setMInputError(false);
            if (EAmount > EBalance) {
                setError("Energy amount exceeds your account balance.");
                setEInputError(true);
            } else {
                setError(undefined);
                setEInputError(false);
            }
        }
    }, [bidSwap, askSwap, buyOrSell]);

    const { writeContractAsync: writeEnergyAMM } = useScaffoldWriteContract({ contractName: "EnergyAMM" });
    const { writeContractAsync: writeEToken } = useScaffoldWriteContract({ contractName: "EToken" });
    const { writeContractAsync: writeMToken } = useScaffoldWriteContract({ contractName: "MToken" });

    const { data: EnergyAMMInfo } = useDeployedContractInfo({ contractName: "EnergyAMM" });

    const confirm = async () => {
        transactionInProgress.current = true;
        try {
            if (buyOrSell == "Buy") {
                await writeMToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, (bidSwap?.[1] || 0) + (bidFee || 0)]
                });
                await writeEnergyAMM({
                    functionName: "buy",
                    args: [EAmount]
                });
            } else if (buyOrSell == "Sell") {
                await writeEToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, askSwap?.[0]]
                });
                await writeEnergyAMM({
                    functionName: "sell",
                    args: [EAmount]
                });
            }
            setEnergyAmount("");
            setEAmount(0);
            setMAmount(0);
        } catch (e) {
            console.error("Trade Confirm: ", e);
        }
        transactionInProgress.current = false;
    }

    return (
      <>
        <Stack sx={{ center: true, pl: 20, pr: 20 }} direction="row" spacing={5}>
          <Box sx={{ center: true, width: '50%', p: 2}}>
            <Tabs
              value={buyOrSell}
              onChange={(event: React.SyntheticEvent, newValue: string) => {
                  setBuyOrSell(newValue);
              }}
            >
              <Tab value="Buy" label="Buy"/>
              <Tab value="Sell" label="Sell"/>
            </Tabs>
            <p className="text-xl">Energy to {buyOrSell} (kWh):</p>
            <BaseInput
              value={energyAmount}
              onChange={(value) => {
                  setEnergyAmount(value);
                  setEAmount(value ? Math.floor(parseFloat(value) * 1e18) : 0);
              }}
              placeholder="0"
              error={EInputError}
              disabled={transactionInProgress.current}
            />
            <p className="text-xl">Base {buyOrSell == "Buy" ? "Price" : "Earnings"} ($):</p>
            <BaseInput
              value={MAmount ? Number(MAmount) / 1.0e18 : 0}
              onChange={(value) => {}}
              placeholder="0"
              error={MInputError}
              disabled={transactionInProgress.current}
            />
            <p className="text-xl">{error}</p>
            <Button
              disabled={error != undefined}
              loading={transactionInProgress.current}
              onClick={confirm}
              variant="contained"
            >
            Confirm
            </Button>
          </Box>
          <Box sx={{ center: true, width: '50%', p: 2}}>
            <Stack>
              <p className="text-3xl">Transaction Info</p>
              <Grid container spacing={2} rowSpacing={1}>
                {/* <Grid size={4}></Grid>
                <Grid size={4}>
                  <p className="text-base">kWh</p>
                </Grid>
                <Grid size={4}>
                  <p className="text-base">$</p>
                </Grid> */}

                <Grid size={2}>
                  <p className="text-base font-bold">Your Assets</p>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {(EBalance ? (Number(EBalance) / 1e18).toFixed(2) : "0.00") + " kWh"}
                  </p>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {"$ " + (MBalance ? (Number(MBalance) / 1e18).toFixed(2) : "0.00")}
                  </p>
                </Grid>

                <Grid size={2}>
                  <p className="text-base font-bold">Swap</p>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {(EAmount ? ((buyOrSell == "Buy" ? "+ " : "- ") + (Number(EAmount) / 1e18).toFixed(2)) : "0.00") + " kWh"}
                  </p>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {(MAmount ? ((buyOrSell == "Buy" ? "- " : "+ ") + "$ " + (Number(MAmount) / 1e18).toFixed(2)) : "$ 0.00")}
                  </p>
                </Grid>

                <Grid size={2}>
                  <p className="text-base font-bold">Swap Fee</p>
                </Grid>
                <Grid size={5}>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {isNaN((Number((buyOrSell == "Buy" ? bidFee : askFee)) / 1e18).toFixed(2)) ? "$ 0.00" : "- $ " + (Number((buyOrSell == "Buy" ? bidFee : askFee)) / 1e18).toFixed(2)}
                  </p>
                </Grid>
              </Grid>
            </Stack>
          </Box>
        </Stack>
      </>
    );
}

export default TradePage;
