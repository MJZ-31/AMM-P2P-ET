"use client";

import Link from "next/link";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { useAccount } from "wagmi";
import { BugAntIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
import { useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-eth";

import HistoryGraph from '~~/components/HistoryGraph';

const Home: NextPage = () => {
    const { address: connectedAddress } = useAccount();
    const { targetNetwork } = useTargetNetwork();

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

    return (
        <>
          <div id="overview" className="flex flex-row">
            <div id="price-history" className="relative m-4 w-1/2 aspect-1/1">
              <HistoryGraph poolPriceMin={pLo} poolPriceMax={pHi}/>
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
