import { redirect } from "@sveltejs/kit";
import db from "$lib/db";
import type { PageServerLoad, Actions } from "./$types";

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) throw redirect(302, "/login");

  const clients = await db.query("SELECT * FROM clients ORDER BY created_at DESC");
  const servers = await db.query("SELECT * FROM servers ORDER BY id");
  return { clients: clients.rows, servers: servers.rows };
};

export const actions: Actions = {
  logout: async ({ cookies }) => {
    const { clearSession } = await import("$lib/auth");
    clearSession(cookies);
    throw redirect(302, "/login");
  },
};
