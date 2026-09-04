import { fail, redirect } from "@sveltejs/kit";
import db from "$lib/db";
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
    const sip_port = (data.get("sip_port") as string || "").trim();

    if (!voip_switch_ip) return fail(400, { error: "VOIP Switch IP required" });

    await db.query(
      "INSERT INTO settings (key, value) VALUES ('voip_switch_ip', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
      [voip_switch_ip]
    );
    await db.query(
      "INSERT INTO settings (key, value) VALUES ('sip_port', $1) ON CONFLICT (key) DO UPDATE SET value = $1",
      [sip_port || "5060"]
    );

    return { success: true };
  },
};
