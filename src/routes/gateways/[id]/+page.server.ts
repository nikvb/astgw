import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { gatewaySlug, addGatewayPjsip, removeGatewayPjsip } from "$lib/ssh";
import { syncSwitchEndpoint } from "$lib/switch";
import type { PageServerLoad, Actions } from "./$types";

async function getGateway(id: string) {
  const res = await db.query("SELECT * FROM gateways WHERE id = $1", [id]);
  return res.rows[0] || null;
}

export const load: PageServerLoad = async ({ params, locals }) => {
  if (!locals.user) throw redirect(302, "/login");
  const gateway = await getGateway(params.id);
  if (!gateway) throw redirect(302, "/gateways");
  return { gateway };
};

export const actions: Actions = {
  // Edit name / IP / port / weight. For a gateway that maps to an existing
  // endpoint (the VOIP switch) the realtime endpoint is updated instead of
  // pjsip_gateways.conf; otherwise its config block is rewritten on every server.
  update: async ({ params, request, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    const gw = await getGateway(params.id);
    if (!gw) throw redirect(302, "/gateways");

    const data = await request.formData();
    const name = ((data.get("name") as string) || "").trim();
    const ip = ((data.get("ip") as string) || "").trim();
    const port = parseInt((data.get("port") as string) || "5060");
    const weight = parseInt((data.get("weight") as string) || "1");

    if (!name || !ip) return fail(400, { error: "Name and IP are required" });
    if (!/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) return fail(400, { error: "Invalid IP address" });
    if (isNaN(port) || port < 1 || port > 65535) return fail(400, { error: "Invalid port" });
    if (isNaN(weight) || weight < 1 || weight > 100) return fail(400, { error: "Weight must be 1–100" });

    try {
      await db.query(
        "UPDATE gateways SET name = $1, ip = $2, port = $3, weight = $4 WHERE id = $5",
        [name, ip, port, weight, params.id]
      );
    } catch (e: any) {
      if (e.code === "23505") return fail(400, { error: "A gateway with this IP already exists" });
      return fail(500, { error: e.message });
    }

    const warnings: string[] = [];

    if (gw.endpoint) {
      // Managed endpoint (voip-switch): update realtime rows + reload.
      if (gw.ip !== ip || gw.port !== port) {
        try {
          warnings.push(...(await syncSwitchEndpoint(ip, port)));
        } catch (e: any) {
          warnings.push(e.message);
        }
      }
    } else if (gw.ip !== ip || gw.port !== port || gw.name !== name) {
      // Portal-managed endpoint: rewrite the pjsip_gateways.conf block.
      const oldSlug = gatewaySlug(gw.name);
      const newSlug = gatewaySlug(name);
      const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
      for (const srv of servers.rows) {
        try {
          await removeGatewayPjsip(srv.ip, oldSlug);
          await addGatewayPjsip(srv.ip, newSlug, ip, port);
        } catch (e: any) {
          warnings.push(`${srv.ip}: ${e.message}`);
        }
      }
    }

    if (warnings.length > 0) {
      return { success: "Gateway updated. Some servers reported errors: " + warnings.join("; ") };
    }
    return { success: "Gateway updated." };
  },

  // Make this the default gateway for clients with no assignment of their own.
  set_default: async ({ params, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    const gw = await getGateway(params.id);
    if (!gw) throw redirect(302, "/gateways");
    if (!gw.enabled) return fail(400, { error: "Enable the gateway before making it the default" });

    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query("UPDATE gateways SET is_default = false WHERE is_default = true");
      await client.query("UPDATE gateways SET is_default = true WHERE id = $1", [params.id]);
      await client.query("COMMIT");
    } catch (e: any) {
      await client.query("ROLLBACK");
      return fail(500, { error: e.message });
    } finally {
      client.release();
    }

    return { success: `${gw.name} is now the default gateway.` };
  },

  clear_default: async ({ params, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    await db.query("UPDATE gateways SET is_default = false WHERE id = $1", [params.id]);
    return { success: "Default cleared — unassigned clients fall back to voip-switch." };
  },

  delete: async ({ params, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    const gw = await getGateway(params.id);
    if (!gw) throw redirect(302, "/gateways");
    if (gw.is_default) {
      return fail(400, { error: "This is the default gateway — make another one default first." });
    }

    await db.query("DELETE FROM gateways WHERE id = $1", [params.id]);

    // Only remove config the portal created; a mapped endpoint (voip-switch)
    // is not ours to delete.
    if (!gw.endpoint) {
      const slug = gatewaySlug(gw.name);
      const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
      for (const srv of servers.rows) {
        try { await removeGatewayPjsip(srv.ip, slug); } catch {}
      }
    }

    throw redirect(302, "/gateways");
  },

  toggle: async ({ params, locals }) => {
    if (!locals.user) throw redirect(302, "/login");
    const gw = await getGateway(params.id);
    if (!gw) throw redirect(302, "/gateways");
    if (gw.enabled && gw.is_default) {
      return fail(400, { error: "This is the default gateway — make another one default before disabling it." });
    }
    await db.query("UPDATE gateways SET enabled = $1 WHERE id = $2", [!gw.enabled, params.id]);
    return { success: gw.enabled ? "Gateway disabled." : "Gateway enabled." };
  },
};
