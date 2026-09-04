import pg from "pg";

// Env-driven so each standalone deployment supplies its own local DB password.
// Falls back to the shared-portal defaults for backward compatibility.
const pool = new pg.Pool({
  host: process.env.PGHOST || "127.0.0.1",
  port: Number(process.env.PGPORT) || 5432,
  database: process.env.PGDATABASE || "asterisk_mgmt",
  user: process.env.PGUSER || "asterisk",
  password: process.env.PGPASSWORD || "ast3r1sk_gw_2026",
  max: 10,
});

export default pool;
