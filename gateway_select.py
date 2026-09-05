#!/usr/bin/python3
"""
AstGW Per-Client Gateway Selector (AGI)

Called as: AGI(gateway_select.py,${CLIENT_IP})

Looks up the client by source IP, reads its assigned gateways + routing mode
from the DB, and sets dialplan variables for routing:

  GW_MODE   = weighted | failover | none
  GW_COUNT  = number of gateway endpoints to try (0 = none assigned)
  GW_1..GW_N = PJSIP endpoint names, in the order to try them

- weighted : GW_COUNT=1, one gateway chosen by weighted-random (load balance)
- failover : GW_COUNT=N, gateways in priority order (dialplan tries each)
- none/no assignment : GW_COUNT=0 -> dialplan falls back to voip-switch
"""
import sys
import os
import re
import random
import subprocess

# --- DB config (matches the local astgw DB) ---
DB_HOST = "127.0.0.1"
DB_PORT = "5432"
DB_NAME = "asterisk_mgmt"
DB_USER = "asterisk"
DB_PASS = "ast3r1sk_gw_2026"


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
    sys.stdout.write('SET VARIABLE {} "{}"\n'.format(key, value))
    sys.stdout.flush()
    sys.stdin.readline()


def agi_verbose(msg):
    sys.stdout.write('VERBOSE "{}" 1\n'.format(str(msg).replace('"', "'")))
    sys.stdout.flush()
    sys.stdin.readline()


def name_to_slug(name):
    return "gateway-" + re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def psql(query):
    result = subprocess.run(
        ["psql", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER, "-d", DB_NAME,
         "-t", "-A", "-F", "\t", "-c", query],
        capture_output=True, text=True,
        env={**os.environ, "PGPASSWORD": DB_PASS},
    )
    return [ln.strip() for ln in result.stdout.strip().splitlines() if ln.strip()]


def no_gateways(mode="none"):
    agi_set("GW_MODE", mode)
    agi_set("GW_COUNT", "0")
    sys.exit(0)


# --- Main ---
env = agi_read_env()
# CLIENT_IP is passed as the first AGI argument; also allow env fallbacks.
client_ip = env.get("agi_arg_1") or ""

try:
    if not client_ip:
        agi_verbose("AstGW: no CLIENT_IP passed, falling back to voip-switch")
        no_gateways()

    # Resolve client by source IP
    rows = psql("SELECT id, COALESCE(gateway_mode,'weighted') FROM clients "
                "WHERE ip = '{}' LIMIT 1".format(client_ip.replace("'", "")))
    if not rows:
        agi_verbose("AstGW: no client for IP {} -> voip-switch".format(client_ip))
        no_gateways()

    parts0 = rows[0].split("\t")
    client_id, mode = parts0[0], parts0[1]
    if mode not in ("weighted", "failover"):
        mode = "weighted"

    # Assigned, enabled gateways for this client
    grows = psql(
        "SELECT g.name, cg.weight, cg.priority "
        "FROM client_gateways cg JOIN gateways g ON g.id = cg.gateway_id "
        "WHERE cg.client_id = {} AND g.enabled = true "
        "ORDER BY cg.priority ASC, g.id ASC".format(int(client_id))
    )
    if not grows:
        agi_verbose("AstGW: client {} has no gateways -> voip-switch".format(client_id))
        no_gateways()

    gateways = []
    for r in grows:
        parts = r.split("\t")
        if len(parts) >= 3:
            gateways.append((parts[0], int(parts[1] or 1), int(parts[2] or 1)))

    if mode == "weighted":
        pool = []
        for name, weight, _ in gateways:
            pool.extend([name] * max(1, weight))
        chosen = name_to_slug(random.choice(pool))
        agi_set("GW_MODE", "weighted")
        agi_set("GW_COUNT", "1")
        agi_set("GW_1", chosen)
        agi_verbose("AstGW: client {} weighted -> {}".format(client_id, chosen))
    else:  # failover: keep priority order
        agi_set("GW_MODE", "failover")
        agi_set("GW_COUNT", str(len(gateways)))
        for i, (name, _, _) in enumerate(gateways, start=1):
            agi_set("GW_{}".format(i), name_to_slug(name))
        agi_verbose("AstGW: client {} failover over {} gateways".format(client_id, len(gateways)))

except Exception as e:
    agi_verbose("AstGW: gateway selection error: {}".format(e))
    no_gateways("error")
