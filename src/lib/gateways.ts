// Upstream gateways as PJSIP realtime rows.
//
// A portal gateway is one `ps_endpoints` row plus one `ps_aors` row, both with
// id `gateway-<slug>`. Asterisk reads realtime on demand, so a change is live on
// every server that uses this database at once: no SSH, no file, no reload.
//
// `gateways.endpoint` stays NULL for these gateways; gateway_select.py then
// dials `gateway-<slug>` (same slug rule as gatewaySlug below). A gateway with
// `endpoint` set (the VOIP switch, see switch.ts) owns its own rows and is not
// touched here.

import db from "$lib/db";

/** The pool or a client inside a transaction. */
type Queryable = { query: (text: string, values?: unknown[]) => Promise<unknown> };

/** Dialplan context of gateway endpoints. Also marks a ps_endpoints row as a gateway. */
export const GATEWAY_CONTEXT = "from-gateway";

/** Endpoint id for a portal gateway. Must match gateway_slug() in gateway_select.py. */
export function gatewaySlug(name: string): string {
  return "gateway-" + name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

/**
 * Another gateway (not `exceptId`) whose name gives the same slug, if any.
 * Two gateways with one slug would share one endpoint.
 */
export async function slugTakenBy(slug: string, exceptId: number | null = null): Promise<string | null> {
  const res = await db.query("SELECT id, name FROM gateways WHERE endpoint IS NULL");
  for (const row of res.rows) {
    if (row.id !== exceptId && gatewaySlug(row.name) === slug) return row.name;
  }
  return null;
}

/** Create or update the realtime endpoint + AOR for a gateway. */
export async function upsertGatewayEndpoint(q: Queryable, slug: string, ip: string, port: number): Promise<void> {
  // The dialplan dials PJSIP/<number>@<slug>; that form finds the target
  // through the endpoint's AORs, so aors= must name the AOR below.
  // context: outbound only. No identify row exists for a gateway, so no
  // inbound call can land in this context.
  //
  // Never overwrite an endpoint that is not a gateway (a client named
  // "Gateway X" also has the id gateway-x).
  const existing = (await q.query("SELECT context FROM ps_endpoints WHERE id = $1", [slug])) as {
    rows: { context: string | null }[];
  };
  if (existing.rows.length > 0 && existing.rows[0].context !== GATEWAY_CONTEXT) {
    throw new Error(`Endpoint ${slug} already exists and is not a gateway — choose another name`);
  }
  await q.query(
    `INSERT INTO ps_endpoints (id, transport, aors, context, disallow, allow, direct_media, rtp_symmetric, force_rport, rewrite_contact)
     VALUES ($1, 'transport-udp', $1, $2, 'all', 'ulaw,alaw', 'no', 'yes', 'yes', 'yes')
     ON CONFLICT (id) DO UPDATE SET transport = 'transport-udp', aors = $1, context = $2,
       disallow = 'all', allow = 'ulaw,alaw', direct_media = 'no', rtp_symmetric = 'yes',
       force_rport = 'yes', rewrite_contact = 'yes'`,
    [slug, GATEWAY_CONTEXT]
  );
  await q.query(
    `INSERT INTO ps_aors (id, contact, max_contacts) VALUES ($1, $2, 1)
     ON CONFLICT (id) DO UPDATE SET contact = $2, max_contacts = 1`,
    [slug, `sip:${ip}:${port}`]
  );
}

/** Remove the realtime endpoint + AOR of a gateway. */
export async function deleteGatewayEndpoint(q: Queryable, slug: string): Promise<void> {
  // Only a gateway endpoint; a client endpoint with the same id stays.
  const del = (await q.query("DELETE FROM ps_endpoints WHERE id = $1 AND context = $2", [
    slug,
    GATEWAY_CONTEXT,
  ])) as { rowCount: number | null };
  if (del.rowCount) await q.query("DELETE FROM ps_aors WHERE id = $1", [slug]);
}
