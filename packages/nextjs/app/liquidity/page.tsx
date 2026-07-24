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

const LiquidityPage = () => {
    const { address: connectedAddress } = useAccount();

    const [addOrRemove, setAddOrRemove] = useState("Add");
    const [liquidityAmount, setLiquidityAmount] = useState("");
    const [LAmount, setLAmount] = useState();
    const [EAmount, setEAmount] = useState();
    const [MAmount, setMAmount] = useState();

    const [error, setError] = useState(undefined);
    const [LInputError, setLInputError] = useState(false);
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

    const liqAdd = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "liquidityProvision",
        args: [LAmount],
        watch: true
    })?.data;

    const liqRemove = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "liquidityReduction",
        args: [LAmount],
        watch: true
    })?.data;

    useEffect(() => {
        if (addOrRemove == "Add") {
            setEAmount(liqAdd?.[1]);
            setMAmount(liqAdd?.[2]);
            setError(undefined);
            setEInputError(false);
            setMInputError(false);
            if (EAmount > EBalance) {
                setError("Required energy exceeds your account balance.");
                setEInputError(true);
            } else if (MAmount > MBalance) {
                setError("Required funds exceed your account balance.");
                setMInputError(true);
            } else {
                setError(undefined);
                setMInputError(false);
            }
        } else if (addOrRemove == "Remove") {
            setEAmount(liqRemove?.[1]);
            setMAmount(liqRemove?.[2]);
        }
    }, [liqAdd, liqRemove, addOrRemove]);

    const { writeContractAsync: writeEnergyAMM } = useScaffoldWriteContract({ contractName: "EnergyAMM" });
    const { writeContractAsync: writeEToken } = useScaffoldWriteContract({ contractName: "EToken" });
    const { writeContractAsync: writeMToken } = useScaffoldWriteContract({ contractName: "MToken" });

    const { data: EnergyAMMInfo } = useDeployedContractInfo({ contractName: "EnergyAMM" });

    const confirm = async () => {
        transactionInProgress.current = true;
        try {
            if (addOrRemove == "Add") {
                await writeEToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, (liqAdd?.[1] || 0)]
                });
                await writeMToken({
                    functionName: "approve",
                    args: [EnergyAMMInfo.address, (liqAdd?.[2] || 0)]
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
            setLiquidityAmount("");
            setEAmount(0);
            setMAmount(0);
        } catch (e) {
            console.error("Liquidity Confirm: ", e);
        }
        transactionInProgress.current = false;
    }

    //  <center>
    //    <Box sx={{ width: '50%', p: 2}}>
    //      <Tabs
    //        value={addOrRemove}
    //        onChange={(event: React.SyntheticEvent, newValue: string) => {
    //            setAddOrRemove(newValue);
    //        }}
    //      >
    //        <Tab value="Add" label="Add"/>
    //        <Tab value="Remove" label="Remove"/>
    //      </Tabs>
    //      <label>Liquidity to {addOrRemove}:</label>
    //      <BaseInput
    //        placeholder="0"
    //        value={liquidityAmount}
    //        onChange={(value) => {
    //            setLiquidityAmount(value);
    //            setLAmount(value ? Math.floor(parseFloat(value) * 1e18) : 0);
    //        }}
    //      />
    //      <label>Energy to {addOrRemove} (kWh):</label>
    //      <BaseInput
    //        placeholder="0"
    //        value={EAmount ? Number(EAmount) / 1.0e18 : 0}
    //        onChange={(value) => {}}
    //      />
    //      <label>Funds to {addOrRemove} ($):</label>
    //      <BaseInput
    //        placeholder="0"
    //        value={MAmount ? Number(MAmount) / 1.0e18 : 0}
    //        onChange={(value) => {}}
    //      />
    //      <Button variant="contained" onClick={confirm}>Confirm</Button>
    //    </Box>
    //  </center>




    return (
      <>
        <Stack sx={{ center: true, pl: 20, pr: 20 }} direction="row" spacing={5}>
          <Box sx={{ center: true, width: '50%', p: 2}}>
            <Tabs
              value={addOrRemove}
              onChange={(event: React.SyntheticEvent, newValue: string) => {
                  setAddOrRemove(newValue);
              }}
            >
              <Tab value="Add" label="Add"/>
              <Tab value="Remove" label="Remove"/>
            </Tabs>
            <p className="text-xl">Liquidity to {addOrRemove}:</p>
            <BaseInput
              value={liquidityAmount}
              onChange={(value) => {
                  setLiquidityAmount(value);
                  setLAmount(value ? Math.floor(parseFloat(value) * 1e18) : 0);
              }}
              placeholder="0"
              error={LInputError}
              disabled={transactionInProgress.current}
            />
            <p className="text-xl">Energy to {addOrRemove} (kWh):</p>
            <BaseInput
              value={EAmount ? Number(EAmount) / 1.0e18 : 0}
              onChange={(value) => {}}
              placeholder="0"
              error={EInputError}
              disabled={transactionInProgress.current}
            />
            <p className="text-xl">Funds to {addOrRemove} ($):</p>
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
                  <p className="text-base font-bold">Liquidity {addOrRemove == "Add" ? "Addition" : "Removal"}</p>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {(EAmount ? ((addOrRemove == "Add" ? "- " : "+ ") + (Number(EAmount) / 1e18).toFixed(2)) : "0.00") + " kWh"}
                  </p>
                </Grid>
                <Grid size={5}>
                  <p className="text-base text-right">
                    {(MAmount ? ((addOrRemove == "Add" ? "- " : "+ ") + "$ " + (Number(MAmount) / 1e18).toFixed(2)) : "$ 0.00")}
                  </p>
                </Grid>
              </Grid>
            </Stack>
          </Box>
        </Stack>
      </>
    );
}

export default LiquidityPage;
