'use server';

import { getDBSettings } from './getDBSettings';

import { unstable_cache } from 'next/cache';
import mysql from 'mysql2/promise';

const readMarketHistory = unstable_cache(
    async (startTimestamp: Date | undefined, endTimestamp: Date | undefined) => {
        const connectionParams = getDBSettings();
        const connection = await mysql.createConnection(connectionParams);
        var rows, fields;
        if (!startTimestamp && !endTimestamp) {
            [rows, fields] = await connection.query("SELECT * FROM AMM_P2P_ET.history");
        } else if (!startTimestamp) {
            [rows, fields] = await connection.query(
                "SELECT * FROM AMM_P2P_ET.history WHERE timestamp <= ?",
                [endTimestamp]);
        } else if (!endTimestamp) {
            [rows, fields] = await connection.query(
                "SELECT * FROM AMM_P2P_ET.history WHERE timestamp >= ?",
                [startTimestamp]);
        } else {
            [rows, fields] = await connection.query(
                "SELECT * FROM AMM_P2P_ET.history WHERE timestamp >= ? AND timestamp <= ?",
                [startTimestamp, endTimestamp]);
        }
        connection.end();
        return rows;
    },
    ['marketHistory'],
    {
        tags: ['marketHistory'],
        revalidate: 30
    }
)

export default readMarketHistory;
