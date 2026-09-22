const mysql = require('mysql2/promise');
require('dotenv').config();

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT) || 4000,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_DATABASE,
  waitForConnections: true,
  connectionLimit: 10,
  dateStrings: true, // return DATE/DATETIME columns as plain strings, not JS Date objects with timezone surprises
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: true } : undefined,
  enableKeepAlive: true,
  keepAliveInitialDelay: 10000,
  connectTimeout: 20000,
});

pool.on('connection', (connection) => {
  connection.on('error', (err) => {
    console.error('MySQL pool connection error (recovered):', err.code || err.message);
  });
});

module.exports = pool;
