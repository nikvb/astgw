import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { removeFirewallRule } from "$lib/ssh";
import type { PageServerLoad, Actions } from "./$types";

export const load: PageServerLoad = async ({ params }) => {
  const res = await db.query("SELECT * FROM clients WHERE id = $1", [params.id]);
  if (res.rows.length === 0) throw redirect(302, "/");
  return { client: res.rows[0] };
};

export const actions: Actions = {
  delete: async ({ params }) => {
    const res = await db.query("SELECT * FROM clients WHERE id = $1", [params.id]);
    if (res.rows.length === 0) throw redirect(302, "/");
    const client = res.rows[0];
    const slug = client.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");

    // Remove PJSIP Realtime records
    await db.query("DELETE FROM ps_endpoint_id_ips WHERE endpoint = $1", [slug]);
    await db.query("DELETE FROM ps_aors WHERE id = $1", [slug]);
    await db.query("DELETE FROM ps_endpoints WHERE id = $1", [slug]);

    // Remove from portal table
    await db.query("DELETE FROM clients WHERE id = $1", [params.id]);

    // Remove firewall rules on all servers
    const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
    for (const srv of servers.rows) {
      try { await removeFirewallRule(srv.ip, client.ip); } catch {}
    }

    throw redirect(302, "/");
  },

  toggle: async ({ params }) => {
    const res = await db.query("SELECT * FROM clients WHERE id = $1", [params.id]);
    if (res.rows.length === 0) throw redirect(302, "/");
    const client = res.rows[0];
    await db.query("UPDATE clients SET enabled = $1 WHERE id = $2", [!client.enabled, params.id]);
    return { success: true };
  },
};
