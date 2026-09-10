import { fail, redirect } from "@sveltejs/kit";
import bcrypt from "bcryptjs";
import db from "$lib/db";
import type { PageServerLoad, Actions } from "./$types";

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) throw redirect(302, "/login");

  // The VOIP switch is managed on the Gateways page (it is the default
  // gateway); shown here read-only so the settings page still points at it.
  const gw = await db.query(
    "SELECT id, name, ip, port FROM gateways WHERE is_default = true LIMIT 1"
  );

  return { defaultGateway: gw.rows[0] || null };
};

export const actions: Actions = {
  password: async ({ request, locals }) => {
    if (!locals.user) return fail(401, { error: "Not authenticated" });

    const data = await request.formData();
    const current_password = (data.get("current_password") as string) || "";
    const new_password = (data.get("new_password") as string) || "";
    const confirm_password = (data.get("confirm_password") as string) || "";

    if (!current_password || !new_password || !confirm_password) {
      return fail(400, { error: "All password fields are required" });
    }
    if (new_password !== confirm_password) {
      return fail(400, { error: "New passwords do not match" });
    }
    if (new_password.length < 4) {
      return fail(400, { error: "Password must be at least 4 characters" });
    }

    const res = await db.query(
      "SELECT password_hash FROM admin_users WHERE username = $1",
      [locals.user]
    );
    if (res.rows.length === 0) return fail(400, { error: "User not found" });

    const valid = await bcrypt.compare(current_password, res.rows[0].password_hash);
    if (!valid) return fail(400, { error: "Current password is incorrect" });

    const hash = await bcrypt.hash(new_password, 10);
    await db.query("UPDATE admin_users SET password_hash = $1 WHERE username = $2", [
      hash,
      locals.user,
    ]);

    return { success: "Password changed successfully." };
  },
};
