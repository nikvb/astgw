import type { Handle } from "@sveltejs/kit";
import { getSession, ensureAdmin } from "$lib/auth";

// NOTE: deliberately NOT importing `redirect` from "@sveltejs/kit" here.
// In the adapter-node bundle, `redirect` lives in the same chunk as the
// top-level `await server.init()`. Because hooks is imported *during* init,
// a static import of that chunk creates a circular top-level-await deadlock
// (server hangs at startup, exits code 13). Returning a Response avoids it.

let initialized = false;

export const handle: Handle = async ({ event, resolve }) => {
  if (!initialized) {
    await ensureAdmin();
    initialized = true;
  }

  const user = getSession(event.cookies);
  event.locals.user = user;

  if (!user && event.url.pathname !== "/login") {
    return new Response(null, { status: 302, headers: { location: "/login" } });
  }

  return resolve(event);
};
