'use client';

import { useScaffoldWatchContractEvent } from '~~/hooks/scaffold-eth';
import { updateMarketHistory } from '~~/hooks/mysql/updateMarketHistory';

const EthEventHandler = ({ children }: { children: React.ReactNode }) => {
    
    useScaffoldWatchContractEvent({
        contractName: "EnergyAMM",
        eventName: "MarketStateChanged",
        onLogs: (logs) => {
            logs.map((log) => {
                const { poolPrice, EReserve, MReserve, liquidity } = log.args;
                try {
                    updateMarketHistory(
                        Number(poolPrice) / 1e18,
                        Number(EReserve),
                        Number(MReserve),
                        Number(liquidity));
                } catch (err) {
                    const msg = (err as Error).message;
                    console.log('ERROR: EthEventHandler -', msg);
                }
            });
        },
    });

    return (
        <>
          {children}
        </>
    );
}

export default EthEventHandler;
