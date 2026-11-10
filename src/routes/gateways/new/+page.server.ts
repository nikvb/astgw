import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { gatewaySlug, slugTakenBy, upsertGatewayEndpoint } from "$lib/gateways";
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
    if (slug === "gateway-") return fail(400, { error: "Name must contain a letter or a digit" });
    const taken = await slugTakenBy(slug);
    if (taken) return fail(400, { error: `Name gives the same endpoint id (${slug}) as gateway "${taken}"` });

    // Gateway row + its realtime endpoint/AOR in one transaction: Asterisk sees
    // the gateway as soon as this commits, on every server using this DB.
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      const inserted = await client.query(
        "INSERT INTO gateways (name, ip, port, weight) VALUES ($1, $2, $3, $4) RETURNING id",
        [name, ip, port, weight]
      );

      // Optionally make it the route for clients with no gateway of their own.
      if (makeDefault) {
        await client.query("UPDATE gateways SET is_default = false WHERE is_default = true");
        await client.query("UPDATE gateways SET is_default = true WHERE id = $1", [inserted.rows[0].id]);
      }

      await upsertGatewayEndpoint(client, slug, ip, port);
      await client.query("COMMIT");
    } catch (e: any) {
      await client.query("ROLLBACK");
      if (e.code === "23505") return fail(400, { error: "A gateway with this IP already exists" });
      return fail(500, { error: e.message });
    } finally {
      client.release();
    }

    throw redirect(302, "/gateways");
  },
};
