-- clients.amd_reject: allow any final SIP code 400-699 (was 403 or 603 only)
--
-- The dialplan now rejects with PJSIPHangup(${AMD_REJECT}), which sends the
-- exact code. Requires Asterisk 18.21 / 20.6 / 21.1 or later on every server
-- that uses this database.

ALTER TABLE clients DROP CONSTRAINT IF EXISTS clients_amd_reject_valid;
ALTER TABLE clients ADD CONSTRAINT clients_amd_reject_valid
    CHECK (amd_reject ~ '^[4-6][0-9]{2}$');
