#!/usr/bin/python3
"""
AstGW Per-Client Gateway Selector (AGI)

Called as: AGI(gateway_select.py,${CLIENT_IP})

Can also be run by hand to check what a client IP would resolve to, without
Asterisk and without placing a call:

    gateway_select.py --test 176.9.119.54

Looks up the client by source IP, reads its assigned gateways + routing mode
from the DB, and sets dialplan variables for routing:

  GW_MODE   = weighted | failover | default | none
  GW_COUNT  = number of gateway endpoints to try (0 = none)
  GW_1..GW_N = PJSIP endpoint names, in the order to try them
  AMD_REJECT = 603 | 403 — the SIP status this client gets on AMD MACHINE
               (inherited to the outbound leg, set as __AMD_REJECT)

- weighted : GW_COUNT=1, one gateway chosen by weighted-random (load balance)
- failover : GW_COUNT=N, gateways in priority order (dialplan tries each)
- default  : client has no assignment (legacy) -> the gateway flagged is_default
- none     : no default configured either -> GW_COUNT=0, dialplan falls back to
             the hardcoded voip-switch (last-resort safety net)

A client WITH assignments is routed only to those gateways — never to the
default gateway and never to the voip-switch fallback.

The endpoint dialled is gateways.endpoint when set, otherwise 'gateway-<slug>'.
That lets an already-existing endpoint (the realtime `voip-switch`) be managed
as a gateway row without duplicating it in pjsip_gateways.conf.
"""
import sys
import os
import re
import random
import subprocess

# --- Test mode: print the decision instead of speaking the AGI protocol ---
TEST_MODE = "--test" in sys.argv

# --- DB config ---
# Read from the node's own realtime config so this works on every kind of node:
# the portal host (local DB), a gateway server pointing at the shared DB, and a
# standalone install with its own local DB and password. Falls back to the
# shared-portal defaults if the file is missing or unreadable.
PGSQL_CONF = "/etc/asterisk/res_pgsql.conf"

DB_HOST = "127.0.0.1"
DB_PORT = "5432"
DB_NAME = "asterisk_mgmt"
DB_USER = "asterisk"
DB_PASS = "ast3r1sk_gw_2026"

try:
    with open(PGSQL_CONF) as fh:
        _conf = {}
        for _line in fh:
            _line = _line.strip()
            if not _line or _line[0] in ";#[":
                continue
            _k, _, _v = _line.partition("=")
            _conf[_k.strip().lower()] = _v.strip()
    DB_HOST = _conf.get("dbhost") or DB_HOST
    DB_PORT = _conf.get("dbport") or DB_PORT
    DB_NAME = _conf.get("dbname") or DB_NAME
    DB_USER = _conf.get("dbuser") or DB_USER
    DB_PASS = _conf.get("dbpass") or DB_PASS
except Exception:
    pass


# --- AGI helpers ---
def agi_read_env():
    """Read the AGI environment block; return dict (incl. agi_arg_1 = CLIENT_IP)."""
    env = {}
    while True:
        line = sys.stdin.readline().strip()
        if not line:
            break
        if ":" in line:
            key, _, val = line.partition(":")
            env[key.strip()] = val.strip()
    return env


def agi_set(key, value):
    if TEST_MODE:
        print("  {:<8} = {}".format(key, value))
        return
    sys.stdout.write('SET VARIABLE {} "{}"\n'.format(key, value))
    sys.stdout.flush()
    sys.stdin.readline()


def agi_verbose(msg):
    if TEST_MODE:
        print("  # {}".format(msg))
        return
    sys.stdout.write('VERBOSE "{}" 1\n'.format(str(msg).replace('"', "'")))
    sys.stdout.flush()
    sys.stdin.readline()


def name_to_slug(name):
    return "gateway-" + re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def endpoint_for(name, endpoint):
    """Explicit endpoint wins; otherwise derive it from the gateway name."""
    endpoint = (endpoint or "").strip()
    return endpoint if endpoint else name_to_slug(name)


def psql(query):
    result = subprocess.run(
        ["psql", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER, "-d", DB_NAME,
         "-t", "-A", "-F", "\t", "-c", query],
        capture_output=True, text=True,
        env={**os.environ, "PGPASSWORD": DB_PASS, "LC_ALL": "C"},
    )
    return [ln.strip() for ln in result.stdout.strip().splitlines() if ln.strip()]


# --- AMD reject status ---
# Every call must leave here with AMD_REJECT set, including the early exits,
# so the dialplan never has to guess. '603' keeps the behaviour AstGW had
# before this variable existed.
AMD_REJECT_DEFAULT = "603"
AMD_REJECT_VALID = ("403", "603")
_amd_reject_sent = False


def set_amd_reject(value):
    """Set __AMD_REJECT once, falling back to the default on any bad value."""
    global _amd_reject_sent
    if _amd_reject_sent:
        return
    code = (value or "").strip()
    if code not in AMD_REJECT_VALID:
        code = AMD_REJECT_DEFAULT
    agi_set("__AMD_REJECT", code)
    _amd_reject_sent = True


def no_gateways(mode="none"):
    set_amd_reject(AMD_REJECT_DEFAULT)
    agi_set("GW_MODE", mode)
    agi_set("GW_COUNT", "0")
    sys.exit(0)


def use_default_gateway(reason):
    """Legacy client (no assignment) -> the gateway flagged is_default."""
    set_amd_reject(AMD_REJECT_DEFAULT)
    rows = psql("SELECT name, COALESCE(endpoint, '') FROM gateways "
                "WHERE is_default = true AND enabled = true LIMIT 1")
    if not rows:
        agi_verbose("AstGW: {} and no default gateway -> voip-switch".format(reason))
        no_gateways()

    parts = rows[0].split("\t")
    ep = endpoint_for(parts[0], parts[1] if len(parts) > 1 else "")
    agi_set("GW_MODE", "default")
    agi_set("GW_COUNT", "1")
    agi_set("GW_1", ep)
    agi_verbose("AstGW: {} -> default gateway {}".format(reason, ep))
    sys.exit(0)


# --- Main ---
if TEST_MODE:
    args = [a for a in sys.argv[1:] if a != "--test"]
    client_ip = args[0] if args else ""
    print("client IP {} on DB {}@{}:{}".format(client_ip or "(none)", DB_NAME, DB_HOST, DB_PORT))
else:
    env = agi_read_env()
    # CLIENT_IP is passed as the first AGI argument; also allow env fallbacks.
    client_ip = env.get("agi_arg_1") or ""

try:
    if not client_ip:
        use_default_gateway("no CLIENT_IP passed")

    # Resolve client by source IP
    rows = psql("SELECT id, COALESCE(gateway_mode,'weighted'), "
                "COALESCE(amd_reject,'{}') FROM clients "
                "WHERE ip = '{}' LIMIT 1".format(
                    AMD_REJECT_DEFAULT, client_ip.replace("'", "")))
    if not rows:
        use_default_gateway("no client for IP {}".format(client_ip))

    parts0 = rows[0].split("\t")
    client_id, mode = parts0[0], parts0[1]
    set_amd_reject(parts0[2] if len(parts0) > 2 else AMD_REJECT_DEFAULT)
    if mode not in ("weighted", "failover"):
        mode = "weighted"

    # Assigned, enabled gateways for this client
    grows = psql(
        "SELECT g.name, cg.weight, cg.priority, COALESCE(g.endpoint, '') "
        "FROM client_gateways cg JOIN gateways g ON g.id = cg.gateway_id "
        "WHERE cg.client_id = {} AND g.enabled = true "
        "ORDER BY cg.priority ASC, g.id ASC".format(int(client_id))
    )
    if not grows:
        use_default_gateway("client {} has no gateways".format(client_id))

    gateways = []
    for r in grows:
        parts = r.split("\t")
        if len(parts) >= 3:
            gateways.append((
                endpoint_for(parts[0], parts[3] if len(parts) > 3 else ""),
                int(parts[1] or 1),
                int(parts[2] or 1),
            ))

    if not gateways:
        use_default_gateway("client {} has no usable gateways".format(client_id))

    if mode == "weighted":
        pool = []
        for ep, weight, _ in gateways:
            pool.extend([ep] * max(1, weight))
        chosen = random.choice(pool)
        agi_set("GW_MODE", "weighted")
        agi_set("GW_COUNT", "1")
        agi_set("GW_1", chosen)
        agi_verbose("AstGW: client {} weighted -> {}".format(client_id, chosen))
    else:  # failover: keep priority order
        agi_set("GW_MODE", "failover")
        agi_set("GW_COUNT", str(len(gateways)))
        for i, (ep, _, _) in enumerate(gateways, start=1):
            agi_set("GW_{}".format(i), ep)
        agi_verbose("AstGW: client {} failover over {} gateways".format(client_id, len(gateways)))

except SystemExit:
    raise
except Exception as e:
    agi_verbose("AstGW: gateway selection error: {}".format(e))
    no_gateways("error")
