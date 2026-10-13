-- Per-client AMD reject code
--
-- clients.amd_reject: the SIP status a client receives when AMD detects an
-- answering machine. '603' (Decline) or '403' (Forbidden). Default '603',
-- which is the status AstGW sends today, so behaviour does not change.
--
-- The dialplan does not send a status code directly. It hangs up with a Q.850
-- cause, and chan_pjsip maps that cause to a SIP status in hangup_cause2sip():
--   cause 21 (AST_CAUSE_CALL_REJECTED)   -> 403 Forbidden
--   cause 16 (AST_CAUSE_NORMAL_CLEARING) -> no entry in the table, so
--        chan_pjsip returns 0 and res_pjsip_session uses its fallback: 603.
-- See [gw-route] in extensions.conf.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'clients' AND column_name = 'amd_reject'
    ) THEN
        ALTER TABLE clients ADD COLUMN amd_reject varchar(3) NOT NULL DEFAULT '603';
    END IF;
END $$;

ALTER TABLE clients DROP CONSTRAINT IF EXISTS clients_amd_reject_valid;
ALTER TABLE clients ADD CONSTRAINT clients_amd_reject_valid
    CHECK (amd_reject IN ('403', '603'));

-- Any row written before this migration keeps today's behaviour.
UPDATE clients SET amd_reject = '603' WHERE amd_reject IS NULL OR amd_reject = '';
