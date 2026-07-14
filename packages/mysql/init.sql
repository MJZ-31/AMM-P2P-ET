CREATE DATABASE IF NOT EXISTS AMM_P2P_ET;
USE AMM_P2P_ET;
CREATE TABLE IF NOT EXISTS history (
    timestamp DATETIME(0),
    pool_price REAL(60, 18),
    EReserve REAL(78, 0),
    MReserve REAL(78, 0),
    liquidity REAL(78, 0));
