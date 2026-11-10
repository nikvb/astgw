-- Portal gateways move to PJSIP realtime
--
-- Before: each portal gateway was a text block in /etc/asterisk/pjsip_gateways.conf
-- on every server, written over SSH. After: one ps_endpoints row and one ps_aors
-- row per gateway, id 'gateway-<slug>', written by src/lib/gateways.ts. Asterisk
-- reads them on demand, on every server that uses this database.
--
-- This migration creates the realtime rows for gateways that already exist.
-- Rows that already exist are kept (ON CONFLICT DO NOTHING), so it never
-- overwrites a client endpoint or a row written by the portal.
-- gateways.endpoint stays NULL: gateway_select.py dials 'gateway-<slug>'.
--
-- AFTER this migration, remove the same gateways from pjsip_gateways.conf on
-- each server and run `pjsip reload`. A config-file endpoint is found before a
-- realtime one (sorcery.conf order), so a stale file block would win.

-- Slug rule = gatewaySlug() in src/lib/gateways.ts = gateway_slug in gateway_select.py
INSERT INTO ps_endpoints (id, transport, aors, context, disallow, allow,
                          direct_media, rtp_symmetric, force_rport, rewrite_contact)
SELECT 'gateway-' || trim(both '-' from regexp_replace(lower(g.name), '[^a-z0-9]+', '-', 'g')),
       'transport-udp',
       'gateway-' || trim(both '-' from regexp_replace(lower(g.name), '[^a-z0-9]+', '-', 'g')),
       'from-gateway', 'all', 'ulaw,alaw', 'no', 'yes', 'yes', 'yes'
  FROM gateways g
 WHERE g.endpoint IS NULL
ON CONFLICT (id) DO NOTHING;

INSERT INTO ps_aors (id, contact, max_contacts)
SELECT 'gateway-' || trim(both '-' from regexp_replace(lower(g.name), '[^a-z0-9]+', '-', 'g')),
       'sip:' || g.ip || ':' || COALESCE(g.port, 5060),
       1
  FROM gateways g
 WHERE g.endpoint IS NULL
ON CONFLICT (id) DO NOTHING;
