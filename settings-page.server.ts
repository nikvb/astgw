import { fail, redirect } from "@sveltejs/kit";
import bcrypt from "bcryptjs";
import db from "$lib/db";
import { sshExec } from "$lib/ssh";
import type { PageServerLoad, Actions } from "./$types";

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) throw redirect(302, "/login");
  const res = await db.query("SELECT key, value FROM settings");
  const settings: Record<string, string> = {};
  for (const row of res.rows) settings[row.key] = row.value;
  return { settings };
};

export const actions: Actions = {
  save: async ({ request }) => {
    const data = await request.formData();
    const voip_switch_ip = (data.get("voip_switch_ip") as string || "").trim();
    const sip_port = (data.get("sip_port") as string || "").trim() || "5060";

    if (!voip_switch_ip) return fail(400, { error: "VOIP Switch IP required" });

    // Save to settings table
    await db.query(
      "INSERT INTO settings (key, value) VALUES ('voip_switch_ip', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
      [voip_switch_ip]
    );
    await db.query(
      "INSERT INTO settings (key, value) VALUES ('sip_port', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
      [sip_port]
    );

    // Update voip-switch in PJSIP realtime tables
    const contact = `sip:${voip_switch_ip}:${sip_port}`;
    await db.query(
      `INSERT INTO ps_endpoints (id, context, disallow, allow, direct_media, rtp_symmetric, force_rport, rewrite_contact, aors)
       VALUES ('voip-switch', 'to-switch', 'all', 'ulaw,alaw', 'no', 'yes', 'yes', 'yes', 'voip-switch')
       ON CONFLICT (id) DO UPDATE SET context='to-switch', disallow='all', allow='ulaw,alaw', direct_media='no', rtp_symmetric='yes', force_rport='yes', rewrite_contact='yes', aors='voip-switch'`
    );
    await db.query(
      `INSERT INTO ps_aors (id, contact, max_contacts)
       VALUES ('voip-switch', $1, 1)
       ON CONFLICT (id) DO UPDATE SET contact = $1, max_contacts = 1`,
      [contact]
    );

    // Update or insert identify row for voip-switch
    await db.query(`DELETE FROM ps_endpoint_id_ips WHERE endpoint = 'voip-switch'`);
    await db.query(
      `INSERT INTO ps_endpoint_id_ips (endpoint, match) VALUES ('voip-switch', $1)`,
      [voip_switch_ip]
    );

    // Reload PJSIP on all servers so they pick up the change
    const servers = await db.query("SELECT ip FROM servers WHERE enabled = true");
    const errors: string[] = [];
    for (const srv of servers.rows) {
      try {
        await sshExec(srv.ip, "asterisk -rx 'pjsip reload'");
      } catch (e: any) {
        errors.push(`${srv.ip}: ${e.message}`);
      }
    }

    if (errors.length > 0) {
      return { success: "Settings saved. Errors reloading some servers: " + errors.join("; ") };
    }

    return { success: "Settings saved and applied to all servers." };
  },

  password: async ({ request, locals }) => {
    if (!locals.user) return fail(401, { error: "Not authenticated" });

    const data = await request.formData();
    const current_password = (data.get("current_password") as string || "");
    const new_password = (data.get("new_password") as string || "");
    const confirm_password = (data.get("confirm_password") as string || "");

    if (!current_password || !new_password || !confirm_password) {
      return fail(400, { error: "All password fields are required" });
    }

    if (new_password !== confirm_password) {
      return fail(400, { error: "New passwords do not match" });
    }

    if (new_password.length < 4) {
      return fail(400, { error: "Password must be at least 4 characters" });
    }

    const res = await db.query("SELECT password_hash FROM admin_users WHERE username = $1", [locals.user]);
    if (res.rows.length === 0) return fail(400, { error: "User not found" });

    const valid = await bcrypt.compare(current_password, res.rows[0].password_hash);
    if (!valid) return fail(400, { error: "Current password is incorrect" });

    const hash = await bcrypt.hash(new_password, 10);
    await db.query("UPDATE admin_users SET password_hash = $1 WHERE username = $2", [hash, locals.user]);

    return { success: "Password changed successfully." };
  },
};
