import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { removeFirewallRule } from "$lib/ssh";
import { unregisterClientIp, updateClientIp } from "$lib/portal";
import type { PageServerLoad, Actions } from "./$types";

export const load: PageServerLoad = async ({ params }) => {
  const res = await db.query("SELECT * FROM clients WHERE id = $1", [params.id]);
  if (res.rows.length === 0) throw redirect(302, "/");

  const assigned = await db.query(
    `SELECT cg.gateway_id, cg.weight, cg.priority, g.name, g.ip, g.enabled
       FROM client_gateways cg JOIN gateways g ON g.id = cg.gateway_id
      WHERE cg.client_id = $1
      ORDER BY cg.priority ASC, g.name ASC`,
    [params.id]
  );
  const available = await db.query(
    `SELECT id, name, ip FROM gateways
      WHERE enabled = true
        AND id NOT IN (SELECT gateway_id FROM client_gateways WHERE client_id = $1)
      ORDER BY name ASC`,
    [params.id]
  );

  return {
    client: res.rows[0],
    assignedGateways: assigned.rows,
    availableGateways: available.rows,
  };
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

    // Remove the client's source IP from the Portal (non-fatal).
    try {
      await unregisterClientIp({ name: client.name, ip: client.ip, tech_prefix: client.tech_prefix });
    } catch {}

    throw redirect(302, "/");
  },

  toggle: async ({ params }) => {
    const res = await db.query("SELECT * FROM clients WHERE id = $1", [params.id]);
    if (res.rows.length === 0) throw redirect(302, "/");
    const client = res.rows[0];
    const enabled = !client.enabled;
    await db.query("UPDATE clients SET enabled = $1 WHERE id = $2", [enabled, params.id]);

    // Keep the Portal's tracking record in sync with the enabled state (non-fatal).
    try {
      await updateClientIp({ name: client.name, ip: client.ip, tech_prefix: client.tech_prefix, enabled });
    } catch {}

    return { success: true };
  },

  set_mode: async ({ params, request }) => {
    const data = await request.formData();
    const mode = (data.get("gateway_mode") as string) === "failover" ? "failover" : "weighted";
    await db.query("UPDATE clients SET gateway_mode = $1 WHERE id = $2", [mode, params.id]);
    return { success: true };
  },

  assign_gateway: async ({ params, request }) => {
    const data = await request.formData();
    const gateway_id = parseInt(data.get("gateway_id") as string);
    const weight = Math.max(1, parseInt(data.get("weight") as string) || 1);
    const priority = Math.max(1, parseInt(data.get("priority") as string) || 1);
    if (!gateway_id) return fail(400, { error: "Select a gateway" });
    await db.query(
      `INSERT INTO client_gateways (client_id, gateway_id, weight, priority)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (client_id, gateway_id) DO UPDATE SET weight = $3, priority = $4`,
      [params.id, gateway_id, weight, priority]
    );
    return { success: true };
  },

  update_gateway: async ({ params, request }) => {
    const data = await request.formData();
    const gateway_id = parseInt(data.get("gateway_id") as string);
    const weight = Math.max(1, parseInt(data.get("weight") as string) || 1);
    const priority = Math.max(1, parseInt(data.get("priority") as string) || 1);
    await db.query(
      "UPDATE client_gateways SET weight = $1, priority = $2 WHERE client_id = $3 AND gateway_id = $4",
      [weight, priority, params.id, gateway_id]
    );
    return { success: true };
  },

  unassign_gateway: async ({ params, request }) => {
    const data = await request.formData();
    const gateway_id = parseInt(data.get("gateway_id") as string);
    await db.query(
      "DELETE FROM client_gateways WHERE client_id = $1 AND gateway_id = $2",
      [params.id, gateway_id]
    );
    return { success: true };
  },
};
