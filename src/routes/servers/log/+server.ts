import { error } from "@sveltejs/kit";
import { readFile } from "fs/promises";
import { existsSync } from "fs";
import type { RequestHandler } from "./$types";

const LOG_DIR = "/var/log/astgw-install";

export const GET: RequestHandler = async ({ url }) => {
  const name = url.searchParams.get("name");
  if (!name || /[^a-zA-Z0-9_-]/.test(name)) throw error(400, "Invalid server name");

  const logFile = `${LOG_DIR}/${name}.log`;
  if (!existsSync(logFile)) throw error(404, "Log not found");

  const content = await readFile(logFile, "utf-8");
  return new Response(content, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};
