import db from "$lib/db";
import { sshExec } from "$lib/ssh";

/** PJSIP endpoint id of the VOIP switch — a realtime endpoint, not a
 *  pjsip_gateways.conf block, so it is kept in sync here rather than over SSH. */
export const SWITCH_ENDPOINT = "voip-switch";

/**
 * Point the realtime `voip-switch` endpoint at ip:port and keep the legacy
 * `settings` rows in step (install scripts still read voip_switch_ip).
 * Returns per-server reload errors; never throws for a reload failure.
 */
export async function syncSwitchEndpoint(ip: string, port: number): Promise<string[]> {
  await db.query(
    "INSERT INTO settings (key, value) VALUES ('voip_switch_ip', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
    [ip]
  );
  await db.query(
    "INSERT INTO settings (key, value) VALUES ('sip_port', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
    [String(port)]
  );

  await db.query(
    `INSERT INTO ps_endpoints (id, context, disallow, allow, direct_media, rtp_symmetric, force_rport, rewrite_contact, aors)
     VALUES ($1, 'to-switch', 'all', 'ulaw,alaw', 'no', 'yes', 'yes', 'yes', $1)
     ON CONFLICT (id) DO UPDATE SET context='to-switch', disallow='all', allow='ulaw,alaw',
       direct_media='no', rtp_symmetric='yes', force_rport='yes', rewrite_contact='yes', aors=$1`,
    [SWITCH_ENDPOINT]
  );
  await db.query(
    `INSERT INTO ps_aors (id, contact, max_contacts) VALUES ($1, $2, 1)
     ON CONFLICT (id) DO UPDATE SET contact = $2, max_contacts = 1`,
    [SWITCH_ENDPOINT, `sip:${ip}:${port}`]
  );

  await db.query("DELETE FROM ps_endpoint_id_ips WHERE endpoint = $1", [SWITCH_ENDPOINT]);
  await db.query(
    "INSERT INTO ps_endpoint_id_ips (endpoint, match) VALUES ($1, $2)",
    [SWITCH_ENDPOINT, ip]
  );

  const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
  const errors: string[] = [];
  for (const srv of servers.rows) {
    try {
      await sshExec(srv.ip, "asterisk -rx 'pjsip reload'");
    } catch (e: any) {
      errors.push(`${srv.ip}: ${e.message}`);
    }
  }
  return errors;
}
