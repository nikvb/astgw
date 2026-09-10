-- Default gateway + explicit endpoint mapping
--
-- 1) gateways.endpoint  : the PJSIP endpoint to dial. NULL => 'gateway-<slug>'.
--    Lets an endpoint that already exists (the realtime `voip-switch`) be
--    registered as a gateway without re-creating it in pjsip_gateways.conf.
-- 2) gateways.is_default: the gateway used by any client that has no explicit
--    assignment (legacy clients). At most one, enforced by a partial index.
-- 3) Seeds the VOIP switch (settings.voip_switch_ip) as that default gateway,
--    so today's behaviour — everything routes to the switch — is unchanged,
--    but now visible and editable on the Gateways page.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'gateways' AND column_name = 'endpoint'
    ) THEN
        ALTER TABLE gateways ADD COLUMN endpoint varchar(100);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'gateways' AND column_name = 'is_default'
    ) THEN
        ALTER TABLE gateways ADD COLUMN is_default boolean NOT NULL DEFAULT false;
    END IF;
END $$;

-- Only one gateway can be the default.
CREATE UNIQUE INDEX IF NOT EXISTS gateways_single_default
    ON gateways (is_default) WHERE is_default;

-- Register the existing VOIP switch as the default gateway (idempotent).
INSERT INTO gateways (name, ip, port, weight, enabled, endpoint, is_default)
SELECT 'VOIP Switch',
       s.value,
       COALESCE(NULLIF((SELECT value FROM settings WHERE key = 'sip_port'), ''), '5060')::int,
       1, true, 'voip-switch', true
  FROM settings s
 WHERE s.key = 'voip_switch_ip'
   AND COALESCE(s.value, '') <> ''
   AND NOT EXISTS (SELECT 1 FROM gateways WHERE endpoint = 'voip-switch')
   AND NOT EXISTS (SELECT 1 FROM gateways WHERE is_default)
ON CONFLICT (ip) DO UPDATE
    SET endpoint = 'voip-switch',
        is_default = true;
