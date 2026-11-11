// SIP status a client receives when AMD detects an answering machine.
//
// The dialplan ([gw-route] label amdreject) sends it with PJSIPHangup(<code>),
// which takes any final code 400-699 (Asterisk 18.21 / 20.6 / 21.1 or later).
// clients.amd_reject holds the code as text; migration 005 allows 400-699.

export const AMD_REJECT_DEFAULT = "603";

/** Codes offered in the portal. Any 400-699 is accepted by the DB and dialplan. */
export const AMD_REJECT_CODES: { code: string; label: string }[] = [
  { code: "603", label: "603 Decline (default)" },
  { code: "403", label: "403 Forbidden" },
  { code: "480", label: "480 Temporarily Unavailable" },
  { code: "486", label: "486 Busy Here" },
  { code: "600", label: "600 Busy Everywhere" },
  { code: "605", label: "605 (non-standard, AMD marker)" },
  { code: "607", label: "607 Unwanted" },
  { code: "608", label: "608 Rejected" },
];

/** A valid code from form input, or the default. */
export function parseAmdReject(value: unknown): string {
  const s = String(value ?? "").trim();
  return /^[4-6][0-9]{2}$/.test(s) ? s : AMD_REJECT_DEFAULT;
}

/** Display label for a stored code. */
export function amdRejectLabel(code: string | null | undefined): string {
  const c = code || AMD_REJECT_DEFAULT;
  return AMD_REJECT_CODES.find((o) => o.code === c)?.label ?? `${c}`;
}
