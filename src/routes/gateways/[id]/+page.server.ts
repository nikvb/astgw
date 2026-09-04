import { redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { gatewaySlug, removeGatewayPjsip } from "$lib/ssh";
import type { PageServerLoad, Actions } from "./$types";

export const load: PageServerLoad = async ({ params, locals }) => {
  if (!locals.user) throw redirect(302, "/login");
  const res = await db.query("SELECT * FROM gateways WHERE id = $1", [params.id]);
  if (res.rows.length === 0) throw redirect(302, "/gateways");
  return { gateway: res.rows[0] };
};

export const actions: Actions = {
  delete: async ({ params, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    const res = await db.query("SELECT * FROM gateways WHERE id = $1", [params.id]);
    if (res.rows.length === 0) throw redirect(302, "/gateways");
    const gw = res.rows[0];
    const slug = gatewaySlug(gw.name);

    await db.query("DELETE FROM gateways WHERE id = $1", [params.id]);

    // Remove PJSIP config from all enabled Asterisk servers
    const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
    for (const srv of servers.rows) {
      try { await removeGatewayPjsip(srv.ip, slug); } catch {}
    }

    throw redirect(302, "/gateways");
  },

  toggle: async ({ params, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    const res = await db.query("SELECT enabled FROM gateways WHERE id = $1", [params.id]);
    if (res.rows.length === 0) throw redirect(302, "/gateways");
    await db.query("UPDATE gateways SET enabled = $1 WHERE id = $2", [!res.rows[0].enabled, params.id]);
    return { success: true };
  },
};
