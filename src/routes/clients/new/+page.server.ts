import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
import { addFirewallRule } from "$lib/ssh";
import { registerClientIp } from "$lib/portal";
import type { Actions } from "./$types";

export const actions: Actions = {
  default: async ({ request }) => {
    const data = await request.formData();
    const name = (data.get("name") as string || "").trim();
    const ip = (data.get("ip") as string || "").trim();
    const tech_prefix = (data.get("tech_prefix") as string || "").trim();
    // SIP status this client gets when AMD detects a machine. 603 is the
    // long-standing AstGW behaviour, so it is the default.
    const amd_reject = (data.get("amd_reject") as string) === "403" ? "403" : "603";

    if (!name || !ip || !tech_prefix) return fail(400, { error: "All fields required" });
    if (!/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) return fail(400, { error: "Invalid IP address" });

    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");

    try {
      // Insert into portal table
      await db.query(
        "INSERT INTO clients (name, ip, tech_prefix, amd_reject) VALUES ($1, $2, $3, $4)",
        [name, ip, tech_prefix, amd_reject]
      );

      // Insert PJSIP Realtime records
      await db.query(
        `INSERT INTO ps_endpoints (id, transport, aors, context, disallow, allow, direct_media, rtp_symmetric, force_rport, rewrite_contact, identify_by, set_var)
         VALUES ($1, 'transport-udp', $1, 'from-clients', 'all', 'ulaw,alaw', 'no', 'yes', 'yes', 'yes', 'ip', $2)`,
        [slug, `TECH_PREFIX=${tech_prefix}`]
      );
      await db.query("INSERT INTO ps_aors (id, max_contacts) VALUES ($1, 5)", [slug]);
      await db.query("INSERT INTO ps_endpoint_id_ips (id, endpoint, match) VALUES ($1, $1, $2)", [slug, ip]);

      // Add firewall rules on all servers
      const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
      const errors: string[] = [];
      for (const srv of servers.rows) {
        try {
          await addFirewallRule(srv.ip, ip, name);
        } catch (e: any) {
          errors.push(`${srv.ip}: ${e.message}`);
        }
      }

      // Report the client's source IP to the Portal for tracking (non-fatal).
      try {
        await registerClientIp({ name, ip, tech_prefix, enabled: true });
      } catch (e: any) {
        errors.push(`portal: ${e.message}`);
      }

      if (errors.length > 0) {
        return { success: true, warnings: errors };
      }
    } catch (e: any) {
      if (e.code === "23505") return fail(400, { error: "Client with this IP already exists" });
      return fail(500, { error: e.message });
    }

    throw redirect(302, "/");
  },
};
