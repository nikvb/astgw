-- Per-client gateway assignment
-- Assign one or more gateways to a client, routed weighted (round-robin) or
-- failover (priority order). Clients with no assigned gateway fall back to the
-- existing voip-switch route, so existing clients are unaffected.

CREATE TABLE IF NOT EXISTS client_gateways (
    id         serial PRIMARY KEY,
    client_id  integer NOT NULL REFERENCES clients(id)  ON DELETE CASCADE,
    gateway_id integer NOT NULL REFERENCES gateways(id) ON DELETE CASCADE,
    weight     integer DEFAULT 1,   -- used in 'weighted' mode
    priority   integer DEFAULT 1,   -- try-order in 'failover' mode (lower = first)
    UNIQUE (client_id, gateway_id)
);

CREATE INDEX IF NOT EXISTS idx_client_gateways_client ON client_gateways(client_id);

-- Routing mode per client: 'weighted' (load-balance) or 'failover' (ordered).
-- Guarded so re-running is safe on PostgreSQL versions without ADD COLUMN IF NOT EXISTS.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'clients' AND column_name = 'gateway_mode'
    ) THEN
        ALTER TABLE clients ADD COLUMN gateway_mode varchar(16) DEFAULT 'weighted';
    END IF;
END $$;
