import { fail, redirect } from "@sveltejs/kit";
import { spawn } from "child_process";
import db from "$lib/db";
import type { PageServerLoad, Actions } from "./$types";

const INSTALL_SCRIPT = "/home/na/astgw-files/install-server.sh";
const LOG_DIR = "/var/log/astgw-install";

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) throw redirect(302, "/login");
  const servers = await db.query("SELECT * FROM servers ORDER BY id");
  return { servers: servers.rows };
};

export const actions: Actions = {
  add: async ({ request }) => {
    const data = await request.formData();
    const name = (data.get("name") as string || "").trim();
    const ip = (data.get("ip") as string || "").trim();
    if (!name || !ip) return fail(400, { error: "Name and IP required" });
    if (!/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) return fail(400, { error: "Invalid IP address" });

    try {
      await db.query(
        "INSERT INTO servers (name, ip, status) VALUES ($1, $2, 'installing')",
        [name, ip]
      );
    } catch (e: any) {
      if (e.code === "23505") return fail(400, { error: "Server with this IP already exists" });
      return fail(500, { error: e.message });
    }

    // Kick off install script in background
    const logFile = `${LOG_DIR}/${name}.log`;
    const child = spawn("bash", [INSTALL_SCRIPT, ip, name], {
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        ASTGW_NONINTERACTIVE: "1",
        ASTGW_DB_HOST: "5.9.21.179",
        ASTGW_DB_PASS: "ast3r1sk_gw_2026",
      },
    });
    child.unref();

    // Stream stdout+stderr to log file
    const fs = await import("fs");
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const logStream = fs.createWriteStream(logFile);
    child.stdout?.pipe(logStream);
    child.stderr?.pipe(logStream);

    child.on("close", async (code) => {
      const status = code === 0 ? "online" : "failed";
      logStream.write(`\n--- install finished with exit code ${code} ---\n`);
      logStream.end();
      try {
        await db.query("UPDATE servers SET status = $1 WHERE ip = $2", [status, ip]);
      } catch { /* best-effort */ }
    });

    return { success: true };
  },

  delete: async ({ request }) => {
    const data = await request.formData();
    const id = data.get("id") as string;
    await db.query("DELETE FROM servers WHERE id = $1", [id]);
    return { success: true };
  },
};
