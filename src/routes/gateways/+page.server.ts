import { redirect } from "@sveltejs/kit";
import db from "$lib/db";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) throw redirect(302, "/login");
  const gateways = await db.query("SELECT * FROM gateways ORDER BY created_at DESC");
  return { gateways: gateways.rows };
};
