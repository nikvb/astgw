import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { gatewaySlug, slugTakenBy, upsertGatewayEndpoint, deleteGatewayEndpoint } from "$lib/gateways";
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
  // Edit name / IP / port / weight. A gateway that maps to an existing endpoint
  // (the VOIP switch) is synced by switch.ts; a portal gateway's realtime
  // endpoint/AOR is rewritten in the same transaction as the gateway row.
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

    const oldSlug = gatewaySlug(gw.name);
    const newSlug = gatewaySlug(name);
    if (!gw.endpoint && newSlug !== oldSlug) {
      if (newSlug === "gateway-") return fail(400, { error: "Name must contain a letter or a digit" });
      const taken = await slugTakenBy(newSlug, gw.id);
      if (taken) return fail(400, { error: `Name gives the same endpoint id (${newSlug}) as gateway "${taken}"` });
    }

    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        "UPDATE gateways SET name = $1, ip = $2, port = $3, weight = $4 WHERE id = $5",
        [name, ip, port, weight, params.id]
      );
      if (!gw.endpoint) {
        // Portal gateway: realtime rows follow the row (a rename moves the id).
        if (newSlug !== oldSlug) await deleteGatewayEndpoint(client, oldSlug);
        await upsertGatewayEndpoint(client, newSlug, ip, port);
      }
      await client.query("COMMIT");
    } catch (e: any) {
      await client.query("ROLLBACK");
      if (e.code === "23505") return fail(400, { error: "A gateway with this IP already exists" });
      return fail(500, { error: e.message });
    } finally {
      client.release();
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

    // Only remove realtime rows the portal created; a mapped endpoint
    // (voip-switch) is not ours to delete.
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query("DELETE FROM gateways WHERE id = $1", [params.id]);
      if (!gw.endpoint) await deleteGatewayEndpoint(client, gatewaySlug(gw.name));
      await client.query("COMMIT");
    } catch (e: any) {
      await client.query("ROLLBACK");
      return fail(500, { error: e.message });
    } finally {
      client.release();
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
