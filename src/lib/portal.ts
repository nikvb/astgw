// Portal client-IP sync
// ----------------------
// Reports client (customer) SIP source IPs to the external Portal so it can
// track which IPs belong to which client. Configured entirely via env vars;
// if PORTAL_API_URL is unset the whole integration is a no-op, so existing
// provisioning keeps working unchanged.
//
// The client's real source IP is conveyed BOTH in the JSON body and via the
// X-Forwarded-For / X-Real-IP / X-Client-IP headers, so the Portal can pick up
// the IP however it is wired to (proxy-style header or explicit field).
//
// Env:
//   PORTAL_API_URL      Base endpoint, e.g. https://portal.primodialler.cloud/api/clients
//   PORTAL_API_TOKEN    Bearer token (optional)
//   PORTAL_API_TIMEOUT  ms (default 8000)

const PORTAL_API_URL = process.env.PORTAL_API_URL || "";
const PORTAL_API_TOKEN = process.env.PORTAL_API_TOKEN || "";
const PORTAL_API_TIMEOUT = Number(process.env.PORTAL_API_TIMEOUT) || 8000;

export interface PortalClient {
  name: string;
  ip: string;
  tech_prefix?: string;
  enabled?: boolean;
}

export function portalEnabled(): boolean {
  return PORTAL_API_URL !== "";
}

/** Register (or upsert) a client's source IP with the Portal. */
export async function registerClientIp(client: PortalClient): Promise<void> {
  await portalRequest("POST", "", client);
}

/** Update a client's tracking record (e.g. enabled toggled). */
export async function updateClientIp(client: PortalClient): Promise<void> {
  await portalRequest("PUT", encodeURIComponent(client.ip), client);
}

/** Remove a client's source IP from the Portal. */
export async function unregisterClientIp(client: PortalClient): Promise<void> {
  await portalRequest("DELETE", encodeURIComponent(client.ip), client);
}

async function portalRequest(
  method: "POST" | "PUT" | "DELETE",
  pathSuffix: string,
  client: PortalClient,
): Promise<void> {
  if (!portalEnabled()) return; // integration disabled

  const url = pathSuffix
    ? `${PORTAL_API_URL.replace(/\/$/, "")}/${pathSuffix}`
    : PORTAL_API_URL;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PORTAL_API_TIMEOUT);

  try {
    const res = await fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(PORTAL_API_TOKEN ? { Authorization: `Bearer ${PORTAL_API_TOKEN}` } : {}),
        // Convey the client's real source IP however the Portal reads it.
        "X-Forwarded-For": client.ip,
        "X-Real-IP": client.ip,
        "X-Client-IP": client.ip,
      },
      body: JSON.stringify({
        name: client.name,
        ip: client.ip,
        tech_prefix: client.tech_prefix ?? null,
        enabled: client.enabled ?? true,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      throw new Error(`Portal API ${method} ${res.status}: ${detail.slice(0, 300)}`);
    }
  } finally {
    clearTimeout(timer);
  }
}
