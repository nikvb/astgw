import { fail, redirect } from "@sveltejs/kit";
import { login, setSessionCookie } from "$lib/auth";
import type { Actions } from "./$types";

export const actions: Actions = {
  default: async ({ request, cookies }) => {
    const data = await request.formData();
    const username = data.get("username") as string;
    const password = data.get("password") as string;
    if (!username || !password) return fail(400, { error: "Username and password required" });

    const token = await login(username, password);
    if (!token) return fail(401, { error: "Invalid credentials" });

    setSessionCookie(cookies, token);
    throw redirect(302, "/");
  },
};
