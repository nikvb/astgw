# Portal client-IP sync

When a client (customer) is added/removed/toggled in AstGW, the portal now also
reports that client's **SIP source IP** to the external **Portal** so it can
track which IPs belong to which client.

## How it works
- `src/lib/portal.ts` — `registerClientIp` / `updateClientIp` / `unregisterClientIp`.
- Wired into:
  - `src/routes/clients/new` → `registerClientIp` after the client is provisioned.
  - `src/routes/clients/[id]` → `unregisterClientIp` on delete, `updateClientIp` on enable/disable.
- All calls are **non-fatal**: failures surface as `warnings`, never block provisioning.
- If `PORTAL_API_URL` is unset the integration is a **no-op** (safe default).

## Passing the client IP
The client's real source IP is sent **both ways**, so the Portal can read it however it's wired:
- JSON body: `{ name, ip, tech_prefix, enabled }`
- Headers: `X-Forwarded-For`, `X-Real-IP`, `X-Client-IP` (all set to the client IP)

## Config (env on the AstGW portal service)
| Var | Meaning |
|---|---|
| `PORTAL_API_URL` | Portal endpoint, e.g. `https://portal.primodialler.cloud/api/clients` |
| `PORTAL_API_TOKEN` | Bearer token (optional) |
| `PORTAL_API_TIMEOUT` | Request timeout ms (default 8000) |

Set them in the `astgw-portal` systemd unit (`Environment=...`) or the portal's env.

## ⚠️ TO CONFIRM before enabling in production
The exact endpoint contract is a placeholder — confirm and adjust `portal.ts`:
1. **Base URL + method** — is add a `POST /api/clients`? Is the IP the resource key for `PUT`/`DELETE`?
2. **Auth** — Bearer token? API key header? Basic?
3. **Payload** — does the Portal expect these field names, or different ones?
4. **IP mechanism** — should it read `X-Forwarded-For`, or the body `ip` field? (We send both.)
