import type { Cookies } from "@sveltejs/kit";
import bcrypt from "bcryptjs";
import db from "$lib/db";

const SESSION_COOKIE = "astgw_session";
const sessions = new Map<string, { username: string; expires: number }>();

export async function login(username: string, password: string): Promise<string | null> {
  const res = await db.query("SELECT password_hash FROM admin_users WHERE username = $1", [username]);
  if (res.rows.length === 0) return null;
  const valid = await bcrypt.compare(password, res.rows[0].password_hash);
  if (!valid) return null;
  const token = crypto.randomUUID();
  sessions.set(token, { username, expires: Date.now() + 24 * 60 * 60 * 1000 });
  return token;
}

export function getSession(cookies: Cookies): string | null {
  const token = cookies.get(SESSION_COOKIE);
  if (!token) return null;
  const session = sessions.get(token);
  if (!session || session.expires < Date.now()) {
    if (token) sessions.delete(token);
    return null;
  }
  return session.username;
}

export function setSessionCookie(cookies: Cookies, token: string) {
  cookies.set(SESSION_COOKIE, token, { path: "/", httpOnly: true, maxAge: 86400, sameSite: "lax", secure: false });
}

export function clearSession(cookies: Cookies) {
  const token = cookies.get(SESSION_COOKIE);
  if (token) sessions.delete(token);
  cookies.delete(SESSION_COOKIE, { path: "/" });
}

export async function ensureAdmin() {
  const res = await db.query("SELECT id FROM admin_users LIMIT 1");
  if (res.rows.length === 0) {
    const hash = await bcrypt.hash("admin", 10);
    await db.query("INSERT INTO admin_users (username, password_hash) VALUES ($1, $2)", ["admin", hash]);
  }
}
