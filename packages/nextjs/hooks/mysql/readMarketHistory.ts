import { getDBSettings } from './getDBSettings';

import mysql from 'mysql2/promise';

export default async function readMarketHistory(startTimestamp: Date | undefined, endTimestamp: Date | undefined) {
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
}
