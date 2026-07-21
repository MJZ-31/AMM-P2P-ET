"use client";

import Link from "next/link";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { useEffect, useState } from 'react';
import { useAccount } from "wagmi";
import { BugAntIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
import { useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-eth";

import HistoryGraph from '~~/components/HistoryGraph';

const Home: NextPage = () => {
    const { address: connectedAddress } = useAccount();
    const { targetNetwork } = useTargetNetwork();

    const [startTimestamp, setStartTimestamp] = useState(new Date(0));
    const [endTimestamp, setEndTimestamp] = useState(new Date());

    const E = Number(
        useScaffoldReadContract({
            contractName: "EnergyAMM",
            functionName: "EReserve",
        }).data);

    const M = Number(
        useScaffoldReadContract({
            contractName: "EnergyAMM",
            functionName: "MReserve",
        }).data);

    const L = Math.sqrt(E) * Math.sqrt(M);

    const p = Number(
        useScaffoldReadContract({
            contractName: "EnergyAMM",
            functionName: "poolPrice",
        }).data) / 1e18;

    const range = useScaffoldReadContract({
        contractName: "EnergyAMM",
        functionName: "poolPriceRange",
    }).data;

    const pLo = range?.isMinBounded ? Number(range.min) / 1e18 : undefined;
    const pHi = range?.isMaxBounded ? Number(range.max) / 1e18 : undefined;

    const updateTimeRange = () => {
        const value = document.getElementById("time-select").value;
        setEndTimestamp(new Date());
        if (value == "Minute") {
            setStartTimestamp(new Date(endTimestamp.setMinutes(endTimestamp.getMinutes() - 1)));
        } else if (value == "Hour") {
            setStartTimestamp(new Date(endTimestamp.setHours(endTimestamp.getHours() - 1)));
        } else if (value == "Day") {
            setStartTimestamp(new Date(endTimestamp.setDate(endTimestamp.getDate() - 1)));
        } else if (value == "Week") {
            setStartTimestamp(new Date(endTimestamp.setDate(endTimestamp.getDate() - 7)));
        } else if (value == "Month") {
            setStartTimestamp(new Date(endTimestamp.setMonth(endTimestamp.getMonth() - 1)));
        } else if (value == "All") {
            setStartTimestamp(new Date(0));
        }
    };

    return (
        <>
          <div id="overview" className="flex flex-row">
            <div id="price-history" className="relative m-4 w-1/2 aspect-1/1">
              <HistoryGraph startTimestamp={startTimestamp} endTimestamp={endTimestamp} poolPriceMin={pLo} poolPriceMax={pHi}/><br/>
              <select id="time-select" defaultValue="Day" onChange={updateTimeRange}>
                <option value="Minute">Minute</option>
                <option value="Hour">Hour</option>
                <option value="Day">Day</option>
                <option value="Week">Week</option>
                <option value="Month">Month</option>
                <option value="All">All</option>
              </select>
            </div>
            <div id="info" className="flex flex-col m-4 w-1/2">
              <p>Pool Price: {p}</p>
              <p>Pool Price Range: {pLo} - {pHi}</p>
              <p>Liquidity: {L}</p>
            </div>
          </div>
        </>
    );
};

export default Home;
