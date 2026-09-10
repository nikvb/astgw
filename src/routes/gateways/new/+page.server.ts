import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { gatewaySlug, addGatewayPjsip } from "$lib/ssh";
import type { Actions } from "./$types";

export const actions: Actions = {
  default: async ({ request, locals }) => {
    if (!locals.user) throw redirect(302, "/login");

    const data = await request.formData();
    const name = (data.get("name") as string || "").trim();
    const ip = (data.get("ip") as string || "").trim();
    const port = parseInt(data.get("port") as string || "5060");
    const weight = parseInt(data.get("weight") as string || "1");
    const makeDefault = data.get("is_default") === "1";

    if (!name || !ip) return fail(400, { error: "Name and IP are required" });
    if (!/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) return fail(400, { error: "Invalid IP address" });
    if (isNaN(port) || port < 1 || port > 65535) return fail(400, { error: "Invalid port" });
    if (isNaN(weight) || weight < 1 || weight > 100) return fail(400, { error: "Weight must be 1–100" });

    const slug = gatewaySlug(name);

    try {
      const inserted = await db.query(
        "INSERT INTO gateways (name, ip, port, weight) VALUES ($1, $2, $3, $4) RETURNING id",
        [name, ip, port, weight]
      );

      // Optionally make it the route for clients with no gateway of their own.
      if (makeDefault) {
        await db.query("UPDATE gateways SET is_default = false WHERE is_default = true");
        await db.query("UPDATE gateways SET is_default = true WHERE id = $1", [inserted.rows[0].id]);
      }

      // Push PJSIP config to all enabled Asterisk servers
      const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
      for (const srv of servers.rows) {
        try { await addGatewayPjsip(srv.ip, slug, ip, port); } catch {}
      }
    } catch (e: any) {
      if (e.code === "23505") return fail(400, { error: "A gateway with this IP already exists" });
      return fail(500, { error: e.message });
    }

    throw redirect(302, "/gateways");
  },
};
