'use server';

import { getDBSettings } from './getDBSettings';

import { revalidateTag } from 'next/cache';

import mysql from 'mysql2/promise';

export async function updateMarketHistory(pool_price: number, EReserve: number, MReserve: number, liquidity: number) {
    const connectionParams = getDBSettings();
    const connection = await mysql.createConnection(connectionParams);
    const [result] = await connection.query(
        "INSERT INTO AMM_P2P_ET.history VALUES (?, ?, ?, ?, ?)",
        [new Date(), pool_price, EReserve, MReserve, liquidity]);
    revalidateTag('marketHistory');
    return [result];
}
